-- Prepared migration only. No execution workers or authorization RPC are enabled here.
begin;

create table public.bsmart_equity_intents (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references auth.users(id) on delete cascade,
  client_intent_id uuid not null,
  wallet_address text not null check(wallet_address ~ '^0x[0-9a-f]{40}$' and wallet_address <> '0x0000000000000000000000000000000000000000'),
  request_hash text not null check(request_hash ~ '^[0-9a-f]{64}$'),
  input jsonb not null check(jsonb_typeof(input)='object'),
  state text not null default 'draft' check(state in ('draft','quoted','authorized','funding_pending','funded',
    'order_pending','filled','return_pending','completed','expired','rejected','cancelled','refund_pending','needs_reconciliation')),
  version integer not null default 0 check(version between 0 and 2147483646),
  preview jsonb,
  quote_expires_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(account_id,client_intent_id),
  unique(id,account_id),
  check((preview is null) = (quote_expires_at is null)),
  check(state <> 'quoted' or preview is not null)
);
create index bsmart_equity_intent_history on public.bsmart_equity_intents(account_id,created_at desc);

create table public.bsmart_equity_legs (
  id uuid primary key default gen_random_uuid(),
  intent_id uuid not null,
  account_id uuid not null,
  kind text not null check(kind in ('funding','approval','order','return')),
  leg_index smallint not null default 0 check(leg_index between 0 and 1),
  source_network text not null check(source_network in ('Ethereum','Ink','Arbitrum','HyperCore')),
  destination_network text not null check(destination_network in ('Ethereum','Ink','Arbitrum','HyperCore')),
  request_hash text not null check(request_hash ~ '^[0-9a-f]{64}$'),
  provider text not null check(provider in ('cow','across','relay','wallet')),
  provider_id text not null check(length(provider_id) between 1 and 256 and provider_id ~ '^[A-Za-z0-9:_-]+$'),
  state text not null default 'reserved' check(state in ('reserved','submitting','submitted','unknown','confirmed','failed')),
  attempts integer not null default 0 check(attempts between 0 and 1),
  version integer not null default 0 check(version between 0 and 2147483646),
  lease_id uuid,
  leased_until timestamptz,
  evidence_hash text check(evidence_hash ~ '^[0-9a-f]{64}$'),
  checked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  foreign key(intent_id,account_id) references public.bsmart_equity_intents(id,account_id) on delete cascade,
  unique(intent_id,kind,leg_index),
  unique(provider,source_network,provider_id),
  check((kind='order' and provider='cow' and leg_index=0 and source_network=destination_network and source_network in ('Ethereum','Ink')) or
        (kind='approval' and provider='wallet' and leg_index=0 and source_network=destination_network and source_network in ('Ethereum','Ink')) or
        (kind in ('funding','return') and provider in ('across','relay'))),
  check((attempts=0 and state='reserved' and lease_id is null and leased_until is null) or
        (attempts=1 and state<>'reserved' and lease_id is not null and leased_until is not null)),
  check(state not in ('confirmed','failed') or (evidence_hash is not null and checked_at is not null))
);

alter table public.bsmart_equity_intents enable row level security;
alter table public.bsmart_equity_legs enable row level security;
revoke all on public.bsmart_equity_intents, public.bsmart_equity_legs from public,anon,authenticated,service_role;
grant select on public.bsmart_equity_intents to authenticated,service_role;
grant select on public.bsmart_equity_legs to service_role;
grant select(id,intent_id,account_id,kind,leg_index,source_network,destination_network,state,provider,provider_id,attempts,checked_at)
  on public.bsmart_equity_legs to authenticated;
create policy bsmart_equity_intents_owner_read on public.bsmart_equity_intents for select to authenticated
  using(account_id=(select auth.uid()));
create policy bsmart_equity_legs_owner_read on public.bsmart_equity_legs for select to authenticated
  using(account_id=(select auth.uid()));

