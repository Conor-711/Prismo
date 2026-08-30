import type { CollectionKind, CollectionRow } from "@/lib/favorites";
import type { KolOpinion, KolSource, Stance } from "@/shared/market/mockDetail";

export type TrackKind = Extract<CollectionKind, "ticker" | "author" | "narrative">;

export const emptyCollections = (): Record<TrackKind, CollectionRow[]> => ({
  ticker: [],
  author: [],
  narrative: [],
});

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
  tickers: string[];
}

export interface TrackingCatalog {
  authors: TrackingAuthorCandidate[];
  narratives: TrackingNarrativeCandidate[];
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

export type TrackingFeedMode = "personal" | "latest" | "quality" | "changes";
export type TrackingPeriod = 1 | 3 | 7 | 30;
export type TrackingStanceFilter = "all" | Stance;
export type TrackingSourceFilter = "all" | KolSource;

export interface TrackingFeedItem {
  symbol: string;
  opinion: KolOpinion;
  narrativeKey?: string;
  svScore?: number;
  svRank?: number;
  svPopulation?: number;
  svPercentile?: number;
}

export interface TrackingRankReason {
  zh: string;
  en: string;
}

export interface TrackingRankedItem extends TrackingFeedItem {
  feedScore: number;
  reasons: TrackingRankReason[];
}
