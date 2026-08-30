export interface SmartVoiceEvidenceCall {
  candidateId: string;
  ticker: string;
  source: string;
  day: string;
  direction: "bull" | "bear" | "neutral";
  horizon: string;
  callWeight: number;
  summaryZh: string;
  summaryEn: string;
  evidenceSpan: string;
  text: string;
  url: string;
  interactions: number;
  contribution: number | null;
  returnPct: number | null;
  excessReturnPct: number | null;
  actualHit: number | null;
  status: string | null;
  entryDay: string;
  exitDay: string;
  entryPrice: number | null;
  exitPrice: number | null;
}

export interface SmartVoiceEvidencePriceBar {
  day: string;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export interface SmartVoiceInvestorEvidence {
  bestCalls: SmartVoiceEvidenceCall[];
  weakCalls: SmartVoiceEvidenceCall[];
  recentCalls: SmartVoiceEvidenceCall[];
  allCalls: SmartVoiceEvidenceCall[];
  performance: SmartVoicePerformanceStats;
  priceByTicker: Record<string, SmartVoiceEvidencePriceBar[]>;
}

export interface SmartVoicePerformanceStats {
  settledCalls: number;
  gradedCalls: number;
  hitRate: number | null;
  positiveCalls: number;
  negativeCalls: number;
  netContribution: number;
  medianDirectionalExcess: number | null;
  coveredTickers: number;
  firstDay: string;
  lastDay: string;
}

export interface SmartVoiceRepresentativeCall {
  candidateId: string;
  ticker: string;
  source: string;
  day: string;
  direction: "bull" | "bear" | "neutral";
  horizon: string;
  summaryZh: string;
  summaryEn: string;
  url: string;
  contribution: number;
  returnPct: number | null;
  excessReturnPct: number | null;
  actualHit: number | null;
  entryDay: string;
  exitDay: string;
  entryPrice: number | null;
  exitPrice: number | null;
}

export interface SmartVoiceRepresentativeShowcase {
  ticker: string;
  kind: "best" | "weak";
  focusContribution: number;
  focusCallCount: number;
  calls: SmartVoiceRepresentativeCall[];
}

export interface SmartVoiceRepresentativeEvidence {
  best: SmartVoiceRepresentativeShowcase | null;
  weak: SmartVoiceRepresentativeShowcase | null;
}

export type SmartVoiceRepresentativePricePoint = [day: string, close: number];

export interface SmartVoiceRepresentativeEvidenceBundle {
  byInvestor: Record<string, SmartVoiceRepresentativeEvidence>;
  priceByTicker: Record<string, SmartVoiceRepresentativePricePoint[]>;
}

export interface SmartVoiceRawEvidenceCall {
  candidateId: string;
  ticker: string;
  source: string;
  day: string;
  direction: "bull" | "bear" | "neutral";
  horizon: string;
  callWeight: number;
  summaryZh: string;
  summaryEn: string;
  evidenceSpan: string;
  text: string;
  url: string;
  interactions: number;
  contribution: number | null;
  returnPct: number | null;
  excessReturnPct: number | null;
  actualHit: number | null;
  status: string | null;
  entryDay: string;
  exitDay: string;
  entryPrice: number | null;
  exitPrice: number | null;
}

export interface SmartVoiceRawRepresentativeCall extends SmartVoiceRepresentativeCall {
  investorId: string;
  focusKind: "best" | "weak";
  focusContribution: number;
  focusCallCount: number;
}