create function public.bsmart_equity_intent_create(p_account uuid,p_owner text,p_client_id uuid,p_input jsonb,p_hash text)
returns public.bsmart_equity_intents language plpgsql security definer set search_path='' as $$
declare r public.bsmart_equity_intents;
begin
  if p_account is null or p_owner is null or p_client_id is null or p_hash is null or p_hash !~ '^[0-9a-f]{64}$'
    or p_input is null or jsonb_typeof(p_input)<>'object'
    or not (p_input ?& array['ticker','side','amount','slippageBps','maxNetworkFeeBps'])
    or p_input - array['ticker','side','amount','slippageBps','maxNetworkFeeBps','minimumOutput'] <> '{}'::jsonb
    or jsonb_typeof(p_input->'ticker') <> 'string' or (p_input->>'ticker') !~ '^[A-Z][A-Z0-9.-]{0,15}$'
    or jsonb_typeof(p_input->'side') <> 'string' or (p_input->>'side') not in ('buy','sell')
    or jsonb_typeof(p_input->'amount') <> 'string'
    or (p_input->>'amount') !~ '^(0|[1-9][0-9]{0,20})(\.[0-9]{1,18})?$'
    or jsonb_typeof(p_input->'slippageBps') <> 'number' or (p_input->>'slippageBps') !~ '^[0-9]{1,4}$'
    or jsonb_typeof(p_input->'maxNetworkFeeBps') <> 'number' or (p_input->>'maxNetworkFeeBps') !~ '^[0-9]{1,4}$'
    or (p_input ? 'minimumOutput' and (jsonb_typeof(p_input->'minimumOutput') <> 'string' or
      (p_input->>'minimumOutput') !~ '^(0|[1-9][0-9]{0,20})(\.[0-9]{1,18})?$')) then
    raise exception 'invalid_intent' using errcode='22023';
  end if;
  if (p_input->>'amount')::numeric <= 0 or (p_input->>'slippageBps')::integer > 1000
    or (p_input->>'maxNetworkFeeBps')::integer > 1000
    or ((p_input->>'side')='buy' and (p_input->>'amount')::numeric > 100000)
    or (p_input ? 'minimumOutput' and (p_input->>'minimumOutput')::numeric <= 0) then
    raise exception 'invalid_intent' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_account::text,773));
  perform 1 from public.bsmart_wallets where account_id=p_account and address=p_owner for share;
  if not found then raise exception 'wallet_changed' using errcode='22023'; end if;
  select * into r from public.bsmart_equity_intents where account_id=p_account and client_intent_id=p_client_id;
  if found then
    if r.wallet_address<>p_owner or r.request_hash<>p_hash or r.input<>p_input then
      raise exception 'intent_idempotency_conflict' using errcode='22023';
    end if;
    return r;
  end if;
  if (select count(*) from public.bsmart_equity_intents where account_id=p_account and state not in
    ('completed','expired','rejected','cancelled')) >= 20 then
    raise exception 'intent_limit' using errcode='22023';
  end if;
  insert into public.bsmart_equity_intents(account_id,client_intent_id,wallet_address,input,request_hash)
    values(p_account,p_client_id,p_owner,p_input,p_hash) returning * into r;
  return r;
end;
$$;

create function public.bsmart_equity_intent_change(p_account uuid,p_id uuid,p_owner text,p_version integer,p_action text,p_preview jsonb default null)
returns public.bsmart_equity_intents language plpgsql security definer set search_path='' as $$
declare r public.bsmart_equity_intents; c jsonb; expires timestamptz; observed timestamptz;
  earliest timestamptz; t timestamptz := clock_timestamp();
