import type { KolSource } from "@/shared/market/mockDetail";
import type { SvTickerBoard } from "@/features/smart-account/svMock";

export type LensKey =
  | "valuation"
  | "growth"
  | "competition"
  | "management"
  | "macro"
  | "catalyst"
  | "flows"
  | "other";

export type SvPreset = "off" | "top25" | "middle50" | "bottom25" | "custom";

export interface SvRangeFilter {
  enabled: boolean;
  low: number;
  high: number;
  preset: SvPreset;
}

export type SvOpinionMeta = {
  rank: number;
  percentile: number;
  score: number;
  investor: SvTickerBoard["investors"][number];
};

export type SvOpinionIndex = {
  byKey: Map<string, SvOpinionMeta>;
  count: number;
};

export type SortMode = "personal" | "sv" | "rel" | "time" | "hot";
export type PersonalDirection = "" | "long" | "short" | "watch";
export type PersonalStyle = "" | "shortterm" | "swing" | "longterm" | "dca";
export type RecommendationReason = { zh: string; en: string };
export type RecommendationMeta = { score: number; reasons: RecommendationReason[] };

export interface PersonalPrefs {
  direction: PersonalDirection;
  style: PersonalStyle;
  costLow: string;
  costHigh: string;
  positionLow: string;
  positionHigh: string;
  targetPrice: string;
  stopLoss: string;
}

export type PlatformAvailability = {
  plat: Set<KolSource | string>;
  lang: Set<string>;
};
