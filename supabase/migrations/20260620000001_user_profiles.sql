-- 账户系统：用户「投资画像」（onboarding 引导采集）。每人一行。
--   experience     投资经验/年龄档位
--   interests      关注方向（主题 key 数组）
--   holdings       当前持仓（ticker 代码数组；同时会被写进 user_collections 作为追踪）
--   portfolio_size 投资规模档位（敏感、可选，含 'na'=不便透露）
--   onboarded_at   完成/跳过引导的时间
-- 站点是静态导出（运行时不连库），用户数据由前端经 anon key + RLS 直接读写本表。
--
-- 安全模型（镜像 user_collections，但本表「可变」故放开 UPDATE）：
--   • RLS 仅放行 auth.uid() = user_id —— 每个登录用户只能读写「自己的」那一行；anon 一行都看不到。
--   • 不放开 DELETE：画像随账号生命周期存在，账号删除时随 on delete cascade 清掉。
--
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。

create table if not exists public.user_profiles (
  user_id        uuid        not null references auth.users(id) on delete cascade,
  experience     text        check (experience in ('new','growing','seasoned','veteran')),
  interests      text[]      not null default '{}',
  holdings       text[]      not null default '{}',
  portfolio_size text        check (portfolio_size in ('lt1k','1k_10k','10k_50k','50k_250k','gt250k','na')),
  onboarded_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (user_id)
);

alter table public.user_profiles enable row level security;

-- 只能读自己的
drop policy if exists "up_own_select" on public.user_profiles;
create policy "up_own_select" on public.user_profiles
  for select using (auth.uid() = user_id);

-- 只能插入「归属自己」的行
drop policy if exists "up_own_insert" on public.user_profiles;
create policy "up_own_insert" on public.user_profiles
  for insert with check (auth.uid() = user_id);

-- 只能改自己的（upsert / 偏好编辑用）
drop policy if exists "up_own_update" on public.user_profiles;
create policy "up_own_update" on public.user_profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 登录用户拥有本表的读/增/改（不含 delete）；anon 无任何权限。
grant select, insert, update on public.user_profiles to authenticated;
