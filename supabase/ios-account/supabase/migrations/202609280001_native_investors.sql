-- Apply to the iOS account project after 202609220004_trade_theses.sql.
begin;

alter table public.bsmart_feed_orders
  add column source_kind text not null default 'opinion'
    check (source_kind in ('opinion', 'direct')),
  alter column opinion_id drop not null,
  alter column opinion drop not null,
  add constraint bsmart_feed_order_source check (
    (source_kind = 'opinion' and opinion_id is not null and opinion is not null) or
    (source_kind = 'direct' and opinion_id is null and opinion is null)
  );
create index bsmart_feed_direct_closes on public.bsmart_feed_orders(account_id, executed_at desc)
  where source_kind = 'direct' and execution is not null;
create index bsmart_feed_verified_account on public.bsmart_feed_orders(account_id, executed_at desc)
  where execution is not null;

create function public.bsmart_native_trade_opinion(
  p_id uuid, p_intent jsonb, p_execution jsonb, p_executed_at timestamptz,
  p_public_id uuid, p_nickname text, p_avatar text, p_thesis text
) returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'id', p_id, 'ticker', p_intent->>'ticker',
    'companyName', p_intent->>'ticker',
    'authorId', 'bsmart:' || p_public_id::text,
    'authorName', p_nickname, 'platform', 'bsmart',
    'score', 0, 'platformPercentile', 1,
    'direction', case when p_intent->>'reduceOnly' = 'true' then 'neutral'
      when p_execution->>'side' = 'long' then 'bullish' else 'bearish' end,
    'lifecycle', case when p_intent->>'reduceOnly' = 'true' then 'closed' else 'new' end,
    'horizon', 'Live trade', 'targetPrice', null,
    'thesis', coalesce(p_thesis, ''), 'invalidation', null,
    'publishedAt', p_executed_at, 'evidenceURL', null,
    'authorAvatarURL', p_avatar, 'sourceKind', 'native_trade'
  );
$$;

create or replace function public.bsmart_thesis_publish(p_actor uuid, p_trade uuid, p_body text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare o public.bsmart_feed_orders; existing text;
begin
  if p_body is null or char_length(p_body) not between 1 and 1000 or p_body !~ '[^[:space:]]'
    or p_body ~ '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]' then
    return jsonb_build_object('error', 'invalid_input');
  end if;
  select * into o from public.bsmart_feed_orders where id = p_trade and account_id = p_actor for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if o.execution is null or o.executed_at is null then return jsonb_build_object('error', 'trade_pending'); end if;
  if o.source_kind = 'opinion' and (
    coalesce(o.opinion->>'sourceKind', 'account') <> 'account' or
    not coalesce((o.opinion->>'platformPercentile')::numeric between 0 and 1, false)
  ) then return jsonb_build_object('error', 'invalid_input'); end if;
  select body into existing from public.bsmart_trade_theses where trade_id = p_trade;
  if found and existing <> p_body then return jsonb_build_object('error', 'thesis_exists'); end if;
  insert into public.bsmart_trade_theses(trade_id, body) values(p_trade, p_body) on conflict do nothing;
  return public.bsmart_thesis_json(p_trade, p_actor);
end;
$$;

create or replace function public.bsmart_feed_social_page(p_actor uuid, p_offset integer, p_limit integer,
  p_profile uuid default null, p_mine boolean default false, p_cloid text default null)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with selected as (
    select o.*, p.public_id, p.nickname, p.handle, p.avatar_url,
      p.account_id as profile_account_id, p.visible, p.feed_visible,
      t.trade_id as thesis_id, t.body as thesis_body, t.published_at as thesis_published_at
    from public.bsmart_feed_orders o join public.bsmart_feed_profiles p using(account_id)
    left join public.bsmart_trade_theses t on t.trade_id = o.id
    where p.visible and p.feed_visible and o.execution is not null and o.executed_at is not null
      and (o.source_kind = 'direct' or (
        coalesce(o.opinion->>'sourceKind', 'account') = 'account' and
        (o.opinion->>'platformPercentile')::numeric between 0 and 1))
      and (p_profile is null or p.public_id = p_profile)
      and (not p_mine or o.account_id = p_actor)
      and (p_cloid is null or (o.cloid = p_cloid and o.account_id = p_actor))
      and (p_mine or p_cloid is not null or o.source_kind = 'direct' or t.trade_id is not null
        or (o.opinion->>'platformPercentile')::numeric <= 0.25)
    order by o.executed_at desc, o.id
    limit greatest(1, least(p_limit, 30)) + 1 offset greatest(p_offset, 0)
  ), page as (select * from selected order by executed_at desc, id limit greatest(1, least(p_limit, 30)))
  select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object(
    'id', id, 'trader', jsonb_build_object('id', public_id, 'nickname', nickname,
      'handle', handle, 'avatarURL', avatar_url),
    'opinion', case when source_kind = 'direct' then public.bsmart_native_trade_opinion(
      id, intent, execution, executed_at, public_id, nickname, avatar_url, thesis_body)
      else opinion end,
    'side', execution->>'side', 'notionalUSD', execution->>'notionalUSD',
    'marketCoin', execution->>'marketCoin', 'executedAt', executed_at,
    'thesis', public.bsmart_thesis_json(id, p_actor),
    'canLikeThesis', account_id <> p_actor and thesis_id is not null,
    'canPublishThesis', account_id = p_actor and thesis_id is null
  ) order by executed_at desc, id) from page), '[]'::jsonb),
    'nextOffset', case when (select count(*) from selected) > p_limit then p_offset + p_limit else null end);
