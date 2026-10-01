-- User-applied migration. No public signing endpoint or execution is enabled.
begin;
alter table public.bsmart_equity_preparations add column signing_started_at timestamptz;
alter table public.bsmart_equity_preparations drop constraint bsmart_equity_preparations_state_check;
alter table public.bsmart_equity_preparations add constraint bsmart_equity_preparations_state_check
  check(state in ('reserved','signing','authorized','released'));
alter table public.bsmart_equity_preparations drop constraint bsmart_equity_preparations_check;
alter table public.bsmart_equity_preparations add constraint bsmart_equity_preparations_check
  check((state='authorized' and signature is not null and authorization_hash is not null and authorized_at is not null)
    or (state in ('reserved','signing','released') and signature is null and authorization_hash is null and authorized_at is null));
alter table public.bsmart_equity_preparations add constraint bsmart_equity_signing_time_check
  check((state in ('reserved','released') and signing_started_at is null)
    or (state='signing' and signing_started_at is not null) or state='authorized');
drop index public.bsmart_one_equity_reservation_per_wallet;
create unique index bsmart_one_equity_reservation_per_wallet on public.bsmart_equity_preparations(wallet_address)
  where state in ('reserved','signing','authorized');

create or replace function public.bsmart_wallet_activity_assert(p_wallet text,p_table text,p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_wallet is null or p_wallet !~ '^0x[0-9a-f]{40}$' then raise exception 'wallet_changed' using errcode='22023'; end if;
  if not pg_try_advisory_xact_lock(hashtextextended(p_wallet,0)) then
    raise exception 'wallet_activity_in_progress' using errcode='23505';
  end if;
  if exists(select 1 from public.bsmart_withdrawals where wallet_address=p_wallet
      and state in ('reserved','submitting','accepted','uncertain','core_debited') and not (p_table='withdrawal' and id=p_id))
    or exists(select 1 from public.bsmart_across_withdrawals where wallet_address=p_wallet
      and state in ('quoted','submitting','submitted','uncertain','deposit_pending','expired') and not (p_table='across' and id=p_id))
    or exists(select 1 from public.bsmart_equity_preparations where wallet_address=p_wallet
      and state in ('reserved','signing','authorized') and not (p_table='equity' and intent_id=p_id))
    or exists(select 1 from public.bsmart_equity_intents where wallet_address=p_wallet
      and state in ('authorized','funding_pending','funded','order_pending','filled','return_pending','refund_pending','needs_reconciliation')
      and not (p_table='equity' and id=p_id)) then
    raise exception 'wallet_activity_in_progress' using errcode='23505';
  end if;
end;
$$;

create or replace function public.bsmart_equity_preparation_guard()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    if new.state<>'reserved' or new.signing_started_at is not null then
      raise exception 'preparation_conflict' using errcode='22023';
    end if;
  else
    if (to_jsonb(new)-array['state','signature','authorization_hash','authorized_at','signing_started_at']) <>
       (to_jsonb(old)-array['state','signature','authorization_hash','authorized_at','signing_started_at']) then
      raise exception 'preparation_conflict' using errcode='22023';
    end if;
    if old.state='reserved' and new.state='signing' then
      if new.signing_started_at is null or new.signing_started_at>clock_timestamp()
        or new.signing_started_at<clock_timestamp()-interval '1 second' then
        raise exception 'preparation_conflict' using errcode='22023';
      end if;
    elsif old.state='reserved' and new.state='released' and new.signing_started_at is null then null;
    elsif old.state='signing' and new.state='authorized' and new.signing_started_at=old.signing_started_at then null;
    else raise exception 'preparation_conflict' using errcode='22023'; end if;
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended(new.wallet_address,0)) then
    raise exception 'wallet_activity_in_progress' using errcode='23505';
  end if;
  if new.state in ('reserved','signing','authorized') then
    perform public.bsmart_wallet_activity_assert(new.wallet_address,'equity',new.intent_id);
  end if;
  return new;
end;
$$;

create or replace function public.bsmart_equity_prepared_intent_guard()
returns trigger language plpgsql security definer set search_path='' as $$
declare p public.bsmart_equity_preparations;
begin
  select * into p from public.bsmart_equity_preparations where intent_id=old.id and state in ('reserved','signing','authorized');
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

create function public.bsmart_equity_signing_start(p_account uuid,p_id uuid,p_owner text,p_version integer,p_hash text)
returns public.bsmart_equity_preparations language plpgsql security definer set search_path='' as $$
declare r public.bsmart_equity_intents; p public.bsmart_equity_preparations;
begin
  select * into r from public.bsmart_equity_intents where id=p_id and account_id=p_account for update;
  if not found then raise exception 'intent_not_found' using errcode='22023'; end if;
  perform 1 from public.bsmart_wallets where account_id=p_account and address=p_owner for share;
  if not found or r.wallet_address<>p_owner then raise exception 'wallet_changed' using errcode='22023'; end if;
  select * into p from public.bsmart_equity_preparations where intent_id=p_id for update;
  if not found or p.preparation_hash is distinct from p_hash or p.wallet_address<>p_owner
    or p.intent_version is distinct from p_version or r.version<>p_version or r.state<>'quoted'
    or p.state not in ('reserved','signing') then raise exception 'preparation_conflict' using errcode='22023'; end if;
  if r.input->>'side'<>'buy' then raise exception 'return_authorization_unavailable' using errcode='22023'; end if;
  if p.expires_at<=clock_timestamp()+interval '5 seconds' then raise exception 'quote_expired' using errcode='22023'; end if;
  perform public.bsmart_wallet_activity_assert(p_owner,'equity',p_id);
  if p.state='signing' then return p; end if;
  update public.bsmart_equity_preparations set state='signing',signing_started_at=clock_timestamp()
    where intent_id=p_id returning * into p;
  return p;
end;
$$;

-- Only the service's crypto verifier may call this. No signature HTTP path.
create or replace function public.bsmart_equity_authorize_prepared(p_account uuid,p_id uuid,p_owner text,p_version integer,
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
  if p.state<>'signing' or r.state<>'quoted' or r.version<>p_version then
    raise exception 'preparation_conflict' using errcode='22023';
  end if;
  if r.input->>'side'<>'buy' then raise exception 'return_authorization_unavailable' using errcode='22023'; end if;
  perform public.bsmart_wallet_activity_assert(p_owner,'equity',p_id);
  t:=clock_timestamp();
  if p.expires_at<=t+interval '5 seconds' then raise exception 'quote_expired' using errcode='22023'; end if;
  update public.bsmart_equity_preparations set state='authorized',signature=p_signature,
    authorization_hash=p_authorization_hash,authorized_at=t where intent_id=p_id returning * into p;
  insert into public.bsmart_equity_legs(intent_id,account_id,kind,source_network,destination_network,request_hash,provider,provider_id)
    values(p_id,p_account,'order',p.network,p.network,p.preparation_hash,'cow',p.order_uid);
  update public.bsmart_equity_intents set state='authorized',version=version+1,updated_at=t where id=p_id;
  return p;
end;
$$;
revoke all on function public.bsmart_equity_signing_start(uuid,uuid,text,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.bsmart_equity_signing_start(uuid,uuid,text,integer,text) to service_role;
-- New columns inherit no client grants; explicitly preserve the private boundary.
revoke all on public.bsmart_equity_preparations from public,anon,authenticated;
commit;
