import type { SvTickerLensProfile, SvTickerSignalEvidence, SvTickerThesisNarrative } from "@/server/queries/smartVoiceTickerSignals";
import type { SvDivergenceDiagnostic, SvMomentumDiagnostic } from "./smartVoiceSignalLogic";
import type { SvOpinionChangeRadar, SvOpportunityIndicators, SvWeightedTargetDistribution } from "./smartVoiceDecisionLogic";
import { svEvidenceWeight } from "./smartVoiceDecisionLogic";

const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value));

function shiftDay(day: string, delta: number) {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return date.toISOString().slice(0, 10);
}

export type SvThesisState = "strengthening" | "fading" | "bullish_reversal" | "bearish_reversal" | "stable" | "new";

export interface SvThesisLifecycleItem {
  lens: string;
  state: SvThesisState;
  currentNet: number;
  previousNet: number | null;
  delta: number | null;
  currentWeight: number;
  previousWeight: number;
  bullLeadZh: string;
  bullLeadEn: string;
  bearLeadZh: string;
  bearLeadEn: string;
}

function periodLensStats(rows: SvTickerSignalEvidence[], asOfDay: string) {
  const output = new Map<string, { signed: number; weight: number }>();
  for (const item of rows) {
    const lenses = item.viewpoints.length ? item.viewpoints : ["other"];
    const weight = svEvidenceWeight(item, asOfDay) / lenses.length;
    const sign = item.direction === "bull" ? 1 : -1;
    for (const lens of lenses) {
      const current = output.get(lens) ?? { signed: 0, weight: 0 };
      current.signed += weight * sign;
      current.weight += weight;
      output.set(lens, current);
    }
  }
  return output;
}

export function buildThesisLifecycle(
  evidence: SvTickerSignalEvidence[],
  narratives: SvTickerThesisNarrative[],
  asOfDay: string,
): SvThesisLifecycleItem[] {
  const currentStart = shiftDay(asOfDay, -6);
  const previousStart = shiftDay(asOfDay, -13);
  const currentRows = evidence.filter((item) => item.createdAt.slice(0, 10) >= currentStart);
  const previousRows = evidence.filter((item) => item.createdAt.slice(0, 10) >= previousStart && item.createdAt.slice(0, 10) < currentStart);
  const current = periodLensStats(currentRows, asOfDay);
  const previous = periodLensStats(previousRows, asOfDay);
  const lenses = new Set([...current.keys(), ...previous.keys()]);
  return [...lenses].map((lens): SvThesisLifecycleItem => {
    const now = current.get(lens) ?? { signed: 0, weight: 0 };
    const before = previous.get(lens);
    const currentNet = now.weight ? now.signed / now.weight : 0;
    const previousNet = before?.weight ? before.signed / before.weight : null;
    const delta = previousNet == null ? null : currentNet - previousNet;
    let state: SvThesisState = previousNet == null ? "new" : "stable";
    if (previousNet != null && previousNet <= -0.12 && currentNet >= 0.12) state = "bullish_reversal";
    else if (previousNet != null && previousNet >= 0.12 && currentNet <= -0.12) state = "bearish_reversal";
    else if (previousNet != null && delta != null && Math.sign(currentNet) === Math.sign(previousNet) && Math.abs(currentNet) - Math.abs(previousNet) >= 0.12) state = "strengthening";
    else if (previousNet != null && delta != null && Math.abs(currentNet) - Math.abs(previousNet) <= -0.12) state = "fading";
    const lead = (stance: "bull" | "bear") => narratives.find((item) => item.lens === lens && item.stance === stance);
    return {
      lens,
      state,
      currentNet,
      previousNet,
      delta,
      currentWeight: now.weight,
      previousWeight: before?.weight ?? 0,
      bullLeadZh: lead("bull")?.leadZh ?? "",
      bullLeadEn: lead("bull")?.leadEn ?? "",
      bearLeadZh: lead("bear")?.leadZh ?? "",
      bearLeadEn: lead("bear")?.leadEn ?? "",
    };
  }).sort((a, b) => b.currentWeight - a.currentWeight).slice(0, 7);
}

export interface SvPortfolioExposure {
  lens: string;
  share: number;
  contributors: { ticker: string; contribution: number }[];
}

export interface SvPortfolioRisk {
  configuredWeight: number;
  concentration: number;
  exposures: SvPortfolioExposure[];
}

export function buildPortfolioRisk(profiles: SvTickerLensProfile[], allocations: Record<string, number>): SvPortfolioRisk {
  const totalAllocation = Object.values(allocations).reduce((sum, value) => sum + Math.max(0, value), 0);
  const byLens = new Map<string, { total: number; contributors: { ticker: string; contribution: number }[] }>();
  for (const profile of profiles) {
    const allocation = Math.max(0, allocations[profile.ticker] ?? 0);
    if (!allocation) continue;
    for (const [lens, share] of Object.entries(profile.lenses)) {
      const contribution = allocation * share;
      const row = byLens.get(lens) ?? { total: 0, contributors: [] };
      row.total += contribution;
      row.contributors.push({ ticker: profile.ticker, contribution });
      byLens.set(lens, row);
    }
  }
  const exposures = [...byLens.entries()].map(([lens, row]) => ({
    lens,
    share: totalAllocation ? row.total / totalAllocation : 0,
    contributors: row.contributors.sort((a, b) => b.contribution - a.contribution),
  })).sort((a, b) => b.share - a.share);
  const hhi = exposures.reduce((sum, item) => sum + item.share ** 2, 0);
  return {
    configuredWeight: totalAllocation,
    concentration: clamp(hhi * 100, 0, 100),
    exposures,
  };
}

