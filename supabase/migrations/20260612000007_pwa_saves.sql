-- 「把站点存下来」的可追踪信号。浏览器原生收藏(Chrome/Safari 书签)无法被网页探测，
-- 最接近的可追踪替代是：① 从主屏/已安装 App 独立启动(standalone) ② Android/桌面 Chrome 的 appinstalled 事件。
-- 数据来源：session_start.meta.standalone（每会话）、pwa_install 事件。
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。沿用 is_admin() —— 仅管理员可读。

create or replace function public.analytics_pwa(p_days int default 30)
returns json language sql security definer set search_path = public stable as $$
  with ss as (
    select * from app_events
     where event_type = 'session_start' and ts >= now() - (p_days || ' days')::interval
  )
  select case when public.is_admin() then json_build_object(
    'standalone_visitors', (select count(distinct visitor) from ss where (meta ->> 'standalone')::boolean is true),
    'standalone_sessions', (select count(*)               from ss where (meta ->> 'standalone')::boolean is true),
    'installs',            (select count(*) from app_events
                              where event_type = 'pwa_install' and ts >= now() - (p_days || ' days')::interval)
  ) else null end;
$$;

grant execute on function public.analytics_pwa(int) to authenticated;
