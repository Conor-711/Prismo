import { all } from "@/lib/db";
import { safeQuery } from "@/server/db/safeQuery";
import { getSmartVoiceEvidencePrices } from "./smartVoiceInvestorEvidenceQueries";
import type {
  SmartVoiceRawRepresentativeCall,
  SmartVoiceRepresentativeCall,
  SmartVoiceRepresentativeEvidence,
  SmartVoiceRepresentativeEvidenceBundle,
  SmartVoiceRepresentativePricePoint,
} from "./smartVoiceInvestorTypes";

export function getSmartVoiceRepresentativeEvidence(
  investorIds: string[],
  limitPerShowcase = 10,
): SmartVoiceRepresentativeEvidenceBundle {
  const ids = [...new Set(investorIds.filter(Boolean))];
  if (!ids.length || limitPerShowcase < 1) return { byInvestor: {}, priceByTicker: {} };
  const placeholders = ids.map(() => "?").join(", ");
  const rows = safeQuery(
    () =>
      all<SmartVoiceRawRepresentativeCall>(
        `WITH eligible AS (
           SELECT c.investor_id AS investorId,
                  c.candidate_id AS candidateId,
                  upper(c.ticker) AS ticker,
                  COALESCE(c.source, 'x') AS source,
                  substr(COALESCE(c.created_at, ''), 1, 10) AS day,
                  COALESCE(c.direction, 'neutral') AS direction,
                  COALESCE(c.horizon_bucket, '') AS horizon,
                  COALESCE(NULLIF(c.summary_zh, ''), NULLIF(c.evidence_span, ''), NULLIF(cc.text, ''), '') AS summaryZh,
                  COALESCE(NULLIF(c.summary_en, ''), NULLIF(c.evidence_span, ''), NULLIF(cc.text, ''), '') AS summaryEn,
                  COALESCE(cc.url, '') AS url,
                  s.contribution AS contribution,
                  s.return_pct AS returnPct,
                  s.excess_return_pct AS excessReturnPct,
                  s.actual_hit AS actualHit,
                  COALESCE(s.entry_day, '') AS entryDay,
                  COALESCE(s.exit_day, '') AS exitDay,
                  s.entry_price AS entryPrice,
                  s.exit_price AS exitPrice,
                  COALESCE(cc.interactions, 0) AS interactions,
                  CASE WHEN s.contribution > 0 THEN 'best' ELSE 'weak' END AS contributionKind
             FROM sv_call c
             LEFT JOIN sv_call_candidate cc ON cc.candidate_id = c.candidate_id
             INNER JOIN sv_call_settlement s
                     ON s.candidate_id = c.candidate_id
                    AND s.horizon = c.horizon_bucket
            WHERE c.investor_id IN (${placeholders})
              AND c.is_actionable_call = 1
              AND c.direction IN ('bull', 'bear', 'neutral')
              AND s.status = 'settled'
              AND s.contribution IS NOT NULL
              AND s.contribution != 0
         ),
         ticker_stats AS (
           SELECT investorId,
                  ticker,
                  contributionKind AS focusKind,
                  SUM(ABS(contribution)) AS magnitude,
                  SUM(contribution) AS focusContribution,
                  COUNT(*) AS focusCallCount
             FROM eligible
            GROUP BY investorId, ticker, contributionKind
         ),
         ranked_tickers AS (
           SELECT *,
                  row_number() OVER (
                    PARTITION BY investorId, focusKind
                    ORDER BY magnitude DESC, focusCallCount DESC, ticker
                  ) AS tickerRank
             FROM ticker_stats
         ),
         showcases AS (
           SELECT investorId, ticker, focusKind, focusContribution, focusCallCount
             FROM ranked_tickers
            WHERE tickerRank = 1
         ),
         ranked_calls AS (
           SELECT s.focusKind,
                  s.focusContribution,
                  s.focusCallCount,
                  e.*,
                  row_number() OVER (
                    PARTITION BY e.investorId, s.focusKind
                    ORDER BY ABS(e.contribution) DESC, e.interactions DESC, e.day DESC
                  ) AS callRank
             FROM showcases s
             INNER JOIN eligible e
                     ON e.investorId = s.investorId
                    AND e.ticker = s.ticker
         )
         SELECT investorId, candidateId, ticker, source, day, direction, horizon,
                summaryZh, summaryEn, url, contribution, returnPct,
                excessReturnPct, actualHit, entryDay, exitDay, entryPrice, exitPrice,
                focusKind, focusContribution, focusCallCount
           FROM ranked_calls
          WHERE callRank <= ?
          ORDER BY investorId, focusKind, day, candidateId`,
        ...ids,
        limitPerShowcase,
      ),
    [],
  );

  const result: Record<string, SmartVoiceRepresentativeEvidence> = {};
  const chartCalls: SmartVoiceRepresentativeCall[] = [];
  for (const row of rows) {
    const group = (result[row.investorId] ??= { best: null, weak: null });
    const call: SmartVoiceRepresentativeCall = {
      candidateId: row.candidateId,
      ticker: row.ticker,
      source: row.source,
      day: row.day,
      direction: row.direction,
      horizon: row.horizon,
      summaryZh: row.summaryZh,
      summaryEn: row.summaryEn,
      url: row.url,
      contribution: Number(row.contribution),
      returnPct: typeof row.returnPct === "number" ? row.returnPct : null,
      excessReturnPct: typeof row.excessReturnPct === "number" ? row.excessReturnPct : null,
      actualHit: typeof row.actualHit === "number" ? row.actualHit : null,
      entryDay: row.entryDay,
      exitDay: row.exitDay,
      entryPrice: typeof row.entryPrice === "number" ? row.entryPrice : null,
      exitPrice: typeof row.exitPrice === "number" ? row.exitPrice : null,
    };
    const showcase = group[row.focusKind] ??= {
      ticker: row.ticker,
      kind: row.focusKind,
      focusContribution: Number(row.focusContribution),
      focusCallCount: Number(row.focusCallCount),
      calls: [],
    };
    showcase.calls.push(call);
    chartCalls.push(call);
  }
  const priceByTicker = Object.fromEntries(
    Object.entries(getSmartVoiceEvidencePrices(chartCalls)).map(([ticker, prices]) => [
      ticker,
      prices.map((price): SmartVoiceRepresentativePricePoint => [price.day, price.close]),
    ]),
  );
  return { byInvestor: result, priceByTicker };
}
