import { all } from "@/lib/db";

function safe<T>(fn: () => T, fallback: T): T {
  try {
    return fn();
  } catch {
    return fallback;
  }
}

export interface SmartVoiceEvidenceCall {
  candidateId: string;
  ticker: string;
  source: string;
  day: string;
  direction: "bull" | "bear" | "neutral";
  horizon: string;
  callWeight: number;
  summaryZh: string;
  summaryEn: string;
  evidenceSpan: string;
  text: string;
  url: string;
  interactions: number;
  contribution: number | null;
  returnPct: number | null;
  excessReturnPct: number | null;
  actualHit: number | null;
  status: string | null;
}

export interface SmartVoiceInvestorEvidence {
  bestCalls: SmartVoiceEvidenceCall[];
  weakCalls: SmartVoiceEvidenceCall[];
  recentCalls: SmartVoiceEvidenceCall[];
}

interface RawCall {
  candidateId: string;
  ticker: string;
  source: string;
  day: string;
  direction: "bull" | "bear" | "neutral";
  horizon: string;
  callWeight: number;
  summaryZh: string;
  summaryEn: string;
  evidenceSpan: string;
  text: string;
  url: string;
  interactions: number;
  contribution: number | null;
  returnPct: number | null;
  excessReturnPct: number | null;
  actualHit: number | null;
  status: string | null;
}

function mapCall(row: RawCall): SmartVoiceEvidenceCall {
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
  };
}

function evidenceRows(investorId: string, order: "best" | "weak" | "recent", limit: number) {
  const orderBy =
    order === "best"
      ? "COALESCE(s.contribution, -999999) DESC, cc.interactions DESC"
      : order === "weak"
        ? "COALESCE(s.contribution, 999999) ASC, cc.interactions DESC"
        : "c.created_at DESC, cc.interactions DESC";
  const contributionFilter = order === "best" ? "AND COALESCE(s.contribution, 0) > 0" : order === "weak" ? "AND COALESCE(s.contribution, 0) < 0" : "";

  return safe(
    () =>
      all<RawCall>(
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
                s.status AS status
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
      ).map(mapCall),
    [],
  );
}

export function getSmartVoiceInvestorEvidence(investorId: string): SmartVoiceInvestorEvidence {
  return {
    bestCalls: evidenceRows(investorId, "best", 6),
    weakCalls: evidenceRows(investorId, "weak", 6),
    recentCalls: evidenceRows(investorId, "recent", 5),
  };
}
