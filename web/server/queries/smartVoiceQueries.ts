import { all } from "@/lib/db";

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
  topHandles: string[];
  signal: "high_bull_low_bear" | "high_bear_low_bull" | "sv_consensus_bull" | "sv_consensus_bear" | "mixed";
}

interface RawCall {
  ticker: string;
  nameZh: string;
  nameEn: string;
  direction: Direction;
  callWeight: number;
  sv: number;
  nEff: number;
  confidence: string;
  handle: string;
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

function weight(row: RawCall) {
  const sv = Math.max(40, Math.min(180, row.sv || 100));
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

function build(rows: RawCall[], limit: number): {
  bullish: SmartVoiceTickerRank[];
  bearish: SmartVoiceTickerRank[];
  contrast: SmartVoiceTickerRank[];
} {
  const byTicker = new Map<string, SmartVoiceTickerRank & { handleScore: Map<string, number> }>();
  for (const row of rows) {
    const current = byTicker.get(row.ticker) ?? {
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
      topHandles: [],
      signal: "mixed" as const,
      handleScore: new Map<string, number>(),
    };
    const w = weight(row);
    const signed = row.direction === "bull" ? w : -w;
    if (row.direction === "bull") {
      current.bullScore += w;
      current.nBull += 1;
      if (row.sv >= 115) current.highBullScore += w;
      if (row.sv <= 95) current.lowBullScore += w;
    } else {
      current.bearScore += w;
      current.nBear += 1;
      if (row.sv >= 115) current.highBearScore += w;
      if (row.sv <= 95) current.lowBearScore += w;
    }
    current.nPosts += 1;
    current.netScore += signed;
    current.highNet = current.highBullScore - current.highBearScore;
    current.lowNet = current.lowBullScore - current.lowBearScore;
    current.contrastScore = Math.abs(current.highNet - current.lowNet);
    current.handleScore.set(row.handle, (current.handleScore.get(row.handle) ?? 0) + Math.abs(w));
    byTicker.set(row.ticker, current);
  }

  const ranked = [...byTicker.values()]
    .filter((row) => row.nBull + row.nBear >= 3)
    .map((row) => {
      row.signal = signalOf(row);
      row.topHandles = [...row.handleScore.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3)
        .map(([handle]) => handle);
      const { handleScore, ...rest } = row;
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
      };
    });

  return {
    bullish: [...ranked].sort((a, b) => b.netScore - a.netScore).slice(0, limit),
    bearish: [...ranked].sort((a, b) => a.netScore - b.netScore).slice(0, limit),
    contrast: [...ranked]
      .filter((row) => row.highBullScore + row.highBearScore > 0 && row.lowBullScore + row.lowBearScore > 0)
      .sort((a, b) => b.contrastScore - a.contrastScore)
      .slice(0, limit),
  };
}

export function getSmartVoiceTickerBoards(limit = 5, days = 14) {
  return safe(() => {
    const rows = all<RawCall>(
      `WITH mx AS (SELECT MAX(substr(created_at,1,10)) AS day FROM sv_call)
       SELECT upper(c.ticker) AS ticker,
              COALESCE(g.name_zh, upper(c.ticker)) AS nameZh,
              COALESCE(g.name_en, upper(c.ticker)) AS nameEn,
              c.direction AS direction,
              COALESCE(c.call_weight, 0.6) AS callWeight,
              COALESCE(s.sv, 100) AS sv,
              COALESCE(s.n_eff, 0) AS nEff,
              COALESCE(s.confidence, 'observing') AS confidence,
              COALESCE(s.handle, c.author_handle, '') AS handle
          FROM sv_call c
          JOIN sv_investor_score s ON s.investor_id = c.investor_id
          JOIN gr_ticker g ON upper(g.ticker) = upper(c.ticker)
         WHERE c.direction IN ('bull','bear')
           AND substr(c.created_at,1,10) >= date((SELECT day FROM mx), ?)
           AND c.is_actionable_call = 1`,
      `-${days} day`,
    );
    return build(rows, limit);
  }, { bullish: [], bearish: [], contrast: [] });
}
