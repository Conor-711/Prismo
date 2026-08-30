export type SmartVoiceDirection = "bull" | "bear";

export interface SmartVoiceTickerRank {
  ticker: string;
  nameZh: string;
  nameEn: string;
  bullScore: number;
  bearScore: number;
  netScore: number;
  highBullScore: number;
  highBearScore: number;
  lowBullScore: number;
  lowBearScore: number;
  highNet: number;
  lowNet: number;
  contrastScore: number;
  nBull: number;
  nBear: number;
  nPosts: number;
  nVoices: number;
  bullVoices: number;
  bearVoices: number;
  highBullCalls: number;
  highBearCalls: number;
  lowBullCalls: number;
  lowBearCalls: number;
  highVoices: number;
  lowVoices: number;
  highBullVoices: number;
  highBearVoices: number;
  lowBullVoices: number;
  lowBearVoices: number;
  highAuthorBullCount: number;
  highAuthorBearCount: number;
  highAuthorNet: number;
  highAuthorConsensus: number;
  previousHighAuthorBullCount: number;
  previousHighAuthorBearCount: number;
  previousHighAuthorNet: number;
  previousHighAuthorConsensus: number;
  authorNetDelta: number;
  authorNetShiftPct: number;
  authorNetAbrupt: boolean;
  authorNetShiftRank: number;
  newCoverageAuthorCount: number;
  newCoverageBullCount: number;
  newCoverageBearCount: number;
  currentTopAuthorCount: number;
  priorTopAuthorCount: number;
  newCoverageRatio: number;
  newCoverageScore: number;
  newestMentionAt: string;
  cohortNew: boolean;
  topHandles: string[];
  evidenceIds: SmartVoiceTickerEvidenceIds;
  signal: "high_bull_low_bear" | "high_bear_low_bull" | "sv_consensus_bull" | "sv_consensus_bear" | "mixed";
}

export interface SmartVoiceTickerEvidence {
  id: string;
  ticker: string;
  source: SmartVoiceMarketSource;
  direction: SmartVoiceDirection;
  rankBand: "top" | "bottom";
  author: string;
  createdAt: string;
  platformSv: number;
  confidence: string;
  callWeight: number;
  horizon: string;
  targetPrice: number | null;
  summaryZh: string;
  summaryEn: string;
  originalEvidence: string;
  url: string;
}

export interface SmartVoiceTickerEvidenceIds {
  highBull: string[];
  highBear: string[];
  lowBull: string[];
  lowBear: string[];
  previousHighBull: string[];
  previousHighBear: string[];
}

export interface SmartVoiceTickerBoards {
  bullish: SmartVoiceTickerRank[];
  bearish: SmartVoiceTickerRank[];
  contrast: SmartVoiceTickerRank[];
  authorShift: SmartVoiceTickerRank[];
  newCoverage: SmartVoiceTickerRank[];
}

export type SmartVoiceMarketSource = "x" | "youtube" | "reddit" | "xueqiu";
export type SmartVoiceMarketWindow = "24H" | "3D" | "7D" | "30D" | "90D";
export type SmartVoiceMarketPlatformKey =
  | "all"
  | "x" | "youtube" | "reddit" | "xueqiu"
  | "x+youtube" | "x+reddit" | "x+xueqiu" | "youtube+reddit" | "youtube+xueqiu" | "reddit+xueqiu"
  | "x+youtube+reddit" | "x+youtube+xueqiu" | "x+reddit+xueqiu" | "youtube+reddit+xueqiu";
export type SmartVoiceTickerBoardMatrix = Record<SmartVoiceMarketPlatformKey, Record<SmartVoiceMarketWindow, SmartVoiceTickerBoards>>;

export interface SmartVoiceMarketData {
  boards: SmartVoiceTickerBoardMatrix;
  evidenceById: Record<string, SmartVoiceTickerEvidence>;
  latestAt: string;
}

export interface SmartVoiceRawCall {
  evidenceId: string;
  investorId: string;
  ticker: string;
  nameZh: string;
  nameEn: string;
  direction: SmartVoiceDirection;
  callWeight: number;
  sv: number;
  platformSv: number;
  nEff: number;
  confidence: string;
  handle: string;
  source: string;
  createdAt: string;
  latestAt: string;
  horizon: string;
  targetPrice: number | null;
  evidenceScore: number;
  rankBand: "top" | "bottom" | "middle";
  platformRankBand: "top" | "bottom" | "middle";
}

export interface SmartVoiceEvidenceContent {
  id: string;
  summaryZh: string;
  summaryEn: string;
  originalEvidence: string;
  url: string;
}

export interface SmartVoiceOverviewStats {
  scoredInvestors: number;
  highConfidenceInvestors: number;
  platformCount: number;
  actionableCalls: number;
  latestCallAt: string;
}

export interface SmartVoiceLiveCall {
  id: string;
  ticker: string;
  nameZh: string;
  nameEn: string;
  source: string;
  direction: SmartVoiceDirection;
  investorId: string;
  author: string;
  createdAt: string;
  horizon: string;
  targetPrice: number | null;
  callWeight: number;
  summaryZh: string;
  summaryEn: string;
  investorStyle: string;
  sv: number;
  confidence: string;
  url: string;
}
