-- 作者库（Reddit 优质作者聚合页）所需的两列。
--   posts.source      ：'scan'=板块扫描（进实时舆情聚合）/ 'author'=作者库历史爬取（只进作者页，不污染聚合）。
--   authors.crawled_at：上次爬取该作者历史帖的时间，用于每日增量（只爬 NULL 或过期的）。
--
-- 站点是静态导出，运行时不连库；这两列只在数据管线（Python）与构建期读取，无需 RLS 改动。
-- 在 Supabase → SQL Editor 整段执行一次（幂等，可重复跑）。

alter table public.posts   add column if not exists source     text default 'scan';
alter table public.authors add column if not exists crawled_at timestamptz;

-- 已有历史帖默认都是板块扫描来源
update public.posts set source = 'scan' where source is null;

-- 实时聚合频繁按 source 过滤 → 建索引
create index if not exists posts_source_idx on public.posts (source);
