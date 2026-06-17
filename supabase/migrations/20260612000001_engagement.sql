-- 用户参与度（engagement）聚合：人均停留时长、人均点击、页/会话、跳出率，以及「最爱页面 + 停留」。
-- 依赖前端 page_leave 信标：meta.ms = 该页活跃毫秒数，meta.clicks = 该页点击数（见 AnalyticsTracker）。
-- 目的：① 产品迭代（看用户停在哪、跳出多不多）② 和广告主谈合作（触达 + 停留 + 互动可信度）。
--
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。沿用 is_admin() 校验：仅管理员可读。

-- ---------------- 总体参与度 KPI ----------------
create or replace function public.analytics_engagement(p_days int default 30)
returns json language sql security definer set search_path = public stable as $$
  with ev as (
    select * from app_events
     where ts >= now() - (p_days || ' days')::interval
  ),
  per_session as (
    select session,
           min(visitor) as visitor,
           count(*) filter (where event_type = 'page_view') as pv,
           coalesce(sum((meta ->> 'ms')::numeric)    filter (where event_type = 'page_leave'), 0) as leave_ms,
           coalesce(sum((meta ->> 'clicks')::int)    filter (where event_type = 'page_leave'), 0) as clicks,
           extract(epoch from (max(ts) - min(ts))) * 1000 as span_ms
    from ev where session is not null
    group by session
  ),
  sess as (
    select session, visitor, pv, clicks, greatest(span_ms, leave_ms) as dur_ms from per_session
  ),
  per_visitor as (
    select visitor, sum(pv) as pv, sum(clicks) as clicks, sum(dur_ms) as dur_ms
    from sess where visitor is not null group by visitor
  )
  select case when public.is_admin() then json_build_object(
    'sessions',               (select count(*) from sess),
    'visitors',               (select count(*) from per_visitor),
    'avg_session_seconds',    (select round(coalesce(avg(dur_ms), 0) / 1000.0, 1) from sess),
    'avg_visitor_seconds',    (select round(coalesce(avg(dur_ms), 0) / 1000.0, 1) from per_visitor),
    'avg_pages_per_session',  (select round(coalesce(avg(pv), 0)::numeric, 2) from sess),
    'avg_pages_per_visitor',  (select round(coalesce(avg(pv), 0)::numeric, 2) from per_visitor),
    'avg_clicks_per_visitor', (select round(coalesce(avg(clicks), 0)::numeric, 2) from per_visitor),
    'avg_clicks_per_session', (select round(coalesce(avg(clicks), 0)::numeric, 2) from sess),
    'bounce_rate',            (select round(100.0 * count(*) filter (where pv <= 1) / nullif(count(*), 0), 1) from sess)
  ) else null end;
$$;

-- ---------------- 最爱页面（含停留/独立访客/点击）----------------
create or replace function public.analytics_top_paths_engaged(p_limit int default 10, p_days int default 30)
returns table(path text, views bigint, visitors bigint, avg_seconds numeric, clicks bigint)
language sql security definer set search_path = public stable as $$
  with ev as (
    select * from app_events
     where ts >= now() - (p_days || ' days')::interval and path is not null
  ),
  pv as (
    select path, count(*) as views, count(distinct visitor) as visitors
    from ev where event_type = 'page_view' group by path
  ),
  pl as (
    select path, avg((meta ->> 'ms')::numeric) as avg_ms, sum((meta ->> 'clicks')::int) as clicks
    from ev where event_type = 'page_leave' group by path
  )
  select pv.path, pv.views, pv.visitors,
         round(coalesce(pl.avg_ms, 0) / 1000.0, 1) as avg_seconds,
         coalesce(pl.clicks, 0)::bigint as clicks
  from pv left join pl on pl.path = pv.path
  where public.is_admin()
  order by pv.views desc
  limit p_limit;
$$;

grant execute on function public.analytics_engagement(int)              to authenticated;
grant execute on function public.analytics_top_paths_engaged(int, int)  to authenticated;
