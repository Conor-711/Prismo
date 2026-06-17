-- 多管理员支持。原先 is_admin() 把管理员邮箱写死成单个字面量；
-- 这里改成读 app_admins 名单表 —— 以后新增/移除管理员只需 INSERT/DELETE 一行，无需改代码重部署。
--
-- 安全：app_admins 开启 RLS 且不建任何策略 => anon/authenticated 都读不到名单；
-- 仅 SECURITY DEFINER 的 is_admin()（以表属主身份运行、绕过 RLS）能读取。
--
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。

-- ---------------- 管理员名单表 ----------------
create table if not exists public.app_admins (
  email     text primary key,           -- 统一小写存储
  note      text,                        -- 备注：谁/做什么用
  added_at  timestamptz not null default now()
);

alter table public.app_admins enable row level security;
-- 故意不建任何 policy：前端拿不到名单，避免泄露管理员邮箱。

-- 种子：原管理员 + 新增的数据看板管理员。
insert into public.app_admins (email, note) values
  ('admin@redditalpha.xyz',     'primary'),
  ('analytics@redditalpha.xyz', 'data dashboard manager')
on conflict (email) do nothing;

-- ---------------- 重定义 is_admin()：改查名单表 ----------------
-- 所有分析聚合函数都调用 is_admin()，这里改了它们自动生效，无需逐个改。
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.app_admins
     where email = coalesce(lower(auth.jwt() ->> 'email'), '')
  );
$$;
