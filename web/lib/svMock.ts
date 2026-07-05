import generatedSmartVoice from "./data/smartVoice.json";

export type SvSource = "x" | "youtube";
export type SvHorizon = "1D" | "5D" | "20D" | "60D";
export type SvConfidence = "observing" | "low" | "medium" | "high";

export interface SvInvestor {
  id: string;
  source: SvSource;
  name: string;
  handle: string;
  avatar?: string;
  url?: string;
  language: "zh" | "en" | "ko" | "ja";
  sv: number;
  confidence: SvConfidence;
  nEff: number;
  settledCalls: number;
  activeDays: number;
  coveredTickers: number;
  topTickers: string[];
  topNarratives: string[];
  platformScores: Partial<Record<SvSource, number>>;
  horizonScores: Record<SvHorizon, number | null>;
  narrativeScores: Record<string, number>;
  tickerScores: Record<string, number>;
  rationaleZh: string;
  rationaleEn: string;
}

export interface SvBoard {
  investors: SvInvestor[];
  x: SvInvestor[];
  youtube: SvInvestor[];
  currentNarratives: { key: string; zh: string; en: string; weight: number }[];
  updatedAt: string;
}

export interface SvTickerBoard {
  ticker: string;
  narrative: { key: string; zh: string; en: string };
  investors: (SvInvestor & { contextualSv: number; basisZh: string; basisEn: string })[];
}

export const SV_HORIZONS: SvHorizon[] = ["1D", "5D", "20D", "60D"];

const FALLBACK_NARRATIVES = [
  { key: "semis", zh: "半导体", en: "Semiconductors", weight: 34 },
  { key: "ai_infra", zh: "AI 基础设施", en: "AI infrastructure", weight: 24 },
  { key: "software", zh: "软件与云", en: "Software & cloud", weight: 16 },
  { key: "crypto", zh: "加密相关", en: "Crypto-linked", weight: 10 },
];

export const NARRATIVE_LABELS: Record<string, { zh: string; en: string }> = {
  semis: { zh: "半导体", en: "Semiconductors" },
  ai_infra: { zh: "AI 基础设施", en: "AI infrastructure" },
  software: { zh: "软件与云", en: "Software & cloud" },
  media: { zh: "媒体娱乐", en: "Media & entertainment" },
  ev: { zh: "电动车", en: "EV" },
  crypto: { zh: "加密相关", en: "Crypto-linked" },
  consumer: { zh: "消费与零售", en: "Consumer" },
  fintech: { zh: "金融科技", en: "Fintech" },
};

const TICKER_NARRATIVE: Record<string, string> = {
  NVDA: "semis",
  MU: "semis",
  AMD: "semis",
  INTC: "semis",
  AVGO: "semis",
  AMAT: "semis",
  TSM: "semis",
  PLTR: "ai_infra",
  SMCI: "ai_infra",
  DELL: "ai_infra",
  MSFT: "software",
  CRM: "software",
  NOW: "software",
  NFLX: "media",
  DIS: "media",
  TSLA: "ev",
  RIVN: "ev",
  COIN: "crypto",
  MSTR: "crypto",
  SQ: "fintech",
  HOOD: "fintech",
  AMZN: "consumer",
  BABA: "consumer",
};

function sourceUrl(source: SvSource, handle: string, id: string) {
  if (source === "x") return `https://x.com/${handle.replace(/^@/, "")}`;
  return `https://www.youtube.com/channel/${id}`;
}

