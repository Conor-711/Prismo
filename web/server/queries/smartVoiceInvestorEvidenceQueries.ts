import { all } from "@/lib/db";
import { safeQuery } from "@/server/db/safeQuery";
import type { SmartVoiceEvidenceCall, SmartVoiceEvidencePriceBar, SmartVoiceInvestorEvidence, SmartVoicePerformanceStats, SmartVoiceRawEvidenceCall } from "./smartVoiceInvestorTypes";

function mapCall(row: SmartVoiceRawEvidenceCall): SmartVoiceEvidenceCall {
  return {
    candidateId: row.candidateId,
    ticker: row.ticker,
    source: row.source,
    day: row.day,
    direction: row.direction,
    horizon: row.horizon,
    callWeight: Number(row.callWeight || 0),
    summaryZh: row.summaryZh || "",
    summaryEn: row.summaryEn || "",
    evidenceSpan: row.evidenceSpan || "",
    text: row.text || "",
    url: row.url || "",
    interactions: Number(row.interactions || 0),
    contribution: typeof row.contribution === "number" ? row.contribution : null,
    returnPct: typeof row.returnPct === "number" ? row.returnPct : null,
    excessReturnPct: typeof row.excessReturnPct === "number" ? row.excessReturnPct : null,
    actualHit: typeof row.actualHit === "number" ? row.actualHit : null,
    status: row.status || null,
    entryDay: row.entryDay || "",
    exitDay: row.exitDay || "",
    entryPrice: typeof row.entryPrice === "number" ? row.entryPrice : null,
    exitPrice: typeof row.exitPrice === "number" ? row.exitPrice : null,
  };
}

function evidenceRows(investorId: string, order: "best" | "weak" | "recent", limit: number) {
  const orderBy = order === "best"
    ? "COALESCE(s.contribution, -999999) DESC, cc.interactions DESC"
    : order === "weak"
      ? "COALESCE(s.contribution, 999999) ASC, cc.interactions DESC"
      : "c.created_at DESC, cc.interactions DESC";
  const contributionFilter = order === "best"
    ? "AND COALESCE(s.contribution, 0) > 0"
    : order === "weak" ? "AND COALESCE(s.contribution, 0) < 0" : "";

  return safeQuery(() => all<SmartVoiceRawEvidenceCall>(
    `SELECT c.candidate_id AS candidateId,
            upper(c.ticker) AS ticker,
            COALESCE(c.source, 'x') AS source,
            substr(COALESCE(c.created_at, ''), 1, 10) AS day,
            COALESCE(c.direction, 'neutral') AS direction,
            COALESCE(c.horizon_bucket, '') AS horizon,
            COALESCE(c.call_weight, 0) AS callWeight,
            COALESCE(c.summary_zh, '') AS summaryZh,
            COALESCE(c.summary_en, '') AS summaryEn,
            COALESCE(c.evidence_span, '') AS evidenceSpan,
            COALESCE(cc.text, '') AS text,
            COALESCE(cc.url, '') AS url,
            COALESCE(cc.interactions, 0) AS interactions,
            s.contribution AS contribution,
            s.return_pct AS returnPct,
            s.excess_return_pct AS excessReturnPct,
            s.actual_hit AS actualHit,
            s.status AS status,
            COALESCE(s.entry_day, '') AS entryDay,
            COALESCE(s.exit_day, '') AS exitDay,
            s.entry_price AS entryPrice,
            s.exit_price AS exitPrice
       FROM sv_call c
       LEFT JOIN sv_call_candidate cc ON cc.candidate_id = c.candidate_id
       LEFT JOIN sv_call_settlement s
              ON s.candidate_id = c.candidate_id
             AND s.horizon = c.horizon_bucket
      WHERE c.investor_id = ?
        AND c.is_actionable_call = 1
        AND c.direction IN ('bull', 'bear', 'neutral')
        ${contributionFilter}
      ORDER BY ${orderBy}
      LIMIT ?`,
    investorId,
    limit,
  ).map(mapCall), []);
}

function performanceRows(investorId: string) {
  return safeQuery(() => all<SmartVoiceRawEvidenceCall>(
    `SELECT c.candidate_id AS candidateId,
            upper(c.ticker) AS ticker,
            COALESCE(c.source, 'x') AS source,
            substr(COALESCE(c.created_at, ''), 1, 10) AS day,
            COALESCE(c.direction, 'neutral') AS direction,
            COALESCE(c.horizon_bucket, '') AS horizon,
            COALESCE(c.call_weight, 0) AS callWeight,
            COALESCE(NULLIF(c.summary_zh, ''), NULLIF(c.evidence_span, ''), NULLIF(cc.text, ''), '') AS summaryZh,
            COALESCE(NULLIF(c.summary_en, ''), NULLIF(c.evidence_span, ''), NULLIF(cc.text, ''), '') AS summaryEn,
            '' AS evidenceSpan,
            '' AS text,
            COALESCE(cc.url, '') AS url,
            COALESCE(cc.interactions, 0) AS interactions,
            s.contribution AS contribution,
            s.return_pct AS returnPct,
            s.excess_return_pct AS excessReturnPct,
            s.actual_hit AS actualHit,
            s.status AS status,
            COALESCE(s.entry_day, '') AS entryDay,
            COALESCE(s.exit_day, '') AS exitDay,
            s.entry_price AS entryPrice,
            s.exit_price AS exitPrice
       FROM sv_call c
       LEFT JOIN sv_call_candidate cc ON cc.candidate_id = c.candidate_id
       INNER JOIN sv_call_settlement s
               ON s.candidate_id = c.candidate_id
              AND s.horizon = c.horizon_bucket
      WHERE c.investor_id = ?
        AND c.is_actionable_call = 1
        AND c.direction IN ('bull', 'bear', 'neutral')
        AND s.status = 'settled'
        AND s.contribution IS NOT NULL
      ORDER BY c.created_at DESC, c.candidate_id DESC`,
    investorId,
  ).map(mapCall), []);
}

