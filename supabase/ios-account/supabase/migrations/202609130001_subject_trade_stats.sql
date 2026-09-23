-- Apply manually in the iOS account project after 005. No order/fund writes.
begin;
create index if not exists bsmart_feed_subject_verified
on public.bsmart_feed_orders (
  (coalesce(opinion->>'sourceKind', 'account')), (opinion->>'authorId'),
  (opinion->>'platform'), opinion_id, account_id, last_filled_at desc
) where execution is not null;

create or replace function public.bsmart_subject_trade_stats(p_kind text, p_subject text, p_platform text)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with latest as (
    select distinct on (opinion_id, account_id) opinion_id, account_id, execution
    from public.bsmart_feed_orders
    where execution is not null
      and coalesce(opinion->>'sourceKind', 'account') = p_kind
      and opinion->>'authorId' = p_subject and opinion->>'platform' = p_platform
    order by opinion_id, account_id, last_filled_at desc, id
  ) select jsonb_build_object(
    'kind', p_kind, 'subjectId', p_subject, 'platform', p_platform,
    'totalTrades', count(*),
    'longTrades', count(*) filter (where execution->>'side' = 'long'),
    'shortTrades', count(*) filter (where execution->>'side' = 'short'),
    'sourceCount', count(distinct opinion_id)
  ) from latest;
$$;
revoke all on function public.bsmart_subject_trade_stats(text, text, text) from public, anon, authenticated;
grant execute on function public.bsmart_subject_trade_stats(text, text, text) to service_role;
commit;
