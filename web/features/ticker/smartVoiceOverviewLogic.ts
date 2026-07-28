import type { SvSignalCohort, SvSignalHorizon, SvTickerSignalData, SvTickerSignalEvidence, SvTickerSignalHistoryPoint } from "@/server/queries/smartVoiceTickerSignals";
import { svEvidenceWeight } from "./smartVoiceDecisionLogic";

const DAY_MS = 86_400_000;

const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value));

function shiftDay(day: string, delta: number) {
  const date = new Date(`${day.slice(0, 10)}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return date.toISOString().slice(0, 10);
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

function pointAtOrBefore(points: SvTickerSignalHistoryPoint[], day: string, beforeIndex: number) {
  for (let index = beforeIndex; index >= 0; index -= 1) {
    if (points[index].day <= day) return points[index];
  }
  return null;
}

function authorKey(item: SvTickerSignalEvidence) {
  return `${item.source}:${item.investorId || item.authorHandle || item.candidateId}`;
}

function latestByAuthor(rows: SvTickerSignalEvidence[]) {
  const output = new Map<string, SvTickerSignalEvidence>();
  for (const row of [...rows].sort((a, b) => a.createdAt.localeCompare(b.createdAt))) {
    output.set(authorKey(row), row);
  }
  return output;
}

function directionValue(direction: SvTickerSignalEvidence["direction"]) {
  return direction === "bull" ? 1 : direction === "bear" ? -1 : 0;
}

export type SvShiftState =
  | "cross_bull"
  | "strong_bull"
  | "bull"
  | "stable"
  | "bear"
  | "strong_bear"
  | "cross_bear"
  | "insufficient";

export interface SvShiftPoint {
  day: string;
  level: number;
  shift: number | null;
}

export interface SvShiftMetric {
  score: number | null;
  currentLevel: number | null;
  previousLevel: number | null;
  historyPercentile: number | null;
  historyDays: number;
  improvingSessions: number;
  state: SvShiftState;
  series: SvShiftPoint[];
}

export interface SvBreadthMetric {
  percent: number | null;
  up: number;
  down: number;
  stable: number;
  newAuthors: number;
  total: number;
  aligned: number;
  opposing: number;
  direction: "bull" | "bear" | "flat";
  state: "broad" | "majority" | "partial" | "narrow" | "mixed" | "insufficient";
}

export interface SvTargetRevisionMetric {
  changePct: number | null;
  previousMedian: number | null;
  currentMedian: number | null;
  low: number | null;
  high: number | null;
  count: number;
  state: "strong_up" | "up" | "stable" | "down" | "strong_down" | "new" | "insufficient";
}

export interface SvPriceDivergenceMetric {
  sigma: number | null;
  priceReturnPct: number | null;
  shiftScore: number | null;
  similarHistoryCount: number;
  state:
    | "opinion_leads_recovery"
    | "opinion_cools_into_rally"
    | "views_resilient_vs_price"
    | "views_lag_rally"
    | "aligned_up"
    | "aligned_down"
    | "neutral"
    | "insufficient";
}

export interface SvOverviewMetrics {
  asOfDay: string;
  shift: SvShiftMetric;
  breadth: SvBreadthMetric;
  targetRevision: SvTargetRevisionMetric;
  priceDivergence: SvPriceDivergenceMetric;
}

function buildShiftMetric(
  data: SvTickerSignalData,
  horizon: SvSignalHorizon,
  cohort: SvSignalCohort,
): SvShiftMetric {
  const points = data.history
    .filter((item) => item.horizon === horizon && item.cohort === cohort)
    .sort((a, b) => a.day.localeCompare(b.day));
  const series = points.map((point, index): SvShiftPoint => {
    const prior = pointAtOrBefore(points, shiftDay(point.day, -7), index - 1)
      ?? (index >= 5 ? points[index - 5] : null);
    return {
      day: point.day,
      level: clamp(point.weightedNet * 100, -100, 100),
      shift: prior ? clamp((point.weightedNet - prior.weightedNet) * 100, -100, 100) : null,
    };
  });
  const current = series.at(-1);
  const currentPoint = points.at(-1);
  if (!current || !currentPoint || current.shift == null) {
    return {
      score: null,
      currentLevel: current?.level ?? null,
      previousLevel: null,
      historyPercentile: null,
      historyDays: 0,
      improvingSessions: 0,
      state: "insufficient",
      series,
    };
  }
  const priorLevel = current.level - current.shift;
  const historical = series.flatMap((item) => item.shift == null ? [] : [Math.abs(item.shift)]);
  const firstDay = points[0]?.day;
  const lastDay = points.at(-1)?.day;
  const historyDays = firstDay && lastDay
    ? Math.max(0, Math.round((Date.parse(`${lastDay}T00:00:00Z`) - Date.parse(`${firstDay}T00:00:00Z`)) / DAY_MS))
    : 0;
  const percentile = historical.length
    ? Math.round(100 * historical.filter((value) => value <= Math.abs(current.shift!)).length / historical.length)
    : null;
  const sign = Math.sign(current.shift);
  let improvingSessions = 0;
  for (let index = points.length - 1; index > 0; index -= 1) {
    const dailyChange = points[index].weightedNet - points[index - 1].weightedNet;
    if (!sign || Math.sign(dailyChange) !== sign || Math.abs(dailyChange) < 0.005) break;
    improvingSessions += 1;
  }
  let state: SvShiftState = "stable";
  if (priorLevel <= -10 && current.level >= 10) state = "cross_bull";
  else if (priorLevel >= 10 && current.level <= -10) state = "cross_bear";
  else if (current.shift >= 8) state = (percentile ?? 0) >= 95 ? "strong_bull" : "bull";
  else if (current.shift <= -8) state = (percentile ?? 0) >= 95 ? "strong_bear" : "bear";
  return {
    score: current.shift,
    currentLevel: current.level,
    previousLevel: priorLevel,
    historyPercentile: percentile,
    historyDays,
    improvingSessions,
    state,
    series,
  };
}

function buildBreadthMetric(
  data: SvTickerSignalData,
  horizon: SvSignalHorizon,
  asOfDay: string,
  shiftScore: number | null,
): SvBreadthMetric {
  const currentStart = shiftDay(asOfDay, -6);
  const previousStart = shiftDay(asOfDay, -13);
  const rows = data.evidence.filter((item) => item.horizon === horizon && item.percentile <= 25);
  const current = latestByAuthor(rows.filter((item) => item.createdAt.slice(0, 10) >= currentStart));
  const previous = latestByAuthor(rows.filter((item) => {
    const day = item.createdAt.slice(0, 10);
    return day >= previousStart && day < currentStart;
  }));
  const authors = new Set([...current.keys(), ...previous.keys()]);
  let up = 0;
  let down = 0;
  let stable = 0;
  let newAuthors = 0;
  for (const author of authors) {
    const now = current.get(author);
    const before = previous.get(author);
    if (!now) {
      stable += 1;
      continue;
    }
    if (!before) {
      newAuthors += 1;
      if (directionValue(now.direction) > 0) up += 1;
      else if (directionValue(now.direction) < 0) down += 1;
      else stable += 1;
      continue;
    }
    const delta = directionValue(now.direction) - directionValue(before.direction);
    if (delta > 0) up += 1;
    else if (delta < 0) down += 1;
    else if (now.lifecycleAction === "reinforce_call") {
      if (directionValue(now.direction) > 0) up += 1;
      else if (directionValue(now.direction) < 0) down += 1;
      else stable += 1;
    } else {
      stable += 1;
    }
  }
  const total = authors.size;
  const direction = (shiftScore ?? 0) > 3 ? "bull" : (shiftScore ?? 0) < -3 ? "bear" : "flat";
  const aligned = direction === "bull" ? up : direction === "bear" ? down : Math.max(up, down);
  const opposing = direction === "bull" ? down : direction === "bear" ? up : Math.min(up, down);
  const percent = total ? aligned / total * 100 : null;
  let state: SvBreadthMetric["state"] = "insufficient";
  if (total >= 3 && percent != null) {
    if (percent < 40) state = "narrow";
    else if (Math.abs(up - down) <= Math.max(1, total * 0.1)) state = "mixed";
    else if (percent >= 70) state = "broad";
    else if (percent >= 55) state = "majority";
    else if (percent >= 40) state = "partial";
  }
  return { percent, up, down, stable, newAuthors, total, aligned, opposing, direction, state };
}

function targetRows(rows: SvTickerSignalEvidence[], asOfDay: string) {
  return [...latestByAuthor(rows.filter((item) => item.targetPrice != null && item.targetPrice > 0)).values()]
    .map((item) => ({ value: item.targetPrice!, weight: svEvidenceWeight(item, asOfDay) }));
}

function buildTargetRevisionMetric(
  data: SvTickerSignalData,
  horizon: SvSignalHorizon,
  asOfDay: string,
): SvTargetRevisionMetric {
  const currentStart = shiftDay(asOfDay, -6);
  const previousStart = shiftDay(asOfDay, -13);
  const evidence = data.evidence.filter((item) => item.horizon === horizon && item.percentile <= 25);
  const current = targetRows(evidence.filter((item) => item.createdAt.slice(0, 10) >= currentStart), asOfDay);
  const previous = targetRows(evidence.filter((item) => {
    const day = item.createdAt.slice(0, 10);
    return day >= previousStart && day < currentStart;
  }), asOfDay);
  const currentMedian = weightedQuantile(current, 0.5);
  const previousMedian = weightedQuantile(previous, 0.5);
  const changePct = currentMedian != null && previousMedian
    ? currentMedian / previousMedian - 1
    : null;
  let state: SvTargetRevisionMetric["state"] = "insufficient";
  if (currentMedian != null && previousMedian == null) state = "new";
  else if (changePct != null && changePct >= 0.1) state = "strong_up";
  else if (changePct != null && changePct >= 0.03) state = "up";
  else if (changePct != null && changePct <= -0.1) state = "strong_down";
  else if (changePct != null && changePct <= -0.03) state = "down";
  else if (changePct != null) state = "stable";
  return {
    changePct,
    previousMedian,
    currentMedian,
    low: weightedQuantile(current, 0.25),
    high: weightedQuantile(current, 0.75),
    count: current.length,
    state,
  };
}

function average(values: number[]) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null;
}

function standardDeviation(values: number[], mean: number) {
  if (values.length < 2) return null;
  return Math.sqrt(values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / (values.length - 1));
}

function buildPriceDivergenceMetric(
  data: SvTickerSignalData,
  shift: SvShiftMetric,
): SvPriceDivergenceMetric {
  const priceIndex = new Map(data.prices.map((item, index) => [item.day, index]));
  const observations = shift.series.flatMap((point) => {
    if (point.shift == null) return [];
    const index = priceIndex.get(point.day);
    if (index == null || index < 20) return [];
    const start = data.prices[index - 20]?.close;
    const end = data.prices[index]?.close;
    if (!start || !end) return [];
    return [{ day: point.day, shift: point.shift, priceReturn: end / start - 1 }];
  });
  const current = observations.at(-1);
  if (!current || observations.length < 12) {
    return {
      sigma: null,
      priceReturnPct: current?.priceReturn ?? null,
      shiftScore: current?.shift ?? shift.score,
      similarHistoryCount: 0,
      state: "insufficient",
    };
  }
  const shiftValues = observations.map((item) => item.shift);
  const priceValues = observations.map((item) => item.priceReturn);
  const shiftMean = average(shiftValues)!;
  const priceMean = average(priceValues)!;
  const shiftStd = standardDeviation(shiftValues, shiftMean);
  const priceStd = standardDeviation(priceValues, priceMean);
  if (!shiftStd || !priceStd) {
    return {
      sigma: null,
      priceReturnPct: current.priceReturn,
      shiftScore: current.shift,
      similarHistoryCount: 0,
      state: "insufficient",
    };
  }
  const divergences = observations.map((item) => (
    ((item.shift - shiftMean) / shiftStd - (item.priceReturn - priceMean) / priceStd) / Math.SQRT2
  ));
  const sigma = divergences.at(-1)!;
  const similarHistoryCount = divergences.slice(0, -1).filter((value) => (
    Math.sign(value) === Math.sign(sigma) && Math.abs(value) >= Math.abs(sigma)
  )).length;
  let state: SvPriceDivergenceMetric["state"] = "neutral";
  if (sigma >= 1 && current.shift >= 8 && current.priceReturn < 0) state = "opinion_leads_recovery";
  else if (sigma <= -1 && current.shift <= -8 && current.priceReturn > 0) state = "opinion_cools_into_rally";
  else if (sigma >= 1 && current.priceReturn < 0) state = "views_resilient_vs_price";
  else if (sigma <= -1 && current.priceReturn > 0) state = "views_lag_rally";
  else if (current.shift > 5 && current.priceReturn > 0.02) state = "aligned_up";
  else if (current.shift < -5 && current.priceReturn < -0.02) state = "aligned_down";
  return {
    sigma,
    priceReturnPct: current.priceReturn,
    shiftScore: current.shift,
    similarHistoryCount,
    state,
  };
}

export function buildSvOverviewMetrics(
  data: SvTickerSignalData,
  horizon: SvSignalHorizon,
  cohort: SvSignalCohort = "top25",
): SvOverviewMetrics {
  const asOfDay = data.current.map((item) => item.day).sort().at(-1)
    ?? data.history.map((item) => item.day).sort().at(-1)
    ?? data.prices.at(-1)?.day
    ?? "";
  const shift = buildShiftMetric(data, horizon, cohort);
  return {
    asOfDay,
    shift,
    breadth: buildBreadthMetric(data, horizon, asOfDay, shift.score),
    targetRevision: buildTargetRevisionMetric(data, horizon, asOfDay),
    priceDivergence: buildPriceDivergenceMetric(data, shift),
  };
}
