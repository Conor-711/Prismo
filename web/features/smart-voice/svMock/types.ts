export type SvSource = "x" | "youtube" | "reddit" | "xueqiu" | "toss";
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

export interface SvAbilityScore {
  benchmark: "SPY" | "industry_etf";
  svPlatform: number | null;
  svGlobal: number | null;
  rawZ: number | null;
  confidence: SvConfidence | "unavailable";
  nEff: number;
  settledCalls: number;
  coverage?: number;
}

export interface SvAbilityScores {
  compositePlatformSv: number;
  compositeRawZ: number;
  industryBlendWeight: number;
  marketSelection: SvAbilityScore;
  industrySelection: SvAbilityScore;
}

export interface SvInvestor {
  id: string;
  rank?: number;
  platformRank?: number;
  observationRank?: number;
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
  abilities?: SvAbilityScores;
  horizonScores: Partial<Record<SvHorizon, number | null>>;
  narrativeScores: Record<string, number>;
  tickerScores: Record<string, number>;
  concentration?: {
    dominantInvestorType?: string;
    investorTypeShare?: Record<string, number>;
    topTicker?: string;
    topTickerWeightShare?: number;
    topPositiveTicker?: string;
    topPositiveContributionShare?: number;
    effectiveTickersByWeight?: number;
    effectiveTickersByPositiveContribution?: number;
    cap?: number;
    capApplied?: boolean;
    rawSvBeforeConcentrationCap?: number;
    svPlatform?: number;
    svPlatformRaw?: number;
    svGlobal?: number;
    svGlobalDeviation?: number;
    confidenceFactor?: number;
    platformBaseline?: number;
    primaryPlatform?: string;
    platformPool?: { qualified?: number; total?: number };
  };
  rationaleZh: string;
  rationaleEn: string;
}

export interface SvPlatformBand {
  source: SvSource;
  scoreKind: "SV_Platform";
  totalCount: number;
  qualifiedCount: number;
  rankedCount: number;
  population: "qualified" | "all_scored_fallback";
  distribution: SvDistribution;
  top25Threshold: number;
  bottom25Threshold: number;
  ranked: SvInvestor[];
  observed: SvInvestor[];
  top10: SvInvestor[];
  bottom10: SvInvestor[];
  top25: SvInvestor[];
  bottom25: SvInvestor[];
}

export interface SvBoard {
  investors: SvInvestor[];
  bottomInvestors?: SvInvestor[];
  x: SvInvestor[];
  youtube: SvInvestor[];
  reddit: SvInvestor[];
  xueqiu: SvInvestor[];
  toss: SvInvestor[];
  currentNarratives: { key: string; zh: string; en: string; weight: number }[];
  updatedAt: string;
  scoringVersion?: string;
  platformScoringVersions?: Partial<Record<SvSource, string>>;
  totalInvestors?: number;
  exportedInvestors?: number;
  distribution?: SvDistribution;
  platformBands?: Partial<Record<SvSource, SvPlatformBand>>;
}

export interface SvTickerBoard {
  ticker: string;
  narrative: { key: string; zh: string; en: string };
  investors: (SvInvestor & { contextualSv: number; basisZh: string; basisEn: string })[];
}

export const SV_HORIZONS: SvHorizon[] = ["1D", "5D", "20D", "60D", "90D", "180D"];
