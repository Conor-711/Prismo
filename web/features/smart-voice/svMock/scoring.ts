import type { SvBoard, SvConfidence, SvInvestor, SvTickerBoard } from "./types";
import { FALLBACK_NARRATIVES, INVESTORS, NARRATIVE_LABELS, TICKER_NARRATIVE } from "./constants";
import { getGeneratedSmartVoiceBoard } from "./generated";

export function getSmartVoiceBoard(): SvBoard {
  const generated = getGeneratedSmartVoiceBoard();
  if (generated) return generated;
  const investors = [...INVESTORS].sort((a, b) => b.sv - a.sv);
  return {
    investors,
    bottomInvestors: [...investors].sort((a, b) => a.sv - b.sv).slice(0, 10),
    x: investors.filter((i) => i.source === "x"),
    youtube: investors.filter((i) => i.source === "youtube"),
    currentNarratives: FALLBACK_NARRATIVES,
    updatedAt: "2026-07-03",
    totalInvestors: investors.length,
    exportedInvestors: investors.length,
  };
}

function hash01(input: string) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return (h % 1000) / 1000;
}

function clamp(n: number, lo = 40, hi = 180) {
  return Math.max(lo, Math.min(hi, Math.round(n)));
}

export function tickerNarrative(ticker: string) {
  const key = TICKER_NARRATIVE[ticker.toUpperCase()] ?? "software";
  return { key, ...NARRATIVE_LABELS[key] };
}

export function investorTickerSv(inv: SvInvestor, ticker: string) {
  const sym = ticker.toUpperCase();
  const direct = inv.tickerScores[sym];
  if (typeof direct === "number") return { score: direct, basisZh: `${sym} 直接样本`, basisEn: `${sym} direct sample` };
  const narrative = tickerNarrative(sym);
  const n = inv.narrativeScores[narrative.key];
  if (typeof n === "number") {
    return { score: clamp(n - 4 + hash01(`${inv.id}:${sym}`) * 6), basisZh: `${narrative.zh} 回退`, basisEn: `${narrative.en} fallback` };
  }
  return { score: clamp(inv.sv - 8 + hash01(`${sym}:${inv.id}`) * 10), basisZh: "全局回退", basisEn: "Global fallback" };
}

export function getTickerSmartVoice(ticker: string): SvTickerBoard {
  const narrative = tickerNarrative(ticker);
  const investors = getSmartVoiceBoard().investors
    .map((inv) => {
      const ctx = investorTickerSv(inv, ticker);
      return { ...inv, contextualSv: ctx.score, basisZh: ctx.basisZh, basisEn: ctx.basisEn };
    })
    .sort((a, b) => b.contextualSv - a.contextualSv)
    .slice(0, 6);
  return { ticker: ticker.toUpperCase(), narrative, investors };
}

export function getTickerSmartVoicePool(ticker: string): SvTickerBoard {
  const narrative = tickerNarrative(ticker);
  const investors = getSmartVoiceBoard().investors
    .map((inv) => {
      const ctx = investorTickerSv(inv, ticker);
      return { ...inv, contextualSv: ctx.score, basisZh: ctx.basisZh, basisEn: ctx.basisEn };
    })
    .sort((a, b) => b.contextualSv - a.contextualSv);
  return { ticker: ticker.toUpperCase(), narrative, investors };
}

export function getCreatorSmartVoice(channelId: string, name?: string): SvInvestor {
  const direct = INVESTORS.find((i) => i.source === "youtube" && (i.id === channelId || i.id === `yt:${channelId}` || i.name === name));
  if (direct) return direct;
  const base = 94 + hash01(channelId) * 32;
  const sv = clamp(base);
  const displayName = name || "YouTube Creator";
  return {
    id: `yt:${channelId}`,
    source: "youtube",
    name: displayName,
    handle: channelId,
    url: `https://www.youtube.com/channel/${channelId}`,
    language: "en",
    sv,
    confidence: sv >= 116 ? "medium" : "low",
    nEff: Math.round(18 + hash01(`${channelId}:n`) * 46),
    settledCalls: Math.round(24 + hash01(`${channelId}:c`) * 74),
    activeDays: Math.round(12 + hash01(`${channelId}:d`) * 42),
    coveredTickers: Math.round(6 + hash01(`${channelId}:t`) * 18),
    topTickers: ["NVDA", "MU", "NFLX", "MSFT"],
    topNarratives: ["ai_infra", "semis", "software"],
    platformScores: { youtube: sv },
    horizonScores: {
      "1D": clamp(sv - 18 + hash01(`${channelId}:1D`) * 10),
      "5D": clamp(sv - 10 + hash01(`${channelId}:5D`) * 14),
      "20D": clamp(sv + hash01(`${channelId}:20D`) * 10),
      "60D": clamp(sv + 4 + hash01(`${channelId}:60D`) * 12),
    },
    narrativeScores: {
      ai_infra: clamp(sv + 6),
      semis: clamp(sv + 4),
      software: clamp(sv + 2),
    },
    tickerScores: {
      NVDA: clamp(sv + 8),
      MU: clamp(sv + 5),
      NFLX: clamp(sv - 2),
      MSFT: clamp(sv + 3),
    },
    rationaleZh: "Mock SV：根据该频道已收录视频构造的作者画像占位，等待真实 SV 管线替换。",
    rationaleEn: "Mock SV profile based on collected channel videos, pending the real SV pipeline.",
  };
}

export function getPortfolioSmartVoice(tickers: string[]) {
  const unique = [...new Set(tickers.map((t) => t.toUpperCase()).filter(Boolean))];
  const symbols = unique.length ? unique : ["NVDA", "MU", "AMD", "NFLX"];
  const investors = getSmartVoiceBoard().investors
    .map((inv) => {
      const parts = symbols.map((t) => investorTickerSv(inv, t).score);
      const score = clamp(parts.reduce((s, x) => s + x, 0) / parts.length);
      return { ...inv, portfolioSv: score };
    })
    .sort((a, b) => b.portfolioSv - a.portfolioSv)
    .slice(0, 5);
  return { tickers: symbols, investors };
}

export function confidenceRank(c: SvConfidence) {
  return c === "high" ? 4 : c === "medium" ? 3 : c === "low" ? 2 : 1;
}