begin
  if p_account is null or p_id is null or p_owner is null or p_version is null or p_version<0
    or p_version>2147483646 or p_action is null or p_action not in ('quote','cancel') then
    raise exception 'invalid_intent' using errcode='22023';
  end if;
  select * into r from public.bsmart_equity_intents where id=p_id and account_id=p_account for update;
  if not found then raise exception 'intent_not_found' using errcode='22023'; end if;
  -- Cancellation remains available after a wallet problem; it cannot move funds.
  if p_action='quote' then
    perform 1 from public.bsmart_wallets where account_id=p_account and address=p_owner for share;
    if not found or r.wallet_address<>p_owner then raise exception 'wallet_changed' using errcode='22023'; end if;
  elsif r.wallet_address<>p_owner then raise exception 'wallet_changed' using errcode='22023'; end if;
  if r.state='cancelled' and p_action='cancel' and p_preview is null and p_version in (r.version,r.version-1) then return r; end if;
  if r.state='quoted' and p_action='quote' and r.version=p_version+1 and r.preview=p_preview then return r; end if;
  if r.version<>p_version then raise exception 'intent_version_conflict' using errcode='22023'; end if;
  if r.state not in ('draft','quoted') then raise exception 'intent_state_conflict' using errcode='22023'; end if;
  if r.version>=2147483646 then raise exception 'intent_version_conflict' using errcode='22023'; end if;
  if exists(select 1 from public.bsmart_equity_legs where intent_id=p_id) then
    raise exception 'intent_state_conflict' using errcode='22023';
  end if;
  if p_action='cancel' then
    if p_preview is not null then raise exception 'invalid_intent' using errcode='22023'; end if;
    update public.bsmart_equity_intents set state='cancelled',version=version+1,updated_at=t where id=p_id returning * into r;
    return r;
  end if;
  if p_preview is null or jsonb_typeof(p_preview)<>'object'
    or (p_preview->'executionEnabled') is distinct from 'false'::jsonb
    or (p_preview->'returnTransferImplemented') is distinct from 'false'::jsonb
    or (p_preview->>'gasCoverage') is distinct from 'unverified'
    or (p_preview->>'defaultSaleProceedsDestination') is distinct from 'hyperliquid_perps'
    or (p_preview->>'ticker') is distinct from (r.input->>'ticker')
    or (p_preview->>'side') is distinct from (r.input->>'side')
    or jsonb_typeof(p_preview->'candidates') is distinct from 'array' then
    raise exception 'invalid_saved_preview' using errcode='22023';
  end if;
  if jsonb_array_length(p_preview->'candidates') not between 1 and 2 or pg_column_size(p_preview)>16384 then
    raise exception 'invalid_saved_preview' using errcode='22023';
  end if;
  for c in select value from jsonb_array_elements(p_preview->'candidates') loop
    if (c->>'owner') is distinct from p_owner or (c->>'receiver') is distinct from p_owner
      or (c->'executable') is distinct from 'false'::jsonb
      or (c->>'fingerprint') is null or (c->>'fingerprint') !~ '^[0-9a-f]{64}$'
      or (c->>'expiresAt') is null or (c->>'observedAt') is null then
      raise exception 'invalid_saved_preview' using errcode='22023';
    end if;
    expires := (c->>'expiresAt')::timestamptz; observed := (c->>'observedAt')::timestamptz;
    if expires<=t+interval '5 seconds' or expires>t+interval '10 minutes' or observed>t or observed<=t-interval '30 seconds' then
      raise exception 'invalid_saved_preview' using errcode='22023';
    end if;
    earliest := least(earliest,expires);
  end loop;
  update public.bsmart_equity_intents set state='quoted',version=version+1,preview=p_preview,
    quote_expires_at=earliest,updated_at=t where id=p_id returning * into r;
  return r;
end;
$$;

