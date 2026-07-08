export type SvSource = "x" | "youtube";
export type SvHorizon = "1D" | "5D" | "20D" | "60D" | "90D" | "180D";
export type SvConfidence = "observing" | "low" | "medium" | "high";

export interface SvDistribution {
  count: number;
  min: number;
  q25: number;
  median: number;
  q75: number;
  max: number;
  top10Threshold: number;
  bottom10Threshold: number;
  bins: { from: number; to: number; count: number }[];
}

export interface SvInvestor {
  id: string;
  rank?: number;
  svDelta?: number | null;
  rankDelta?: number | null;
  nEffDelta?: number | null;
  settledCallsDelta?: number | null;
  previousConfidence?: SvConfidence | null;
  source: SvSource;
  name: string;
  handle: string;
  avatar?: string;
  url?: string;
  language: "zh" | "en" | "ko" | "ja";
  sv: number;
  confidence: SvConfidence;
  nEff: number;
  settledCalls: number;
  activeDays: number;
  coveredTickers: number;
  topTickers: string[];
  topNarratives: string[];
  platformScores: Partial<Record<SvSource, number>>;
  horizonScores: Partial<Record<SvHorizon, number | null>>;
  narrativeScores: Record<string, number>;
  tickerScores: Record<string, number>;
  concentration?: {
    dominantInvestorType?: string;
    investorTypeShare?: Record<string, number>;
    topTicker?: string;
    topTickerWeightShare?: number;
    effectiveTickersByWeight?: number;
    capApplied?: boolean;
  };
  rationaleZh: string;
  rationaleEn: string;
}

export interface SvBoard {
  investors: SvInvestor[];
  bottomInvestors?: SvInvestor[];
  x: SvInvestor[];
  youtube: SvInvestor[];
  currentNarratives: { key: string; zh: string; en: string; weight: number }[];
  updatedAt: string;
  scoringVersion?: string;
  totalInvestors?: number;
  exportedInvestors?: number;
  distribution?: SvDistribution;
}

export interface SvTickerBoard {
  ticker: string;
  narrative: { key: string; zh: string; en: string };
  investors: (SvInvestor & { contextualSv: number; basisZh: string; basisEn: string })[];
}

export const SV_HORIZONS: SvHorizon[] = ["1D", "5D", "20D", "60D", "90D", "180D"];
