-- 可见曝光(viewable impression)入库聚合：把 analytics_inventory 升级为「真实可见曝光」口径。
-- 数据来源：前端 ViewTracker 发的 ad_view 事件（MRC：元素 ≥50% 可见、连续 ≥1 秒、页面在前台）。
-- eCPM 由「页面浏览 × 广告位估算」升级为「真实可见曝光估算」。
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。沿用 is_admin() —— 仅管理员可读。

create or replace function public.analytics_inventory(p_days int default 30)
returns json language sql security definer set search_path = public stable as $$
  with ev as (select * from app_events where ts >= now() - (p_days || ' days')::interval)
  select case when public.is_admin() then json_build_object(
    'days',        p_days,
    'impressions', (select count(*) from ev where event_type = 'page_view'),
    'visitors',    (select count(distinct visitor) from ev where visitor is not null),
    'sessions',    (select count(distinct session) from ev where session is not null),
    'viewable',    (select count(*) from ev where event_type = 'ad_view'),
    'view_slots',  (select coalesce(json_agg(json_build_object('k', k, 'n', n) order by n desc), '[]'::json)
                      from (select coalesce(meta ->> 'slot', '?') k, count(*) n
                              from ev where event_type = 'ad_view' group by 1) s)
  ) else null end;
$$;

grant execute on function public.analytics_inventory(int) to authenticated;
