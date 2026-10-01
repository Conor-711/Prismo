-- Prepared only: the user runs this migration on the iOS account project.
-- No worker, signing endpoint, transfer or execution switch is installed.
begin;

create table public.bsmart_equity_preparations (
  intent_id uuid primary key,
  account_id uuid not null,
  wallet_address text not null check(wallet_address ~ '^0x[0-9a-f]{40}$'),
  intent_version integer not null check(intent_version between 1 and 2147483645),
  network text not null check(network in ('Ethereum','Ink')),
  order_uid text not null check(order_uid ~ '^0x[0-9a-f]{112}$'),
  fingerprint text not null check(fingerprint ~ '^[0-9a-f]{64}$'),
  preparation_hash text not null check(preparation_hash ~ '^[0-9a-f]{64}$'),
  material jsonb not null check(jsonb_typeof(material)='object' and pg_column_size(material)<=32768),
  prepared jsonb not null check(jsonb_typeof(prepared)='object' and pg_column_size(prepared)<=16384),
  expires_at timestamptz not null,
  state text not null default 'reserved' check(state in ('reserved','authorized','released')),
  signature text check(signature ~ '^0x[0-9a-f]{130}$'),
  authorization_hash text check(authorization_hash ~ '^[0-9a-f]{64}$'),
  authorized_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  foreign key(intent_id,account_id) references public.bsmart_equity_intents(id,account_id) on delete cascade,
  unique(network,order_uid),
  check((state='authorized' and signature is not null and authorization_hash is not null and authorized_at is not null)
    or (state in ('reserved','released') and signature is null and authorization_hash is null and authorized_at is null))
);
create unique index bsmart_one_equity_reservation_per_wallet on public.bsmart_equity_preparations(wallet_address)
  where state in ('reserved','authorized');
alter table public.bsmart_equity_preparations enable row level security;
revoke all on public.bsmart_equity_preparations from public,anon,authenticated,service_role;
grant select on public.bsmart_equity_preparations to service_role;

-- Use the existing withdrawal lock key, not an equity-only lock. Every entry
-- and transition into an active state is protected, including direct service updates.
create function public.bsmart_wallet_activity_assert(p_wallet text,p_table text,p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_wallet is null or p_wallet !~ '^0x[0-9a-f]{40}$' then
    raise exception 'wallet_changed' using errcode='22023';
  end if;
  -- Older reserve RPCs acquire wallet before row; direct update callers acquire
  -- row first. Fail closed on contention instead of creating a row/wallet deadlock.
  if not pg_try_advisory_xact_lock(hashtextextended(p_wallet,0)) then
    raise exception 'wallet_activity_in_progress' using errcode='23505';
  end if;
  if exists(select 1 from public.bsmart_withdrawals where wallet_address=p_wallet
      and state in ('reserved','submitting','accepted','uncertain','core_debited')
      and not (p_table='withdrawal' and id=p_id))
    or exists(select 1 from public.bsmart_across_withdrawals where wallet_address=p_wallet
      and state in ('quoted','submitting','submitted','uncertain','deposit_pending','expired')
      and not (p_table='across' and id=p_id))
    or exists(select 1 from public.bsmart_equity_preparations where wallet_address=p_wallet
      and state in ('reserved','authorized') and not (p_table='equity' and intent_id=p_id))
    or exists(select 1 from public.bsmart_equity_intents where wallet_address=p_wallet
      and state in ('authorized','funding_pending','funded','order_pending','filled','return_pending','refund_pending','needs_reconciliation')
      and not (p_table='equity' and id=p_id)) then
    raise exception 'wallet_activity_in_progress' using errcode='23505';
  end if;
end;
$$;

create function public.bsmart_withdrawal_activity_guard()
returns trigger language plpgsql security definer set search_path='' as $$
declare active boolean; label text;
begin
  if tg_op='UPDATE' and (new.wallet_address<>old.wallet_address or new.account_id<>old.account_id or new.id<>old.id) then
    raise exception 'wallet_changed' using errcode='22023';
  end if;
  label := case when tg_table_name='bsmart_withdrawals' then 'withdrawal' else 'across' end;
  active := case when label='withdrawal' then new.state in ('reserved','submitting','accepted','uncertain','core_debited')
    else new.state in ('quoted','submitting','submitted','uncertain','deposit_pending','expired') end;
  -- Release transitions take the same lock, but must not be blocked by older conflicts.
  if not pg_try_advisory_xact_lock(hashtextextended(new.wallet_address,0)) then
    raise exception 'wallet_activity_in_progress' using errcode='23505';
  end if;
  if active then perform public.bsmart_wallet_activity_assert(new.wallet_address,label,new.id); end if;
  return new;
end;
$$;
create trigger bsmart_withdrawal_activity_guard before insert or update on public.bsmart_withdrawals
  for each row execute function public.bsmart_withdrawal_activity_guard();
create trigger bsmart_across_activity_guard before insert or update on public.bsmart_across_withdrawals
  for each row execute function public.bsmart_withdrawal_activity_guard();

create function public.bsmart_equity_preparation_guard()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='UPDATE' then
    if (to_jsonb(new)-array['state','signature','authorization_hash','authorized_at']) <>
       (to_jsonb(old)-array['state','signature','authorization_hash','authorized_at'])
      or old.state<>'reserved' or new.state not in ('authorized','released') then
      raise exception 'preparation_conflict' using errcode='22023';
    end if;
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended(new.wallet_address,0)) then
    raise exception 'wallet_activity_in_progress' using errcode='23505';
  end if;
  if new.state in ('reserved','authorized') then
    perform public.bsmart_wallet_activity_assert(new.wallet_address,'equity',new.intent_id);
  end if;
  return new;
