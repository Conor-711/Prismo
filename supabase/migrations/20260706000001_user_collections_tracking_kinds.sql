-- 扩展用户追踪对象：叙事与区域。
-- 旧库已有 user_collections_kind_check 时替换约束；新库会直接走 20260612000007 的完整约束。

alter table public.user_collections
  drop constraint if exists user_collections_kind_check;

alter table public.user_collections
  add constraint user_collections_kind_check
  check (kind in ('post','comment','subreddit','ticker','author','narrative','region'));
