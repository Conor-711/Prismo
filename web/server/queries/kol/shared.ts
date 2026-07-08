import { all } from "@/lib/db";
import type { Bi, KolCandle, KolJudgment, KolSource, Stance, TweetMetrics, YtSeg } from "@/shared/market/mockDetail";

export function safe<T>(fn: () => T, fb: T): T {
  try {
    return fn();
  } catch {
    return fb;
  }
}

export const dayOf = (ts: string) => (ts || "").slice(0, 10);

// 去 HTML 标签 + 解码常见实体（雪球 gr_post.body 是富文本，含 <p>/<b>/<a>/<img>，直接展示会露出标签）。
export function stripHtml(s: string): string {
  return (s || "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&")
    .replace(/\n{3,}/g, "\n\n").replace(/[ \t]+\n/g, "\n").trim();
}

// 「无明确观点」识别：新闻转述 / 被 mentions 过度匹配到的标的（同一帖映射到多只标的，
// 多数标的下其实没观点）。提炼后这类 reason 形如「未给出明确理由」「仅转述…新闻」"no clear thesis"。
// 保守匹配（宁可漏判、不可误杀真观点；「仅」必须接转述类动词，避免误伤「仅在$50以下买入」这类真立场）。
const NO_THESIS_RE =
  /未给出明确|未给出个人|未给出.{0,4}(立场|观点|理由)|未表达|未提供.{0,4}(立场|观点)|未在原文|未发表|未明确表态|没有明确(观点|立场)|仅(转发|转述|转载|分享|引用|提及|提到|列入)|no clear (thesis|stance|view|opinion|position)|no (personal )?(opinion|stance|view|thesis)( (given|expressed|provided))?|merely (shar|mention|relay|list)|just (shar|relay|mention)|only (shar|relay|mention)/i;
export function isNoThesis(reason?: Bi): boolean {
  if (!reason) return false;
  return NO_THESIS_RE.test(`${reason.zh || ""} ${reason.en || ""}`);
}

export function stanceOf(s?: string | null, senti?: number | null): Stance {
  const x = (s || "").toLowerCase();
  if (x.startsWith("bull")) return "bull";
  if (x.startsWith("bear")) return "bear";
  if (typeof senti === "number") {
    if (senti > 0.15) return "bull";
    if (senti < -0.15) return "bear";
  }
  return "neutral";
}

