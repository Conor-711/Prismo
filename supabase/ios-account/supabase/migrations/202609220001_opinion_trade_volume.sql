begin;

create or replace function public.bsmart_opinion_traders(p_opinion uuid, p_offset integer, p_limit integer)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with ranked as (
    select o.*, row_number() over(partition by account_id order by last_filled_at desc, id) as rank
    from public.bsmart_feed_orders o where opinion_id = p_opinion and execution is not null
  ), volume as (
    select case
      when count(*) = count(*) filter (where execution->>'notionalUSD' ~ '^[0-9]+(\.[0-9]+)?$')
      then coalesce(sum(case when execution->>'notionalUSD' ~ '^[0-9]+(\.[0-9]+)?$'
        then (execution->>'notionalUSD')::numeric end), 0)::text
      else null end as total_notional_usd
    from ranked
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
    'totalNotionalUSD', (select total_notional_usd from volume),
    'publicTraders', (select count(*) from visible),
    'nextOffset', case when p_offset + (select count(*) from page) < (select count(*) from visible)
      then p_offset + (select count(*) from page) else null end,
    'traders', coalesce((select jsonb_agg(jsonb_build_object('id', public_id, 'nickname', nickname, 'handle', handle,
      'avatarURL', avatar_url, 'side', side, 'tradedAt', last_filled_at)
      order by last_filled_at desc, public_id) from page), '[]'::jsonb));
$$;

commit;
