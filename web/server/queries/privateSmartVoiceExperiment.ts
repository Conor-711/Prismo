import privateSmartVoiceMvp from "@/lib/data/privateSmartVoiceMvp.json";
import type {
  SmartVoiceRepresentativeCall,
  SmartVoiceRepresentativePricePoint,
} from "@/server/queries/smartVoiceInvestorQueries";

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

export interface PrivateSmartVoicePortfolioBacktest {
  version: string;
  methodology: {
    mode: string;
    entry: string;
    exit: string;
    allocation: string;
    cashWhenInactive: boolean;
    roundTripCostBps: number;
    riskFreeRate: number;
    sameTickerRule: string;
    overlappingCallsReplaced: number;
  };
  base: {
    costBps: number;
    startDay: string;
    endDay: string;
    tradingDays: number;
    activeDays: number;
    tradeCount: number;
    exposurePct: number;
    averageActivePositions: number;
    turnoverUnits: number;
    totalReturn: number;
    annualizedReturn: number | null;
    annualizedExcessReturn: number | null;
    annualizedVolatility: number | null;
    sharpe: number | null;
    sortino: number | null;
    maxDrawdown: number;
    drawdownPeakDay: string;
    drawdownTroughDay: string;
    calmar: number | null;
    positiveActiveDayRate: number | null;
    benchmarkTotalReturn: number;
    benchmarkAnnualizedReturn: number | null;
    benchmarkMaxDrawdown: number;
    beta: number | null;
    annualizedAlpha: number | null;
    yearReturns: {
      year: string;
      return: number;
      benchmarkReturn: number;
    }[];
    equityCurve: {
      day: string;
      strategy: number;
      benchmark: number;
      drawdown: number;
      activePositions: number;
    }[];
  };
  costSensitivity: {
    costBps: number;
    totalReturn: number;
    annualizedReturn: number | null;
    sharpe: number | null;
  }[];
}

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
