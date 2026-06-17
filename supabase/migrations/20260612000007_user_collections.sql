-- 账户系统：用户私有「收藏 / 追踪」。一张表承载 5 类对象，kind 区分：
--   post / comment（收藏，snapshot 存展示快照）；subreddit / ticker / author（追踪，snapshot 为 null）。
-- 站点是静态导出（运行时不连库），用户数据由前端经 anon key + RLS 直接读写本表。
--
-- 安全模型：
--   • RLS 仅放行 auth.uid() = user_id —— 每个登录用户只能读写「自己的」行；anon（未登录）一行都看不到。
--   • 不开放 UPDATE：收藏是「加/删」语义，快照为收藏时刻的不可变副本；重复收藏走 ON CONFLICT DO NOTHING。
--
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。

create table if not exists public.user_collections (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  kind       text        not null check (kind in ('post','comment','subreddit','ticker','author')),
  ref_id     text        not null,            -- posts.id / comments.id / subreddits.id / ticker / author 用户名
  snapshot   jsonb,                            -- 帖子/评论的展示快照；追踪类为 null
  created_at timestamptz not null default now(),
  primary key (user_id, kind, ref_id)
);

-- 个人主页按 (用户, 类型) 倒序拉列表
create index if not exists user_collections_user_kind_idx
  on public.user_collections (user_id, kind, created_at desc);

alter table public.user_collections enable row level security;

-- 只能读自己的
drop policy if exists "uc_own_select" on public.user_collections;
create policy "uc_own_select" on public.user_collections
  for select using (auth.uid() = user_id);

-- 只能插入「归属自己」的行
drop policy if exists "uc_own_insert" on public.user_collections;
create policy "uc_own_insert" on public.user_collections
  for insert with check (auth.uid() = user_id);

-- 只能删自己的
drop policy if exists "uc_own_delete" on public.user_collections;
create policy "uc_own_delete" on public.user_collections
  for delete using (auth.uid() = user_id);

-- 登录用户拥有本表的读/增/删（不含 update：见上「不可变快照」）；anon 无任何权限。
grant select, insert, delete on public.user_collections to authenticated;
