-- N 日留存（同期群三角）+ 广告库存量（供前端估算 eCPM）。
-- 留存口径（GA4/Mixpanel 同期群）：以「访客在数据内首个活跃自然日(UTC+8)」为获取日期分组，
--   Dn = 该同期群在首访后第 n 天仍有任意事件的访客占比；聚合曲线按「已满 n 天的同期群」加权。
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。沿用 is_admin() —— 仅管理员可读。

-- ============ N 日留存（同期群）============
create or replace function public.analytics_retention(p_days int default 21, p_max int default 7)
returns json language sql security definer set search_path = public stable as $$
  with ev as (
    select visitor, (ts at time zone 'Asia/Shanghai')::date as d
    from app_events
    where visitor is not null
      and ts >= now() - ((p_days + p_max + 1) || ' days')::interval
  ),
  firsts as (
    select visitor, min(d) as cohort from ev group by visitor
  ),
  today as ( select (now() at time zone 'Asia/Shanghai')::date as t ),
  coh as (
    select f.cohort, count(*) as size
    from firsts f
    where f.cohort >= (select t from today) - p_days
    group by f.cohort
  ),
  cell as (
    select f.cohort, (e.d - f.cohort) as off, count(distinct e.visitor) as retained
    from ev e
    join firsts f on f.visitor = e.visitor
    where f.cohort >= (select t from today) - p_days
      and (e.d - f.cohort) between 0 and p_max
    group by f.cohort, (e.d - f.cohort)
  ),
  offs as ( select generate_series(0, p_max) as off ),
  curve as (
    select o.off,
           sum(c.size) filter (where c.cohort <= (select t from today) - o.off)               as elig,
           coalesce(sum(cl.retained) filter (where c.cohort <= (select t from today) - o.off), 0) as ret
    from offs o
    cross join coh c
    left join cell cl on cl.cohort = c.cohort and cl.off = o.off
    group by o.off
  ),
  cohort_rows as (
    select c.cohort, c.size,
      (select json_agg(
          case when c.size > 0 then round(100.0 * coalesce(x.retained, 0) / c.size) else 0 end
          order by o.off)
        from offs o left join cell x on x.cohort = c.cohort and x.off = o.off
      ) as pct
    from coh c
  )
  select case when public.is_admin() then json_build_object(
    'max', p_max,
    'cohorts', (select coalesce(json_agg(json_build_object(
        'date', to_char(cohort, 'YYYY-MM-DD'), 'size', size, 'pct', pct) order by cohort desc), '[]'::json)
      from cohort_rows),
    'curve', (select coalesce(json_agg(json_build_object(
        'd', off, 'pct', case when elig > 0 then round(100.0 * ret / elig) else null end) order by off), '[]'::json)
      from curve)
  ) else null end;
$$;

-- ============ 广告库存量（页面浏览=可售展示，供前端估 eCPM）============
create or replace function public.analytics_inventory(p_days int default 30)
returns json language sql security definer set search_path = public stable as $$
  with ev as (select * from app_events where ts >= now() - (p_days || ' days')::interval)
  select case when public.is_admin() then json_build_object(
    'days',        p_days,
    'impressions', (select count(*) from ev where event_type = 'page_view'),
    'visitors',    (select count(distinct visitor) from ev where visitor is not null),
    'sessions',    (select count(distinct session) from ev where session is not null)
  ) else null end;
$$;

grant execute on function public.analytics_retention(int, int) to authenticated;
grant execute on function public.analytics_inventory(int)      to authenticated;
