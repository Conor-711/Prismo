import type { SvSignalHorizon, SvTickerSignalEvidence, SvTickerSignalSnapshot } from "@/server/queries/smartVoiceTickerSignals";
import type { PersonalPrefs } from "./opinionExplorerTypes";

const DAY_MS = 86_400_000;
const CONFIDENCE_WEIGHT: Record<SvTickerSignalEvidence["confidence"], number> = {
  observing: 0.55,
  low: 0.72,
  medium: 0.88,
  high: 1,
};

const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value));
const numeric = (value: string) => {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};

function dayDistance(later: string, earlier: string) {
  const a = Date.parse(`${later.slice(0, 10)}T00:00:00Z`);
  const b = Date.parse(`${earlier.slice(0, 10)}T00:00:00Z`);
  return Number.isFinite(a) && Number.isFinite(b) ? Math.max(0, Math.round((a - b) / DAY_MS)) : 0;
}

export function svEvidenceWeight(item: SvTickerSignalEvidence, asOfDay: string) {
  const quality = (item.convictionScore + item.evidenceScore + item.specificityScore) / 3;
  const percentileWeight = 0.7 + 0.8 * (1 - clamp(item.percentile, 0, 100) / 100);
  const callWeight = clamp(item.callWeight / 1.6, 0.25, 1.25);
  const recency = Math.exp(-dayDistance(asOfDay, item.createdAt) / 35);
  return Math.max(0.01, percentileWeight * CONFIDENCE_WEIGHT[item.confidence] * (0.45 + 0.55 * quality) * callWeight * recency);
}

function weightedQuantile(rows: { value: number; weight: number }[], fraction: number) {
  if (!rows.length) return null;
  const sorted = [...rows].sort((a, b) => a.value - b.value);
  const total = sorted.reduce((sum, item) => sum + item.weight, 0);
  const threshold = total * fraction;
  let running = 0;
  for (const item of sorted) {
    running += item.weight;
    if (running >= threshold) return item.value;
  }
  return sorted.at(-1)!.value;
}

export interface SvWeightedTargetPoint {
  candidateId: string;
  author: string;
  source: string;
  direction: "bull" | "bear";
  target: number;
  weight: number;
  sv: number;
  percentile: number;
  createdAt: string;
}

export interface SvWeightedTargetDistribution {
  points: SvWeightedTargetPoint[];
  count: number;
  low: number | null;
  median: number | null;
  high: number | null;
  impliedMove: number | null;
  dispersion: number | null;
  bullWeightShare: number;
}

export function buildWeightedTargetDistribution(
  evidence: SvTickerSignalEvidence[],
  horizon: SvSignalHorizon,
  currentPrice: number | null,
  asOfDay: string,
): SvWeightedTargetDistribution {
  const points = evidence.flatMap((item): SvWeightedTargetPoint[] => {
    if (item.horizon !== horizon || item.targetPrice == null || item.direction === "neutral") return [];
    if (item.targetPrice <= 0) return [];
    if (currentPrice && (item.targetPrice < currentPrice * 0.2 || item.targetPrice > currentPrice * 5)) return [];
    return [{
      candidateId: item.candidateId,
      author: item.authorHandle || item.investorId || item.source,
      source: item.source,
      direction: item.direction,
      target: item.targetPrice,
      weight: svEvidenceWeight(item, asOfDay),
      sv: item.asofSv,
      percentile: item.percentile,
      createdAt: item.createdAt,
    }];
  });
  const weighted = points.map((item) => ({ value: item.target, weight: item.weight }));
  const totalWeight = points.reduce((sum, item) => sum + item.weight, 0);
  const bullWeight = points.filter((item) => item.direction === "bull").reduce((sum, item) => sum + item.weight, 0);
  const low = weightedQuantile(weighted, 0.25);
  const median = weightedQuantile(weighted, 0.5);
  const high = weightedQuantile(weighted, 0.75);
  return {
    points,
    count: points.length,
    low,
    median,
    high,
    impliedMove: median != null && currentPrice ? median / currentPrice - 1 : null,
    dispersion: low != null && high != null && currentPrice ? (high - low) / currentPrice : null,
    bullWeightShare: totalWeight ? bullWeight / totalWeight : 0.5,
  };
}

export type SvChangeKind = "new" | "reinforce" | "reverse" | "invalidate" | "close";

export interface SvOpinionChange {
  kind: SvChangeKind;
  evidence: SvTickerSignalEvidence;
  weight: number;
}

export interface SvOpinionChangeRadar {
  currentNet: number | null;
  previousNet: number | null;
  netDelta: number | null;
  currentCalls: number;
  previousCalls: number;
  targetShift: number | null;
  counts: Record<SvChangeKind, number>;
  changes: SvOpinionChange[];
}

