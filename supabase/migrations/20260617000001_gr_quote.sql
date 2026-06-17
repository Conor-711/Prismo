-- gr_quote：各 gr 标的最新行情（pipeline `gr-quote` 从 Yahoo 15m chart 抓），
-- 供标的页展示「最新价 + 涨跌幅」。在 Supabase → SQL Editor 整段执行一次（幂等，可重复跑）。
-- 本地 sqlite 由 pipeline 的 _ensure_tables 自动建表，无需手动跑。
create table if not exists public.gr_quote (
  ticker      text primary key,
  price       double precision default 0,
  prev_close  double precision default 0,
  change_pct  double precision default 0,
  currency    text default 'USD',
  asof        text default '',
  updated_at  timestamptz default now()
);
