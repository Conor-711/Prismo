import type { CollectionKind, CollectionRow } from "@/lib/favorites";

export type TrackKind = Extract<CollectionKind, "ticker" | "author" | "narrative" | "region" | "subreddit">;
export type SortKey = "added" | "sent" | "posts";
export type ActiveTab = "all" | TrackKind;

export const TRACK_KINDS: TrackKind[] = ["ticker", "author", "narrative", "region", "subreddit"];

export const emptyCollections = (): Record<TrackKind, CollectionRow[]> => ({
  ticker: [],
  author: [],
  narrative: [],
  region: [],
  subreddit: [],
});

export function emptyCounts(): Record<TrackKind, number> {
  return { ticker: 0, author: 0, narrative: 0, region: 0, subreddit: 0 };
}

export interface TrackingAuthorCandidate {
  refId: string;
  source: string;
  name: string;
  avatar?: string;
  url?: string;
  href?: string;
  metric: number;
  posts: number;
  tickers: string[];
}

export interface TrackingNarrativeCandidate {
  refId: string;
  titleZh: string;
  titleEn: string;
  descriptionZh: string;
  descriptionEn: string;
  color: string;
  rank: number | null;
  share: number;
  volume: number;
  trendZh: string;
  trendEn: string;
}

export interface TrackingRegionCandidate {
  refId: string;
  posts: number;
  tickers: number;
  avgSentiment: number;
  bullPct: number;
  bearPct: number;
}

export interface TrackingCatalog {
  authors: TrackingAuthorCandidate[];
  narratives: TrackingNarrativeCandidate[];
  regions: TrackingRegionCandidate[];
}

export type QuickCandidate = {
  kind: TrackKind;
  refId: string;
  label: string;
  sub: string;
  href?: string;
  url?: string;
  color?: string;
  avatar?: string;
  ticker?: string;
};

export function kindLabel(kind: TrackKind, zh: boolean) {
  const z: Record<TrackKind, string> = { ticker: "标的", author: "作者", narrative: "叙事", region: "区域", subreddit: "社区" };
  const e: Record<TrackKind, string> = { ticker: "Tickers", author: "Authors", narrative: "Narratives", region: "Regions", subreddit: "Communities" };
  return (zh ? z : e)[kind];
}

export function kindHint(kind: TrackKind, zh: boolean) {
  const z: Record<TrackKind, string> = { ticker: "价格与情绪", author: "观点来源", narrative: "市场故事", region: "本土社区", subreddit: "Reddit" };
  const e: Record<TrackKind, string> = { ticker: "prices & sentiment", author: "source voices", narrative: "market stories", region: "native boards", subreddit: "Reddit" };
  return (zh ? z : e)[kind];
}