end;
$$;
create trigger bsmart_equity_preparation_guard before insert or update on public.bsmart_equity_preparations
  for each row execute function public.bsmart_equity_preparation_guard();

create function public.bsmart_equity_prepared_intent_guard()
returns trigger language plpgsql security definer set search_path='' as $$
declare p public.bsmart_equity_preparations;
begin
  select * into p from public.bsmart_equity_preparations where intent_id=old.id and state in ('reserved','authorized');
  if not found then return new; end if;
  if not pg_try_advisory_xact_lock(hashtextextended(p.wallet_address,0)) then
    raise exception 'wallet_activity_in_progress' using errcode='23505';
  end if;
  if (to_jsonb(new)-array['state','version','updated_at'])<>(to_jsonb(old)-array['state','version','updated_at'])
    or new.version<>old.version+1 then raise exception 'preparation_conflict' using errcode='22023'; end if;
  if p.state='reserved' and old.state='quoted' and new.state='cancelled' then
    update public.bsmart_equity_preparations set state='released' where intent_id=old.id;
    return new;
  end if;
  if p.state='authorized' and old.state='quoted' and new.state='authorized' then return new; end if;
  raise exception 'preparation_conflict' using errcode='22023';
end;
$$;
create trigger bsmart_equity_prepared_intent_guard before update on public.bsmart_equity_intents
  for each row execute function public.bsmart_equity_prepared_intent_guard();

create function public.bsmart_equity_prepare(p_account uuid,p_id uuid,p_owner text,p_version integer,
  p_preview jsonb,p_material jsonb,p_prepared jsonb,p_hash text)
returns public.bsmart_equity_preparations language plpgsql security definer set search_path='' as $$
declare r public.bsmart_equity_intents; p public.bsmart_equity_preparations; c jsonb;
  t timestamptz; expiry timestamptz;
