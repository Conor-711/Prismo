import generatedSmartVoice from "@/lib/data/smartVoice.json";
import type { SvBoard, SvConfidence, SvDistribution, SvHorizon, SvInvestor, SvSource } from "./types";
import { FALLBACK_NARRATIVES, sourceUrl } from "./constants";

function normalizeLanguage(value: unknown): SvInvestor["language"] {
  return value === "zh" || value === "ko" || value === "ja" ? value : "en";
}

function normalizeConfidence(value: unknown): SvConfidence {
  return value === "high" || value === "medium" || value === "low" ? value : "observing";
}

function normalizeHorizonScores(value: unknown): Partial<Record<SvHorizon, number | null>> {
  const raw = (value && typeof value === "object" ? value : {}) as Partial<Record<SvHorizon, unknown>>;
  return {
    "1D": typeof raw["1D"] === "number" ? raw["1D"] : null,
    "5D": typeof raw["5D"] === "number" ? raw["5D"] : null,
    "20D": typeof raw["20D"] === "number" ? raw["20D"] : null,
    "60D": typeof raw["60D"] === "number" ? raw["60D"] : null,
    "90D": typeof raw["90D"] === "number" ? raw["90D"] : null,
    "180D": typeof raw["180D"] === "number" ? raw["180D"] : null,
  };
}

function normalizeScoreMap(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object") return {};
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).filter((entry): entry is [string, number] => typeof entry[1] === "number"),
  );
}

function normalizeRealInvestor(value: unknown): SvInvestor | null {
  const raw = value as Partial<SvInvestor> | null;
  if (!raw || typeof raw !== "object" || !raw.id || typeof raw.sv !== "number") return null;
  const source: SvSource = raw.source === "youtube" ? "youtube" : "x";
  const handle = String(raw.handle || raw.name || raw.id);
  return {
    id: String(raw.id),
    rank: typeof raw.rank === "number" ? raw.rank : undefined,
    svDelta: typeof raw.svDelta === "number" ? raw.svDelta : null,
    rankDelta: typeof raw.rankDelta === "number" ? raw.rankDelta : null,
    nEffDelta: typeof raw.nEffDelta === "number" ? raw.nEffDelta : null,
    settledCallsDelta: typeof raw.settledCallsDelta === "number" ? raw.settledCallsDelta : null,
    previousConfidence: raw.previousConfidence ? normalizeConfidence(raw.previousConfidence) : null,
    source,
    name: String(raw.name || handle),
    handle,
    avatar: raw.avatar || (source === "x" ? `https://unavatar.io/twitter/${handle.replace(/^@/, "")}` : undefined),
    url: raw.url || sourceUrl(source, handle, String(raw.id).replace(/^yt:/, "")),
    language: normalizeLanguage(raw.language),
    sv: raw.sv,
    confidence: normalizeConfidence(raw.confidence),
    nEff: Number(raw.nEff || 0),
    settledCalls: Number(raw.settledCalls || 0),
    activeDays: Number(raw.activeDays || 0),
    coveredTickers: Number(raw.coveredTickers || 0),
    topTickers: Array.isArray(raw.topTickers) ? raw.topTickers.map(String) : [],
    topNarratives: Array.isArray(raw.topNarratives) ? raw.topNarratives.map(String) : [],
    platformScores: normalizeScoreMap(raw.platformScores) as Partial<Record<SvSource, number>>,
    horizonScores: normalizeHorizonScores(raw.horizonScores),
    narrativeScores: normalizeScoreMap(raw.narrativeScores),
    tickerScores: normalizeScoreMap(raw.tickerScores),
    concentration: raw.concentration && typeof raw.concentration === "object" ? raw.concentration as SvInvestor["concentration"] : undefined,
    rationaleZh: String(raw.rationaleZh || "真实 SV v0：根据已结构化 call 的历史结算结果生成。"),
    rationaleEn: String(raw.rationaleEn || "Real SV v0 generated from settled structured calls."),
  };
}

export function getGeneratedSmartVoiceBoard(): SvBoard | null {
  const raw = generatedSmartVoice as unknown as Partial<SvBoard>;
  const investors = Array.isArray(raw.investors) ? raw.investors.map(normalizeRealInvestor).filter((i): i is SvInvestor => Boolean(i)) : [];
  const bottomInvestors = Array.isArray(raw.bottomInvestors) ? raw.bottomInvestors.map(normalizeRealInvestor).filter((i): i is SvInvestor => Boolean(i)) : [];
  if (!investors.length) return null;
  const sorted = investors.sort((a, b) => b.sv - a.sv);
  return {
    investors: sorted,
    bottomInvestors: bottomInvestors.sort((a, b) => (a.rank ?? 0) - (b.rank ?? 0)),
    x: sorted.filter((i) => i.source === "x"),
    youtube: sorted.filter((i) => i.source === "youtube"),
    currentNarratives: Array.isArray(raw.currentNarratives) && raw.currentNarratives.length ? raw.currentNarratives : FALLBACK_NARRATIVES,
    updatedAt: raw.updatedAt || new Date().toISOString().slice(0, 10),
    scoringVersion: typeof raw.scoringVersion === "string" ? raw.scoringVersion : undefined,
    totalInvestors: typeof raw.totalInvestors === "number" ? raw.totalInvestors : investors.length,
    exportedInvestors: typeof raw.exportedInvestors === "number" ? raw.exportedInvestors : investors.length,
    distribution: raw.distribution as SvDistribution | undefined,
  };
}
