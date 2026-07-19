import type { SvSignalCohort, SvSignalHorizon, SvTickerSignalEvidence, SvTickerSignalHistoryPoint, SvTickerSignalSnapshot } from "@/server/queries/smartVoiceTickerSignals";

export const SV_SIGNAL_HORIZONS: SvSignalHorizon[] = ["1D", "5D", "20D", "60D", "90D", "180D"];

type NetDirection = "bull" | "bear" | "flat";

function clamp(value: number, low: number, high: number) {
  return Math.min(high, Math.max(low, value));
}

function netDirection(value: number, deadband = 0.1): NetDirection {
  if (value > deadband) return "bull";
  if (value < -deadband) return "bear";
  return "flat";
}

export interface SvDivergenceDiagnostic {
  state: "insufficient" | "aligned_bull" | "aligned_bear" | "bullish_divergence" | "bearish_divergence" | "mixed";
  topNet: number | null;
  bottomNet: number | null;
  spread: number | null;
  strength: number;
  coverage: number;
}

export function buildSvDivergence(
  top?: SvTickerSignalSnapshot,
  bottom?: SvTickerSignalSnapshot,
): SvDivergenceDiagnostic {
  if (!top || !bottom) {
    return { state: "insufficient", topNet: top?.weightedNet ?? null, bottomNet: bottom?.weightedNet ?? null, spread: null, strength: 0, coverage: 0 };
  }
  const topDirection = netDirection(top.weightedNet);
  const bottomDirection = netDirection(bottom.weightedNet);
  const spread = top.weightedNet - bottom.weightedNet;
  const coverage = clamp(Math.min(top.effectiveVoices, bottom.effectiveVoices) / 3, 0, 1);
  let state: SvDivergenceDiagnostic["state"] = "mixed";
  if (topDirection === "bull" && bottomDirection === "bear") state = "bullish_divergence";
  else if (topDirection === "bear" && bottomDirection === "bull") state = "bearish_divergence";
  else if (topDirection === "bull" && bottomDirection === "bull") state = "aligned_bull";
  else if (topDirection === "bear" && bottomDirection === "bear") state = "aligned_bear";
  const rawStrength = state.startsWith("aligned")
    ? Math.min(Math.abs(top.weightedNet), Math.abs(bottom.weightedNet))
    : Math.abs(spread) / 2;
  return {
    state,
    topNet: top.weightedNet,
    bottomNet: bottom.weightedNet,
    spread,
    strength: clamp(rawStrength * coverage * 100, 0, 100),
    coverage,
  };
}

export interface SvTermPoint {
  horizon: SvSignalHorizon;
  net: number | null;
  authors: number;
}

export interface SvTermStructure {
  state: "insufficient" | "broad_bull" | "broad_bear" | "short_bull_long_bear" | "short_bear_long_bull" | "bullish_steepening" | "bearish_steepening" | "mixed";
  shortNet: number | null;
  longNet: number | null;
  slope: number | null;
  points: SvTermPoint[];
}

function average(values: number[]) {
  return values.length ? values.reduce((total, value) => total + value, 0) / values.length : null;
}

export function buildSvTermStructure(current: SvTickerSignalSnapshot[], cohort: SvSignalCohort): SvTermStructure {
  const points = SV_SIGNAL_HORIZONS.map((horizon) => {
    const snapshot = current.find((item) => item.cohort === cohort && item.horizon === horizon);
    return { horizon, net: snapshot?.weightedNet ?? null, authors: snapshot?.nAuthors ?? 0 };
  });
  const shortNet = average(points.slice(0, 3).flatMap((point) => point.net == null ? [] : [point.net]));
  const longNet = average(points.slice(3).flatMap((point) => point.net == null ? [] : [point.net]));
  if (shortNet == null || longNet == null) return { state: "insufficient", shortNet, longNet, slope: null, points };
  const slope = shortNet - longNet;
  const available = points.flatMap((point) => point.net == null ? [] : [point.net]);
  const shortDirection = netDirection(shortNet);
  const longDirection = netDirection(longNet);
  let state: SvTermStructure["state"] = "mixed";
  if (available.length >= 3 && available.every((value) => value > 0.1)) state = "broad_bull";
  else if (available.length >= 3 && available.every((value) => value < -0.1)) state = "broad_bear";
  else if (shortDirection === "bull" && longDirection === "bear") state = "short_bull_long_bear";
  else if (shortDirection === "bear" && longDirection === "bull") state = "short_bear_long_bull";
  else if (slope >= 0.25) state = "bullish_steepening";
  else if (slope <= -0.25) state = "bearish_steepening";
  return { state, shortNet, longNet, slope, points };
}

