-- 网站分析（埋点 + 聚合）。前端静态托管，无自有后端，故用 Supabase 收集与聚合行为数据。
-- 在 Supabase → SQL Editor 整段执行一次；或连 GitHub 后推送自动应用。
--
-- 安全模型：
--   • 任何访客（anon）只能 INSERT 埋点事件，不能读取原始事件（保护原始数据/隐私）。
--   • 仪表盘只读「聚合结果」，且仅限**管理员**：聚合函数内用 is_admin() 校验 JWT 邮箱，
--     非管理员即便直接调用 RPC 也拿不到数据。
--   • 更换管理员邮箱：改下面 is_admin() 里的字面量，并同步前端 NEXT_PUBLIC_ADMIN_EMAIL。

create table if not exists public.app_events (
  id          bigint generated always as identity primary key,
  ts          timestamptz not null default now(),
  event_type  text not null,                  -- page_view / search / ad_view / ad_close / translate_toggle / share / landing ...
  path        text,                            -- 去掉语言前缀后的路径，如 /ticker/NVDA
  lang        text,                            -- zh / en
  ticker      text,                            -- 相关标的（若有）
  ref         text,                            -- 来源 host
  visitor     text,                            -- 持久访客 id（localStorage）
  session     text,                            -- 会话 id（sessionStorage）
  meta        jsonb
);

create index if not exists app_events_ts_idx     on public.app_events (ts);
create index if not exists app_events_type_idx   on public.app_events (event_type);
create index if not exists app_events_path_idx   on public.app_events (path);
create index if not exists app_events_ticker_idx on public.app_events (ticker);

alter table public.app_events enable row level security;

-- 仅允许写入埋点（不开放任何 SELECT 给 anon）
drop policy if exists "app_events_insert" on public.app_events;
create policy "app_events_insert" on public.app_events
  for insert to anon, authenticated with check (true);

grant insert on public.app_events to anon, authenticated;

-- ---------------- 管理员判定 ----------------
-- 改这里的邮箱即可更换管理员（需与前端 NEXT_PUBLIC_ADMIN_EMAIL 一致）。
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(lower(auth.jwt() ->> 'email'), '') = 'admin@redditalpha.xyz';
$$;

-- ---------------- 聚合函数（SECURITY DEFINER，内置 is_admin 校验，仅管理员可读）----------------

create or replace function public.analytics_overview()
returns json language sql security definer set search_path = public stable as $$
  select case when public.is_admin() then json_build_object(
    'events',          (select count(*) from app_events),
    'page_views',      (select count(*) from app_events where event_type = 'page_view'),
    'visitors',        (select count(distinct visitor) from app_events where visitor is not null),
    'sessions',        (select count(distinct session) from app_events where session is not null),
    'views_today',     (select count(*) from app_events where event_type = 'page_view' and ts >= date_trunc('day', now())),
    'visitors_today',  (select count(distinct visitor) from app_events where ts >= date_trunc('day', now()) and visitor is not null)
  ) else null end;
$$;

create or replace function public.analytics_daily(p_days int default 14)
returns table(day date, views bigint, visitors bigint)
language sql security definer set search_path = public stable as $$
  select d::date as day,
         count(e.id) filter (where e.event_type = 'page_view') as views,
         count(distinct e.visitor) as visitors
    from generate_series(date_trunc('day', now()) - ((p_days - 1) || ' days')::interval,
                         date_trunc('day', now()), interval '1 day') d
    left join app_events e on e.ts >= d and e.ts < d + interval '1 day'
   where public.is_admin()
   group by d order by d;
$$;

create or replace function public.analytics_top_paths(p_limit int default 10, p_days int default 30)
returns table(path text, views bigint)
language sql security definer set search_path = public stable as $$
  select path, count(*) as views from app_events
   where public.is_admin() and event_type = 'page_view' and path is not null
     and ts >= now() - (p_days || ' days')::interval
   group by path order by views desc limit p_limit;
$$;

create or replace function public.analytics_event_breakdown(p_days int default 30)
returns table(event_type text, n bigint)
language sql security definer set search_path = public stable as $$
  select event_type, count(*) as n from app_events
   where public.is_admin() and ts >= now() - (p_days || ' days')::interval
   group by event_type order by n desc;
$$;

create or replace function public.analytics_top_tickers(p_limit int default 10, p_days int default 30)
returns table(ticker text, n bigint)
language sql security definer set search_path = public stable as $$
  select ticker, count(*) as n from app_events
   where public.is_admin() and ticker is not null and ticker <> ''
     and ts >= now() - (p_days || ' days')::interval
   group by ticker order by n desc limit p_limit;
$$;

create or replace function public.analytics_lang_split(p_days int default 30)
returns table(lang text, n bigint)
language sql security definer set search_path = public stable as $$
  select coalesce(lang, '?') as lang, count(*) as n from app_events
   where public.is_admin() and event_type = 'page_view'
     and ts >= now() - (p_days || ' days')::interval
   group by lang order by n desc;
$$;

-- 增长：流量来源（来源 host）—— 看分享/外链带来的访问
create or replace function public.analytics_traffic_sources(p_limit int default 10, p_days int default 30)
returns table(source text, n bigint)
language sql security definer set search_path = public stable as $$
  select coalesce(nullif(ref, ''), '(direct)') as source, count(*) as n from app_events
   where public.is_admin() and event_type = 'page_view'
     and ts >= now() - (p_days || ' days')::interval
   group by 1 order by n desc limit p_limit;
$$;

-- 增长：分享次数按平台 —— 看用户主动传播
create or replace function public.analytics_shares(p_days int default 30)
returns table(platform text, n bigint)
language sql security definer set search_path = public stable as $$
  select coalesce(meta ->> 'platform', '?') as platform, count(*) as n from app_events
   where public.is_admin() and event_type = 'share'
     and ts >= now() - (p_days || ' days')::interval
   group by 1 order by n desc;
$$;

create or replace function public.analytics_recent(p_limit int default 30)
returns table(ts timestamptz, event_type text, path text, lang text, ticker text)
language sql security definer set search_path = public stable as $$
  select ts, event_type, path, lang, ticker from app_events
   where public.is_admin()
   order by ts desc limit p_limit;
$$;

grant execute on function public.is_admin()                            to authenticated;
grant execute on function public.analytics_overview()                  to authenticated;
grant execute on function public.analytics_daily(int)                  to authenticated;
grant execute on function public.analytics_top_paths(int, int)         to authenticated;
grant execute on function public.analytics_event_breakdown(int)        to authenticated;
grant execute on function public.analytics_top_tickers(int, int)       to authenticated;
grant execute on function public.analytics_lang_split(int)             to authenticated;
grant execute on function public.analytics_traffic_sources(int, int)   to authenticated;
grant execute on function public.analytics_shares(int)                 to authenticated;
grant execute on function public.analytics_recent(int)                 to authenticated;
