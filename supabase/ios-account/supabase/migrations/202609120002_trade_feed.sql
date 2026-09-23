-- Operator-reviewed migration. Never executed by the mobile client.
create table public.bsmart_feed_profiles (
  account_id uuid primary key references auth.users(id) on delete cascade,
  public_id uuid not null default gen_random_uuid() unique,
  nickname text not null check (char_length(nickname) between 1 and 28),
  avatar_url text,
  visible boolean not null default false,
  feed_visible boolean not null default false,
  updated_at timestamptz not null default now(),
  check (not feed_visible or visible)
);
create table public.bsmart_feed_orders (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references auth.users(id) on delete cascade,
  wallet text not null,
  cloid text not null unique,
  opinion_id uuid not null,
  intent jsonb not null,
  opinion jsonb not null,
  registered_at timestamptz not null default clock_timestamp(),
  checked_at timestamptz,
  execution jsonb,
  executed_at timestamptz,
  last_filled_at timestamptz,
  unique(wallet, cloid)
);
create index bsmart_feed_pending on public.bsmart_feed_orders(account_id, checked_at) where execution is null;
create index bsmart_feed_time on public.bsmart_feed_orders(executed_at desc, id);
create index bsmart_feed_opinion on public.bsmart_feed_orders(opinion_id, account_id);
alter table public.bsmart_feed_profiles enable row level security;
alter table public.bsmart_feed_orders enable row level security;
revoke all on public.bsmart_feed_profiles, public.bsmart_feed_orders from anon, authenticated;
grant select, insert, update, delete on public.bsmart_feed_profiles, public.bsmart_feed_orders to service_role;

create function public.bsmart_feed_page(p_offset integer, p_limit integer, p_profile uuid default null)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with selected as (
    select o.id, o.opinion, o.execution, o.executed_at, p.public_id, p.nickname, p.avatar_url
    from public.bsmart_feed_orders o join public.bsmart_feed_profiles p using(account_id)
    where p.visible and p.feed_visible and o.execution is not null
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

create function public.bsmart_opinion_traders(p_opinion uuid, p_offset integer, p_limit integer)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with ranked as (
    select o.*, row_number() over(partition by account_id order by last_filled_at desc, id) as rank
    from public.bsmart_feed_orders o where opinion_id = p_opinion and execution is not null
  ), visible as (
    select p.public_id, p.nickname, p.avatar_url, o.execution->>'side' as side, o.last_filled_at
    from ranked o join public.bsmart_feed_profiles p using(account_id) where rank = 1 and p.visible
  ), page as (
    select * from visible order by last_filled_at desc, public_id
    limit greatest(1, least(p_limit, 50)) offset greatest(p_offset, 0)
  ) select jsonb_build_object(
    'totalTraders', (select count(*) from ranked where rank = 1),
    'publicTraders', (select count(*) from visible),
    'nextOffset', case when p_offset + (select count(*) from page) < (select count(*) from visible)
      then p_offset + (select count(*) from page) else null end,
    'traders', coalesce((select jsonb_agg(jsonb_build_object('id', public_id, 'nickname', nickname,
      'avatarURL', avatar_url, 'side', side, 'tradedAt', last_filled_at)
      order by last_filled_at desc, public_id) from page), '[]'::jsonb));
$$;
revoke all on function public.bsmart_feed_page(integer, integer, uuid) from public, anon, authenticated;
revoke all on function public.bsmart_opinion_traders(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.bsmart_feed_page(integer, integer, uuid) to service_role;
grant execute on function public.bsmart_opinion_traders(uuid, integer, integer) to service_role;