const INVESTORS: SvInvestor[] = [
  {
    id: "x:sixsigma",
    source: "x",
    name: "@SixSigmaCapital",
    handle: "SixSigmaCapital",
    language: "en",
    sv: 128,
    confidence: "high",
    nEff: 118,
    settledCalls: 164,
    activeDays: 73,
    coveredTickers: 34,
    topTickers: ["MU", "NVDA", "INTC", "AVGO"],
    topNarratives: ["semis", "ai_infra"],
    platformScores: { x: 130 },
    horizonScores: { "1D": 113, "5D": 134, "20D": 126, "60D": 111 },
    narrativeScores: { semis: 141, ai_infra: 132, software: 108 },
    tickerScores: { MU: 146, NVDA: 133, INTC: 128, AVGO: 121, PLTR: 118 },
    rationaleZh: "半导体短线与波段 call 持续跑赢同标的基准，样本覆盖较宽。",
    rationaleEn: "Consistently beats ticker baselines on semiconductor short-term and swing calls with broad coverage.",
  },
  {
    id: "x:chanos",
    source: "x",
    name: "@RealJimChanos",
    handle: "RealJimChanos",
    language: "en",
    sv: 123,
    confidence: "high",
    nEff: 96,
    settledCalls: 142,
    activeDays: 61,
    coveredTickers: 22,
    topTickers: ["TSLA", "COIN", "RIVN", "NFLX"],
    topNarratives: ["ev", "crypto", "media"],
    platformScores: { x: 124 },
    horizonScores: { "1D": 106, "5D": 118, "20D": 130, "60D": 126 },
    narrativeScores: { ev: 136, crypto: 128, media: 119, consumer: 103 },
    tickerScores: { TSLA: 139, COIN: 129, RIVN: 126, NFLX: 116 },
    rationaleZh: "空头与反共识观点兑现率高，尤其在高估值与事件驱动标的上稳定。",
    rationaleEn: "Bearish and contrarian calls score well, especially on high-valuation and event-driven names.",
  },
  {
    id: "yt:rule1",
    source: "youtube",
    name: "Rule #1 Investing",
    handle: "@rule1investing",
    language: "en",
    sv: 121,
    confidence: "medium",
    nEff: 58,
    settledCalls: 83,
    activeDays: 44,
    coveredTickers: 18,
    topTickers: ["NFLX", "AMZN", "BABA", "DIS"],
    topNarratives: ["consumer", "media"],
    platformScores: { youtube: 122 },
    horizonScores: { "1D": 98, "5D": 106, "20D": 124, "60D": 132 },
    narrativeScores: { media: 134, consumer: 126, software: 112 },
    tickerScores: { NFLX: 138, AMZN: 124, BABA: 119, DIS: 116 },
    rationaleZh: "中期价值修复类观点更强，目标价与估值框架较完整。",
    rationaleEn: "Stronger on medium-term value-reversion calls with explicit targets and valuation frameworks.",
  },
  {
    id: "x:bluth",
    source: "x",
    name: "@BluthCapital",
    handle: "BluthCapital",
    language: "en",
    sv: 119,
    confidence: "high",
    nEff: 88,
    settledCalls: 126,
    activeDays: 69,
    coveredTickers: 29,
    topTickers: ["MU", "PLTR", "CRM", "COIN"],
    topNarratives: ["semis", "software", "crypto"],
    platformScores: { x: 120 },
    horizonScores: { "1D": 111, "5D": 121, "20D": 122, "60D": 104 },
    narrativeScores: { semis: 125, software: 122, crypto: 117 },
    tickerScores: { MU: 128, PLTR: 124, CRM: 121, COIN: 116 },
    rationaleZh: "覆盖面广，短期和短中期表现均衡，适合做跨赛道参考。",
    rationaleEn: "Broad coverage with balanced short-term and swing performance across multiple narratives.",
  },
  {
    id: "yt:patient",
    source: "youtube",
    name: "The Patient Investor",
    handle: "@patientinvestor",
    language: "en",
    sv: 116,
    confidence: "medium",
    nEff: 47,
    settledCalls: 68,
    activeDays: 38,
    coveredTickers: 15,
    topTickers: ["NVDA", "MSFT", "NFLX", "AMZN"],
    topNarratives: ["ai_infra", "software", "media"],
    platformScores: { youtube: 117 },
    horizonScores: { "1D": 92, "5D": 101, "20D": 119, "60D": 128 },
    narrativeScores: { ai_infra: 124, software: 120, media: 116 },
    tickerScores: { NVDA: 125, MSFT: 119, NFLX: 112, AMZN: 111 },
    rationaleZh: "长视频中的中期 thesis 更有参考性，短线跟单价值较弱。",
    rationaleEn: "Medium-term theses from long-form videos are more useful than short-term timing.",
  },
  {
    id: "x:limitless",
    source: "x",
    name: "@Limitlesss1",
    handle: "Limitlesss1",
    language: "en",
    sv: 114,
    confidence: "medium",
    nEff: 62,
    settledCalls: 91,
    activeDays: 55,
    coveredTickers: 26,
    topTickers: ["NVDA", "AMD", "PLTR", "SMCI"],
    topNarratives: ["ai_infra", "semis"],
    platformScores: { x: 115 },
    horizonScores: { "1D": 117, "5D": 119, "20D": 110, "60D": 97 },
    narrativeScores: { ai_infra: 124, semis: 118, software: 104 },
    tickerScores: { NVDA: 122, AMD: 118, PLTR: 120, SMCI: 116 },
    rationaleZh: "AI 硬件与高 beta 科技股短线节奏较好，但中期样本仍不足。",
    rationaleEn: "Good short-term timing on AI hardware and high-beta tech, with thinner medium-term evidence.",
  },
  {
    id: "yt:futurum",
    source: "youtube",
    name: "Futurum Equities",
    handle: "@futurumequities",
    language: "en",
    sv: 112,
    confidence: "medium",
    nEff: 41,
    settledCalls: 59,
    activeDays: 35,
    coveredTickers: 14,
    topTickers: ["CRM", "NOW", "MSFT", "PLTR"],
    topNarratives: ["software", "ai_infra"],
    platformScores: { youtube: 113 },
    horizonScores: { "1D": 91, "5D": 99, "20D": 118, "60D": 120 },
    narrativeScores: { software: 127, ai_infra: 116, semis: 101 },
    tickerScores: { CRM: 128, NOW: 124, MSFT: 116, PLTR: 110 },
    rationaleZh: "软件和 AI 应用层中期观点更强，短线不是主要优势。",
    rationaleEn: "Stronger on medium-term software and AI application calls than short-term timing.",
  },
  {
    id: "x:coles",
    source: "x",
    name: "@ColesTrades",
    handle: "ColesTrades",
    language: "en",
    sv: 109,
    confidence: "medium",
    nEff: 50,
    settledCalls: 86,
    activeDays: 48,
    coveredTickers: 17,
    topTickers: ["HOOD", "SQ", "COIN", "MSTR"],
    topNarratives: ["fintech", "crypto"],
    platformScores: { x: 110 },
    horizonScores: { "1D": 116, "5D": 113, "20D": 104, "60D": 93 },
    narrativeScores: { fintech: 121, crypto: 117, software: 96 },
    tickerScores: { HOOD: 123, SQ: 115, COIN: 112, MSTR: 110 },
    rationaleZh: "金融科技和加密相关标的短线 call 较强，但长周期可信度较低。",
    rationaleEn: "Short-term calls on fintech and crypto-linked names are stronger than longer horizons.",
  },
  {
    id: "yt:schwab",
    source: "youtube",
    name: "Schwab Network",
    handle: "@schwabnetwork",
    language: "en",
    sv: 104,
    confidence: "medium",
    nEff: 64,
    settledCalls: 105,
    activeDays: 52,
    coveredTickers: 31,
    topTickers: ["AAPL", "MSFT", "AMZN", "TSLA"],
    topNarratives: ["software", "consumer", "ev"],
    platformScores: { youtube: 105 },
    horizonScores: { "1D": 101, "5D": 103, "20D": 106, "60D": 107 },
    narrativeScores: { software: 109, consumer: 105, ev: 99 },
    tickerScores: { AAPL: 108, MSFT: 109, AMZN: 105, TSLA: 98 },
    rationaleZh: "覆盖面广但观点偏市场平均，适合作为背景声音。",
    rationaleEn: "Broad coverage but close to market median, useful as background context.",
  },
  {
    id: "x:memewhale",
    source: "x",
    name: "@unusual_whales",
    handle: "unusual_whales",
    language: "en",
    sv: 98,
    confidence: "high",
    nEff: 142,
    settledCalls: 238,
    activeDays: 82,
    coveredTickers: 39,
    topTickers: ["GME", "AMC", "TSLA", "COIN"],
    topNarratives: ["crypto", "ev"],
    platformScores: { x: 99 },
    horizonScores: { "1D": 101, "5D": 97, "20D": 96, "60D": 94 },
    narrativeScores: { crypto: 103, ev: 96, semis: 92 },
    tickerScores: { GME: 106, AMC: 104, TSLA: 94, COIN: 101 },
    rationaleZh: "高覆盖高互动，但方向性准确度接近或低于 Prismo 中位数。",
    rationaleEn: "High reach and broad coverage, but directional accuracy is near or below the Prismo median.",
  },
];