// 近 ~11 个交易日价格（price_daily 通常 ~19 行，取最后 11）
export function priceDays(symbol: string): KolCandle[] {
  const rows = safe(
    () =>
      all<{ day: string; open: number; high: number; low: number; close: number }>(
        `SELECT day, open, high, low, close FROM price_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ),
    []
  );
  return rows.slice(-11);
}

// 现价（散点基准线 + 目标价剔噪锚点）：price_daily 最新收盘优先，缺则 gr_quote。
export function currentPrice(symbol: string): number | null {
  const d = priceDays(symbol);
  const last = d.length ? d[d.length - 1].close : 0;
  if (last > 0) return last;
  const gr = safe(() => all<{ price: number }>(`SELECT price FROM gr_quote WHERE ticker = ?`, symbol), []);
  return gr.length && gr[0].price > 0 ? gr[0].price : null;
}

// 价格短语 → 数字（区间取中点；含 % 的相对幅度 → undefined）。供 YouTube yt_judgment.target 字符串解析。
export function parseRange(s?: string | null): [number, number] | null {
  if (!s) return null;
  const t = String(s).toLowerCase();
  if (t.includes("%")) return null; // 相对幅度不是价位
  const cleaned = t.replace(/,/g, "").replace(/\$/g, "").replace(/usd|美元|美金/g, "");
  const nums = (cleaned.match(/\d+(?:\.\d+)?/g) || []).map(Number).filter((n) => n > 0 && n < 1e7);
  if (!nums.length) return null;
  if (nums.length >= 2 && /[-–—~]|到|至|\bto\b/.test(cleaned)) return [Math.min(nums[0], nums[1]), Math.max(nums[0], nums[1])];
  return [nums[0], nums[0]];
}

// 周期文本 → 归一档（仅 YouTube 用：yt_judgment 无 bucket；kol_judgment 的 bucket 由 LLM 给）。
export function bucketHorizon(text: string): "short" | "mid" | "long" | undefined {
  const t = (text || "").toLowerCase();
  if (!t.trim()) return undefined;
  if (/长期|长线|数年|两到三年|多年|\d+\s*年|year|202[7-9]|2030|12-18|18-24|long[- ]?term/.test(t)) return "long";
  if (/日内|几天|数天|几周|数周|swing|波段|反弹|短期|短线|day trade|this week|next week|\bdays?\b|\bweeks?\b|short[- ]?term/.test(t)) return "short";
  if (/个月|月底|季度|quarter|months?\b|到年底|半年|下半年/.test(t)) return "mid";
  return undefined;
}

// 任意日期 snap 到窗口内最近的交易日（同日优先，否则最近的更早交易日；早于窗口则丢弃）
export function snapToTradingDay(day: string, tradingDays: string[]): string | null {
  if (!tradingDays.length || day < tradingDays[0]) return null;
  let best = tradingDays[0];
  for (const d of tradingDays) {
    if (d <= day) best = d;
    else break;
  }
  return best;
}

export interface RawOp {
  id: string;
  day: string;
  source: KolSource;
  author: string;
  interactions: number;
  stance: Stance;
  zh: string; // 原文/标题（兜底）
  en: string;
  url: string;
  avatarKey: string; // 头像 join key：reddit=author_id / youtube=channel_id / 其余=""
  refKey: string; // kol_refined join key（源生 id：reddit=post id / xueqiu/Toss/YahooJP=gr_post id / x=tweet_id）
  orig?: string; // 原帖原文（native 语言、未翻译；reddit=英文标题 / x=推文 / 雪球/Toss/YahooJP=原文；youtube 无原文）
  reason?: Bi; // YouTube 直接取自 yt_analysis；reddit/x/xueqiu/toss/yahoojp 在 getKolFlowReal 里补
  points?: { zh: string[]; en: string[] };
  metrics?: TweetMetrics; // X 逐项互动数（赞/转/评/引/看/藏）
  ytSegments?: YtSeg[]; // YouTube 完整口播段落（yt_fulltext.segments；多人带说话人）
  relevance?: number; // 没有 kol_relevance 时的源侧兜底相关度（SV X call）
  quality?: number; // 没有 kol_quality 时的源侧兜底质量分（SV X call）
  judgment?: KolJudgment; // 源侧直接结构化出的目标价/周期（SV X call）
}

function cleanAuthorKey(author: string): string {
  return String(author || "")
    .trim()
    .replace(/^@/, "")
    .replace(/^u\//, "")
    .replace(/\s+/g, " ");
}

export function authorRefIdFor(source: KolSource, author: string, avatarKey: string): string {
  const key = (avatarKey || cleanAuthorKey(author)).trim();
  return `${source}:${key || "unknown"}`;
}

// kol_refined（pipeline kol-refine 产出）：source:item_id -> 提炼结果。
export interface Refined {
  stance: Stance;
  reason: Bi;
  points: { zh: string[]; en: string[] };
  quote: Bi; // 本人原话（忠实翻译，建立可信度）
  trans: Bi; // 原帖完整忠实翻译（逐句、不压缩；「译」选项首选）
}

export function svDirectionToStance(direction?: string | null): Stance {
  const d = String(direction || "").toLowerCase();
  if (d === "bull") return "bull";
  if (d === "bear") return "bear";
  return "neutral";
}

export function svHorizon(bucket?: string | null): { horizon?: Bi; bucket?: KolJudgment["bucket"] } {
  const b = String(bucket || "").toUpperCase();
  if (!b || b === "UNKNOWN") return {};
  const days = Number((b.match(/\d+/) || [])[0]);
  const horizon = Number.isFinite(days) && days > 0
    ? { zh: `${days} 天`, en: `${days}D` }
    : { zh: b, en: b };
  const outBucket: KolJudgment["bucket"] =
    days <= 5 ? "short" : days <= 20 ? "mid" : "long";
  return { horizon, bucket: outBucket };
}

export function svFallbackRelevance(heuristic: number, conviction: number, specificity: number): number {
  const h = Math.max(0, Math.min(1, (heuristic - 46) / 12));
  return Math.round(Math.max(62, Math.min(96, 62 + h * 18 + conviction * 10 + specificity * 6)));
}

export function svFallbackQuality(conviction: number, evidence: number, specificity: number): number {
  return Math.round(Math.max(50, Math.min(95, 45 + evidence * 22 + specificity * 18 + conviction * 12)));
}
