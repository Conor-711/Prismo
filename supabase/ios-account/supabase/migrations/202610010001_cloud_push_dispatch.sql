-- Apply manually in the native iOS project dzyitinagewdfkzjkuiz.
-- Requires interest_push, pg_cron, pg_net and Vault (already used by Feed).
-- No grants to client roles; no credential contents are returned.
begin;

do $$ begin
  if not exists(select 1 from vault.secrets where name='bsmart_push_worker_token') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'bsmart_push_worker_token');
  end if;
end $$;

create table if not exists public.bsmart_push_provider_tokens (
  identity text primary key check (length(identity) between 10 and 100),
  token text not null check (length(token) between 100 and 2048),
  expires_at timestamptz not null
);
alter table public.bsmart_push_provider_tokens enable row level security;
revoke all on public.bsmart_push_provider_tokens from public,anon,authenticated,service_role;

create or replace function public.bsmart_push_provider_token(p_identity text,p_token text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cached record;
begin
  if p_identity is null or length(p_identity) not between 10 and 100 then return null; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('apns:'||p_identity,0));
  select * into cached from public.bsmart_push_provider_tokens
    where identity=p_identity and expires_at>now();
  if found then return jsonb_build_object('token',cached.token,'expires_at',cached.expires_at); end if;
  if p_token is null then return null; end if;
  if length(p_token) not between 100 and 2048 or p_token !~ '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' then
    raise exception 'Invalid provider token';
  end if;
  insert into public.bsmart_push_provider_tokens(identity,token,expires_at)
    values(p_identity,p_token,now()+interval '45 minutes')
    on conflict(identity) do update set token=excluded.token,expires_at=excluded.expires_at
    returning * into cached;
  return jsonb_build_object('token',cached.token,'expires_at',cached.expires_at);
end;
$$;

create or replace function public.bsmart_push_worker_authorized(p_token text)
returns boolean language sql security definer set search_path='' as $$
  select coalesce(length(p_token)=64 and exists(
    select 1 from vault.decrypted_secrets where name='bsmart_push_worker_token'
      and extensions.digest(decrypted_secret,'sha256')=extensions.digest(p_token,'sha256')
  ),false);
$$;

create or replace function public.bsmart_push_matches(p_device uuid,p_user uuid,p_actor text,p_ticker text,p_kind text)
returns boolean language sql security definer set search_path='' as $$
  select p_kind='opinion' and exists(select 1 from public.bsmart_push_devices d
    where d.id=p_device and d.user_id=p_user and d.enabled
      and d.environment='production' and d.updated_at>now()-interval '30 days'
      and ((d.notify_authors and lower(p_actor)=any(d.followed_author_ids))
        or (d.notify_tickers and p_ticker=any(d.followed_tickers))
        or (d.notify_holdings and p_ticker=any(d.held_tickers))));
$$;

create or replace function public.bsmart_push_prepare_slot()
returns integer language plpgsql security definer set search_path='' as $$
declare
  local_now timestamp:=now() at time zone 'Asia/Shanghai';
  slot_at_value timestamptz;
  users uuid[];
begin
  if extract(hour from local_now) not in (8,18,22) or extract(minute from local_now)>=30 then return 0; end if;
  slot_at_value:=date_trunc('hour',local_now) at time zone 'Asia/Shanghai';
  perform pg_catalog.pg_advisory_xact_lock(721534916);
  update public.bsmart_interest_push_events q set state='pending',slot_at=null
    where q.state='batched' and exists(select 1 from public.bsmart_interest_push_batches b
      where b.user_id=q.user_id and b.slot_at=q.slot_at and b.state='pending' and b.slot_at<slot_at_value);
  update public.bsmart_interest_push_batches set state='skipped' where state='pending' and slot_at<slot_at_value;
  with eligible as (
    select distinct q.user_id,q.event_kind,q.event_id,d.id as device_id,d.updated_at
    from public.bsmart_interest_push_events q join public.bsmart_push_devices d on d.user_id=q.user_id
    where q.state='pending' and q.created_at<=slot_at_value
      and public.bsmart_push_matches(d.id,q.user_id,q.actor_id,q.ticker,q.event_kind)
  ), counts as (
    select user_id,count(distinct(event_kind,event_id))::integer as item_count from eligible group by user_id
  ), preferred as (
    select distinct on(user_id) user_id,device_id from eligible order by user_id,updated_at desc,device_id
  ), inserted as (
    insert into public.bsmart_interest_push_batches(user_id,slot_at,device_id,item_count)
    select c.user_id,slot_at_value,p.device_id,c.item_count from counts c join preferred p using(user_id)
    on conflict(user_id,slot_at) do nothing returning user_id
  ) select array_agg(user_id) into users from inserted;
  if users is not null then
    update public.bsmart_interest_push_events q set state='batched',slot_at=slot_at_value
      where q.user_id=any(users) and q.state='pending' and q.created_at<=slot_at_value
        and exists(select 1 from public.bsmart_push_devices d
          where public.bsmart_push_matches(d.id,q.user_id,q.actor_id,q.ticker,q.event_kind));
  end if;
  return coalesce(cardinality(users),0);