export function buildOpinionChangeRadar(
  evidence: SvTickerSignalEvidence[],
  horizon: SvSignalHorizon,
  asOfDay: string,
): SvOpinionChangeRadar {
  const rows = evidence.filter((item) => item.horizon === horizon).sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  const currentStart = new Date(`${asOfDay}T00:00:00Z`);
  currentStart.setUTCDate(currentStart.getUTCDate() - 6);
  const previousStart = new Date(currentStart);
  previousStart.setUTCDate(previousStart.getUTCDate() - 7);
  const currentStartDay = currentStart.toISOString().slice(0, 10);
  const previousStartDay = previousStart.toISOString().slice(0, 10);
  const current = rows.filter((item) => item.createdAt.slice(0, 10) >= currentStartDay);
  const previous = rows.filter((item) => item.createdAt.slice(0, 10) >= previousStartDay && item.createdAt.slice(0, 10) < currentStartDay);
  const net = (items: SvTickerSignalEvidence[]) => {
    const weights = items.map((item) => ({ weight: svEvidenceWeight(item, asOfDay), sign: item.direction === "bull" ? 1 : -1 }));
    const total = weights.reduce((sum, item) => sum + item.weight, 0);
    return total ? weights.reduce((sum, item) => sum + item.weight * item.sign, 0) / total : null;
  };
  const targetMedian = (items: SvTickerSignalEvidence[]) => weightedQuantile(
    items.flatMap((item) => item.targetPrice == null ? [] : [{ value: item.targetPrice, weight: svEvidenceWeight(item, asOfDay) }]),
    0.5,
  );
  const priorByInvestor = new Map<string, SvTickerSignalEvidence>();
  const changes: SvOpinionChange[] = [];
  for (const item of rows) {
    const investor = item.investorId || `${item.source}:${item.authorHandle}`;
    const prior = priorByInvestor.get(investor);
    if (item.createdAt.slice(0, 10) >= currentStartDay) {
      let kind: SvChangeKind = "new";
      if (item.lifecycleAction === "reverse_call" || (prior && prior.direction !== item.direction)) kind = "reverse";
      else if (item.lifecycleAction === "invalidate_prior_call") kind = "invalidate";
      else if (item.lifecycleAction === "close_prior_call") kind = "close";
      else if (item.lifecycleAction === "reinforce_call" || prior?.direction === item.direction) kind = "reinforce";
      changes.push({ kind, evidence: item, weight: svEvidenceWeight(item, asOfDay) });
    }
    priorByInvestor.set(investor, item);
  }
  const counts: Record<SvChangeKind, number> = { new: 0, reinforce: 0, reverse: 0, invalidate: 0, close: 0 };
  changes.forEach((item) => { counts[item.kind] += 1; });
  const currentNet = net(current);
  const previousNet = net(previous);
  const currentTarget = targetMedian(current);
  const previousTarget = targetMedian(previous);
  return {
    currentNet,
    previousNet,
    netDelta: currentNet != null && previousNet != null ? currentNet - previousNet : null,
    currentCalls: current.length,
    previousCalls: previous.length,
    targetShift: currentTarget != null && previousTarget ? currentTarget / previousTarget - 1 : null,
    counts,
    changes: changes.sort((a, b) => b.weight - a.weight).slice(0, 6),
  };
}

export interface SvOpportunityIndicators {
  divergence: number;
  crowding: number;
  confidence: number;
  freshnessDays: number | null;
}

export function buildOpportunityIndicators(
  top: SvTickerSignalSnapshot | undefined,
  bottom: SvTickerSignalSnapshot | undefined,
  evidence: SvTickerSignalEvidence[],
  horizon: SvSignalHorizon,
  asOfDay: string,
): SvOpportunityIndicators {
  const rows = evidence.filter((item) => item.horizon === horizon);
  const avgQuality = rows.length
    ? rows.reduce((sum, item) => sum + (item.convictionScore + item.evidenceScore + item.specificityScore) / 3, 0) / rows.length
    : 0;
  const latest = rows.map((item) => item.createdAt.slice(0, 10)).sort().at(-1);
  const effective = top?.effectiveVoices ?? 0;
  const authors = top?.nAuthors ?? 0;
  const concentration = authors ? 1 - clamp(effective / authors, 0, 1) : 1;
  return {
    divergence: top && bottom ? clamp(Math.abs(top.weightedNet - bottom.weightedNet) * 50, 0, 100) : 0,
    crowding: top ? clamp(top.consensusStrength * (0.55 + concentration * 0.45) * 100, 0, 100) : 0,
    confidence: clamp(avgQuality * Math.min(1, Math.sqrt(rows.length / 20)) * 100, 0, 100),
    freshnessDays: latest ? dayDistance(asOfDay, latest) : null,
  };
}

