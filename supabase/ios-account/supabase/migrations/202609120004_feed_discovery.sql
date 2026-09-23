-- Apply manually in the iOS account project. Aggregate verified fills only.
begin;
create or replace function public.bsmart_opinion_traders(p_opinion uuid, p_offset integer, p_limit integer)
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
    'longTraders', (select count(*) from ranked where rank = 1 and execution->>'side' = 'long'),
    'shortTraders', (select count(*) from ranked where rank = 1 and execution->>'side' = 'short'),
    'publicTraders', (select count(*) from visible),
    'nextOffset', case when p_offset + (select count(*) from page) < (select count(*) from visible)
      then p_offset + (select count(*) from page) else null end,
    'traders', coalesce((select jsonb_agg(jsonb_build_object('id', public_id, 'nickname', nickname,
      'avatarURL', avatar_url, 'side', side, 'tradedAt', last_filled_at)
      order by last_filled_at desc, public_id) from page), '[]'::jsonb));
$$;

create or replace function public.bsmart_feed_popular(p_offset integer, p_limit integer)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with latest as (
    select distinct on (opinion_id, account_id) opinion_id, account_id, opinion, execution, last_filled_at, id
    from public.bsmart_feed_orders
    where execution is not null and last_filled_at >= now() - interval '7 days'
      and last_filled_at <= now()
    order by opinion_id, account_id, last_filled_at desc, id
  ), totals as (
    select opinion_id, count(*) as total,
      count(*) filter(where execution->>'side' = 'long') as longs,
      count(*) filter(where execution->>'side' = 'short') as shorts,
      max(last_filled_at) as last_trade
    from latest group by opinion_id
  ), snapshots as (
    select distinct on (opinion_id) opinion_id, opinion
    from latest order by opinion_id, last_filled_at desc, id
  ), selected as (
    select t.*, s.opinion from totals t join snapshots s using(opinion_id)
    where (s.opinion->>'platformPercentile')::numeric between 0 and 0.25
    order by total desc, last_trade desc, opinion_id
    limit greatest(1, least(p_limit, 30)) + 1 offset greatest(p_offset, 0)
  ), page as (
    select * from selected order by total desc, last_trade desc, opinion_id
    limit greatest(1, least(p_limit, 30))
  ) select jsonb_build_object('windowDays', 7,
    'items', coalesce((select jsonb_agg(jsonb_build_object('opinion', opinion,
      'totalTraders', total, 'longTraders', longs, 'shortTraders', shorts)
      order by total desc, last_trade desc, opinion_id) from page), '[]'::jsonb),
    'nextOffset', case when (select count(*) from selected) > greatest(1, least(p_limit, 30))
      then greatest(p_offset, 0) + (select count(*) from page) else null end);
$$;
revoke all on function public.bsmart_feed_popular(integer, integer) from public, anon, authenticated;
grant execute on function public.bsmart_feed_popular(integer, integer) to service_role;
commit;
