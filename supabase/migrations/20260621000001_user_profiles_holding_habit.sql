-- 给「投资画像」加一个维度：持有习惯（持仓/交易节奏）。
--   longterm  长线持有（数月~数年）
--   swing     波段操作（数周~数月）
--   shortterm 短线 / 日内
--   dca       定投（定期定额）
-- 追加列，幂等：原表见 20260620000001_user_profiles.sql。
-- 在 Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。

alter table public.user_profiles
  add column if not exists holding_habit text
  check (holding_habit in ('longterm','swing','shortterm','dca'));