-- Legs must be installed by a future verified-authorization transaction. P3 exposes
-- no insert/authorize RPC, so the following service-only primitives cannot trade.
create function public.bsmart_equity_leg_claim(p_id uuid,p_version integer)
returns public.bsmart_equity_legs language plpgsql security definer set search_path='' as $$
declare l public.bsmart_equity_legs; r public.bsmart_equity_intents; t timestamptz:=clock_timestamp();
begin
  if p_id is null or p_version is null or p_version<0 then raise exception 'invalid_leg' using errcode='22023'; end if;
  select i.* into r from public.bsmart_equity_intents i join public.bsmart_equity_legs e on e.intent_id=i.id
    where e.id=p_id for update of i;
  if not found then raise exception 'leg_not_found' using errcode='22023'; end if;
  select * into l from public.bsmart_equity_legs where id=p_id for update;
  if l.version<>p_version then raise exception 'leg_version_conflict' using errcode='22023'; end if;
  if l.version>=2147483646 then raise exception 'leg_version_conflict' using errcode='22023'; end if;
  if l.state<>'reserved' or l.attempts<>0 then raise exception 'leg_already_attempted' using errcode='22023'; end if;
  if (l.kind='funding' and r.state<>'funding_pending') or (l.kind='order' and r.state<>'order_pending')
    or (l.kind='return' and (r.state<>'return_pending' or r.input->>'side'<>'sell'))
    or (l.kind='approval' and r.state not in ('authorized','funded')) then
    raise exception 'intent_state_conflict' using errcode='22023';
  end if;
  if l.leg_index=1 and not exists(select 1 from public.bsmart_equity_legs where intent_id=l.intent_id
    and kind=l.kind and leg_index=0 and state='confirmed' and destination_network=l.source_network) then
    raise exception 'leg_dependency_pending' using errcode='22023';
  end if;
  if l.kind='order' and exists(select 1 from public.bsmart_equity_legs where intent_id=l.intent_id
    and kind in ('funding','approval') and state<>'confirmed') then
    raise exception 'leg_dependency_pending' using errcode='22023';
  end if;
  if l.kind='return' and not exists(select 1 from public.bsmart_equity_legs where intent_id=l.intent_id
    and kind='order' and state='confirmed') then
    raise exception 'leg_dependency_pending' using errcode='22023';
  end if;
  if l.kind in ('order','approval') and (r.quote_expires_at is null or r.quote_expires_at<=t+interval '5 seconds') then
    raise exception 'quote_expired' using errcode='22023';
  end if;
  perform 1 from public.bsmart_wallets where account_id=r.account_id and address=r.wallet_address for share;
  if not found then raise exception 'wallet_changed' using errcode='22023'; end if;
  update public.bsmart_equity_legs set state='submitting',attempts=1,version=version+1,
    lease_id=gen_random_uuid(),leased_until=t+interval '60 seconds' where id=p_id returning * into l;
  return l;
end;
$$;

create function public.bsmart_equity_leg_observe(p_id uuid,p_version integer,p_state text,p_evidence_hash text)
returns public.bsmart_equity_legs language plpgsql security definer set search_path='' as $$
declare l public.bsmart_equity_legs;
begin
  if p_id is null or p_version is null or p_version<0 or p_state is null
    or p_state not in ('submitted','unknown','confirmed','failed') or p_evidence_hash is null
    or p_evidence_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_leg' using errcode='22023'; end if;
  select * into l from public.bsmart_equity_legs where id=p_id for update;
  if not found then raise exception 'leg_not_found' using errcode='22023'; end if;
  if l.version<>p_version then
    if l.version=p_version+1 and l.state=p_state and l.evidence_hash=p_evidence_hash then return l; end if;
    raise exception 'leg_version_conflict' using errcode='22023';
  end if;
  if l.attempts<>1 or l.state not in ('submitting','submitted','unknown') then
    raise exception 'leg_state_conflict' using errcode='22023';
  end if;
  if l.version>=2147483646 then raise exception 'leg_version_conflict' using errcode='22023'; end if;
  if p_state='unknown' and l.state='submitting' and l.leased_until>clock_timestamp() then
    raise exception 'leg_lease_active' using errcode='22023';
  end if;
  update public.bsmart_equity_legs set state=p_state,version=version+1,evidence_hash=p_evidence_hash,
    checked_at=clock_timestamp() where id=p_id returning * into l;
  return l;
end;
$$;

revoke all on function public.bsmart_equity_intent_create(uuid,text,uuid,jsonb,text),
  public.bsmart_equity_intent_change(uuid,uuid,text,integer,text,jsonb),
  public.bsmart_equity_leg_claim(uuid,integer),public.bsmart_equity_leg_observe(uuid,integer,text,text)
  from public,anon,authenticated;
grant execute on function public.bsmart_equity_intent_create(uuid,text,uuid,jsonb,text),
  public.bsmart_equity_intent_change(uuid,uuid,text,integer,text,jsonb),
  public.bsmart_equity_leg_claim(uuid,integer),public.bsmart_equity_leg_observe(uuid,integer,text,text) to service_role;
commit;