begin
  select * into r from public.bsmart_equity_intents where id=p_id and account_id=p_account for update;
  if not found then raise exception 'intent_not_found' using errcode='22023'; end if;
  perform 1 from public.bsmart_wallets where account_id=p_account and address=p_owner for share;
  if not found or r.wallet_address<>p_owner then raise exception 'wallet_changed' using errcode='22023'; end if;
  select * into p from public.bsmart_equity_preparations where intent_id=p_id;
  if found then
    if p.state<>'reserved' or r.state<>'quoted' then raise exception 'preparation_conflict' using errcode='22023'; end if;
    if p_version not in (p.intent_version,p.intent_version-1) or p_version is null then
      raise exception 'intent_version_conflict' using errcode='22023';
    end if;
    if p_hash is distinct from p.preparation_hash or p_material is distinct from p.material or p_prepared is distinct from p.prepared
      or p_preview is distinct from r.preview then raise exception 'preparation_conflict' using errcode='22023'; end if;
    if p.expires_at<=clock_timestamp()+interval '5 seconds' then raise exception 'quote_expired' using errcode='22023'; end if;
    perform public.bsmart_wallet_activity_assert(p_owner,'equity',p_id);
    return p;
  end if;
  if p_version is null or p_version<0 or p_version>2147483644 or r.version<>p_version then
    raise exception 'intent_version_conflict' using errcode='22023';
  end if;
  if r.state not in ('draft','quoted') then raise exception 'intent_state_conflict' using errcode='22023'; end if;
  -- Nested RPC locks the same intent and validates safe preview freshness. Any
  -- later failure rolls back both quote and private reservation together.
  r := public.bsmart_equity_intent_change(p_account,p_id,p_owner,p_version,'quote',p_preview);
  t := clock_timestamp();
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_material is null or p_prepared is null
    or jsonb_typeof(p_material)<>'object' or jsonb_typeof(p_prepared)<>'object'
    or pg_column_size(p_material)>32768 or pg_column_size(p_prepared)>16384
    or (p_prepared->>'schema') is distinct from 'cow_order_v1'
    or (p_prepared->>'intentId') is distinct from p_id::text or (p_prepared->>'account') is distinct from p_account::text
    or (p_prepared->'intentVersion') is distinct from to_jsonb(r.version)
    or (p_prepared->>'owner') is distinct from p_owner or (p_material->>'owner') is distinct from p_owner
    or (p_material->>'account') is distinct from p_account::text or (p_material->'version') is distinct from '1'::jsonb
    or (p_material->'input') is distinct from r.input or (p_prepared->>'side') is distinct from (r.input->>'side')
    or (p_prepared->'order') is distinct from (p_material->'order')
    or (p_prepared->'domain') is distinct from (p_material->'domain')
    or (p_prepared->'instrument') is distinct from (p_material->'instrument')
    or (p_material->'quote'->'verified') is distinct from 'true'::jsonb
    or coalesce(p_prepared->>'orderUid','') !~ '^0x[0-9a-f]{112}$'
    or coalesce(p_prepared->>'orderDigest','') !~ '^0x[0-9a-f]{64}$'
    or coalesce(p_prepared->>'fingerprint','') !~ '^[0-9a-f]{64}$'
    or (p_prepared->'order'->>'receiver') is distinct from p_owner
    or (p_prepared->'order'->>'kind') is distinct from 'sell'
    or (p_prepared->'order'->'partiallyFillable') is distinct from 'false'::jsonb
    or (p_prepared->'order'->>'feeAmount') is distinct from '0'
    or (p_prepared->'instrument'->>'network') not in ('Ethereum','Ink') then
    raise exception 'preparation_invalid' using errcode='22023';
  end if;
  select value into c from jsonb_array_elements(r.preview->'candidates') where value->>'fingerprint'=p_prepared->>'fingerprint';
  if not found or (select count(*) from jsonb_array_elements(r.preview->'candidates') where value->>'fingerprint'=p_prepared->>'fingerprint')<>1
    or (c->'providerVerified') is distinct from 'true'::jsonb or (c->'instrument') is distinct from (p_prepared->'instrument')
    or (c->>'inputAmountRaw') is distinct from (p_prepared->'order'->>'sellAmount')
    or (c->>'minimumOutputAmountRaw') is distinct from (p_prepared->'order'->>'buyAmount')
    or (c->>'expiresAt') is distinct from (p_prepared->>'expiresAt') then
    raise exception 'preparation_invalid' using errcode='22023';
  end if;
  expiry := (p_prepared->>'expiresAt')::timestamptz;
  if expiry is null or expiry<=t+interval '5 seconds' or expiry>t+interval '10 minutes'
    or expiry>r.quote_expires_at or (p_prepared->'order'->>'validTo') is null
    or expiry>to_timestamp((p_prepared->'order'->>'validTo')::double precision)
    or (p_material->'expiresAt') is distinct from to_jsonb(extract(epoch from expiry)*1000) then
    raise exception 'quote_expired' using errcode='22023';
  end if;
  insert into public.bsmart_equity_preparations(intent_id,account_id,wallet_address,intent_version,network,order_uid,
    fingerprint,preparation_hash,material,prepared,expires_at)
  values(p_id,p_account,p_owner,r.version,p_prepared->'instrument'->>'network',p_prepared->>'orderUid',
    p_prepared->>'fingerprint',p_hash,p_material,p_prepared,expiry) returning * into p;
  return p;