export type SvAlertSeverity = "high" | "medium" | "info";
export interface SvExplainableAlert {
  id: string;
  severity: SvAlertSeverity;
  titleZh: string;
  titleEn: string;
  reasonZh: string;
  reasonEn: string;
}

export function buildExplainableAlerts({
  divergence,
  momentum,
  targets,
  radar,
  indicators,
  thesis,
}: {
  divergence: SvDivergenceDiagnostic;
  momentum: SvMomentumDiagnostic;
  targets: SvWeightedTargetDistribution;
  radar: SvOpinionChangeRadar;
  indicators: SvOpportunityIndicators;
  thesis: SvThesisLifecycleItem[];
}): SvExplainableAlert[] {
  const alerts: SvExplainableAlert[] = [];
  if (indicators.divergence >= 35 && divergence.spread != null) alerts.push({
    id: "divergence", severity: indicators.divergence >= 65 ? "high" : "medium",
    titleZh: "高低 SV 出现预期差", titleEn: "High/low SV expectation gap",
    reasonZh: `净方向差 ${divergence.spread >= 0 ? "+" : ""}${divergence.spread.toFixed(2)}，信号强度 ${indicators.divergence.toFixed(0)}/100。`,
    reasonEn: `Net direction spread is ${divergence.spread >= 0 ? "+" : ""}${divergence.spread.toFixed(2)} with ${indicators.divergence.toFixed(0)}/100 strength.`,
  });
  if (momentum.state === "bullish_reversal" || momentum.state === "bearish_reversal") alerts.push({
    id: "momentum-reversal", severity: "high",
    titleZh: momentum.state === "bullish_reversal" ? "Top SV 转为看多" : "Top SV 转为看空",
    titleEn: momentum.state === "bullish_reversal" ? "Top SV turned bullish" : "Top SV turned bearish",
    reasonZh: `近 5 个交易日净方向变化 ${momentum.delta == null ? "—" : `${momentum.delta >= 0 ? "+" : ""}${momentum.delta.toFixed(2)}`}。`,
    reasonEn: `Net direction changed ${momentum.delta == null ? "—" : `${momentum.delta >= 0 ? "+" : ""}${momentum.delta.toFixed(2)}`} over roughly five sessions.`,
  });
  if (indicators.crowding >= 60) alerts.push({
    id: "crowding", severity: indicators.crowding >= 78 ? "high" : "medium",
    titleZh: "观点存在拥挤风险", titleEn: "Thesis crowding risk",
    reasonZh: `近期高 SV 作者观点同向且集中，拥挤度为 ${indicators.crowding.toFixed(0)}/100。`,
    reasonEn: `Recent high-SV views are aligned and concentrated, with a crowding score of ${indicators.crowding.toFixed(0)}/100.`,
  });
  if (targets.impliedMove != null && Math.abs(targets.impliedMove) >= 0.15) alerts.push({
    id: "target-gap", severity: Math.abs(targets.impliedMove) >= 0.3 ? "high" : "medium",
    titleZh: "SV 目标价与现价偏离", titleEn: "SV target diverges from spot",
    reasonZh: `加权目标中位数隐含 ${targets.impliedMove >= 0 ? "+" : ""}${(targets.impliedMove * 100).toFixed(1)}%，多数目标区间跨度相当于现价的 ${targets.dispersion == null ? "—" : `${(targets.dispersion * 100).toFixed(0)}%`}。`,
    reasonEn: `The weighted median implies ${targets.impliedMove >= 0 ? "+" : ""}${(targets.impliedMove * 100).toFixed(1)}%; the middle target range spans ${targets.dispersion == null ? "—" : `${(targets.dispersion * 100).toFixed(0)}%`} of spot.`,
  });
  const reversals = radar.counts.reverse + radar.counts.invalidate + radar.counts.close;
  if (reversals > 0) alerts.push({
    id: "lifecycle", severity: reversals >= 3 ? "high" : "medium",
    titleZh: "作者正在撤销或反转观点", titleEn: "Authors are reversing or closing views",
    reasonZh: `最近 7 天识别到 ${reversals} 次反转、失效或关闭。`,
    reasonEn: `${reversals} reversals, invalidations or closures were identified in the last 7 days.`,
  });
  const thesisReversals = thesis.filter((item) => item.state.includes("reversal"));
  if (thesisReversals.length) alerts.push({
    id: "thesis-reversal", severity: "medium",
    titleZh: "核心投资逻辑发生反转", titleEn: "Core thesis reversed",
    reasonZh: `${thesisReversals.map((item) => item.lens).join("、")} 的多空结构已跨越中性区。`,
    reasonEn: `${thesisReversals.map((item) => item.lens).join(", ")} crossed the neutral zone.`,
  });
  if (!alerts.length) alerts.push({
    id: "stable", severity: "info", titleZh: "暂无高优先级变化", titleEn: "No high-priority change",
    reasonZh: "分歧、拥挤、目标价和观点生命周期均未触发当前阈值。",
    reasonEn: "Divergence, crowding, targets and call lifecycle remain below alert thresholds.",
  });
  return alerts.slice(0, 6);
}