$$;

create function public.bsmart_native_investor_snapshot()
returns jsonb language sql stable security invoker set search_path = '' as $$
  with participants as (
    select p.* from public.bsmart_feed_profiles p
    where p.visible and p.feed_visible and exists (
      select 1 from public.bsmart_feed_orders o
      where o.account_id = p.account_id and o.execution is not null)
  ), performance as (
    select p.public_id,
      count(*) filter(where o.source_kind = 'direct' and o.execution->>'reduceOnly' = 'true'
        and o.execution ? 'netRealizedPnlUSD')::integer as closed_trades,
      count(*) filter(where o.source_kind = 'direct' and o.execution->>'reduceOnly' = 'true'
        and (o.execution->>'netRealizedPnlUSD')::numeric > 0)::integer as wins,
      coalesce(sum((o.execution->>'realizedPnlUSD')::numeric) filter(
        where o.source_kind = 'direct' and o.execution->>'reduceOnly' = 'true'), 0)
        - coalesce(sum((o.execution->>'feeUSD')::numeric) filter(
          where o.source_kind = 'direct'), 0) as net_pnl,
      coalesce(sum((o.execution->>'notionalUSD')::numeric) filter(
        where o.source_kind = 'direct' and o.execution->>'reduceOnly' = 'true'), 0) as closed_notional,
      max(o.executed_at) filter(where o.source_kind = 'direct' and o.execution->>'reduceOnly' = 'true') as as_of
    from participants p join public.bsmart_feed_orders o using(account_id)
    where o.execution is not null group by p.public_id
  ), ranked as (
    select public_id, row_number() over(order by net_pnl / nullif(closed_notional, 0) desc, public_id) as place,
      count(*) over() as cohort
    from performance where closed_trades >= 10 and closed_notional > 0
  ), profiles as (
    select p.*, s.closed_trades, s.wins, s.net_pnl, s.closed_notional, s.as_of,
      case when r.cohort >= 10 then r.place end as place,
      case when r.cohort >= 10 then r.place::numeric / r.cohort end as percentile
    from participants p join performance s using(public_id)
    left join ranked r using(public_id)
  ), latest as (
    select distinct on (o.account_id) o.account_id, o.intent->>'ticker' as ticker
    from public.bsmart_feed_orders o where o.execution is not null
    order by o.account_id, o.executed_at desc
  ), published as (
    select o.id, o.intent->>'ticker' as ticker, o.intent->>'reduceOnly' as reducing,
      o.execution->>'side' as side, p.public_id, p.nickname, p.avatar_url,
      p.place, p.percentile, t.body, t.published_at
    from public.bsmart_trade_theses t join public.bsmart_feed_orders o on o.id = t.trade_id
    join profiles p using(account_id)
    where o.execution is not null
    order by t.published_at desc, o.id desc limit 1000
  )
  select jsonb_build_object(
    'profiles', coalesce((select jsonb_agg(jsonb_build_object(
      'publicID', p.public_id, 'nickname', p.nickname, 'handle', p.handle,
      'avatarURL', p.avatar_url, 'bio', p.bio, 'recentTicker', l.ticker,
      'closedTrades', p.closed_trades, 'wins', p.wins,
      'realizedReturn', case when p.closed_notional > 0 then p.net_pnl / p.closed_notional end,
      'netPnlUSD', p.net_pnl, 'rank', p.place, 'percentile', p.percentile,
      'asOf', p.as_of
    ) order by p.updated_at desc, p.public_id) from profiles p left join latest l using(account_id)), '[]'::jsonb),
    'updates', coalesce((select jsonb_agg(jsonb_build_object(
      'id', u.id, 'publicID', u.public_id, 'nickname', u.nickname,
      'avatarURL', u.avatar_url, 'ticker', u.ticker, 'reducing', u.reducing = 'true',
      'side', u.side, 'body', u.body, 'publishedAt', u.published_at,
      'rank', u.place, 'percentile', u.percentile
    ) order by u.published_at desc, u.id desc) from published u), '[]'::jsonb));
$$;

revoke all on function public.bsmart_native_trade_opinion(uuid, jsonb, jsonb, timestamptz,
  uuid, text, text, text),
  public.bsmart_native_investor_snapshot() from public, anon, authenticated;
grant execute on function public.bsmart_native_trade_opinion(uuid, jsonb, jsonb, timestamptz,
  uuid, text, text, text),
  public.bsmart_native_investor_snapshot() to service_role;
commit;
