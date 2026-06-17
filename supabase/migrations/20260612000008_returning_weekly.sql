-- 「回访（周维度）」专用聚合：周同期群留存、每周新/回访活跃、回访频次、WAU/MAU 粘性。
-- 口径：以持久 visitor id 归并访客；自然周按 UTC+8（ISO 周一为起点）。
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。沿用 is_admin() —— 仅管理员可读。

-- ============ 周同期群留存（Wn = 获取后第 n 周仍回访的比例）============
create or replace function public.analytics_retention_weekly(p_weeks int default 8, p_max int default 6)
returns json language sql security definer set search_path = public stable as $$
  with ev as (
    select visitor, date_trunc('week', (ts at time zone 'Asia/Shanghai'))::date as wk
    from app_events
    where visitor is not null
      and ts >= now() - (((p_weeks + p_max + 1) * 7) || ' days')::interval
  ),
  firsts as ( select visitor, min(wk) as cohort from ev group by visitor ),
  today as ( select date_trunc('week', (now() at time zone 'Asia/Shanghai'))::date as t ),
  coh as (
    select f.cohort, count(*) as size
    from firsts f
    where f.cohort >= (select t from today) - (p_weeks * 7)
    group by f.cohort
  ),
  cell as (
    select f.cohort, ((e.wk - f.cohort) / 7) as off, count(distinct e.visitor) as retained
    from ev e join firsts f on f.visitor = e.visitor
    where f.cohort >= (select t from today) - (p_weeks * 7)
      and ((e.wk - f.cohort) / 7) between 0 and p_max
    group by f.cohort, ((e.wk - f.cohort) / 7)
  ),
  offs as ( select generate_series(0, p_max) as off ),
  curve as (
    select o.off,
           sum(c.size) filter (where c.cohort <= (select t from today) - (o.off * 7))               as elig,
           coalesce(sum(cl.retained) filter (where c.cohort <= (select t from today) - (o.off * 7)), 0) as ret
    from offs o cross join coh c
    left join cell cl on cl.cohort = c.cohort and cl.off = o.off
    group by o.off
  ),
  cohort_rows as (
    select c.cohort, c.size,
      (select json_agg(case when c.size > 0 then round(100.0 * coalesce(x.retained, 0) / c.size) else 0 end order by o.off)
        from offs o left join cell x on x.cohort = c.cohort and x.off = o.off) as pct
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

-- ============ 每周活跃(新 vs 回访) + 回访频次 + WAU/MAU 粘性 ============
create or replace function public.analytics_returning(p_weeks int default 8)
returns json language sql security definer set search_path = public stable as $$
  with base as (
    select visitor,
           (ts at time zone 'Asia/Shanghai')::date as d,
           date_trunc('week', (ts at time zone 'Asia/Shanghai'))::date as wk
    from app_events
    where visitor is not null
  ),
  firsts as ( select visitor, min(wk) as first_wk from base group by visitor ),
  today as (
    select date_trunc('week', (now() at time zone 'Asia/Shanghai'))::date as t,
           (now() at time zone 'Asia/Shanghai')::date as td
  ),
  wk_active as (
    select distinct b.visitor, b.wk from base b
    where b.wk >= (select t from today) - (p_weeks * 7)
  ),
  wk_series as (
    select a.wk,
           count(*) filter (where a.wk = f.first_wk) as new_v,
           count(*) filter (where a.wk > f.first_wk) as ret_v,
           count(*) as total
    from wk_active a join firsts f on f.visitor = a.visitor
    group by a.wk
  ),
  freq as (
    select visitor, count(distinct wk) as weeks
    from base where wk >= (select t from today) - (p_weeks * 7)
    group by visitor
  )
  select case when public.is_admin() then json_build_object(
    'weeks', (select coalesce(json_agg(json_build_object(
                'week', to_char(wk, 'YYYY-MM-DD'), 'new', new_v, 'returning', ret_v, 'total', total) order by wk), '[]'::json)
              from wk_series),
    'frequency', json_build_array(
        json_build_object('k', '1',   'n', (select count(*) from freq where weeks = 1)),
        json_build_object('k', '2',   'n', (select count(*) from freq where weeks = 2)),
        json_build_object('k', '3-4', 'n', (select count(*) from freq where weeks between 3 and 4)),
        json_build_object('k', '5+',  'n', (select count(*) from freq where weeks >= 5))
      ),
    'wau',        (select count(distinct visitor) from base where wk = (select t from today)),
    'mau',        (select count(distinct visitor) from base where d >= (select td from today) - 28),
    'stickiness', (select case when m.c > 0 then round(100.0 * w.c / m.c) else 0 end
                     from (select count(distinct visitor) c from base where wk = (select t from today)) w,
                          (select count(distinct visitor) c from base where d >= (select td from today) - 28) m)
  ) else null end;
$$;

grant execute on function public.analytics_retention_weekly(int, int) to authenticated;
grant execute on function public.analytics_returning(int)             to authenticated;
