import data from "./data/narrativeRotation.json";
import type { Locale } from "./i18n";

export interface BiText { zh: string; en: string }

export interface NarrativeCategory {
  id: string;
  slug: string;
  title: BiText;
  description: BiText;
  color: string;
  tickers?: string[];
}

export interface NarrativeDay {
  day: string;
  volume: number;
  share: number;
  sentiment: number;
  rank: number | null;
  bull?: number;
  bear?: number;
  neutral?: number;
  sources?: Record<string, number>;
}

export interface NarrativeLeader {
  id: string;
  slug: string;
  title: BiText;
  color: string;
  rank: number | null;
  previousRank: number | null;
  rankDelta: number | null;
  volume: number;
  share: number;
  shareDelta: number;
  sentiment: number;
  sentimentDelta: number;
  trend: "rising" | "gaining_share" | "turning_bull" | "turning_bear" | "cooling" | "stable" | "quiet";
  topTickers: { ticker: string; count: number }[];
}

export interface NarrativeDetail {
  topTickers: { ticker: string; count: number }[];
  sources: { source: string; count: number }[];
  regions: { region: string; count: number }[];
  windowVolume: number;
  windowSentiment: number;
}

export interface NarrativeRotationData {
  version: number;
  updated_at: string;
  window: { start: string; end: string; days: string[] };
  sourceLabels: Record<string, BiText>;
  categories: NarrativeCategory[];
  summary: {
    active: number;
    totalVolume: number;
    topNarrative: string | null;
    windowDays: number;
    recentDays: number;
  };
  leaderboard: NarrativeLeader[];
  series: Record<string, NarrativeDay[]>;
  details: Record<string, NarrativeDetail>;
}

const DATA = data as unknown as NarrativeRotationData;

export function narrativeText(text: BiText, lang: Locale): string {
  return lang === "zh" ? text.zh : text.en;
}

export function getNarrativeRotation(): NarrativeRotationData {
  return DATA;
}

export function getNarrativeSlugs(): string[] {
  return DATA.categories.map((c) => c.slug);
}

export function getNarrativeBySlug(slug: string) {
  const category = DATA.categories.find((c) => c.slug === slug);
  if (!category) return null;
  const leader = DATA.leaderboard.find((r) => r.id === category.id) ?? null;
  return {
    category,
    leader,
    series: DATA.series[category.id] ?? [],
    detail: DATA.details[category.id] ?? { topTickers: [], sources: [], regions: [], windowVolume: 0, windowSentiment: 0 },
  };
}

export function trendLabel(trend: NarrativeLeader["trend"], lang: Locale): string {
  const zh: Record<NarrativeLeader["trend"], string> = {
    rising: "排名上升",
    gaining_share: "占比扩大",
    turning_bull: "情绪转多",
    turning_bear: "情绪转空",
    cooling: "热度降温",
    stable: "平稳",
    quiet: "低活跃",
  };
  const en: Record<NarrativeLeader["trend"], string> = {
    rising: "Rank rising",
    gaining_share: "Share gaining",
    turning_bull: "Turning bullish",
    turning_bear: "Turning bearish",
    cooling: "Cooling",
    stable: "Stable",
    quiet: "Quiet",
  };
  return (lang === "zh" ? zh : en)[trend];
}
