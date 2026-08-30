import { all, get } from "@/lib/db";
import { safeQuery } from "@/server/db/safeQuery";
import type { SmartVoiceLiveCall, SmartVoiceOverviewStats } from "./smartVoiceTypes";

const EMPTY_OVERVIEW: SmartVoiceOverviewStats = {
  scoredInvestors: 0,
  highConfidenceInvestors: 0,
  platformCount: 0,
  actionableCalls: 0,
  latestCallAt: "",
};

export function getSmartVoiceOverviewStats(): SmartVoiceOverviewStats {
  return safeQuery(() => get<SmartVoiceOverviewStats>(
    `SELECT
       (SELECT COUNT(*) FROM sv_investor_score) AS scoredInvestors,
       (SELECT COUNT(*) FROM sv_investor_score WHERE confidence = 'high') AS highConfidenceInvestors,
       (SELECT COUNT(DISTINCT source) FROM sv_investor_score) AS platformCount,
       (SELECT COUNT(*) FROM sv_call WHERE is_actionable_call = 1) AS actionableCalls,
       COALESCE((SELECT MAX(datetime(created_at)) FROM sv_call WHERE is_actionable_call = 1), '') AS latestCallAt`,
  ) ?? EMPTY_OVERVIEW, EMPTY_OVERVIEW);
}

export function getSmartVoiceLiveCalls(limit = 240, days = 60): SmartVoiceLiveCall[] {
  const perSourceLimit = Math.max(20, Math.ceil(limit / 4));
  const recentDays = Math.max(1, Math.floor(days));
  return safeQuery(() => all<SmartVoiceLiveCall>(
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