const STYLE_HORIZON: Record<string, SvSignalHorizon> = {
  shortterm: "5D",
  swing: "20D",
  longterm: "180D",
  dca: "180D",
};

export interface SvPersonalDecision {
  horizon: SvSignalHorizon;
  score: number;
  state: "supportive" | "conflicted" | "caution" | "unconfigured";
  pnlPct: number | null;
  rewardRisk: number | null;
  reasonsZh: string[];
  reasonsEn: string[];
}

export function buildPersonalDecision(
  prefs: PersonalPrefs,
  fallbackHorizon: SvSignalHorizon,
  topSnapshots: SvTickerSignalSnapshot[],
  targets: SvWeightedTargetDistribution,
  currentPrice: number | null,
): SvPersonalDecision {
  const configured = Object.values(prefs).some(Boolean);
  const horizon = STYLE_HORIZON[prefs.style] ?? fallbackHorizon;
  if (!configured) return { horizon, score: 50, state: "unconfigured", pnlPct: null, rewardRisk: null, reasonsZh: [], reasonsEn: [] };
  const snapshot = topSnapshots.find((item) => item.horizon === horizon && item.cohort === "top25");
  const desired = prefs.direction === "short" ? -1 : prefs.direction === "long" ? 1 : 0;
  const signal = snapshot?.weightedNet ?? 0;
  const targetMove = targets.impliedMove ?? 0;
  const costValues = [numeric(prefs.costLow), numeric(prefs.costHigh)].filter((value): value is number => value != null && value > 0);
  const cost = costValues.length ? costValues.reduce((sum, value) => sum + value, 0) / costValues.length : null;
  const positionValues = [numeric(prefs.positionLow), numeric(prefs.positionHigh)].filter((value): value is number => value != null && value >= 0);
  const position = positionValues.length ? positionValues.reduce((sum, value) => sum + value, 0) / positionValues.length : null;
  const target = numeric(prefs.targetPrice);
  const stop = numeric(prefs.stopLoss);
  const pnlPct = cost && currentPrice ? currentPrice / cost - 1 : null;
  const rewardRisk = cost && target && stop && Math.abs(cost - stop) > 0 ? Math.abs(target - cost) / Math.abs(cost - stop) : null;
  let score = 50;
  if (desired) {
    score += clamp(signal * desired * 25, -25, 25);
    score += clamp(targetMove * desired * 60, -15, 15);
  }
  if (position != null && position >= 20 && desired && signal * desired < 0) score -= 12;
  if (rewardRisk != null) score += clamp((rewardRisk - 1) * 5, -8, 10);
  score = clamp(score, 0, 100);
  const reasonsZh: string[] = [];
  const reasonsEn: string[] = [];
  if (snapshot) {
    const aligned = desired === 0 || signal * desired >= 0;
    reasonsZh.push(`Top 25% Score 在 ${horizon} 周期${aligned ? "与仓位方向一致" : "与仓位方向相反"}（净值 ${signal >= 0 ? "+" : ""}${signal.toFixed(2)}）`);
    reasonsEn.push(`Top 25% Score is ${aligned ? "aligned with" : "against"} the position on ${horizon} (net ${signal >= 0 ? "+" : ""}${signal.toFixed(2)})`);
  }
  if (targets.median != null) {
    reasonsZh.push(`Score 加权目标中位数 $${targets.median.toFixed(0)}，相对现价 ${targetMove >= 0 ? "+" : ""}${(targetMove * 100).toFixed(1)}%`);
    reasonsEn.push(`Score-weighted median target $${targets.median.toFixed(0)}, ${targetMove >= 0 ? "+" : ""}${(targetMove * 100).toFixed(1)}% vs spot`);
  }
  if (position != null && position >= 20) {
    reasonsZh.push(`持仓占比约 ${position.toFixed(0)}%，应提高失效条件与反方观点权重`);
    reasonsEn.push(`Position size is about ${position.toFixed(0)}%; invalidations and opposing evidence deserve more weight`);
  }
  if (rewardRisk != null) {
    reasonsZh.push(`用户目标价与止损对应的回报风险比约 ${rewardRisk.toFixed(1)}x`);
    reasonsEn.push(`User target/stop implies roughly ${rewardRisk.toFixed(1)}x reward-to-risk`);
  }
  return {
    horizon,
    score,
    state: score >= 65 ? "supportive" : score < 42 ? "conflicted" : "caution",
    pnlPct,
    rewardRisk,
    reasonsZh,
    reasonsEn,
  };
}
