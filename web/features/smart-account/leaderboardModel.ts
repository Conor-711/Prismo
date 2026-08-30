import { SOURCE } from "@/shared/market/kolPresentation";
import type { SmartVoiceLeaderboardInvestor } from "./svLeaderboardData";
import type { SvHorizon } from "./svMock";

export type Platform = "all" | "x" | "youtube" | "reddit" | "xueqiu";
export type Band = "all" | "observed" | "top" | "bottom";
export type ScoreMode = "overall" | SvHorizon;
export type HorizonLevel = "all" | "short" | "medium" | "long";

export interface FilterOption<T extends string> {
  value: T;
  label: string;
  hint?: string;
}

const HORIZON_LEVELS: Record<Exclude<HorizonLevel, "all">, SvHorizon[]> = {
  short: ["1D", "5D"],
  medium: ["20D", "60D"],
  long: ["90D", "180D"],
};

export const HORIZON_LEVEL_LABELS: Record<HorizonLevel, [string, string]> = {
  all: ["全部周期", "All horizons"],
  short: ["短线", "Short-term"],
  medium: ["中线", "Medium-term"],
  long: ["长线", "Long-term"],
};

export const NARRATIVE_ORDER = [
  "semis",
  "ai_infra",
  "software",
  "consumer",
  "fintech",
  "media",
  "ev",
  "crypto",
  "other",
];

export const STYLE_LABEL: Record<string, [string, string]> = {
  technical: ["技术分析", "Technical"],
  fundamental: ["基本面", "Fundamental"],
  event_driven: ["事件驱动", "Event driven"],
  macro: ["宏观", "Macro"],
  flow_momentum: ["资金流 / 动量", "Flow / momentum"],
  mixed: ["混合", "Mixed"],
  unknown: ["未分类", "Unknown"],
};

export function styleLabel(inv: SmartVoiceLeaderboardInvestor, zh: boolean) {
  const key = inv.dominantInvestorType || "unknown";
  const value = STYLE_LABEL[key] ?? [key, key];
  return value[zh ? 0 : 1];
}

function scoreOf(inv: SmartVoiceLeaderboardInvestor, platform: Platform, scoreMode: ScoreMode) {
  if (scoreMode !== "overall") return inv.horizonScores[scoreMode] ?? -Infinity;
  if (platform !== "all") return inv.platformScores[platform] ?? inv.sv;
  return inv.sv;
}

function average(values: Array<number | null | undefined>) {
  const available = values.filter((value): value is number => typeof value === "number" && Number.isFinite(value));
  if (!available.length) return null;
  return available.reduce((sum, value) => sum + value, 0) / available.length;
}

function horizonLevelScore(inv: SmartVoiceLeaderboardInvestor, level: Exclude<HorizonLevel, "all">) {
  return average(HORIZON_LEVELS[level].map((horizon) => inv.horizonScores[horizon]));
}

export function dominantHorizonLevel(inv: SmartVoiceLeaderboardInvestor): Exclude<HorizonLevel, "all"> | null {
  const scores = (Object.keys(HORIZON_LEVELS) as Array<Exclude<HorizonLevel, "all">>)
    .map((level) => ({ level, score: horizonLevelScore(inv, level) }))
    .filter((item): item is { level: Exclude<HorizonLevel, "all">; score: number } => item.score !== null);
  if (!scores.length) return null;
  return scores.sort((a, b) => b.score - a.score)[0].level;
}

export function contextualScore(
  inv: SmartVoiceLeaderboardInvestor,
  platform: Platform,
  scoreMode: ScoreMode,
  horizonLevel: HorizonLevel,
  narrative: string,
) {
  if (scoreMode !== "overall") return scoreOf(inv, platform, scoreMode);
  const abilityScores: number[] = [];
  if (horizonLevel !== "all") {
    const value = horizonLevelScore(inv, horizonLevel);
    if (value !== null) abilityScores.push(value);
  }
  if (narrative !== "all" && typeof inv.narrativeScores[narrative] === "number") {
    abilityScores.push(inv.narrativeScores[narrative]);
  }
  return average(abilityScores) ?? scoreOf(inv, platform, scoreMode);
}

export function formattedScore(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

export function cleanHandle(handle: string) {
  return handle.replace(/^@+/, "");
}

export function sourceColor(inv: SmartVoiceLeaderboardInvestor) {
  return SOURCE[inv.source]?.color ?? "#8C96A2";
}

export function uniqueInvestors(investors: SmartVoiceLeaderboardInvestor[]) {
  return [...new Map(investors.map((investor) => [investor.id, investor])).values()];
}