end;
$$;

create or replace function public.bsmart_push_claim()
returns jsonb language plpgsql security definer set search_path='' as $$
declare delivery record;
begin
  -- An uncertain send is never reclaimed; limits remain one batch/user/slot.
  update public.bsmart_interest_push_batches b set state='skipped'
    where b.state='pending' and b.slot_at<=now() and b.slot_at+interval '30 minutes'>now()
      and not exists(select 1 from public.bsmart_interest_push_events q
        where q.user_id=b.user_id and q.slot_at=b.slot_at
          and public.bsmart_push_matches(b.device_id,q.user_id,q.actor_id,q.ticker,q.event_kind));
  select b.*,d.apns_token,d.locale,d.environment,d.updated_at as device_updated_at into delivery
    from public.bsmart_interest_push_batches b join public.bsmart_push_devices d on d.id=b.device_id
    where b.state='pending' and b.slot_at<=now() and b.slot_at+interval '30 minutes'>now()
      and d.user_id=b.user_id and d.enabled and d.environment='production'
      and d.updated_at>now()-interval '30 days'
    order by b.slot_at,b.user_id limit 1 for update of b skip locked;
  if not found then return null; end if;
  update public.bsmart_interest_push_batches set state='sending',attempts=1
    where user_id=delivery.user_id and slot_at=delivery.slot_at and state='pending';
  return jsonb_build_object('user_id',delivery.user_id,'slot_at',delivery.slot_at,
    'device_id',delivery.device_id,'apns_id',delivery.apns_id,'apns_token',delivery.apns_token,
    'locale',delivery.locale,'environment',delivery.environment,'item_count',delivery.item_count,
    'device_updated_at',delivery.device_updated_at);
end;
$$;

create or replace function public.bsmart_push_complete(p_user uuid,p_slot timestamptz,p_apns_id uuid,
  p_status integer,p_invalid boolean,p_registered timestamptz)
returns boolean language plpgsql security definer set search_path='' as $$
declare device uuid;
begin
  if p_status is not null and p_status not between 100 and 599 then return false; end if;
  if p_invalid is null or (p_invalid and (p_status is null or p_status not in(400,410))) then return false; end if;
  update public.bsmart_interest_push_batches set state=case when p_status=200 then 'accepted' else 'failed' end,
      last_status=p_status
    where user_id=p_user and slot_at=p_slot and apns_id=p_apns_id and state='sending'
    returning device_id into device;
  if not found then return false; end if;
  if p_invalid then
    -- Do not disable a token re-registered after this batch began.
    update public.bsmart_push_devices set enabled=false
      where id=device and user_id=p_user and environment='production' and updated_at=p_registered;
  end if;
  return true;
end;
$$;

create or replace function public.bsmart_push_run_worker()
returns bigint language sql security definer set search_path='' as $$
  select net.http_post(
    url:='https://dzyitinagewdfkzjkuiz.supabase.co/functions/v1/bsmart-push/dispatch',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization',
      'Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='bsmart_push_worker_token')),
    body:='{}'::jsonb,timeout_milliseconds:=60000);
$$;

revoke all on function public.bsmart_push_worker_authorized(text),
  public.bsmart_push_provider_token(text,text),
  public.bsmart_push_matches(uuid,uuid,text,text,text),public.bsmart_push_prepare_slot(),
  public.bsmart_push_claim(),public.bsmart_push_complete(uuid,timestamptz,uuid,integer,boolean,timestamptz),
  public.bsmart_push_run_worker() from public,anon,authenticated;
grant execute on function public.bsmart_push_worker_authorized(text),
  public.bsmart_push_provider_token(text,text),
  public.bsmart_push_prepare_slot(),public.bsmart_push_claim(),
  public.bsmart_push_complete(uuid,timestamptz,uuid,integer,boolean,timestamptz) to service_role;
-- UTC slots correspond to 08:00, 18:00, 22:00 Asia/Shanghai. No catch-up broadcast.
select cron.schedule('bsmart-content-push','0-29 0,10,14 * * *','select public.bsmart_push_run_worker();');
commit;
