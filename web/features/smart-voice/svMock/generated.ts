import generatedSmartVoice from "@/lib/data/smartVoice.json";
import type { SvBoard, SvConfidence, SvDistribution, SvHorizon, SvInvestor, SvPlatformBand, SvSource } from "./types";
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
  const source: SvSource = raw.source === "youtube" || raw.source === "reddit" || raw.source === "xueqiu" || raw.source === "toss"
    ? raw.source
    : "x";
  const handle = String(raw.handle || raw.name || raw.id);
  return {
    id: String(raw.id),
    rank: typeof raw.rank === "number" ? raw.rank : undefined,
    platformRank: typeof raw.platformRank === "number" ? raw.platformRank : undefined,
    observationRank: typeof raw.observationRank === "number" ? raw.observationRank : undefined,
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

type NormalizedExport = Partial<SvBoard> & {
  investorIndex?: Record<string, unknown>;
  investorIds?: string[];
  bottomInvestorIds?: string[];
  sourceTop25Ids?: Partial<Record<SvSource, string[]>>;
};

function normalizePlatformBand(
  value: unknown,
  source: SvSource,
  investorIndex: Map<string, SvInvestor>,
): SvPlatformBand | null {
  const raw = value as (Partial<SvPlatformBand> & {
    rankedIds?: string[];
    observedIds?: string[];
    top10Ids?: string[];
    bottom10Ids?: string[];
    top25Ids?: string[];
    bottom25Ids?: string[];
  }) | null;
  if (!raw || typeof raw !== "object" || !raw.distribution) return null;
  const investors = (items: unknown, ids: unknown): SvInvestor[] => {
    if (Array.isArray(items)) {
      return items.map(normalizeRealInvestor).filter((item): item is SvInvestor => Boolean(item));
    }
    return Array.isArray(ids)
      ? ids.map((id) => investorIndex.get(String(id))).filter((item): item is SvInvestor => Boolean(item))
      : [];
  };
  return {
    source,
    scoreKind: "SV_Platform",
    totalCount: Number(raw.totalCount || 0),
    qualifiedCount: Number(raw.qualifiedCount || 0),
    rankedCount: Number(raw.rankedCount || 0),
    population: raw.population === "all_scored_fallback" ? "all_scored_fallback" : "qualified",
    distribution: raw.distribution as SvDistribution,
    top25Threshold: Number(raw.top25Threshold || 0),
    bottom25Threshold: Number(raw.bottom25Threshold || 0),
    ranked: investors(raw.ranked, raw.rankedIds),
    observed: investors(raw.observed, raw.observedIds),
    top10: investors(raw.top10, raw.top10Ids),
    bottom10: investors(raw.bottom10, raw.bottom10Ids),
    top25: investors(raw.top25, raw.top25Ids),
    bottom25: investors(raw.bottom25, raw.bottom25Ids),
  };
}

export function getGeneratedSmartVoiceBoard(): SvBoard | null {
  const raw = generatedSmartVoice as unknown as NormalizedExport;
  const normalizedInvestorIndex = new Map<string, SvInvestor>();
  if (raw.investorIndex && typeof raw.investorIndex === "object") {
    for (const [id, value] of Object.entries(raw.investorIndex)) {
      const investor = normalizeRealInvestor(value);
      if (investor) normalizedInvestorIndex.set(id, investor);
    }
  }
  const rawBands = raw.platformBands && typeof raw.platformBands === "object" ? raw.platformBands : {};
  const platformBands: Partial<Record<SvSource, SvPlatformBand>> = {};
  for (const source of ["x", "youtube", "reddit", "xueqiu", "toss"] as SvSource[]) {
    const band = normalizePlatformBand(rawBands[source], source, normalizedInvestorIndex);
    if (band) platformBands[source] = band;
  }
  const platformInvestorById = new Map<string, SvInvestor>();
  for (const band of Object.values(platformBands)) {
    if (!band) continue;
    for (const investor of band.ranked) platformInvestorById.set(investor.id, investor);
  }
  const normalizeList = (items: unknown, ids?: unknown): SvInvestor[] => {
    const normalized = Array.isArray(items)
      ? items.map(normalizeRealInvestor).filter((i): i is SvInvestor => Boolean(i))
      : Array.isArray(ids)
        ? ids.map((id) => normalizedInvestorIndex.get(String(id))).filter((i): i is SvInvestor => Boolean(i))
        : [];
    return normalized.map((investor) => {
      const platformInvestor = platformInvestorById.get(investor.id);
      return platformInvestor?.platformRank ? { ...investor, platformRank: platformInvestor.platformRank } : investor;
    });
  };
  const investors = normalizeList(raw.investors, raw.investorIds);
  const bottomInvestors = normalizeList(raw.bottomInvestors, raw.bottomInvestorIds);
  if (!investors.length) return null;
  const sorted = investors.sort((a, b) => b.sv - a.sv);
  const rootX = normalizeList(raw.x, raw.sourceTop25Ids?.x);
  const rootYoutube = normalizeList(raw.youtube, raw.sourceTop25Ids?.youtube);
  return {
    investors: sorted,
    bottomInvestors: bottomInvestors.sort((a, b) => (a.rank ?? 0) - (b.rank ?? 0)),
    x: platformBands.x?.top25 ?? (rootX.length ? rootX : sorted.filter((i) => i.source === "x")),
    youtube: platformBands.youtube?.top25 ?? (rootYoutube.length ? rootYoutube : sorted.filter((i) => i.source === "youtube")),
    reddit: platformBands.reddit?.top25 ?? normalizeList(raw.reddit, raw.sourceTop25Ids?.reddit),
    xueqiu: platformBands.xueqiu?.top25 ?? normalizeList(raw.xueqiu, raw.sourceTop25Ids?.xueqiu),
    toss: platformBands.toss?.top25 ?? normalizeList(raw.toss, raw.sourceTop25Ids?.toss),
    currentNarratives: Array.isArray(raw.currentNarratives) && raw.currentNarratives.length ? raw.currentNarratives : FALLBACK_NARRATIVES,
    updatedAt: raw.updatedAt || new Date().toISOString().slice(0, 10),
    scoringVersion: typeof raw.scoringVersion === "string" ? raw.scoringVersion : undefined,
    totalInvestors: typeof raw.totalInvestors === "number" ? raw.totalInvestors : investors.length,
    exportedInvestors: typeof raw.exportedInvestors === "number" ? raw.exportedInvestors : investors.length,
    distribution: raw.distribution as SvDistribution | undefined,
    platformBands,
  };
}
