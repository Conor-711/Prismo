import { all } from "@/lib/db";

const SV_TICKER_SIGNAL_ROLLOUT = new Set(["MU", "NVDA", "MSTR"]);

export type SvSignalHorizon = "1D" | "5D" | "20D" | "60D" | "90D" | "180D";
export type SvSignalCohort = "top10" | "top25" | "bottom25" | "bottom10";

export interface SvTickerSignalSnapshot {
  day: string;
  horizon: SvSignalHorizon;
  cohort: SvSignalCohort;
  percentileCut: number;
  nAuthors: number;
  nBull: number;
  nBear: number;
  bullShare: number;
  bearShare: number;
  weightedNet: number;
  consensusStrength: number;
  effectiveVoices: number;
  dominantDirection: "bull" | "bear";
  cluster: boolean;
  avgSv: number;
  targetCount: number;
  targetMedian: number | null;
  explicitHorizonCount: number;
  sourceCount: number;
  callTypes: Record<string, number>;
  sources: Record<string, number>;
  candidateIds: string[];
  investorIds: string[];
}

export interface SvTickerSignalHistoryPoint {
  day: string;
  horizon: SvSignalHorizon;
  cohort: SvSignalCohort;
  nAuthors: number;
  weightedNet: number;
  consensusStrength: number;
  effectiveVoices: number;
  dominantDirection: "bull" | "bear";
  cluster: boolean;
}

export interface SvTickerSignalEvidence {
  candidateId: string;
  investorId: string | null;
  authorHandle: string;
  source: string;
  createdAt: string;
  direction: "bull" | "bear" | "neutral";
  horizon: SvSignalHorizon;
  percentile: number;
  asofSv: number;
  confidence: "observing" | "low" | "medium" | "high";
  effectiveSample: number;
  settledCalls: number;
  targetPrice: number | null;
  callWeight: number;
  convictionScore: number;
  evidenceScore: number;
  specificityScore: number;
  lifecycleAction: string;
  callStructure: string;
  entryStatus: string;
  viewpoints: string[];
  triggerCondition: string;
  invalidationCondition: string;
  evidenceSpan: string;
  summaryZh: string;
  summaryEn: string;
}

export interface SvTickerAuthorAbility {
  investorId: string;
  name: string;
  source: string;
  sv: number;
  confidence: string;
  tickerCalls: number;
  weightedHitRate: number | null;
  avgDirectionalExcessPct: number | null;
  contribution: number;
  dominantStyle: string;
}

export interface SvTickerThesisNarrative {
  lens: string;
  stance: "bull" | "bear" | "neutral";
  leadZh: string;
  leadEn: string;
}

export interface SvTickerLensProfile {
  ticker: string;
  totalWeight: number;
  lenses: Record<string, number>;
}

export interface SvTickerSignalOutcome {
  horizon: SvSignalHorizon;
  exitDay: string | null;
  returnPct: number | null;
  excessReturnPct: number | null;
  directionalReturnPct: number | null;
  directionalExcessPct: number | null;
  hit: boolean | null;
  maxFavorableExcess: number | null;
  maxAdverseExcess: number | null;
  timeToPeakDays: number | null;
  status: "settled" | "pending";
}

export interface SvTickerSignalEvent {
  id: string;
  cohort: SvSignalCohort;
  percentileCut: number;
  horizon: SvSignalHorizon;
  direction: "bull" | "bear";
  startDay: string;
  endDay: string;
  signalDay: string;
  nAuthors: number;
  nBull: number;
  nBear: number;
  consensusStrength: number;
  effectiveVoices: number;
  weightedNet: number;
  avgSv: number;
  sourceCount: number;
  targetMedian: number | null;
  entryDay: string | null;
  entryPrice: number | null;
  outcomes: SvTickerSignalOutcome[];
}

