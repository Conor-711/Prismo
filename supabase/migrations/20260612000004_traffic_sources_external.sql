-- 「流量来源」改为「站外来源」视图：只显示真正把用户带进来的来源。
--   • 保留 (direct) 直接访问；
--   • 剔除自有域名的站内自引用（redditalpha.xyz / www.redditalpha.xyz，含端口与子域）；
--   • 剔除 localhost / 私有·环回 IP / .local / 无点内部名（本地·开发流量）。
-- 并物理清除「来源=本地/内网」的历史脏数据，使其不再污染任何指标。
--
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。沿用 is_admin() 仅管理员可读。

-- ---------------- ① 清除「来源=本地/内网」的历史埋点 ----------------
-- 只删「referrer 明确是本地/内网」的行 —— 这类一定是本机/开发会话，安全删除。
delete from public.app_events
 where ref is not null and ref <> ''
   and (
        lower(ref) like 'localhost%'
     or lower(split_part(ref, ':', 1)) like '%.local'
     or split_part(ref, ':', 1) ~ '^(127\.|10\.|192\.168\.|169\.254\.|0\.0\.0\.0|172\.(1[6-9]|2[0-9]|3[01])\.)'
   );

-- ---------------- ② 重定义流量来源：站外来源视图 ----------------
create or replace function public.analytics_traffic_sources(p_limit int default 10, p_days int default 30)
returns table(source text, n bigint)
language sql security definer set search_path = public stable as $$
  with src as (
    select
      case
        when ref is null or ref = '' then '(direct)'
        else lower(split_part(ref, ':', 1))      -- 去掉端口，统一小写
      end as host
    from app_events
    where public.is_admin()
      and event_type = 'page_view'
      and ts >= now() - (p_days || ' days')::interval
  )
  select host as source, count(*) as n
  from src
  where host = '(direct)'                         -- 直接访问保留
     or (
          host like '%.%'                          -- 必须是含点的真实域名（剔除 localhost / 无点内部名）
      and host !~ '(^|\.)redditalpha\.xyz$'        -- 剔除自有域名的站内自引用（apex + 任意子域）
      and host !~ '^(127\.|10\.|192\.168\.|169\.254\.|0\.0\.0\.0|172\.(1[6-9]|2[0-9]|3[01])\.)'  -- 私有/环回 IP
      and host !~ '\.local$'
        )
  group by host
  order by n desc
  limit p_limit;
$$;

grant execute on function public.analytics_traffic_sources(int, int) to authenticated;
