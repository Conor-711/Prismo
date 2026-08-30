import type { SmartVoiceDirection, SmartVoiceRawCall, SmartVoiceTickerEvidence, SmartVoiceTickerEvidenceIds, SmartVoiceTickerRank } from "./smartVoiceTypes";

const CONF_WEIGHT: Record<string, number> = {
  high: 1,
  medium: 0.82,
  low: 0.62,
  observing: 0.48,
};

export function smartVoiceCallWeight(row: SmartVoiceRawCall, scoreScope: "global" | "platform") {
  const score = scoreScope === "platform" ? row.platformSv : row.sv;
  const sv = Math.max(40, Math.min(180, score || 100));
  const svWeight = Math.max(0.35, sv / 100);
  const callWeight = Math.max(0.2, Math.min(1.2, row.callWeight || 0.6));
  const confidence = CONF_WEIGHT[row.confidence] ?? 0.48;
  const sample = Math.min(1.18, Math.max(0.72, Math.log10(Math.max(10, row.nEff || 10)) / 2));
  return svWeight * callWeight * confidence * sample;
}

export function smartVoiceSignal(row: SmartVoiceTickerRank): SmartVoiceTickerRank["signal"] {
  if (row.highNet > 0 && row.lowNet < 0 && row.contrastScore > 1.5) return "high_bull_low_bear";
  if (row.highNet < 0 && row.lowNet > 0 && row.contrastScore > 1.5) return "high_bear_low_bull";
  if (row.netScore > 2 && row.highNet > 0) return "sv_consensus_bull";
  if (row.netScore < -2 && row.highNet < 0) return "sv_consensus_bear";
  return "mixed";
}

export type SmartVoiceEvidenceBucket = keyof SmartVoiceTickerEvidenceIds;

interface RankedEvidence {
  evidence: SmartVoiceTickerEvidence;
  priority: number;
  authorKey: string;
}

interface AuthorDirectionState {
  direction: SmartVoiceDirection;
  createdAt: string;
  evidenceId: string;
}

export interface SmartVoiceTickerAggregate extends SmartVoiceTickerRank {
  handleScore: Map<string, number>;
  bullHandles: Set<string>;
  bearHandles: Set<string>;
  evidenceBuckets: Record<SmartVoiceEvidenceBucket, RankedEvidence[]>;
  handleBuckets: Record<SmartVoiceEvidenceBucket, Set<string>>;
  topAuthorStates: Map<string, AuthorDirectionState>;
  previousTopAuthorStates: Map<string, AuthorDirectionState>;
}

export function emptySmartVoiceEvidenceIds(): SmartVoiceTickerEvidenceIds {
  return { highBull: [], highBear: [], lowBull: [], lowBear: [], previousHighBull: [], previousHighBear: [] };
}

function emptyEvidenceBuckets(): Record<SmartVoiceEvidenceBucket, RankedEvidence[]> {
  return { highBull: [], highBear: [], lowBull: [], lowBear: [], previousHighBull: [], previousHighBear: [] };
}

function emptyHandleBuckets(): Record<SmartVoiceEvidenceBucket, Set<string>> {
  return { highBull: new Set(), highBear: new Set(), lowBull: new Set(), lowBear: new Set(), previousHighBull: new Set(), previousHighBear: new Set() };
}

export function createSmartVoiceTickerAggregate(row: SmartVoiceRawCall): SmartVoiceTickerAggregate {
  return {
    ticker: row.ticker,
    nameZh: row.nameZh,
    nameEn: row.nameEn,
    bullScore: 0,
    bearScore: 0,
    netScore: 0,
    highBullScore: 0,
    highBearScore: 0,
    lowBullScore: 0,
    lowBearScore: 0,
    highNet: 0,
    lowNet: 0,
    contrastScore: 0,
    nBull: 0,
    nBear: 0,
    nPosts: 0,
    nVoices: 0,
    bullVoices: 0,
    bearVoices: 0,
    highBullCalls: 0,
    highBearCalls: 0,
    lowBullCalls: 0,
    lowBearCalls: 0,
    highVoices: 0,
    lowVoices: 0,
    highBullVoices: 0,
    highBearVoices: 0,
    lowBullVoices: 0,
    lowBearVoices: 0,
    highAuthorBullCount: 0,
    highAuthorBearCount: 0,
    highAuthorNet: 0,
    highAuthorConsensus: 0,
    previousHighAuthorBullCount: 0,
    previousHighAuthorBearCount: 0,
    previousHighAuthorNet: 0,
    previousHighAuthorConsensus: 0,
    authorNetDelta: 0,
    authorNetShiftPct: 0,
    authorNetAbrupt: false,
    authorNetShiftRank: 0,
    newCoverageAuthorCount: 0,
    newCoverageBullCount: 0,
    newCoverageBearCount: 0,
    currentTopAuthorCount: 0,
    priorTopAuthorCount: 0,
    newCoverageRatio: 0,
    newCoverageScore: 0,
    newestMentionAt: "",
    cohortNew: false,
    topHandles: [],
    evidenceIds: emptySmartVoiceEvidenceIds(),
    signal: "mixed",
    handleScore: new Map<string, number>(),
    bullHandles: new Set<string>(),
    bearHandles: new Set<string>(),
    evidenceBuckets: emptyEvidenceBuckets(),
    handleBuckets: emptyHandleBuckets(),
    topAuthorStates: new Map<string, AuthorDirectionState>(),
    previousTopAuthorStates: new Map<string, AuthorDirectionState>(),
  };
}

export function smartVoiceEvidenceBucket(
  rankBand: "top" | "bottom" | "middle",
  direction: SmartVoiceDirection,
): SmartVoiceEvidenceBucket | null {
  if (rankBand === "top") return direction === "bull" ? "highBull" : "highBear";
  if (rankBand === "bottom") return direction === "bull" ? "lowBull" : "lowBear";
  return null;
}

export function selectSmartVoiceEvidence(
  items: RankedEvidence[],
  evidenceById: Record<string, SmartVoiceTickerEvidence> | undefined,
  limit = 4,
) {
  const ranked = [...items].sort((a, b) => b.priority - a.priority || b.evidence.createdAt.localeCompare(a.evidence.createdAt));
  const selected: RankedEvidence[] = [];
  const authors = new Set<string>();
  for (const item of ranked) {
    if (authors.has(item.authorKey)) continue;
    selected.push(item);
    authors.add(item.authorKey);
    if (selected.length >= limit) break;
  }
  if (selected.length < limit) {
    for (const item of ranked) {
      if (selected.includes(item)) continue;
      selected.push(item);
      if (selected.length >= limit) break;
    }
  }
  for (const item of selected) {
    if (evidenceById) evidenceById[item.evidence.id] = item.evidence;
  }
  return selected.map((item) => item.evidence.id);
}
