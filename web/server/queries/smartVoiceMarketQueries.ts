import { all } from "@/lib/db";
import { safeQuery } from "@/server/db/safeQuery";
import { buildSmartVoiceTickerBoards } from "./smartVoiceMarketBuilder";
import type { SmartVoiceEvidenceContent, SmartVoiceMarketData, SmartVoiceMarketPlatformKey, SmartVoiceMarketSource, SmartVoiceMarketWindow, SmartVoiceRawCall, SmartVoiceTickerBoardMatrix, SmartVoiceTickerBoards, SmartVoiceTickerEvidence } from "./smartVoiceTypes";

const MARKET_WINDOWS: Record<SmartVoiceMarketWindow, number> = {
  "24H": 24,
  "3D": 72,
  "7D": 168,
  "30D": 720,
  "90D": 2160,
};

const NEW_COVERAGE_LOOKBACK_HOURS = 180 * 24;

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

function getSmartVoiceTickerRows(hours: number, minSv: number) {
  return all<SmartVoiceRawCall>(
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

function hydrateEvidence(evidenceById: Record<string, SmartVoiceTickerEvidence>) {
  const ids = Object.keys(evidenceById);
  const chunkSize = 400;
  for (let offset = 0; offset < ids.length; offset += chunkSize) {
    const chunk = ids.slice(offset, offset + chunkSize);
    const placeholders = chunk.map(() => "?").join(",");
    const rows = all<SmartVoiceEvidenceContent>(
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

function emptySmartVoiceTickerBoardMatrix(): SmartVoiceTickerBoardMatrix {
  const matrix = {} as SmartVoiceTickerBoardMatrix;
  for (const platformKey of Object.keys(MARKET_PLATFORM_GROUPS) as SmartVoiceMarketPlatformKey[]) {
    matrix[platformKey] = {} as Record<SmartVoiceMarketWindow, SmartVoiceTickerBoards>;
    for (const windowKey of Object.keys(MARKET_WINDOWS) as SmartVoiceMarketWindow[]) {
      matrix[platformKey][windowKey] = { bullish: [], bearish: [], contrast: [], authorShift: [], newCoverage: [] };
    }
  }
  return matrix;
}

export function getSmartVoiceTickerBoards(limit = 5, days = 14, minSv = 0) {
  return safeQuery(() => {
    const rows = getSmartVoiceTickerRows(days * 24, minSv);
    return buildSmartVoiceTickerBoards(rows, limit);
  }, { bullish: [], bearish: [], contrast: [], authorShift: [], newCoverage: [] });
}

export function getSmartVoiceMarketData(limit = 24): SmartVoiceMarketData {
  return safeQuery(() => {
    const rows = getSmartVoiceTickerRows(MARKET_WINDOWS["90D"] + NEW_COVERAGE_LOOKBACK_HOURS, 0);
    const latestMs = rows.length ? Date.parse(`${rows[0].latestAt.replace(" ", "T")}Z`) : 0;
    const evidenceById: Record<string, SmartVoiceTickerEvidence> = {};
    const matrix = {} as SmartVoiceTickerBoardMatrix;
    for (const [platformKey, sources] of Object.entries(MARKET_PLATFORM_GROUPS) as [SmartVoiceMarketPlatformKey, SmartVoiceMarketSource[]][]) {
      const sourceSet = new Set<string>(sources);
      matrix[platformKey] = {} as Record<SmartVoiceMarketWindow, SmartVoiceTickerBoards>;
      for (const [windowKey, hours] of Object.entries(MARKET_WINDOWS) as [SmartVoiceMarketWindow, number][]) {
        const cutoffMs = latestMs - hours * 60 * 60 * 1000;
        const previousCutoffMs = latestMs - hours * 2 * 60 * 60 * 1000;
        const historyCutoffMs = cutoffMs - NEW_COVERAGE_LOOKBACK_HOURS * 60 * 60 * 1000;
        const scopedRows = rows.filter((row) => sourceSet.has(row.source) && Date.parse(`${row.createdAt.replace(" ", "T")}Z`) >= cutoffMs);
        const previousRows = rows.filter((row) => {
          if (!sourceSet.has(row.source)) return false;
          const createdMs = Date.parse(`${row.createdAt.replace(" ", "T")}Z`);
          return createdMs >= previousCutoffMs && createdMs < cutoffMs;
        });
        const historyRows = rows.filter((row) => {
          if (!sourceSet.has(row.source)) return false;
          const createdMs = Date.parse(`${row.createdAt.replace(" ", "T")}Z`);
          return createdMs >= historyCutoffMs && createdMs < cutoffMs;
        });
        matrix[platformKey][windowKey] = buildSmartVoiceTickerBoards(scopedRows, limit, "platform", evidenceById, previousRows, historyRows);
      }
    }
    hydrateEvidence(evidenceById);
    return { boards: matrix, evidenceById, latestAt: rows[0]?.latestAt ?? "" };
  }, { boards: emptySmartVoiceTickerBoardMatrix(), evidenceById: {}, latestAt: "" });
}

export function getSmartVoiceTickerBoardMatrix(limit = 24): SmartVoiceTickerBoardMatrix {
  return getSmartVoiceMarketData(limit).boards;
}
