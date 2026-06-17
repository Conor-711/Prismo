-- 专业化分析聚合 v2：受众画像 / 获取渠道 / 新老留存 / 活跃时段 / 转化漏斗 / 站内搜索词 / 滚动深度。
-- 数据来源：前端 session_start 事件（带用户画像 meta：device/os/browser/channel/utm/lang/tz/returning），
--           以及 page_leave 事件的 meta.maxScroll（滚动深度）。
-- 设计参考：Amplitude/Mixpanel 事件分类法（事件属性 + 用户属性）、GA4 新老/留存/同期群、内容站滚动深度。
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。沿用 is_admin() —— 仅管理员可读。

-- ============ 受众画像（设备 / 浏览器 / 系统 / 语言 / 时区 / 新老）============
create or replace function public.analytics_audience(p_days int default 30)
returns json language sql security definer set search_path = public stable as $$
  with ss as (
    select * from app_events
     where event_type = 'session_start' and ts >= now() - (p_days || ' days')::interval
  ),
  vis as (
    select visitor,
           bool_or(coalesce((meta ->> 'returning')::boolean, false)) as ret,
           count(distinct session) as sessions
    from ss where visitor is not null group by visitor
  )
  select case when public.is_admin() then json_build_object(
    'devices',   (select coalesce(json_agg(json_build_object('k', k, 'n', n) order by n desc), '[]'::json)
                    from (select coalesce(nullif(meta ->> 'device',''),'?') k, count(*) n from ss group by 1) d),
    'browsers',  (select coalesce(json_agg(json_build_object('k', k, 'n', n) order by n desc), '[]'::json)
                    from (select coalesce(nullif(meta ->> 'browser',''),'?') k, count(*) n from ss group by 1 order by count(*) desc limit 8) b),
    'os',        (select coalesce(json_agg(json_build_object('k', k, 'n', n) order by n desc), '[]'::json)
                    from (select coalesce(nullif(meta ->> 'os',''),'?') k, count(*) n from ss group by 1 order by count(*) desc limit 8) o),
    'languages', (select coalesce(json_agg(json_build_object('k', k, 'n', n) order by n desc), '[]'::json)
                    from (select coalesce(nullif(meta ->> 'lang',''),'?') k, count(*) n from ss group by 1 order by count(*) desc limit 8) l),
    'timezones', (select coalesce(json_agg(json_build_object('k', k, 'n', n) order by n desc), '[]'::json)
                    from (select coalesce(nullif(meta ->> 'tz',''),'?') k, count(*) n from ss group by 1 order by count(*) desc limit 8) z),
    'new_visitors',       (select count(*) from vis where not ret and sessions <= 1),
    'returning_visitors', (select count(*) from vis where ret or sessions > 1),
    'visitors',           (select count(*) from vis),
    'sessions',           (select count(*) from ss)
  ) else null end;
$$;

-- ============ 获取渠道（direct/organic/social/referral… + UTM campaign）============
create or replace function public.analytics_channels(p_days int default 30)
returns json language sql security definer set search_path = public stable as $$
  with ss as (
    select * from app_events
     where event_type = 'session_start' and ts >= now() - (p_days || ' days')::interval
  )
  select case when public.is_admin() then json_build_object(
    'channels',  (select coalesce(json_agg(json_build_object('k', k, 'n', n) order by n desc), '[]'::json)
                    from (select coalesce(nullif(meta ->> 'channel',''),'direct') k, count(*) n from ss group by 1) c),
    'campaigns', (select coalesce(json_agg(json_build_object('k', k, 'n', n) order by n desc), '[]'::json)
                    from (select meta ->> 'utm_campaign' k, count(*) n from ss
                           where coalesce(meta ->> 'utm_campaign','') <> '' group by 1 order by count(*) desc limit 8) g)
  ) else null end;
$$;

-- ============ 活跃时段（UTC+8 小时分布，按 page_view；含 0 补全 24 小时）============
create or replace function public.analytics_hourly(p_days int default 30)
returns table(hour int, n bigint)
language sql security definer set search_path = public stable as $$
  select h::int as hour, coalesce(x.c, 0)::bigint as n
  from generate_series(0, 23) h
  left join (
    select extract(hour from ts at time zone 'Asia/Shanghai')::int hh, count(*) c
      from app_events
     where public.is_admin() and event_type = 'page_view'
       and ts >= now() - (p_days || ' days')::interval
     group by 1
  ) x on x.hh = h
  order by h;
$$;

-- ============ 转化漏斗（各阶段独立访客）：落地 → 看板 → 个股 → 帖子 → 分享 ============
create or replace function public.analytics_funnel(p_days int default 30)
returns json language sql security definer set search_path = public stable as $$
  with ev as (select * from app_events where ts >= now() - (p_days || ' days')::interval)
  select case when public.is_admin() then json_build_object(
    'landing',   (select count(distinct visitor) from ev where event_type = 'page_view' and coalesce(path,'/') in ('/','')),
    'dashboard', (select count(distinct visitor) from ev where event_type = 'page_view' and (path like '/dashboard%' or path = '/cn' or path like '/cn/dashboard%')),
    'ticker',    (select count(distinct visitor) from ev where event_type = 'page_view' and path like '%/ticker%'),
    'post',      (select count(distinct visitor) from ev where event_type = 'page_view' and path like '%/post%'),
    'share',     (select count(distinct visitor) from ev where event_type = 'share')
  ) else null end;
$$;

-- ============ 站内搜索词（含命中数 → 看内容缺口）============
create or replace function public.analytics_search_terms(p_limit int default 12, p_days int default 30)
returns table(term text, n bigint, found bigint)
language sql security definer set search_path = public stable as $$
  select coalesce(nullif(meta ->> 'q',''), ticker, '?') as term,
         count(*) as n,
         count(*) filter (where (meta ->> 'found')::boolean is true) as found
    from app_events
   where public.is_admin() and event_type = 'search'
     and ts >= now() - (p_days || ' days')::interval
   group by 1 order by n desc limit p_limit;
$$;

-- ============ 最爱页面：在原有基础上加「平均滚动深度」(内容质量)  ============
-- 该函数已在 …_engagement.sql 建过（无 avg_scroll 列）；改返回类型必须先 DROP，CREATE OR REPLACE 不行。
drop function if exists public.analytics_top_paths_engaged(int, int);
create or replace function public.analytics_top_paths_engaged(p_limit int default 10, p_days int default 30)
returns table(path text, views bigint, visitors bigint, avg_seconds numeric, clicks bigint, avg_scroll numeric)
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
    select path,
           avg((meta ->> 'ms')::numeric)              as avg_ms,
           sum((meta ->> 'clicks')::int)              as clicks,
           avg(nullif(meta ->> 'maxScroll','')::numeric) as avg_scroll
    from ev where event_type = 'page_leave' group by path
  )
  select pv.path, pv.views, pv.visitors,
         round(coalesce(pl.avg_ms, 0) / 1000.0, 1) as avg_seconds,
         coalesce(pl.clicks, 0)::bigint as clicks,
         round(coalesce(pl.avg_scroll, 0), 0) as avg_scroll
  from pv left join pl on pl.path = pv.path
  where public.is_admin()
  order by pv.views desc
  limit p_limit;
$$;

grant execute on function public.analytics_audience(int)               to authenticated;
grant execute on function public.analytics_channels(int)               to authenticated;
grant execute on function public.analytics_hourly(int)                 to authenticated;
grant execute on function public.analytics_funnel(int)                 to authenticated;
grant execute on function public.analytics_search_terms(int, int)      to authenticated;
grant execute on function public.analytics_top_paths_engaged(int, int) to authenticated;
