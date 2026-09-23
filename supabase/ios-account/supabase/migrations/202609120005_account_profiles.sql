-- Manually apply to the iOS account project after 004. Historical table name retained.
begin;
alter table public.bsmart_feed_profiles
  add column handle text not null default ('u_' || substr(replace(gen_random_uuid()::text,'-',''),1,20)),
  add column bio text not null default '',
  add column revision integer not null default 0,
  alter column nickname set default 'bSmart Investor',
  add constraint bsmart_profile_handle_format check(handle ~ '^[a-z][a-z0-9_]{2,23}$'),
  add constraint bsmart_profile_bio_length check(char_length(bio) <= 120),
  add constraint bsmart_profile_handle_unique unique(handle);

create function public.bsmart_profile_ensure(p_account uuid)
returns public.bsmart_feed_profiles language plpgsql security invoker set search_path = '' as $$
declare result public.bsmart_feed_profiles;
begin
  insert into public.bsmart_feed_profiles(account_id) values(p_account) on conflict(account_id) do nothing;
  select * into strict result from public.bsmart_feed_profiles where account_id=p_account;
  return result;
end;
$$;
revoke all on function public.bsmart_profile_ensure(uuid) from public, anon, authenticated;
grant execute on function public.bsmart_profile_ensure(uuid) to service_role;

create function public.bsmart_profile_on_signup()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.bsmart_feed_profiles(account_id) values(new.id) on conflict(account_id) do nothing;
  return new;
end;
$$;
revoke all on function public.bsmart_profile_on_signup() from public, anon, authenticated;
create trigger bsmart_profile_signup after insert on auth.users
for each row execute function public.bsmart_profile_on_signup();
insert into public.bsmart_feed_profiles(account_id) select id from auth.users on conflict(account_id) do nothing;

-- Avatar replacement/account deletion enqueue private objects for Storage API removal.
create table public.bsmart_profile_avatar_cleanup(path text primary key, created_at timestamptz not null default now());
alter table public.bsmart_profile_avatar_cleanup enable row level security;
revoke all on public.bsmart_profile_avatar_cleanup from anon, authenticated;
grant select, insert, delete on public.bsmart_profile_avatar_cleanup to service_role;
create function public.bsmart_profile_old_avatar()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.avatar_url like 'storage:%' and (tg_op='DELETE' or old.avatar_url is distinct from new.avatar_url) then
    insert into public.bsmart_profile_avatar_cleanup(path) values(substr(old.avatar_url,9)) on conflict do nothing;
  end if;
  return null;
end;
$$;
revoke all on function public.bsmart_profile_old_avatar() from public, anon, authenticated;
create trigger bsmart_profile_avatar_cleanup after update of avatar_url or delete on public.bsmart_feed_profiles
for each row execute function public.bsmart_profile_old_avatar();

create or replace function public.bsmart_feed_page(p_offset integer, p_limit integer, p_profile uuid default null)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with selected as (
    select o.id, o.opinion, o.execution, o.executed_at, p.public_id, p.nickname, p.handle, p.avatar_url
    from public.bsmart_feed_orders o join public.bsmart_feed_profiles p using(account_id)
    where p.visible and p.feed_visible and o.execution is not null
      and (o.opinion->>'platformPercentile')::numeric between 0 and 0.25
      and (p_profile is null or p.public_id = p_profile)
    order by o.executed_at desc, o.id limit greatest(1, least(p_limit, 50)) + 1 offset greatest(p_offset, 0)
  ), page as (select * from selected order by executed_at desc, id limit greatest(1, least(p_limit, 50)))
  select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object(
    'id', id, 'trader', jsonb_build_object('id', public_id, 'nickname', nickname, 'handle', handle, 'avatarURL', avatar_url),
    'opinion', opinion, 'side', execution->>'side', 'notionalUSD', execution->>'notionalUSD',
    'marketCoin', execution->>'marketCoin', 'executedAt', executed_at
  ) order by executed_at desc, id) from page), '[]'::jsonb),
    'nextOffset', case when (select count(*) from selected) > p_limit
      then p_offset + (select count(*) from page) else null end);
$$;

create or replace function public.bsmart_opinion_traders(p_opinion uuid, p_offset integer, p_limit integer)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with ranked as (
    select o.*, row_number() over(partition by account_id order by last_filled_at desc, id) as rank
    from public.bsmart_feed_orders o where opinion_id = p_opinion and execution is not null
  ), visible as (
    select p.public_id, p.nickname, p.handle, p.avatar_url, o.execution->>'side' as side, o.last_filled_at
    from ranked o join public.bsmart_feed_profiles p using(account_id) where rank = 1 and p.visible
  ), page as (
    select * from visible order by last_filled_at desc, public_id
    limit greatest(1, least(p_limit, 50)) offset greatest(p_offset, 0)
  ) select jsonb_build_object(
    'totalTraders', (select count(*) from ranked where rank = 1),
    'longTraders', (select count(*) from ranked where rank = 1 and execution->>'side' = 'long'),
    'shortTraders', (select count(*) from ranked where rank = 1 and execution->>'side' = 'short'),
    'publicTraders', (select count(*) from visible),
    'nextOffset', case when p_offset + (select count(*) from page) < (select count(*) from visible)
      then p_offset + (select count(*) from page) else null end,
    'traders', coalesce((select jsonb_agg(jsonb_build_object('id', public_id, 'nickname', nickname, 'handle', handle,
      'avatarURL', avatar_url, 'side', side, 'tradedAt', last_filled_at)
      order by last_filled_at desc, public_id) from page), '[]'::jsonb));
$$;
commit;
