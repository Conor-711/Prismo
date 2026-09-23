-- Apply in the iOS account project before deploying the rankings endpoint.
begin;
create index if not exists bsmart_feed_rankings_window
  on public.bsmart_feed_orders(last_filled_at desc) where execution is not null;
create or replace function public.bsmart_discovery_rankings(
  p_kind text, p_sort text, p_window text, p_as_of timestamptz, p_offset integer, p_limit integer)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
begin
  if p_kind not in ('opinions','investors') or p_sort not in ('traders','volume')
    or p_window not in ('1d','7d','30d','all') or p_as_of is null
    or p_kind is null or p_sort is null or p_window is null
    or p_offset is null or p_limit is null or p_offset < 0 or p_offset > 10000 or p_limit not between 1 and 30 then
    raise exception 'invalid_input';
  end if;
  return (
    with eligible as (
      select o.*, case when p_kind = 'opinions' then opinion_id::text
        else lower(opinion->>'platform') || ':' || (opinion->>'authorId') end as group_id,
        case when length(execution->>'notionalUSD') <= 100
          and execution->>'notionalUSD' ~ '^[0-9]+([.][0-9]+)?$'
          then (execution->>'notionalUSD')::numeric end as amount
      from public.bsmart_feed_orders o
      where execution is not null and execution->>'side' in ('long','short')
        and last_filled_at <= p_as_of
        and (p_window = 'all' or last_filled_at >= p_as_of - case p_window
          when '1d' then interval '1 day' when '7d' then interval '7 days' else interval '30 days' end)
        and coalesce(opinion->>'sourceKind','account') = 'account'
        and nullif(opinion->>'platform','') is not null
        and lower(opinion->>'platform') != 'hyperliquid'
        and nullif(opinion->>'authorId','') is not null
        and nullif(opinion->>'authorName','') is not null
        and case when jsonb_typeof(opinion->'platformPercentile') = 'number'
          then (opinion->>'platformPercentile')::numeric between 0 and 0.25 else false end
    ), totals as (
      select group_id, count(distinct account_id) as total,
        count(distinct opinion_id) as opinions,
        case when count(*) = count(*) filter (where amount > 0) then sum(amount) end as volume,
        max(last_filled_at) as last_trade
      from eligible group by group_id
    ), latest_people as (
      select distinct on (group_id, account_id) group_id, account_id, execution->>'side' as side
      from eligible order by group_id, account_id, last_filled_at desc, id
    ), sides as (
      select group_id, count(*) filter (where side = 'long') as longs,
        count(*) filter (where side = 'short') as shorts from latest_people group by group_id
    ), snapshots as (
      select distinct on (group_id) group_id, opinion from eligible order by group_id, last_filled_at desc, id
    ), ranked as (
      select t.*, s.longs, s.shorts, o.opinion,
        row_number() over (order by case when p_sort = 'volume' then volume else total end desc,
          last_trade desc, t.group_id) as rank
      from totals t join sides s using (group_id) join snapshots o using (group_id)
      where p_sort != 'volume' or volume is not null
    ), page as (
      select * from ranked order by rank limit p_limit offset p_offset
    ) select jsonb_build_object('kind',p_kind,'sort',p_sort,'window',p_window,'asOf',p_as_of,
      'items',coalesce((select jsonb_agg(jsonb_build_object(
        'id',group_id,'opinion',opinion,'totalTraders',total,'totalNotionalUSD',volume::text,
        'opinionCount',opinions,'longTraders',longs,'shortTraders',shorts,'lastTradedAt',last_trade)
        order by rank) from page),'[]'::jsonb),
      'nextOffset',case when p_offset + (select count(*) from page) < (select count(*) from ranked)
        then p_offset + (select count(*) from page) else null end)
  );
end;
$$;
revoke all on function public.bsmart_discovery_rankings(text,text,text,timestamptz,integer,integer) from public, anon, authenticated;
grant execute on function public.bsmart_discovery_rankings(text,text,text,timestamptz,integer,integer) to service_role;
commit;