end;
$$;

-- Service verification is necessary before this RPC; SQL is the atomic CAS and
-- deduplication boundary, not an EIP-712 verifier. No public authorize endpoint.
create function public.bsmart_equity_authorize_prepared(p_account uuid,p_id uuid,p_owner text,p_version integer,
  p_hash text,p_signature text,p_authorization_hash text)
returns public.bsmart_equity_preparations language plpgsql security definer set search_path='' as $$
declare r public.bsmart_equity_intents; p public.bsmart_equity_preparations; t timestamptz;
begin
  select * into r from public.bsmart_equity_intents where id=p_id and account_id=p_account for update;
  if not found then raise exception 'intent_not_found' using errcode='22023'; end if;
  perform 1 from public.bsmart_wallets where account_id=p_account and address=p_owner for share;
  if not found or r.wallet_address<>p_owner then raise exception 'wallet_changed' using errcode='22023'; end if;
  select * into p from public.bsmart_equity_preparations where intent_id=p_id for update;
  if not found or p.preparation_hash is distinct from p_hash or p.wallet_address<>p_owner
    or p.intent_version is distinct from p_version then raise exception 'preparation_conflict' using errcode='22023'; end if;
  if p_signature is null or p_signature !~ '^0x[0-9a-f]{130}$' or p_authorization_hash is null
    or p_authorization_hash !~ '^[0-9a-f]{64}$' then raise exception 'preparation_invalid' using errcode='22023'; end if;
  if p.state='authorized' and r.state='authorized' and r.version=p_version+1 then
    if p.signature is distinct from p_signature or p.authorization_hash is distinct from p_authorization_hash then
      raise exception 'preparation_conflict' using errcode='22023';
    end if;
    return p;
  end if;
  if p.state<>'reserved' or r.state<>'quoted' or r.version<>p_version then
    raise exception 'intent_version_conflict' using errcode='22023';
  end if;
  if r.input->>'side'<>'buy' then raise exception 'return_authorization_unavailable' using errcode='22023'; end if;
  perform public.bsmart_wallet_activity_assert(p_owner,'equity',p_id);
  t := clock_timestamp();
  if p.expires_at<=t+interval '5 seconds' then raise exception 'quote_expired' using errcode='22023'; end if;
  update public.bsmart_equity_preparations set state='authorized',signature=p_signature,
    authorization_hash=p_authorization_hash,authorized_at=t where intent_id=p_id returning * into p;
  insert into public.bsmart_equity_legs(intent_id,account_id,kind,source_network,destination_network,request_hash,provider,provider_id)
    values(p_id,p_account,'order',p.network,p.network,p.preparation_hash,'cow',p.order_uid);
  update public.bsmart_equity_intents set state='authorized',version=version+1,updated_at=t where id=p_id;
  return p;
end;
$$;

-- Defense in depth: installing an authorized order leg cannot enable execution.
create function public.bsmart_equity_execution_closed()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.attempts<>0 or new.state<>'reserved' then
    raise exception 'equity_execution_disabled' using errcode='22023';
  end if;
  return new;
end;
$$;
create trigger bsmart_equity_execution_closed before insert or update on public.bsmart_equity_legs
  for each row execute function public.bsmart_equity_execution_closed();

revoke all on function public.bsmart_wallet_activity_assert(text,text,uuid),public.bsmart_withdrawal_activity_guard(),
  public.bsmart_equity_preparation_guard(),public.bsmart_equity_prepared_intent_guard(),public.bsmart_equity_execution_closed(),
  public.bsmart_equity_prepare(uuid,uuid,text,integer,jsonb,jsonb,jsonb,text),
  public.bsmart_equity_authorize_prepared(uuid,uuid,text,integer,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.bsmart_equity_prepare(uuid,uuid,text,integer,jsonb,jsonb,jsonb,text),
  public.bsmart_equity_authorize_prepared(uuid,uuid,text,integer,text,text,text) to service_role;
commit;
