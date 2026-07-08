import type { KolOpinion, KolSource } from "@/shared/market/mockDetail";
import type { SvSource, SvTickerBoard } from "@/features/smart-voice/svMock";
import { QUALITY_MIN_BY_SOURCE, STYLE_BUCKET, STYLE_LABEL } from "./opinionExplorerConstants";
import type {
  LensKey,
  PersonalPrefs,
  RecommendationMeta,
  RecommendationReason,
  SvOpinionMeta,
} from "./opinionExplorerTypes";

export const shiftDay = (day: string, delta: number): string => {
  if (!day) return "";
  const d = new Date(day + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
};

const KO_RE = /[가-힯]/;
const JA_RE = /[ぁ-ゟ゠-ヿ]/;
const HAN_RE = /[一-鿿]/;
const HANT_CHARS = "們這實國對學區與來為灣臺體萬沒關係點龍鳳麗東車馬鳥魚龜歲廣應該說話語讀書寫個麼樣讓會發開關閉問題經濟總統當網絡軟體資訊機構價值買賣漲跌觀認覺號";
const HANS_CHARS = "们这实国对学区与来为湾台体万没关系点龙凤丽东车马鸟鱼龟岁广应该说话语读书写个么样让会发开关闭问题经济总统当网络软件资讯机构价值买卖涨跌观认觉号";

export function langOf(o: KolOpinion): string {
  const t = o.orig || o.text?.en || o.text?.zh || "";
  if (KO_RE.test(t)) return "ko";
  if (JA_RE.test(t)) return "ja";
  if (HAN_RE.test(t)) {
    let hant = 0;
    let hans = 0;
    for (const ch of t) {
      if (HANT_CHARS.includes(ch)) hant++;
      else if (HANS_CHARS.includes(ch)) hans++;
    }
    return hant > hans ? "zh-Hant" : "zh-Hans";
  }
  return "en";
}

export const lensesOf = (o: KolOpinion): LensKey[] =>
  (o.viewpoints && o.viewpoints.length ? o.viewpoints : ["other"]) as LensKey[];

export const relOf = (o: KolOpinion): number => (typeof o.relevance === "number" ? o.relevance : -1);
export const qualOf = (o: KolOpinion): number => (typeof o.quality === "number" ? o.quality : -1);

export const hasSubstantiveText = (o: KolOpinion): boolean => {
  if (o.source === "youtube") return Boolean(o.ytSegments?.length || o.ytDigest);
  const body = (o.orig || o.text?.zh || o.text?.en || "").replace(/\s+/g, " ").trim();
  const reason = `${o.reason?.zh || ""} ${o.reason?.en || ""}`.trim();
  const points = (o.points?.zh?.length || 0) + (o.points?.en?.length || 0);
  return body.length >= 180 || reason.length >= 40 || points >= 2;
};

export const isHighQuality = (o: KolOpinion): boolean =>
  qualOf(o) >= QUALITY_MIN_BY_SOURCE[o.source] && relOf(o) >= 60 && hasSubstantiveText(o);

const svSourceFor = (source: KolSource): SvSource | null => {
  if (source === "x" || source === "youtube") return source;
  return null;
};

export const normalizeSvKey = (value?: string): string =>
  String(value || "")
    .trim()
    .toLowerCase()
    .replace(/^@/, "")
    .replace(/^u\//, "")
    .replace(/\s+/g, "");

export const normalizeAuthorKey = (value?: string): string =>
  String(value || "")
    .trim()
    .replace(/^@/, "")
    .replace(/^u\//, "")
    .replace(/\s+/g, " ");

export const opinionAuthorRefId = (o: KolOpinion): string =>
  o.authorRefId || `${o.source}:${normalizeAuthorKey(o.author) || "unknown"}`;

export const svKeysForInvestor = (inv: SvTickerBoard["investors"][number]): string[] => {
  const idTail = inv.id.replace(/^(x|yt|youtube):/i, "");
  return Array.from(new Set([inv.handle, inv.name, idTail].map(normalizeSvKey).filter(Boolean)));
};

export function getOpinionSvMeta(o: KolOpinion, byKey: Map<string, SvOpinionMeta>): SvOpinionMeta | null {
  const source = svSourceFor(o.source);
  if (!source) return null;
  return byKey.get(`${source}:${normalizeSvKey(o.author)}`) ?? null;
}

const cleanNumericText = (value: string) => value.replace(/[$,%\s,]/g, "");
const toNumber = (value: string): number | null => {
  const n = Number(cleanNumericText(value));
  return Number.isFinite(n) ? n : null;
};

const rangeOf = (loText: string, hiText: string): [number, number] | null => {
  const lo = toNumber(loText);
  const hi = toNumber(hiText);
  if (lo == null && hi == null) return null;
  const a = lo ?? hi!;
  const b = hi ?? lo!;
  return a <= b ? [a, b] : [b, a];
};

const midOf = (range: [number, number] | null): number | null =>
  range ? (range[0] + range[1]) / 2 : null;

const judgmentMid = (lo?: number, hi?: number): number | null => {
  if (lo == null && hi == null) return null;
  const a = lo ?? hi!;
  const b = hi ?? lo!;
  return (a + b) / 2;
};

const nearScore = (a: number | null, b: number | null): number => {
  if (a == null || b == null || b <= 0) return 0;
  const gap = Math.abs(a - b) / Math.max(1, Math.abs(b));
  if (gap <= 0.03) return 34;
  if (gap <= 0.08) return 24;
  if (gap <= 0.15) return 12;
  return 0;
};

export const isPersonalConfigured = (p: PersonalPrefs): boolean =>
  Boolean(p.direction || p.style || p.costLow || p.costHigh || p.positionLow || p.positionHigh || p.targetPrice || p.stopLoss);

const withReason = (reasons: RecommendationReason[], reason: RecommendationReason) => {
  if (!reasons.some((r) => r.zh === reason.zh)) reasons.push(reason);
};

export function personalRecommendation(
  o: KolOpinion,
  prefs: PersonalPrefs,
  currentPrice?: number | null
): RecommendationMeta {
  let score =
    Math.max(0, relOf(o)) * 0.35 +
    Math.max(0, qualOf(o)) * 0.28 +
    Math.log1p(Math.max(0, o.interactions || 0)) * 4;
  const reasons: RecommendationReason[] = [];
  if (!isPersonalConfigured(prefs)) return { score, reasons };

  const costRange = rangeOf(prefs.costLow, prefs.costHigh);
  const costMid = midOf(costRange);
  const positionRange = rangeOf(prefs.positionLow, prefs.positionHigh);
  const positionMid = midOf(positionRange);
  const target = toNumber(prefs.targetPrice);
  const stop = toNumber(prefs.stopLoss);
  const buyMid = judgmentMid(o.judgment?.buyLo, o.judgment?.buyHi);
  const sellMid = judgmentMid(o.judgment?.sellLo, o.judgment?.sellHi);
  const highPosition = positionMid != null && positionMid >= 20;
  const mediumPosition = positionMid != null && positionMid >= 10;
  const lenses = lensesOf(o);

  if (prefs.direction === "long") {
    if (o.stance === "bull") {
      score += 18;
      withReason(reasons, { zh: "与你的多头方向一致", en: "Aligned with your long position" });
    } else if (o.stance === "bear") {
      score += highPosition ? 26 : 8;
      withReason(reasons, highPosition
        ? { zh: "高仓位下优先看的反方风险", en: "Contrarian risk check for a large position" }
        : { zh: "补充反方风险校验", en: "Useful contrarian risk check" });
    } else {
      score += 8;
      withReason(reasons, { zh: "中性观点有助于校准仓位", en: "Neutral view helps calibrate sizing" });
    }
  } else if (prefs.direction === "short") {
    if (o.stance === "bear") {
      score += 18;
      withReason(reasons, { zh: "与你的空头方向一致", en: "Aligned with your short position" });
    } else if (o.stance === "bull") {
      score += highPosition ? 24 : 8;
      withReason(reasons, highPosition
        ? { zh: "高仓位下优先看的反向挤压风险", en: "Squeeze-risk check for a large short" }
        : { zh: "补充多头反方观点", en: "Useful bullish counter-view" });
    } else {
      score += 8;
      withReason(reasons, { zh: "中性观点有助于控制风险", en: "Neutral view helps control risk" });
    }
  } else if (prefs.direction === "watch") {
    if (o.stance === "neutral") score += 10;
    score += Math.max(0, qualOf(o)) >= 80 ? 10 : 0;
    withReason(reasons, { zh: "适合观望状态下建立判断", en: "Useful while building a watchlist view" });
  }

  if (prefs.style) {
    const want = STYLE_BUCKET[prefs.style];
    if (o.judgment?.bucket === want) {
      score += 22;
      withReason(reasons, {
        zh: `周期匹配你的${STYLE_LABEL[prefs.style].zh}风格`,
        en: `Horizon matches your ${STYLE_LABEL[prefs.style].en} style`,
      });
    } else if (prefs.style === "dca" && (lenses.includes("valuation") || lenses.includes("growth") || lenses.includes("management"))) {
      score += 12;
      withReason(reasons, { zh: "更适合定投复盘的基本面视角", en: "Fundamental lens fits DCA review" });
    }
  }

  const targetMatch = nearScore(sellMid, target);
  if (targetMatch > 0) {
    score += targetMatch;
    withReason(reasons, { zh: "目标价接近你的目标区", en: "Target price is close to your target zone" });
  }
  const stopMatch = nearScore(sellMid, stop) || nearScore(buyMid, stop);
  if (stopMatch > 0) {
    score += stopMatch * 0.8;
    withReason(reasons, { zh: "价位接近你的止损/风险线", en: "Price level is near your risk line" });
  }

  if (costRange) {
    if (buyMid != null && buyMid >= costRange[0] * 0.94 && buyMid <= costRange[1] * 1.06) {
      score += 18;
      withReason(reasons, { zh: "买入区间接近你的成本区", en: "Buy zone is close to your cost basis" });
    }
    if (costMid != null && sellMid != null) {
      if (prefs.direction === "long" && o.stance === "bull" && sellMid >= costMid * 1.08) {
        score += 10;
        withReason(reasons, { zh: "上行目标覆盖你的成本区", en: "Upside target clears your cost basis" });
      }
      if (prefs.direction === "long" && o.stance === "bear" && sellMid <= costMid * 0.96) {
        score += 18;
        withReason(reasons, { zh: "下行目标低于你的成本区，适合风险校验", en: "Downside target is below your cost basis" });
      }
    }
  }

  if (costMid != null && currentPrice != null && currentPrice > 0) {
    if (prefs.direction === "long" && currentPrice >= costMid * 1.15 && (o.stance !== "bull" || sellMid != null)) {
      score += 14;
      withReason(reasons, { zh: "盈利仓位下适合检查止盈与回撤", en: "Useful for take-profit and drawdown checks" });
    } else if (prefs.direction === "long" && currentPrice <= costMid * 0.9) {
      score += o.stance === "bear" ? 14 : 10;
      withReason(reasons, o.stance === "bear"
        ? { zh: "亏损仓位下优先看的风险观点", en: "Risk view for an underwater position" }
        : { zh: "亏损仓位下的修复逻辑", en: "Recovery thesis for an underwater position" });
    }
  }

  if ((highPosition || mediumPosition) && qualOf(o) >= 80) {
    score += highPosition ? 12 : 7;
    withReason(reasons, highPosition
      ? { zh: "高仓位优先高质量观点", en: "High-quality view prioritized for large sizing" }
      : { zh: "仓位不低，优先高质量观点", en: "Quality prioritized for meaningful sizing" });
  }

  return { score, reasons: reasons.slice(0, 3) };
}
