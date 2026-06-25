// 账户系统的客户端数据层：用户「投资画像」（onboarding 引导采集）。
// 照抄 favorites.ts 范式 —— 客户端经 anon key + RLS 直接读写 Supabase，未配置时静默降级。
// 后端 schema 见 supabase/migrations/20260620000001_user_profiles.sql。
import type { User } from "@supabase/supabase-js";
import { supabase } from "./supabase";

export type Experience = "new" | "growing" | "seasoned" | "veteran";
export type PortfolioSize = "lt1k" | "1k_10k" | "10k_50k" | "50k_250k" | "gt250k" | "na";
export type HoldingHabit = "longterm" | "swing" | "shortterm" | "dca";

// 关注方向的稳定 key（存库；文案在 dict.onboarding.interests[key]）。顺序即展示顺序。
export const INTEREST_KEYS = [
  "ai",
  "semi",
  "crypto",
  "ev",
  "software",
  "china",
  "meme",
  "bluechip",
  "biotech",
  "energy",
  "options",
  "etf",
] as const;
export type InterestKey = (typeof INTEREST_KEYS)[number];

export const EXPERIENCE_KEYS: Experience[] = ["new", "growing", "seasoned", "veteran"];
export const SIZE_KEYS: PortfolioSize[] = ["lt1k", "1k_10k", "10k_50k", "50k_250k", "gt250k", "na"];
export const HABIT_KEYS: HoldingHabit[] = ["longterm", "swing", "shortterm", "dca"];

// 把（可能不完整 / 含旧单值 / 含脏值的）持有习惯排名规整成「4 项有序全集」：
// 先按给定顺序保留合法且去重的项，再把缺失项按默认顺序补到末尾。
export function normalizeHabitRank(arr: readonly string[] | null | undefined): HoldingHabit[] {
  const out: HoldingHabit[] = [];
  for (const x of arr ?? []) {
    if ((HABIT_KEYS as readonly string[]).includes(x) && !out.includes(x as HoldingHabit)) out.push(x as HoldingHabit);
  }
  for (const k of HABIT_KEYS) if (!out.includes(k)) out.push(k);
  return out;
}

export interface UserProfile {
  experience: Experience | null;
  interests: string[];
  holdings: string[];
  holding_habit: HoldingHabit | null; // 兼容旧单值：= 排名队首
  habit_rank: HoldingHabit[] | null; // 持有习惯排名（有序，队首=最贴合）
  portfolio_size: PortfolioSize | null;
  onboarded_at: string | null;
}

export const EMPTY_PROFILE: UserProfile = {
  experience: null,
  interests: [],
  holdings: [],
  holding_habit: null,
  habit_rank: null,
  portfolio_size: null,
  onboarded_at: null,
};

// 读当前用户画像（不存在 → null；未配置/出错 → null，静默降级）。
export async function loadProfile(userId: string): Promise<UserProfile | null> {
  if (!supabase) return null;
  try {
    const { data, error } = await supabase
      .from("user_profiles")
      // 用 * 避免「habit_rank 列尚未迁移」时整条查询报错（缺列即不返回该键，静默降级）。
      .select("*")
      .eq("user_id", userId)
      .maybeSingle();
    if (error || !data) return null;
    return {
      experience: (data.experience as Experience) ?? null,
      interests: (data.interests as string[]) ?? [],
      holdings: (data.holdings as string[]) ?? [],
      holding_habit: (data.holding_habit as HoldingHabit) ?? null,
      habit_rank: (data.habit_rank as HoldingHabit[]) ?? null,
      portfolio_size: (data.portfolio_size as PortfolioSize) ?? null,
      onboarded_at: (data.onboarded_at as string) ?? null,
    };
  } catch {
    return null;
  }
}

// upsert 画像（部分字段）。成功 true。
export async function saveProfile(
  userId: string,
  patch: Partial<Omit<UserProfile, "onboarded_at">> & { onboarded_at?: string | null }
): Promise<boolean> {
  if (!supabase) return false;
  try {
    const row: Record<string, unknown> = { user_id: userId, updated_at: new Date().toISOString() };
    if (patch.experience !== undefined) row.experience = patch.experience;
    if (patch.interests !== undefined) row.interests = patch.interests;
    if (patch.holdings !== undefined) row.holdings = patch.holdings;
    if (patch.holding_habit !== undefined) row.holding_habit = patch.holding_habit;
    if (patch.portfolio_size !== undefined) row.portfolio_size = patch.portfolio_size;
    if (patch.onboarded_at !== undefined) row.onboarded_at = patch.onboarded_at;
    const { error } = await supabase.from("user_profiles").upsert(row, { onConflict: "user_id" });
    if (error) return false;
    // habit_rank 单独尽力写：列可能尚未迁移；失败不影响上面已保存的其余字段（含 holding_habit=队首）。
    if (patch.habit_rank !== undefined) {
      await supabase.from("user_profiles").update({ habit_rank: patch.habit_rank }).eq("user_id", userId);
    }
    return true;
  } catch {
    return false;
  }
}

// 本地「已引导」标志：跨设备真源是 user_metadata，但 updateUser→React state 传播有微小时延，
// 完成后立刻跳转可能让门禁用旧 user 误判→闪回引导页。这个按 uid 的本地旗作为同设备即时兜底。
const onbFlagKey = (uid: string) => `redditalpha:onb:${uid}`;
function setLocalOnboarded(uid: string) {
  try {
    if (typeof window !== "undefined") window.localStorage.setItem(onbFlagKey(uid), "1");
  } catch {
    /* localStorage 不可用 → 忽略，仍有 metadata 真源 */
  }
}
function hasLocalOnboarded(uid: string): boolean {
  try {
    return typeof window !== "undefined" && window.localStorage.getItem(onbFlagKey(uid)) === "1";
  } catch {
    return false;
  }
}

// 把「已完成引导」写进 auth user_metadata（跨设备真源）+ 本地旗（同设备即时）。
export async function markOnboarded(userId?: string): Promise<void> {
  if (userId) setLocalOnboarded(userId);
  if (!supabase) return;
  try {
    await supabase.auth.updateUser({ data: { onboarded: true } });
  } catch {
    /* 静默：失败时门禁会再次引导，无大碍 */
  }
}

// 门禁判定：读 session 里的 user_metadata.onboarded（同步、无 IO）；本地旗兜底传播时延。
export function isOnboarded(user: User | null): boolean {
  if (!user) return false;
  if ((user.user_metadata as Record<string, unknown> | undefined)?.onboarded) return true;
  return hasLocalOnboarded(user.id);
}

// 测试用：清掉「已引导」标志（本地旗 + user_metadata.onboarded=false）→ 下次门禁会重新引导。
export async function resetOnboarding(userId: string): Promise<void> {
  try {
    if (typeof window !== "undefined") window.localStorage.removeItem(onbFlagKey(userId));
  } catch {
    /* ignore */
  }
  if (!supabase) return;
  try {
    await supabase.auth.updateUser({ data: { onboarded: false } });
  } catch {
    /* ignore */
  }
}

// 测试用：把画像清空（本表无 delete 权限 → upsert 成空行）。
export async function clearProfile(userId: string): Promise<boolean> {
  return saveProfile(userId, {
    experience: null,
    interests: [],
    holdings: [],
    holding_habit: null,
    habit_rank: null,
    portfolio_size: null,
    onboarded_at: null,
  });
}
