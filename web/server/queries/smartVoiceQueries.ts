import { all, get } from "@/lib/db";

type Direction = "bull" | "bear";

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
  topHandles: string[];
  evidenceIds: SmartVoiceTickerEvidenceIds;
  signal: "high_bull_low_bear" | "high_bear_low_bull" | "sv_consensus_bull" | "sv_consensus_bear" | "mixed";
}

export interface SmartVoiceTickerEvidence {
  id: string;
  ticker: string;
  source: SmartVoiceMarketSource;
  direction: Direction;
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

interface RawCall {
  evidenceId: string;
  investorId: string;
  ticker: string;
  nameZh: string;
  nameEn: string;
  direction: Direction;
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

interface EvidenceContent {
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
  direction: Direction;
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

const CONF_WEIGHT: Record<string, number> = {
  high: 1,
  medium: 0.82,
  low: 0.62,
  observing: 0.48,
};

function safe<T>(fn: () => T, fallback: T): T {
  try {
    return fn();
  } catch {
    return fallback;
  }
}

function weight(row: RawCall, scoreScope: "global" | "platform") {
  const score = scoreScope === "platform" ? row.platformSv : row.sv;
  const sv = Math.max(40, Math.min(180, score || 100));
  const svWeight = Math.max(0.35, sv / 100);
  const callWeight = Math.max(0.2, Math.min(1.2, row.callWeight || 0.6));
  const confidence = CONF_WEIGHT[row.confidence] ?? 0.48;
  const sample = Math.min(1.18, Math.max(0.72, Math.log10(Math.max(10, row.nEff || 10)) / 2));
  return svWeight * callWeight * confidence * sample;
}

function signalOf(row: SmartVoiceTickerRank): SmartVoiceTickerRank["signal"] {
  if (row.highNet > 0 && row.lowNet < 0 && row.contrastScore > 1.5) return "high_bull_low_bear";
  if (row.highNet < 0 && row.lowNet > 0 && row.contrastScore > 1.5) return "high_bear_low_bull";
  if (row.netScore > 2 && row.highNet > 0) return "sv_consensus_bull";
  if (row.netScore < -2 && row.highNet < 0) return "sv_consensus_bear";
  return "mixed";
}

type EvidenceBucket = keyof SmartVoiceTickerEvidenceIds;

interface RankedEvidence {
  evidence: SmartVoiceTickerEvidence;
  priority: number;
  authorKey: string;
}

interface AuthorDirectionState {
  direction: Direction;
  createdAt: string;
  evidenceId: string;
}

interface TickerAggregate extends SmartVoiceTickerRank {
  handleScore: Map<string, number>;
  bullHandles: Set<string>;
  bearHandles: Set<string>;
  evidenceBuckets: Record<EvidenceBucket, RankedEvidence[]>;
  handleBuckets: Record<EvidenceBucket, Set<string>>;
  topAuthorStates: Map<string, AuthorDirectionState>;
  previousTopAuthorStates: Map<string, AuthorDirectionState>;
}

function emptyEvidenceIds(): SmartVoiceTickerEvidenceIds {
  return { highBull: [], highBear: [], lowBull: [], lowBear: [], previousHighBull: [], previousHighBear: [] };
}

function emptyEvidenceBuckets(): Record<EvidenceBucket, RankedEvidence[]> {
  return { highBull: [], highBear: [], lowBull: [], lowBear: [], previousHighBull: [], previousHighBear: [] };
}

function emptyHandleBuckets(): Record<EvidenceBucket, Set<string>> {
  return { highBull: new Set(), highBear: new Set(), lowBull: new Set(), lowBear: new Set(), previousHighBull: new Set(), previousHighBear: new Set() };
}

function createTickerAggregate(row: RawCall): TickerAggregate {
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
    topHandles: [],
    evidenceIds: emptyEvidenceIds(),
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

function evidenceBucket(rankBand: "top" | "bottom" | "middle", direction: Direction): EvidenceBucket | null {
  if (rankBand === "top") return direction === "bull" ? "highBull" : "highBear";
  if (rankBand === "bottom") return direction === "bull" ? "lowBull" : "lowBear";
  return null;
}

function selectEvidence(
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

function hydrateEvidence(evidenceById: Record<string, SmartVoiceTickerEvidence>) {
  const ids = Object.keys(evidenceById);
  const chunkSize = 400;
  for (let offset = 0; offset < ids.length; offset += chunkSize) {
    const chunk = ids.slice(offset, offset + chunkSize);
    const placeholders = chunk.map(() => "?").join(",");
    const rows = all<EvidenceContent>(
      `SELECT c.candidate_id AS id,
              COALESCE(NULLIF(c.summary_zh, ''), NULLIF(c.evidence_span, ''), NULLIF(cc.text, ''), '') AS summaryZh,
              COALESCE(NULLIF(c.summary_en, ''), NULLIF(c.evidence_span, ''), NULLIF(cc.text, ''), '') AS summaryEn,
              COALESCE(NULLIF(c.evidence_span, ''), NULLIF(cc.text, ''), '') AS originalEvidence,
              COALESCE(cc.url, '') AS url
         FROM sv_call c
         LEFT JOIN sv_call_candidate cc ON cc.candidate_id = c.candidate_id
        WHERE c.candidate_id IN (${placeholders})`,
      ...chunk,
    );
    for (const row of rows) {
      const target = evidenceById[row.id];
      if (!target) continue;
      target.summaryZh = row.summaryZh;
      target.summaryEn = row.summaryEn;
      target.originalEvidence = row.originalEvidence;
      target.url = row.url;
    }
  }
}

function build(
  rows: RawCall[],
  limit: number,
  rankScope: "global" | "platform" = "global",
  evidenceById?: Record<string, SmartVoiceTickerEvidence>,
  previousRows: RawCall[] = [],
): SmartVoiceTickerBoards {
  const byTicker = new Map<string, TickerAggregate>();

  for (const row of previousRows) {
    const current = byTicker.get(row.ticker) ?? createTickerAggregate(row);
    const rankBand = rankScope === "platform" ? row.platformRankBand : row.rankBand;
    if (rankBand !== "top") {
      byTicker.set(row.ticker, current);
      continue;
    }
    const authorKey = row.investorId || row.handle || row.evidenceId;
    const platformAuthorKey = `${row.source}:${authorKey}`;
    const previous = current.previousTopAuthorStates.get(platformAuthorKey);
    if (!previous || row.createdAt > previous.createdAt || (row.createdAt === previous.createdAt && row.evidenceId > previous.evidenceId)) {
      current.previousTopAuthorStates.set(platformAuthorKey, {
        direction: row.direction,
        createdAt: row.createdAt,
        evidenceId: row.evidenceId,
      });
    }
    const bucket: EvidenceBucket = row.direction === "bull" ? "previousHighBull" : "previousHighBear";
    const w = weight(row, rankScope);
    current.evidenceBuckets[bucket].push({
      authorKey: platformAuthorKey,
      priority: w * (0.75 + Math.max(0, Math.min(1, row.evidenceScore || 0)) * 0.25),
      evidence: {
        id: row.evidenceId,
        ticker: row.ticker,
        source: row.source as SmartVoiceMarketSource,
        direction: row.direction,
        rankBand: "top",
        author: row.handle || row.investorId || "Unknown",
        createdAt: row.createdAt,
        platformSv: +row.platformSv.toFixed(1),
        confidence: row.confidence,
        callWeight: +row.callWeight.toFixed(2),
        horizon: row.horizon,
        targetPrice: row.targetPrice,
        summaryZh: "",
        summaryEn: "",
        originalEvidence: "",
        url: "",
      },
    });
    byTicker.set(row.ticker, current);
  }

  for (const row of rows) {
    const current = byTicker.get(row.ticker) ?? createTickerAggregate(row);
    const w = weight(row, rankScope);
    const signed = row.direction === "bull" ? w : -w;
    const rankBand = rankScope === "platform" ? row.platformRankBand : row.rankBand;
    if (row.direction === "bull") {
      current.bullScore += w;
      current.nBull += 1;
      if (rankBand === "top") current.highBullScore += w;
      if (rankBand === "bottom") current.lowBullScore += w;
      if (row.handle) current.bullHandles.add(row.handle);
    } else {
      current.bearScore += w;
      current.nBear += 1;
      if (rankBand === "top") current.highBearScore += w;
      if (rankBand === "bottom") current.lowBearScore += w;
      if (row.handle) current.bearHandles.add(row.handle);
    }
    const bucket = evidenceBucket(rankBand, row.direction);
    if (bucket) {
      const authorKey = row.investorId || row.handle || row.evidenceId;
      const platformAuthorKey = `${row.source}:${authorKey}`;
      current.handleBuckets[bucket].add(platformAuthorKey);
      if (bucket === "highBull") current.highBullCalls += 1;
      if (bucket === "highBear") current.highBearCalls += 1;
      if (bucket === "lowBull") current.lowBullCalls += 1;
      if (bucket === "lowBear") current.lowBearCalls += 1;
      current.evidenceBuckets[bucket].push({
        authorKey: platformAuthorKey,
        priority: w * (0.75 + Math.max(0, Math.min(1, row.evidenceScore || 0)) * 0.25),
        evidence: {
          id: row.evidenceId,
          ticker: row.ticker,
          source: row.source as SmartVoiceMarketSource,
          direction: row.direction,
          rankBand: rankBand as "top" | "bottom",
          author: row.handle || row.investorId || "Unknown",
          createdAt: row.createdAt,
          platformSv: +row.platformSv.toFixed(1),
          confidence: row.confidence,
          callWeight: +row.callWeight.toFixed(2),
          horizon: row.horizon,
          targetPrice: row.targetPrice,
          summaryZh: "",
          summaryEn: "",
          originalEvidence: "",
          url: "",
        },
      });
      if (rankBand === "top") {
        const previous = current.topAuthorStates.get(platformAuthorKey);
        if (!previous || row.createdAt > previous.createdAt || (row.createdAt === previous.createdAt && row.evidenceId > previous.evidenceId)) {
          current.topAuthorStates.set(platformAuthorKey, {
            direction: row.direction,
            createdAt: row.createdAt,
            evidenceId: row.evidenceId,
          });
        }
      }
    }
    current.nPosts += 1;
    current.netScore += signed;
    current.highNet = current.highBullScore - current.highBearScore;
    current.lowNet = current.lowBullScore - current.lowBearScore;
    current.contrastScore = Math.abs(current.highNet - current.lowNet);
    current.bullVoices = current.bullHandles.size;
    current.bearVoices = current.bearHandles.size;
    current.nVoices = new Set([...current.bullHandles, ...current.bearHandles]).size;
    current.highBullVoices = current.handleBuckets.highBull.size;
    current.highBearVoices = current.handleBuckets.highBear.size;
    current.lowBullVoices = current.handleBuckets.lowBull.size;
    current.lowBearVoices = current.handleBuckets.lowBear.size;
    current.highVoices = new Set([...current.handleBuckets.highBull, ...current.handleBuckets.highBear]).size;
    current.lowVoices = new Set([...current.handleBuckets.lowBull, ...current.handleBuckets.lowBear]).size;
    current.handleScore.set(row.handle, (current.handleScore.get(row.handle) ?? 0) + Math.abs(w));
    byTicker.set(row.ticker, current);
  }

  const ranked = [...byTicker.values()]
    .filter((row) => row.highBullCalls + row.highBearCalls + row.lowBullCalls + row.lowBearCalls >= 3 || row.previousTopAuthorStates.size >= 2)
    .map((row) => {
      const latestAuthorDirections = [...row.topAuthorStates.values()];
      const previousAuthorDirections = [...row.previousTopAuthorStates.values()];
      row.highAuthorBullCount = latestAuthorDirections.filter((state) => state.direction === "bull").length;
      row.highAuthorBearCount = latestAuthorDirections.filter((state) => state.direction === "bear").length;
      row.highAuthorNet = row.highAuthorBullCount - row.highAuthorBearCount;
      row.highAuthorConsensus = latestAuthorDirections.length ? (row.highAuthorNet / latestAuthorDirections.length) * 100 : 0;
      row.previousHighAuthorBullCount = previousAuthorDirections.filter((state) => state.direction === "bull").length;
      row.previousHighAuthorBearCount = previousAuthorDirections.filter((state) => state.direction === "bear").length;
      row.previousHighAuthorNet = row.previousHighAuthorBullCount - row.previousHighAuthorBearCount;
      row.previousHighAuthorConsensus = previousAuthorDirections.length ? (row.previousHighAuthorNet / previousAuthorDirections.length) * 100 : 0;
      row.authorNetDelta = row.highAuthorNet - row.previousHighAuthorNet;
      const currentAuthorTotal = latestAuthorDirections.length;
      const previousAuthorTotal = previousAuthorDirections.length;
      const authorBase = Math.max(1, currentAuthorTotal, previousAuthorTotal);
      row.authorNetShiftPct = (row.authorNetDelta / authorBase) * 100;
      row.authorNetAbrupt = Math.abs(row.authorNetDelta) >= 3
        && Math.abs(row.authorNetShiftPct) >= 50
        && currentAuthorTotal >= 3
        && previousAuthorTotal >= 3;
      row.signal = signalOf(row);
      row.topHandles = [...row.handleScore.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3)
        .map(([handle]) => handle);
      const { handleScore, bullHandles, bearHandles, handleBuckets, topAuthorStates, previousTopAuthorStates, ...rest } = row;
      return {
        ...rest,
        bullScore: +rest.bullScore.toFixed(2),
        bearScore: +rest.bearScore.toFixed(2),
        netScore: +rest.netScore.toFixed(2),
        highBullScore: +rest.highBullScore.toFixed(2),
        highBearScore: +rest.highBearScore.toFixed(2),
        lowBullScore: +rest.lowBullScore.toFixed(2),
        lowBearScore: +rest.lowBearScore.toFixed(2),
        highNet: +rest.highNet.toFixed(2),
        lowNet: +rest.lowNet.toFixed(2),
        contrastScore: +rest.contrastScore.toFixed(2),
        highAuthorConsensus: +rest.highAuthorConsensus.toFixed(1),
        previousHighAuthorConsensus: +rest.previousHighAuthorConsensus.toFixed(1),
        authorNetShiftPct: +rest.authorNetShiftPct.toFixed(1),
      };
    });

  const finalize = (items: typeof ranked, includePreviousEvidence = false): SmartVoiceTickerRank[] => items.map((row) => {
    const { evidenceBuckets, ...rest } = row;
    return {
      ...rest,
      evidenceIds: {
        highBull: selectEvidence(evidenceBuckets.highBull, evidenceById),
        highBear: selectEvidence(evidenceBuckets.highBear, evidenceById),
        lowBull: selectEvidence(evidenceBuckets.lowBull, evidenceById),
        lowBear: selectEvidence(evidenceBuckets.lowBear, evidenceById),
        previousHighBull: includePreviousEvidence ? selectEvidence(evidenceBuckets.previousHighBull, evidenceById) : [],
        previousHighBear: includePreviousEvidence ? selectEvidence(evidenceBuckets.previousHighBear, evidenceById) : [],
      },
    };
  });

  const authorShiftRanked = [...ranked]
    .filter((row) => row.authorNetDelta !== 0 && Math.max(
      row.highAuthorBullCount + row.highAuthorBearCount,
      row.previousHighAuthorBullCount + row.previousHighAuthorBearCount,
    ) >= 2)
    .sort((a, b) => Number(b.authorNetAbrupt) - Number(a.authorNetAbrupt)
      || Math.abs(b.authorNetShiftPct) - Math.abs(a.authorNetShiftPct)
      || Math.abs(b.authorNetDelta) - Math.abs(a.authorNetDelta)
      || a.ticker.localeCompare(b.ticker))
    .slice(0, limit);
  authorShiftRanked.forEach((row, index) => {
    row.authorNetShiftRank = index + 1;
  });

  return {
    bullish: finalize([...ranked]
      .filter((row) => row.highNet > 0 && row.highBullCalls >= 2 && row.highBullVoices >= 2)
      .sort((a, b) => b.highNet - a.highNet || b.highBullScore - a.highBullScore)
      .slice(0, limit)),
    bearish: finalize([...ranked]
      .filter((row) => row.highNet < 0 && row.highBearCalls >= 2 && row.highBearVoices >= 2)
      .sort((a, b) => a.highNet - b.highNet || b.highBearScore - a.highBearScore)
      .slice(0, limit)),
    contrast: finalize([...ranked]
      .filter((row) => row.highNet * row.lowNet < 0 && row.contrastScore > 1.5 && row.highVoices >= 2 && row.lowVoices >= 2)
      .sort((a, b) => b.contrastScore - a.contrastScore)
      .slice(0, limit)),
    authorShift: finalize(authorShiftRanked, true),
  };
}

function getSmartVoiceTickerRows(hours: number, minSv: number) {
  return all<RawCall>(
      `WITH ranked_investors AS (
         SELECT investor_id,
                ROW_NUMBER() OVER (
                  ORDER BY sv DESC, raw_z DESC,
                           CASE confidence WHEN 'high' THEN 4 WHEN 'medium' THEN 3 WHEN 'low' THEN 2 ELSE 1 END DESC,
                           n_eff DESC, settled_calls DESC, investor_id ASC
                ) AS rank_no,
                COUNT(*) OVER () AS population
           FROM sv_investor_score
       ),
       qualified AS (
         SELECT investor_id, source, n_eff, settled_calls,
                COALESCE(json_extract(platform_scores_json, '$.' || source), sv, 100) AS platform_sv
           FROM sv_investor_score
          WHERE (source = 'x' AND n_eff >= 8 AND settled_calls >= 10)
             OR (source = 'youtube' AND n_eff >= 4 AND settled_calls >= 5)
             OR (source = 'reddit' AND n_eff >= 3 AND settled_calls >= 4)
             OR (source IN ('xueqiu','toss') AND n_eff >= 5 AND settled_calls >= 8)
       ),
       platform_ranked AS (
         SELECT investor_id, source,
                ROW_NUMBER() OVER (
                  PARTITION BY source
                  ORDER BY platform_sv DESC, n_eff DESC, settled_calls DESC, investor_id ASC
                ) AS rank_no,
                COUNT(*) OVER (PARTITION BY source) AS population
           FROM qualified
       ),
       mx AS (
         SELECT MAX(datetime(created_at)) AS at
           FROM sv_call
          WHERE is_actionable_call = 1
       )
       SELECT COALESCE(NULLIF(c.candidate_id, ''), c.source || ':' || c.tweet_id || ':' || upper(c.ticker)) AS evidenceId,
              COALESCE(c.investor_id, '') AS investorId,
              upper(c.ticker) AS ticker,
              COALESCE(g.name_zh, upper(c.ticker)) AS nameZh,
              COALESCE(g.name_en, upper(c.ticker)) AS nameEn,
              c.direction AS direction,
              COALESCE(c.call_weight, 0.6) AS callWeight,
              COALESCE(s.sv, 100) AS sv,
              COALESCE(json_extract(s.platform_scores_json, '$.' || s.source), s.sv, 100) AS platformSv,
              COALESCE(s.n_eff, 0) AS nEff,
              COALESCE(s.confidence, 'observing') AS confidence,
              COALESCE(s.handle, c.author_handle, '') AS handle,
              c.source AS source,
              datetime(c.created_at) AS createdAt,
              mx.at AS latestAt,
              COALESCE(c.horizon_bucket, 'unknown') AS horizon,
              c.target_price AS targetPrice,
              COALESCE(c.evidence_score, 0) AS evidenceScore,
              CASE
                WHEN r.rank_no <= CAST((r.population + 9) / 10 AS INTEGER) THEN 'top'
                WHEN r.rank_no > r.population - CAST((r.population + 9) / 10 AS INTEGER) THEN 'bottom'
                ELSE 'middle'
              END AS rankBand,
              CASE
                WHEN p.rank_no <= CAST((p.population + 9) / 10 AS INTEGER) THEN 'top'
                WHEN p.rank_no > p.population - CAST((p.population + 9) / 10 AS INTEGER) THEN 'bottom'
                ELSE 'middle'
              END AS platformRankBand
          FROM sv_call c
          JOIN sv_investor_score s ON s.investor_id = c.investor_id
          JOIN ranked_investors r ON r.investor_id = s.investor_id
          LEFT JOIN platform_ranked p ON p.investor_id = s.investor_id AND p.source = s.source
          CROSS JOIN mx
          JOIN gr_ticker g ON upper(g.ticker) = upper(c.ticker)
         WHERE c.direction IN ('bull','bear')
           AND datetime(c.created_at) >= datetime(mx.at, ?)
           AND c.is_actionable_call = 1
           AND COALESCE(s.sv, 100) >= ?`,
    `-${Math.max(1, Math.floor(hours))} hours`,
    minSv,
  );
}

export function getSmartVoiceTickerBoards(limit = 5, days = 14, minSv = 0) {
  return safe(() => {
    const rows = getSmartVoiceTickerRows(days * 24, minSv);
    return build(rows, limit);
  }, { bullish: [], bearish: [], contrast: [], authorShift: [] });
}

const MARKET_WINDOWS: Record<SmartVoiceMarketWindow, number> = {
  "24H": 24,
  "3D": 72,
  "7D": 168,
  "30D": 720,
  "90D": 2160,
};

const MARKET_PLATFORM_GROUPS: Record<SmartVoiceMarketPlatformKey, SmartVoiceMarketSource[]> = {
  all: ["x", "youtube", "reddit", "xueqiu"],
  x: ["x"],
  youtube: ["youtube"],
  reddit: ["reddit"],
  xueqiu: ["xueqiu"],
  "x+youtube": ["x", "youtube"],
  "x+reddit": ["x", "reddit"],
  "x+xueqiu": ["x", "xueqiu"],
  "youtube+reddit": ["youtube", "reddit"],
  "youtube+xueqiu": ["youtube", "xueqiu"],
  "reddit+xueqiu": ["reddit", "xueqiu"],
  "x+youtube+reddit": ["x", "youtube", "reddit"],
  "x+youtube+xueqiu": ["x", "youtube", "xueqiu"],
  "x+reddit+xueqiu": ["x", "reddit", "xueqiu"],
  "youtube+reddit+xueqiu": ["youtube", "reddit", "xueqiu"],
};

function emptySmartVoiceTickerBoardMatrix(): SmartVoiceTickerBoardMatrix {
  const matrix = {} as SmartVoiceTickerBoardMatrix;
  for (const platformKey of Object.keys(MARKET_PLATFORM_GROUPS) as SmartVoiceMarketPlatformKey[]) {
    matrix[platformKey] = {} as Record<SmartVoiceMarketWindow, SmartVoiceTickerBoards>;
    for (const windowKey of Object.keys(MARKET_WINDOWS) as SmartVoiceMarketWindow[]) {
      matrix[platformKey][windowKey] = { bullish: [], bearish: [], contrast: [], authorShift: [] };
    }
  }
  return matrix;
}

export function getSmartVoiceMarketData(limit = 24): SmartVoiceMarketData {
  return safe(() => {
    const rows = getSmartVoiceTickerRows(MARKET_WINDOWS["90D"] * 2, 0);
    const latestMs = rows.length ? Date.parse(`${rows[0].latestAt.replace(" ", "T")}Z`) : 0;
    const evidenceById: Record<string, SmartVoiceTickerEvidence> = {};
    const matrix = {} as SmartVoiceTickerBoardMatrix;
    for (const [platformKey, sources] of Object.entries(MARKET_PLATFORM_GROUPS) as [SmartVoiceMarketPlatformKey, SmartVoiceMarketSource[]][]) {
      const sourceSet = new Set<string>(sources);
      matrix[platformKey] = {} as Record<SmartVoiceMarketWindow, SmartVoiceTickerBoards>;
      for (const [windowKey, hours] of Object.entries(MARKET_WINDOWS) as [SmartVoiceMarketWindow, number][]) {
        const cutoffMs = latestMs - hours * 60 * 60 * 1000;
        const previousCutoffMs = latestMs - hours * 2 * 60 * 60 * 1000;
        const scopedRows = rows.filter((row) => sourceSet.has(row.source) && Date.parse(`${row.createdAt.replace(" ", "T")}Z`) >= cutoffMs);
        const previousRows = rows.filter((row) => {
          if (!sourceSet.has(row.source)) return false;
          const createdMs = Date.parse(`${row.createdAt.replace(" ", "T")}Z`);
          return createdMs >= previousCutoffMs && createdMs < cutoffMs;
        });
        matrix[platformKey][windowKey] = build(scopedRows, limit, "platform", evidenceById, previousRows);
      }
    }
    hydrateEvidence(evidenceById);
    return { boards: matrix, evidenceById, latestAt: rows[0]?.latestAt ?? "" };
  }, { boards: emptySmartVoiceTickerBoardMatrix(), evidenceById: {}, latestAt: "" });
}

export function getSmartVoiceTickerBoardMatrix(limit = 24): SmartVoiceTickerBoardMatrix {
  return getSmartVoiceMarketData(limit).boards;
}

export function getSmartVoiceOverviewStats(): SmartVoiceOverviewStats {
  return safe(() => get<SmartVoiceOverviewStats>(
    `SELECT
       (SELECT COUNT(*) FROM sv_investor_score) AS scoredInvestors,
       (SELECT COUNT(*) FROM sv_investor_score WHERE confidence = 'high') AS highConfidenceInvestors,
       (SELECT COUNT(DISTINCT source) FROM sv_investor_score) AS platformCount,
       (SELECT COUNT(*) FROM sv_call WHERE is_actionable_call = 1) AS actionableCalls,
       COALESCE((SELECT MAX(datetime(created_at)) FROM sv_call WHERE is_actionable_call = 1), '') AS latestCallAt`,
  ) ?? {
    scoredInvestors: 0,
    highConfidenceInvestors: 0,
    platformCount: 0,
    actionableCalls: 0,
    latestCallAt: "",
  }, {
    scoredInvestors: 0,
    highConfidenceInvestors: 0,
    platformCount: 0,
    actionableCalls: 0,
    latestCallAt: "",
  });
}

export function getSmartVoiceLiveCalls(limit = 240, days = 60): SmartVoiceLiveCall[] {
  const perSourceLimit = Math.max(20, Math.ceil(limit / 4));
  const recentDays = Math.max(1, Math.floor(days));
  return safe(() => all<SmartVoiceLiveCall>(
    `WITH qualified AS (
       SELECT investor_id, source, n_eff, settled_calls,
              COALESCE(json_extract(platform_scores_json, '$.' || source), sv, 100) AS platform_sv
         FROM sv_investor_score
        WHERE (source = 'x' AND n_eff >= 8 AND settled_calls >= 10)
           OR (source = 'youtube' AND n_eff >= 4 AND settled_calls >= 5)
           OR (source = 'reddit' AND n_eff >= 3 AND settled_calls >= 4)
           OR (source IN ('xueqiu','toss') AND n_eff >= 5 AND settled_calls >= 8)
     ),
     platform_ranked AS (
       SELECT investor_id, source,
              ROW_NUMBER() OVER (
                PARTITION BY source
                ORDER BY platform_sv DESC, n_eff DESC, settled_calls DESC, investor_id ASC
              ) AS platform_rank,
              COUNT(*) OVER (PARTITION BY source) AS platform_population
         FROM qualified
     ),
     eligible AS (
       SELECT investor_id FROM sv_investor_score WHERE confidence IN ('high','medium')
       UNION
       SELECT investor_id FROM platform_ranked
        WHERE platform_rank <= CAST((platform_population + 9) / 10 AS INTEGER)
     ),
     latest AS (
       SELECT MAX(substr(created_at, 1, 10)) AS day
         FROM sv_call
        WHERE is_actionable_call = 1
     ),
     ranked_calls AS (
       SELECT c.candidate_id AS id,
              upper(c.ticker) AS ticker,
              COALESCE(g.name_zh, upper(c.ticker)) AS nameZh,
              COALESCE(g.name_en, upper(c.ticker)) AS nameEn,
              c.source AS source,
              c.direction AS direction,
              COALESCE(c.investor_id, '') AS investorId,
              COALESCE(NULLIF(s.handle, ''), NULLIF(c.author_handle, ''), 'Unknown') AS author,
              COALESCE(c.created_at, '') AS createdAt,
              COALESCE(c.horizon_bucket, 'unknown') AS horizon,
              c.target_price AS targetPrice,
              COALESCE(c.call_weight, 0) AS callWeight,
              COALESCE(NULLIF(c.summary_zh, ''), NULLIF(c.evidence_span, ''), NULLIF(cc.text, ''), '') AS summaryZh,
              COALESCE(NULLIF(c.summary_en, ''), NULLIF(c.evidence_span, ''), NULLIF(cc.text, ''), '') AS summaryEn,
              COALESCE(c.investor_style, 'unknown') AS investorStyle,
              COALESCE(s.sv, 100) AS sv,
              COALESCE(s.confidence, 'observing') AS confidence,
              COALESCE(cc.url, '') AS url,
              ROW_NUMBER() OVER (
                PARTITION BY c.source
                ORDER BY c.created_at DESC, c.call_weight DESC, c.candidate_id ASC
              ) AS sourceRank
         FROM sv_call c
         JOIN eligible e ON e.investor_id = c.investor_id
         JOIN sv_investor_score s ON s.investor_id = c.investor_id
         CROSS JOIN latest
         LEFT JOIN sv_call_candidate cc ON cc.candidate_id = c.candidate_id
         LEFT JOIN gr_ticker g ON upper(g.ticker) = upper(c.ticker)
        WHERE c.is_actionable_call = 1
          AND c.direction IN ('bull', 'bear')
          AND substr(c.created_at, 1, 10) >= date(latest.day, ?)
     )
     SELECT * FROM ranked_calls
      WHERE sourceRank <= ?
      ORDER BY createdAt DESC, callWeight DESC
      LIMIT ?`,
    `-${recentDays} day`,
    perSourceLimit,
    limit,
  ), []);
}
