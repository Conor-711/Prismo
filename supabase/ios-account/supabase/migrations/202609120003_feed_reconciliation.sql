-- Run manually in the iOS account project after 202609120002_trade_feed.sql.
begin;
alter table public.bsmart_feed_orders
  add column verification_attempts integer not null default 0,
  add column next_check_at timestamptz not null default now(),
  add column verification_state text not null default 'pending'
    check (verification_state in ('pending', 'verified', 'expired'));
update public.bsmart_feed_orders set verification_state = 'verified' where execution is not null;
create index bsmart_feed_due on public.bsmart_feed_orders(next_check_at) where verification_state = 'pending';

create function public.bsmart_feed_claim(p_account uuid, p_cloid text, p_limit integer)
returns setof public.bsmart_feed_orders language plpgsql security invoker set search_path = '' as $$
begin
  update public.bsmart_feed_orders set verification_state = 'expired'
    where verification_state = 'pending' and registered_at < now() - interval '7 days'
      and (p_account is null or account_id = p_account);
  return query with candidates as (
    select o.id from public.bsmart_feed_orders o
    join public.bsmart_wallets w on w.account_id = o.account_id and w.address = o.wallet
    where o.execution is null and o.verification_state = 'pending' and o.next_check_at <= now()
      and (p_account is null or o.account_id = p_account) and (p_cloid is null or o.cloid = p_cloid)
    order by o.next_check_at, o.registered_at
    limit greatest(1, least(p_limit, 5)) for update of o skip locked
  ) update public.bsmart_feed_orders o set checked_at = clock_timestamp(),
      next_check_at = clock_timestamp() + interval '120 seconds',
      verification_attempts = verification_attempts + 1
    from candidates c where o.id = c.id returning o.*;
end;
$$;
revoke all on function public.bsmart_feed_claim(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.bsmart_feed_claim(uuid, text, integer) to service_role;

-- Opinion counts include all scored authors; the discovery Feed remains Top 25%.
create or replace function public.bsmart_feed_page(p_offset integer, p_limit integer, p_profile uuid default null)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with selected as (
    select o.id, o.opinion, o.execution, o.executed_at, p.public_id, p.nickname, p.avatar_url
    from public.bsmart_feed_orders o join public.bsmart_feed_profiles p using(account_id)
    where p.visible and p.feed_visible and o.execution is not null
      and (o.opinion->>'platformPercentile')::numeric between 0 and 0.25
      and (p_profile is null or p.public_id = p_profile)
    order by o.executed_at desc, o.id limit greatest(1, least(p_limit, 50)) + 1 offset greatest(p_offset, 0)
  ), page as (select * from selected order by executed_at desc, id limit greatest(1, least(p_limit, 50)))
  select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object(
    'id', id, 'trader', jsonb_build_object('id', public_id, 'nickname', nickname, 'avatarURL', avatar_url),
    'opinion', opinion, 'side', execution->>'side', 'notionalUSD', execution->>'notionalUSD',
    'marketCoin', execution->>'marketCoin', 'executedAt', executed_at
  ) order by executed_at desc, id) from page), '[]'::jsonb),
    'nextOffset', case when (select count(*) from selected) > p_limit
      then p_offset + (select count(*) from page) else null end);
$$;

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
-- Only a digest comparison is exposed to the service, never the worker secret.
do $$ begin
  if not exists(select 1 from vault.secrets where name = 'bsmart_feed_worker_token') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'bsmart_feed_worker_token');
  end if;
end $$;
create function public.bsmart_feed_worker_authorized(p_token text)
returns boolean language sql security definer set search_path = '' as $$
  select length(p_token) = 64 and exists (
    select 1 from vault.decrypted_secrets where name = 'bsmart_feed_worker_token'
      and extensions.digest(decrypted_secret, 'sha256') = extensions.digest(p_token, 'sha256')
  );
$$;
create function public.bsmart_feed_run_worker()
returns bigint language sql security definer set search_path = '' as $$
  select net.http_post(
    url := 'https://dzyitinagewdfkzjkuiz.supabase.co/functions/v1/bsmart-feed/reconcile',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'bsmart_feed_worker_token')),
    body := '{}'::jsonb, timeout_milliseconds := 110000
  );
$$;
revoke all on function public.bsmart_feed_worker_authorized(text) from public, anon, authenticated;
revoke all on function public.bsmart_feed_run_worker() from public, anon, authenticated;
grant execute on function public.bsmart_feed_worker_authorized(text) to service_role;
grant execute on function public.bsmart_feed_run_worker() to service_role;
select cron.schedule('bsmart-feed-reconcile', '* * * * *', 'select public.bsmart_feed_run_worker();');

create function public.bsmart_feed_status()
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object('registered', count(*), 'verified', count(*) filter(where execution is not null),
    'pending', count(*) filter(where verification_state = 'pending'),
    'expired', count(*) filter(where verification_state = 'expired'),
    'scheduled', exists(select 1 from cron.job where jobname = 'bsmart-feed-reconcile' and active))
  from public.bsmart_feed_orders;
$$;
revoke all on function public.bsmart_feed_status() from public, anon, authenticated;
grant execute on function public.bsmart_feed_status() to service_role;
commit;
