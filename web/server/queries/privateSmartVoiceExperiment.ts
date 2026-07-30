import privateSmartVoiceMvp from "@/lib/data/privateSmartVoiceMvp.json";
import type {
  SmartVoiceRepresentativeCall,
  SmartVoiceRepresentativePricePoint,
} from "@/server/queries/smartVoiceInvestorQueries";
import type { SmartVoicePortfolioBacktest } from "@/server/queries/smartVoicePortfolioQueries";

export interface PrivateSmartVoiceCall extends SmartVoiceRepresentativeCall {
  publishedAt: string;
  evidence: string;
  industryBenchmark: string;
  industryDirectionalExcessPct: number | null;
  style: string;
  views: number;
  reactions: number;
}

export interface PrivateSmartVoiceTicker {
  ticker: string;
  companyName: string;
  sector: string;
  settledCalls: number;
  bullCalls: number;
  bearCalls: number;
  hitRate: number;
  meanDirectionalSpyExcessPct: number;
  focusContribution: number;
  latestDirection: "bull" | "bear" | "neutral";
  latestAt: string;
  latestUrl: string;
  calls: PrivateSmartVoiceCall[];
  prices: SmartVoiceRepresentativePricePoint[];
}

export type PrivateSmartVoicePortfolioBacktest = SmartVoicePortfolioBacktest;

export interface PrivateSmartVoiceExperimentData {
  version: string;
  generatedAt: string;
  reportVersion: string;
  scoringVersion: string;
  settlementVersion: string;
  channel: {
    handle: string;
    title: string;
    description: string;
    publicUrl: string;
    subscriberCount: number;
    messageCount: number;
    firstMessageAt: string;
    lastMessageAt: string;
  };
  score: {
    sv: number;
    confidence: string;
    nEff: number;
    settledCalls: number;
    activeDays: number;
    coveredTickers: number;
    referencePercentile: number;
    referencePopulation: number;
    explanationZh: string;
  };
  style: {
    dominant: string;
    distribution: Record<string, number>;
  };
  performance: {
    calls: number;
    bullCalls: number;
    bearCalls: number;
    spyExcessHitRate: number | null;
    meanDirectionalSpyExcessPct: number | null;
    medianDirectionalSpyExcessPct: number | null;
    averagePositiveExcessPct: number | null;
    averageNegativeExcessPct: number | null;
    payoffRatio: number | null;
    profitFactor: number | null;
    industryCalls: number;
    industryExcessHitRate: number | null;
    meanDirectionalIndustryExcessPct: number | null;
    callsByYear: Record<string, number>;
  };
  dataQuality: {
    messages: number;
    forwardedExcluded: number;
    candidateTickerPairs: number;
    extractedPairs: number;
    actionableCalls: number;
    settledPrimaryCalls: number;
  };
  portfolioBacktest: PrivateSmartVoicePortfolioBacktest;
  bestCases: PrivateSmartVoiceCall[];
  weakCases: PrivateSmartVoiceCall[];
  tickers: PrivateSmartVoiceTicker[];
}

export function getPrivateSmartVoiceExperiment(): PrivateSmartVoiceExperimentData {
  return privateSmartVoiceMvp as unknown as PrivateSmartVoiceExperimentData;
}