function median(values: number[]) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function performanceStats(calls: SmartVoiceEvidenceCall[]): SmartVoicePerformanceStats {
  const graded = calls.filter((call) => call.actualHit != null);
  const directionalExcess = calls.flatMap((call) => {
    if (call.excessReturnPct == null) return [];
    return [call.direction === "bear" ? -call.excessReturnPct : call.excessReturnPct];
  });
  return {
    settledCalls: calls.length,
    gradedCalls: graded.length,
    hitRate: graded.length ? graded.filter((call) => call.actualHit === 1).length / graded.length : null,
    positiveCalls: calls.filter((call) => (call.contribution ?? 0) > 0).length,
    negativeCalls: calls.filter((call) => (call.contribution ?? 0) < 0).length,
    netContribution: calls.reduce((sum, call) => sum + (call.contribution ?? 0), 0),
    medianDirectionalExcess: median(directionalExcess),
    coveredTickers: new Set(calls.map((call) => call.ticker)).size,
    firstDay: calls.at(-1)?.day ?? "",
    lastDay: calls[0]?.day ?? "",
  };
}

function shiftDay(day: string, offset: number) {
  const date = new Date(`${day}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + offset);
  return date.toISOString().slice(0, 10);
}

export function getSmartVoiceEvidencePrices(
  calls: Pick<SmartVoiceEvidenceCall, "ticker" | "day" | "entryDay" | "exitDay">[],
): Record<string, SmartVoiceEvidencePriceBar[]> {
  const ranges = new Map<string, { start: string; end: string }>();
  for (const call of calls) {
    const ticker = call.ticker.toUpperCase();
    const entry = call.entryDay || call.day;
    const exit = call.exitDay || call.entryDay || call.day;
    if (!ticker || !entry || !exit) continue;
    const start = shiftDay(entry, -35);
    const end = shiftDay(exit, 12);
    const current = ranges.get(ticker);
    ranges.set(ticker, {
      start: !current || start < current.start ? start : current.start,
      end: !current || end > current.end ? end : current.end,
    });
  }
  if (!ranges.size) return {};

  const rows: (SmartVoiceEvidencePriceBar & { ticker: string })[] = [];
  const entries = [...ranges.entries()];
  for (let offset = 0; offset < entries.length; offset += 200) {
    const batch = entries.slice(offset, offset + 200);
    const where: string[] = [];
    const params: unknown[] = [];
    for (const [ticker, range] of batch) {
      where.push("(ticker = ? AND day BETWEEN ? AND ?)");
      params.push(ticker, range.start, range.end);
    }
    rows.push(...all<SmartVoiceEvidencePriceBar & { ticker: string }>(
      `SELECT ticker, day,
              open, high, low, close, COALESCE(volume, 0) AS volume
         FROM price_daily
        WHERE close IS NOT NULL
          AND open IS NOT NULL
          AND high IS NOT NULL
          AND low IS NOT NULL
          AND (${where.join(" OR ")})
        ORDER BY ticker, day`,
      ...params,
    ));
  }
  const result: Record<string, SmartVoiceEvidencePriceBar[]> = {};
  for (const row of rows) {
    const ticker = String(row.ticker);
    (result[ticker] ??= []).push({
      day: String(row.day),
      open: Number(row.open),
      high: Number(row.high),
      low: Number(row.low),
      close: Number(row.close),
      volume: Number(row.volume),
    });
  }
  return result;
}

export function getSmartVoiceInvestorEvidence(investorId: string): SmartVoiceInvestorEvidence {
  const bestCalls = evidenceRows(investorId, "best", 6);
  const weakCalls = evidenceRows(investorId, "weak", 6);
  const recentCalls = evidenceRows(investorId, "recent", 5);
  const allCalls = performanceRows(investorId);
  const chartCalls = [...bestCalls, ...weakCalls];
  return {
    bestCalls,
    weakCalls,
    recentCalls,
    allCalls,
    performance: performanceStats(allCalls),
    priceByTicker: getSmartVoiceEvidencePrices(chartCalls),
  };
}