export interface SvTickerSignalStat {
  cohort: SvSignalCohort;
  signalHorizon: SvSignalHorizon;
  outcomeHorizon: SvSignalHorizon;
  direction: "bull" | "bear" | "all";
  nEvents: number;
  hitRate: number | null;
  avgDirectionalReturnPct: number | null;
  medianDirectionalReturnPct: number | null;
  avgDirectionalExcessPct: number | null;
  medianDirectionalExcessPct: number | null;
  avgMaxFavorableExcess: number | null;
  avgMaxAdverseExcess: number | null;
  avgTimeToPeakDays: number | null;
}

export interface SvTickerSignalData {
  ticker: string;
  current: SvTickerSignalSnapshot[];
  history: SvTickerSignalHistoryPoint[];
  evidence: SvTickerSignalEvidence[];
  evidenceWindowDays: number;
  authorAbilities: SvTickerAuthorAbility[];
  thesisNarratives: SvTickerThesisNarrative[];
  peerLensProfiles: SvTickerLensProfile[];
  events: SvTickerSignalEvent[];
  stats: SvTickerSignalStat[];
  prices: { day: string; close: number }[];
  updatedAt: string | null;
}

function safeJson(value: unknown): Record<string, number> {
  try {
    const parsed = JSON.parse(String(value || "{}"));
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function safeStringArray(value: unknown): string[] {
  try {
    const parsed = JSON.parse(String(value || "[]"));
    return Array.isArray(parsed) ? parsed.map(String) : [];
  } catch {
    return [];
  }
}

function numberOrNull(value: unknown): number | null {
  return value == null ? null : Number(value);
}

export function getTickerSmartVoiceSignals(symbol: string): SvTickerSignalData | null {
  const ticker = symbol.trim().toUpperCase();
  if (!SV_TICKER_SIGNAL_ROLLOUT.has(ticker)) return null;

  try {
    const currentRows = all<any>(
      `WITH ranked AS (
         SELECT d.*,
                ROW_NUMBER() OVER (PARTITION BY horizon, cohort ORDER BY day DESC) AS rn
           FROM sv_ticker_signal_daily d
          WHERE ticker = ?
       )
       SELECT * FROM ranked WHERE rn = 1 ORDER BY horizon, cohort`,
      ticker,
    );
    if (!currentRows.length) return null;

    const historyRows = all<any>(
      `WITH ranked AS (
         SELECT d.*,
                ROW_NUMBER() OVER (PARTITION BY horizon, cohort ORDER BY day DESC) AS rn
           FROM sv_ticker_signal_daily d
          WHERE ticker = ?
       )
       SELECT * FROM ranked WHERE rn <= 260 ORDER BY day, horizon, cohort`,
      ticker,
    );
    const latestSignalDay = currentRows.map((row) => String(row.day)).sort().pop()!;
    const evidenceWindowDays = 45;
    const evidenceRows = all<any>(
      `SELECT c.candidate_id, c.investor_id, c.author_handle, c.source, c.created_at, c.direction,
              upper(c.horizon_bucket) AS horizon, a.percentile, a.sv AS asof_sv,
              a.confidence, a.n_eff, a.settled_calls, c.target_price, c.call_weight,
              c.conviction_score, c.evidence_score, c.specificity_score,
              c.lifecycle_action, c.call_structure, c.entry_status,
              c.trigger_condition, c.invalidation_condition, c.evidence_span, v.viewpoints,
              c.summary_zh, c.summary_en
         FROM sv_call c
         JOIN sv_investor_score_asof a
          ON a.asof_day = substr(c.created_at,1,10)
          AND a.investor_id = c.investor_id
         LEFT JOIN kol_viewpoint v
           ON v.source = c.source
          AND v.item_id = c.tweet_id
          AND upper(v.ticker) = upper(c.ticker)
        WHERE upper(c.ticker) = ?
          AND c.is_actionable_call = 1
          AND c.direction IN ('bull','bear')
          AND upper(c.horizon_bucket) IN ('1D','5D','20D','60D','90D','180D')
          AND substr(c.created_at,1,10) >= date(?, '-' || ? || ' days')
        ORDER BY c.created_at DESC
        LIMIT 1200`,
      ticker,
      latestSignalDay,
      evidenceWindowDays - 1,
    );

    const eventRows = all<any>(
      `SELECT * FROM sv_ticker_signal_event
        WHERE ticker = ?
        ORDER BY signal_day DESC
        LIMIT 240`,
      ticker,
    );
    const eventIds = eventRows.map((row) => String(row.event_id));
    const outcomeRows = eventIds.length
      ? all<any>(
          `SELECT * FROM sv_ticker_signal_outcome
            WHERE event_id IN (${eventIds.map(() => "?").join(",")})`,
          ...eventIds,
        )
      : [];
    const outcomesByEvent = new Map<string, SvTickerSignalOutcome[]>();
    for (const row of outcomeRows) {
      const list = outcomesByEvent.get(String(row.event_id)) ?? [];
      list.push({
        horizon: row.outcome_horizon,
        exitDay: row.exit_day || null,
        returnPct: numberOrNull(row.return_pct),
        excessReturnPct: numberOrNull(row.excess_return_pct),
        directionalReturnPct: numberOrNull(row.directional_return_pct),
        directionalExcessPct: numberOrNull(row.directional_excess_pct),
        hit: row.actual_hit == null ? null : Boolean(row.actual_hit),
        maxFavorableExcess: numberOrNull(row.max_favorable_excess),
        maxAdverseExcess: numberOrNull(row.max_adverse_excess),
        timeToPeakDays: numberOrNull(row.time_to_peak_days),
        status: row.status,
      });
      outcomesByEvent.set(String(row.event_id), list);
    }

    const stats = all<any>(
      `SELECT * FROM sv_ticker_signal_stat
        WHERE ticker = ?
        ORDER BY cohort, signal_horizon, outcome_horizon, direction`,
      ticker,
    ).map((row): SvTickerSignalStat => ({
      cohort: row.cohort,
      signalHorizon: row.signal_horizon,
      outcomeHorizon: row.outcome_horizon,
      direction: row.direction,
      nEvents: Number(row.n_events || 0),
      hitRate: numberOrNull(row.hit_rate),
      avgDirectionalReturnPct: numberOrNull(row.avg_directional_return_pct),
      medianDirectionalReturnPct: numberOrNull(row.median_directional_return_pct),
      avgDirectionalExcessPct: numberOrNull(row.avg_directional_excess_pct),
      medianDirectionalExcessPct: numberOrNull(row.median_directional_excess_pct),
      avgMaxFavorableExcess: numberOrNull(row.avg_max_favorable_excess),
      avgMaxAdverseExcess: numberOrNull(row.avg_max_adverse_excess),
      avgTimeToPeakDays: numberOrNull(row.avg_time_to_peak_days),
    }));

    const authorAbilities = all<any>(
      `SELECT s.investor_id,
              COALESCE(NULLIF(i.name,''), NULLIF(i.handle,''), NULLIF(MAX(c.author_handle),''), s.investor_id) AS name,
              COALESCE(i.source, MAX(c.source), 'unknown') AS source,
              COALESCE(i.sv,100) AS sv, COALESCE(i.confidence,'observing') AS confidence,
              COUNT(DISTINCT s.candidate_id) AS ticker_calls,
              SUM(s.score_weight * s.actual_hit) / NULLIF(SUM(s.score_weight),0) AS weighted_hit_rate,
              SUM(s.score_weight * CASE WHEN c.direction='bull' THEN s.excess_return_pct ELSE -s.excess_return_pct END)
                / NULLIF(SUM(s.score_weight),0) AS avg_directional_excess_pct,
              SUM(COALESCE(s.contribution,0)) AS contribution,
              COALESCE((SELECT sc.investor_style FROM sv_call sc
                         WHERE sc.investor_id=s.investor_id AND upper(sc.ticker)=?
                           AND sc.investor_style NOT IN ('','unknown')
                         GROUP BY sc.investor_style ORDER BY COUNT(*) DESC LIMIT 1),'unknown') AS dominant_style
         FROM sv_call_settlement s
         JOIN sv_call c ON c.candidate_id=s.candidate_id
         LEFT JOIN sv_investor_score i ON i.investor_id=s.investor_id
        WHERE upper(s.ticker)=? AND s.status='settled' AND s.actual_hit IS NOT NULL
        GROUP BY s.investor_id
       HAVING COUNT(DISTINCT s.candidate_id)>=2
        ORDER BY ABS(SUM(COALESCE(s.contribution,0))) DESC, ticker_calls DESC
        LIMIT 24`,
      ticker,
      ticker,
    ).map((row): SvTickerAuthorAbility => ({
      investorId: String(row.investor_id),
      name: String(row.name || row.investor_id),
      source: String(row.source || "unknown"),
      sv: Number(row.sv || 100),
      confidence: String(row.confidence || "observing"),
      tickerCalls: Number(row.ticker_calls || 0),
      weightedHitRate: numberOrNull(row.weighted_hit_rate),
      avgDirectionalExcessPct: numberOrNull(row.avg_directional_excess_pct),
      contribution: Number(row.contribution || 0),
      dominantStyle: String(row.dominant_style || "unknown"),
    }));

    const thesisNarratives = all<any>(
      `SELECT lens, stance, lead_zh, lead_en
         FROM kol_narrative
        WHERE upper(ticker)=? AND window='1mo'
        ORDER BY lens, stance`,
      ticker,
    ).map((row): SvTickerThesisNarrative => ({
      lens: String(row.lens),
      stance: row.stance,
      leadZh: String(row.lead_zh || ""),
      leadEn: String(row.lead_en || ""),
    }));

    const peerLensRows = all<any>(
      `SELECT upper(c.ticker) AS ticker, j.value AS lens,
              SUM(c.call_weight * (1.5 - MIN(100,MAX(0,a.percentile))/100.0)) AS weight
         FROM sv_call c
         JOIN sv_investor_score_asof a
           ON a.asof_day=substr(c.created_at,1,10) AND a.investor_id=c.investor_id
         JOIN kol_viewpoint v
           ON v.source=c.source AND v.item_id=c.tweet_id AND upper(v.ticker)=upper(c.ticker)
         JOIN json_each(v.viewpoints) j
        WHERE upper(c.ticker) IN ('MU','NVDA','MSTR')
          AND c.is_actionable_call=1
          AND substr(c.created_at,1,10)>=date(?, '-' || ? || ' days')
        GROUP BY upper(c.ticker), j.value
        ORDER BY ticker, weight DESC`,
      latestSignalDay,
      evidenceWindowDays - 1,
    );
    const peerProfileMap = new Map<string, { totalWeight: number; lenses: Record<string, number> }>();
    for (const row of peerLensRows) {
      const key = String(row.ticker);
      const profile = peerProfileMap.get(key) ?? { totalWeight: 0, lenses: {} };
      const weight = Number(row.weight || 0);
      profile.totalWeight += weight;
      profile.lenses[String(row.lens)] = weight;
      peerProfileMap.set(key, profile);
    }
    const peerLensProfiles = [...peerProfileMap.entries()].map(([profileTicker, profile]): SvTickerLensProfile => ({
      ticker: profileTicker,
      totalWeight: profile.totalWeight,
      lenses: Object.fromEntries(Object.entries(profile.lenses).map(([lens, weight]) => [lens, profile.totalWeight ? weight / profile.totalWeight : 0])),
    }));

    return {
      ticker,
      current: currentRows.map((row): SvTickerSignalSnapshot => ({
        day: row.day,
        horizon: row.horizon,
        cohort: row.cohort,
        percentileCut: Number(row.percentile_cut),
        nAuthors: Number(row.n_authors),
        nBull: Number(row.n_bull),
        nBear: Number(row.n_bear),
        bullShare: Number(row.bull_share),
        bearShare: Number(row.bear_share),
        weightedNet: Number(row.weighted_net),
        consensusStrength: Number(row.consensus_strength),
        effectiveVoices: Number(row.effective_voices),
        dominantDirection: row.dominant_direction,
        cluster: Boolean(row.cluster_flag),
        avgSv: Number(row.avg_sv),
        targetCount: Number(row.target_count),
        targetMedian: numberOrNull(row.target_median),
        explicitHorizonCount: Number(row.explicit_horizon_count),
        sourceCount: Number(row.source_count),
        callTypes: safeJson(row.call_types_json),
        sources: safeJson(row.sources_json),
        candidateIds: safeStringArray(row.candidate_ids_json),
        investorIds: safeStringArray(row.investor_ids_json),
      })),
      history: historyRows.map((row): SvTickerSignalHistoryPoint => ({
        day: String(row.day),
        horizon: row.horizon,
        cohort: row.cohort,
        nAuthors: Number(row.n_authors),
        weightedNet: Number(row.weighted_net),
        consensusStrength: Number(row.consensus_strength),
        effectiveVoices: Number(row.effective_voices),
        dominantDirection: row.dominant_direction,
        cluster: Boolean(row.cluster_flag),
      })),
      evidence: evidenceRows.map((row): SvTickerSignalEvidence => ({
        candidateId: String(row.candidate_id),
        investorId: row.investor_id ? String(row.investor_id) : null,
        authorHandle: String(row.author_handle || "").trim(),
        source: String(row.source || "unknown"),
        createdAt: String(row.created_at || ""),
        direction: row.direction,
        horizon: row.horizon,
        percentile: Number(row.percentile),
        asofSv: Number(row.asof_sv || 100),
        confidence: row.confidence || "observing",
        effectiveSample: Number(row.n_eff || 0),
        settledCalls: Number(row.settled_calls || 0),
        targetPrice: numberOrNull(row.target_price),
        callWeight: Number(row.call_weight || 0),
        convictionScore: Number(row.conviction_score || 0),
        evidenceScore: Number(row.evidence_score || 0),
        specificityScore: Number(row.specificity_score || 0),
        lifecycleAction: String(row.lifecycle_action || "none"),
        callStructure: String(row.call_structure || ""),
        entryStatus: String(row.entry_status || ""),
        viewpoints: safeStringArray(row.viewpoints),
        triggerCondition: String(row.trigger_condition || "").trim(),
        invalidationCondition: String(row.invalidation_condition || "").trim(),
        evidenceSpan: String(row.evidence_span || "").trim(),
        summaryZh: String(row.summary_zh || "").trim(),
        summaryEn: String(row.summary_en || "").trim(),
      })),
      evidenceWindowDays,
      authorAbilities,
      thesisNarratives,
      peerLensProfiles,
      events: eventRows.map((row): SvTickerSignalEvent => ({
        id: row.event_id,
        cohort: row.cohort,
        percentileCut: Number(row.percentile_cut),
        horizon: row.horizon,
        direction: row.direction,
        startDay: row.start_day,
        endDay: row.end_day,
        signalDay: row.signal_day,
        nAuthors: Number(row.n_authors),
        nBull: Number(row.n_bull),
        nBear: Number(row.n_bear),
        consensusStrength: Number(row.consensus_strength),
        effectiveVoices: Number(row.effective_voices),
        weightedNet: Number(row.weighted_net),
        avgSv: Number(row.avg_sv),
        sourceCount: Number(row.source_count),
        targetMedian: numberOrNull(row.target_median),
        entryDay: row.entry_day || null,
        entryPrice: numberOrNull(row.entry_price),
        outcomes: outcomesByEvent.get(String(row.event_id)) ?? [],
      })),
      stats,
      prices: all<any>(
        `SELECT day, close FROM price_daily
          WHERE upper(ticker) = ? AND close IS NOT NULL
          ORDER BY day DESC LIMIT 370`,
        ticker,
      ).reverse().map((row) => ({ day: String(row.day), close: Number(row.close) })),
      updatedAt: currentRows.map((row) => String(row.updated_at || "")).sort().pop() || null,
    };
  } catch {
    return null;
  }
}
