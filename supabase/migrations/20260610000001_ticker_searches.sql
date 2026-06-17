-- 搜索热度榜（全局共享）：记录每个 ticker 被搜索的次数。
-- 站点是静态导出（GitHub Pages），没有自己的后端，因此用 Supabase 作为计数后端。
-- 在 Supabase 控制台 → SQL Editor 里整段执行一次即可。
--
-- 安全模型：
--   • anon（前端匿名 key）只能「读榜」+ 调用受控的自增函数；不能直接 UPDATE/INSERT 任意行。
--   • 自增走 SECURITY DEFINER 函数，内部只能把某个 ticker 的计数 +1，杜绝刷任意数据。

create table if not exists public.ticker_searches (
  ticker        text primary key,
  search_count  bigint      not null default 0,
  updated_at    timestamptz not null default now()
);

alter table public.ticker_searches enable row level security;

-- 所有人可读排行榜
drop policy if exists "ticker_searches_read" on public.ticker_searches;
create policy "ticker_searches_read"
  on public.ticker_searches for select
  using (true);

-- 受控自增：把单个 ticker 的计数 +1（不存在则插入）。规范化为大写、限长，避免脏数据。
create or replace function public.increment_ticker_search(p_ticker text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  t text := upper(btrim(p_ticker));
begin
  if t is null or t = '' or length(t) > 12 then
    return;
  end if;
  insert into public.ticker_searches as s (ticker, search_count, updated_at)
  values (t, 1, now())
  on conflict (ticker) do update
    set search_count = s.search_count + 1,
        updated_at   = now();
end;
$$;

-- 允许匿名/登录用户调用自增函数（但 table 的写权限不放开）
grant execute on function public.increment_ticker_search(text) to anon, authenticated;

-- 读取榜单走 RLS 的 select 策略，无需额外 grant（anon 默认有 select 权限 + 策略放行）。