export interface SvMomentumDiagnostic {
  state: "insufficient" | "bullish_reversal" | "bearish_reversal" | "accelerating" | "fading" | "stable";
  currentNet: number | null;
  previousNet: number | null;
  delta: number | null;
  authorDelta: number;
  reversalDay: string | null;
  points: SvTickerSignalHistoryPoint[];
}

export function buildSvMomentum(
  history: SvTickerSignalHistoryPoint[],
  cohort: SvSignalCohort,
  horizon: SvSignalHorizon,
): SvMomentumDiagnostic {
  const points = history
    .filter((point) => point.cohort === cohort && point.horizon === horizon)
    .sort((a, b) => a.day.localeCompare(b.day));
  if (points.length < 2) {
    return { state: "insufficient", currentNet: points.at(-1)?.weightedNet ?? null, previousNet: null, delta: null, authorDelta: 0, reversalDay: null, points };
  }
  const current = points.at(-1)!;
  const previous = points[Math.max(0, points.length - 6)];
  const delta = current.weightedNet - previous.weightedNet;
  const currentDirection = netDirection(current.weightedNet);
  const previousDirection = netDirection(previous.weightedNet);
  let state: SvMomentumDiagnostic["state"] = "stable";
  if (currentDirection === "bull" && previousDirection === "bear") state = "bullish_reversal";
  else if (currentDirection === "bear" && previousDirection === "bull") state = "bearish_reversal";
  else if (currentDirection !== "flat" && currentDirection === previousDirection && Math.abs(current.weightedNet) - Math.abs(previous.weightedNet) >= 0.12) state = "accelerating";
  else if (Math.abs(current.weightedNet) - Math.abs(previous.weightedNet) <= -0.12) state = "fading";
  let reversalDay: string | null = null;
  for (let index = Math.max(1, points.length - 10); index < points.length; index += 1) {
    const before = netDirection(points[index - 1].weightedNet);
    const after = netDirection(points[index].weightedNet);
    if (before !== "flat" && after !== "flat" && before !== after) reversalDay = points[index].day;
  }
  return {
    state,
    currentNet: current.weightedNet,
    previousNet: previous.weightedNet,
    delta,
    authorDelta: current.nAuthors - previous.nAuthors,
    reversalDay,
    points: points.slice(-12),
  };
}

export interface SvTargetSummary {
  count: number;
  bullCount: number;
  bearCount: number;
  reachedCount: number;
  dominantDirection: "bull" | "bear" | "mixed";
  low: number | null;
  median: number | null;
  high: number | null;
  impliedMove: number | null;
}

function quantile(values: number[], fraction: number) {
  if (!values.length) return null;
  const position = (values.length - 1) * fraction;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) return values[lower];
  return values[lower] + (values[upper] - values[lower]) * (position - lower);
}

export function summarizeSvTargets(evidence: SvTickerSignalEvidence[], currentPrice: number | null): SvTargetSummary {
  const valid = evidence.filter((item) => (
    item.targetPrice != null
    && item.targetPrice > 0
    && (currentPrice == null || (item.targetPrice >= currentPrice * 0.2 && item.targetPrice <= currentPrice * 5))
  ));
  const values = valid
    .map((item) => item.targetPrice!)
    .sort((a, b) => a - b);
  const median = quantile(values, 0.5);
  const bullCount = valid.filter((item) => item.direction === "bull").length;
  const bearCount = valid.filter((item) => item.direction === "bear").length;
  const reachedCount = currentPrice == null ? 0 : valid.filter((item) => (
    item.direction === "bull" ? item.targetPrice! <= currentPrice : item.targetPrice! >= currentPrice
  )).length;
  return {
    count: values.length,
    bullCount,
    bearCount,
    reachedCount,
    dominantDirection: bullCount > bearCount
      ? "bull"
      : bearCount > bullCount
        ? "bear"
        : "mixed",
    low: quantile(values, 0.25),
    median,
    high: quantile(values, 0.75),
    impliedMove: median != null && currentPrice ? median / currentPrice - 1 : null,
  };
}

export interface SvConditionEvidence {
  text: string;
  source: string;
  direction: "bull" | "bear" | "neutral";
  createdAt: string;
}

export function uniqueSvConditions(
  evidence: SvTickerSignalEvidence[],
  field: "triggerCondition" | "invalidationCondition",
  limit = 3,
): SvConditionEvidence[] {
  const seen = new Set<string>();
  const output: SvConditionEvidence[] = [];
  for (const item of [...evidence].sort((a, b) => b.createdAt.localeCompare(a.createdAt))) {
    const text = item[field].trim();
    const key = text.toLocaleLowerCase().replace(/\s+/g, " ");
    if (!key || seen.has(key)) continue;
    seen.add(key);
    output.push({ text, source: item.source, direction: item.direction, createdAt: item.createdAt });
    if (output.length >= limit) break;
  }
  return output;
}