for (const investor of INVESTORS) {
  investor.url = sourceUrl(investor.source, investor.handle, investor.id.replace(/^yt:/, ""));
  if (investor.source === "x") investor.avatar = `https://unavatar.io/twitter/${investor.handle}`;
}

function normalizeLanguage(value: unknown): SvInvestor["language"] {
  return value === "zh" || value === "ko" || value === "ja" ? value : "en";
}

function normalizeConfidence(value: unknown): SvConfidence {
  return value === "high" || value === "medium" || value === "low" ? value : "observing";
}

function normalizeHorizonScores(value: unknown): Record<SvHorizon, number | null> {
  const raw = (value && typeof value === "object" ? value : {}) as Partial<Record<SvHorizon, unknown>>;
  return {
    "1D": typeof raw["1D"] === "number" ? raw["1D"] : null,
    "5D": typeof raw["5D"] === "number" ? raw["5D"] : null,
    "20D": typeof raw["20D"] === "number" ? raw["20D"] : null,
    "60D": typeof raw["60D"] === "number" ? raw["60D"] : null,
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
  const source: SvSource = raw.source === "youtube" ? "youtube" : "x";
  const handle = String(raw.handle || raw.name || raw.id);
  return {
    id: String(raw.id),
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
    rationaleZh: String(raw.rationaleZh || "真实 SV v0：根据已结构化 call 的历史结算结果生成。"),
    rationaleEn: String(raw.rationaleEn || "Real SV v0 generated from settled structured calls."),
  };
}

function getGeneratedSmartVoiceBoard(): SvBoard | null {
  const raw = generatedSmartVoice as unknown as Partial<SvBoard>;
  const investors = Array.isArray(raw.investors) ? raw.investors.map(normalizeRealInvestor).filter((i): i is SvInvestor => Boolean(i)) : [];
  if (!investors.length) return null;
  const sorted = investors.sort((a, b) => b.sv - a.sv);
  return {
    investors: sorted,
    x: sorted.filter((i) => i.source === "x"),
    youtube: sorted.filter((i) => i.source === "youtube"),
    currentNarratives: Array.isArray(raw.currentNarratives) && raw.currentNarratives.length ? raw.currentNarratives : FALLBACK_NARRATIVES,
    updatedAt: raw.updatedAt || new Date().toISOString().slice(0, 10),
  };
}

export function getSmartVoiceBoard(): SvBoard {
  const generated = getGeneratedSmartVoiceBoard();
  if (generated) return generated;
  const investors = [...INVESTORS].sort((a, b) => b.sv - a.sv);
  return {
    investors,
    x: investors.filter((i) => i.source === "x"),
    youtube: investors.filter((i) => i.source === "youtube"),
    currentNarratives: FALLBACK_NARRATIVES,
    updatedAt: "2026-07-03",
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
