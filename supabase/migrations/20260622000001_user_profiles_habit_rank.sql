-- 持有习惯：从「单选」升级为「排序/排名」。
-- 用 text[] 存有序的习惯排名（队首=最贴合）；旧的单值列 holding_habit 继续写入排名队首，
-- 以兼容既有读取与 check 约束（见 20260621000001_user_profiles_holding_habit.sql）。
-- 幂等追加列。Supabase → SQL Editor 整段执行一次（或连 GitHub 自动应用）。
alter table public.user_profiles
  add column if not exists habit_rank text[];
