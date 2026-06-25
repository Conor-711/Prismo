// 第 1 块「个体观点 · KOL」的**真实数据**取数层（替换 mock）。
//   - 价格：price_daily（pipeline/ingest/price_daily.py，Yahoo 日 OHLC）。
//   - 观点：Reddit（posts+mentions+item_analysis）+ YouTube（yt_video+yt_analysis）+ 雪球（gr_post source=xueqiu）。
//   - X/Twitter 暂缺（tw_* 仅在云端、未拉进 dev.db）。
// 数据不足（无价格历史/无观点）时返回 null → 详情页回退 getKolFlow(mock)，保证不空。
import { all, parseJSON } from "./db";
import type { KolFlow, KolOpinion, KolCandle, KolSource, Stance, Bi } from "./mockDetail";

function safe<T>(fn: () => T, fb: T): T {
  try {
    return fn();
  } catch {
    return fb;
  }
}

const dayOf = (ts: string) => (ts || "").slice(0, 10);

// 去 HTML 标签 + 解码常见实体（雪球 gr_post.body 是富文本，含 <p>/<b>/<a>/<img>，直接展示会露出标签）。
function stripHtml(s: string): string {
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
function isNoThesis(reason?: Bi): boolean {
  if (!reason) return false;
  return NO_THESIS_RE.test(`${reason.zh || ""} ${reason.en || ""}`);
}

function stanceOf(s?: string | null, senti?: number | null): Stance {
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
function priceDays(symbol: string): KolCandle[] {
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

// 任意日期 snap 到窗口内最近的交易日（同日优先，否则最近的更早交易日；早于窗口则丢弃）
function snapToTradingDay(day: string, tradingDays: string[]): string | null {
  if (!tradingDays.length || day < tradingDays[0]) return null;
  let best = tradingDays[0];
  for (const d of tradingDays) {
    if (d <= day) best = d;
    else break;
  }
  return best;
}

interface RawOp {
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
  refKey: string; // kol_refined join key（源生 id：reddit=post id / xueqiu=gr_post id / x=tweet_id）
  orig?: string; // 原帖原文（native 语言、未翻译；reddit=英文标题 / x=推文 / 雪球=中文；youtube 无原文）
  reason?: Bi; // YouTube 直接取自 yt_analysis；reddit/x/xueqiu 在 getKolFlowReal 里补
  points?: { zh: string[]; en: string[] };
}

// kol_refined（pipeline kol-refine 产出）：source:item_id -> 提炼结果。
interface Refined {
  stance: Stance;
  reason: Bi;
  points: { zh: string[]; en: string[] };
  quote: Bi; // 本人原话（忠实翻译，建立可信度）
  trans: Bi; // 原帖完整忠实翻译（逐句、不压缩；「译」选项首选）
}
function refinedMap(symbol: string): Map<string, Refined> {
  const rows = safe(
    () =>
      all<any>(
        `SELECT source, item_id, stance, reason_zh, reason_en, points_zh, points_en, quote_zh, quote_en,
                COALESCE(trans_zh,'') AS trans_zh, COALESCE(trans_en,'') AS trans_en
           FROM kol_refined WHERE ticker = ?`,
        symbol
      ),
    []
  );
  const m = new Map<string, Refined>();
  for (const r of rows) {
    m.set(`${r.source}:${r.item_id}`, {
      stance: stanceOf(r.stance, 0),
      reason: { zh: r.reason_zh || r.reason_en || "", en: r.reason_en || r.reason_zh || "" },
      points: { zh: parseJSON<string[]>(r.points_zh, []), en: parseJSON<string[]>(r.points_en, []) },
      quote: { zh: r.quote_zh || "", en: r.quote_en || "" },
      trans: { zh: r.trans_zh || "", en: r.trans_en || "" },
    });
  }
  return m;
}

// kol_viewpoint（pipeline kol-viewpoint 产出）：source:item_id -> 有序视角键数组（首个为主视角）。
function viewpointMap(symbol: string): Map<string, string[]> {
  const rows = safe(
    () => all<any>(`SELECT source, item_id, viewpoints FROM kol_viewpoint WHERE ticker = ?`, symbol),
    []
  );
  const m = new Map<string, string[]>();
  for (const r of rows) {
    const vps = parseJSON<string[]>(r.viewpoints, []);
    if (Array.isArray(vps) && vps.length) m.set(`${r.source}:${r.item_id}`, vps);
  }
  return m;
}

// author_avatar（pipeline/ingest/author_avatars.py 爬取）→ "source:handle" -> url
function avatarMap(): Map<string, string> {
  const rows = safe(
    () => all<{ source: string; handle: string; url: string }>(
      `SELECT source, handle, url FROM author_avatar WHERE url IS NOT NULL AND url <> ''`
    ),
    []
  );
  const m = new Map<string, string>();
  for (const r of rows) m.set(`${r.source}:${r.handle}`, r.url);
  return m;
}

function redditOps(symbol: string, since: string, limit = 40): RawOp[] {
  const rows = safe(
    () =>
      all<any>(
        `SELECT p.id AS id, p.author_id AS author, p.title AS title, p.title_zh AS title_zh,
                p.permalink AS url, COALESCE(p.score,0) AS score, COALESCE(p.num_comments,0) AS comments,
                p.created_utc AS created, a.stance AS stance, COALESCE(a.sentiment_score,0) AS senti
           FROM mentions m
           JOIN posts p ON p.id = m.item_id AND m.item_type = 'post'
           LEFT JOIN item_analysis a ON a.item_id = p.id AND a.item_type = 'post'
          WHERE m.ticker = ? AND p.created_utc >= ?
          ORDER BY (p.score + p.num_comments) DESC
          LIMIT ${limit | 0}`,
        symbol,
        since
      ),
    []
  );
  return rows.map((r) => ({
    id: "rd-" + r.id,
    day: dayOf(r.created),
    source: "reddit" as KolSource,
    author: r.author && r.author !== "[deleted]" ? "u/" + r.author : "u/—",
    interactions: (r.score || 0) + (r.comments || 0),
    stance: stanceOf(r.stance, r.senti),
    zh: r.title_zh || r.title || "",
    en: r.title || "",
    url: r.url || "#",
    avatarKey: r.author || "", // reddit 头像按 author_id join
    refKey: r.id, // kol_refined: reddit:<post id>
    orig: r.title || "", // 原文 = 英文标题（title_zh 是译文，不算原文）
  }));
}

function youtubeOps(symbol: string, since: string, limit = 20): RawOp[] {
  const rows = safe(
    () =>
      all<any>(
        `SELECT v.id AS id, v.channel AS author, v.channel_id AS channel_id, v.title AS title,
                COALESCE(v.like_count,0) AS likes, COALESCE(v.comment_count,0) AS comments,
                v.url AS url, v.published_utc AS created,
                a.stance AS stance, COALESCE(a.sentiment,0) AS senti,
                COALESCE(a.summary_zh,'') AS sum_zh, COALESCE(a.summary_en,'') AS sum_en,
                a.key_points_zh AS kp_zh, a.key_points_en AS kp_en
           FROM yt_video v
           LEFT JOIN yt_analysis a ON a.video_id = v.id
          WHERE v.ticker = ? AND v.published_utc >= ?
          ORDER BY (COALESCE(v.like_count,0) + COALESCE(v.comment_count,0)) DESC
          LIMIT ${limit | 0}`,
        symbol,
        since
      ),
    []
  );
  return rows.map((r) => {
    // YouTube 复用 Gemini 产出的 yt_analysis：summary→reason、key_points→points（无需 kol_refined）
    const reason: Bi | undefined =
      r.sum_zh || r.sum_en ? { zh: r.sum_zh || r.sum_en, en: r.sum_en || r.sum_zh } : undefined;
    return {
      id: "yt-" + r.id,
      day: dayOf(r.created),
      source: "youtube" as KolSource,
      author: r.author || "YouTube",
      interactions: (r.likes || 0) + (r.comments || 0),
      stance: stanceOf(r.stance, r.senti),
      zh: r.sum_zh || r.title || "",
      en: r.sum_en || r.title || "",
      url: r.url || "#",
      avatarKey: r.channel_id || "", // youtube 头像按 channel_id join
      refKey: r.id,
      reason,
      points: { zh: parseJSON<string[]>(r.kp_zh, []), en: parseJSON<string[]>(r.kp_en, []) },
    };
  });
}

function xueqiuOps(symbol: string, since: string, limit = 40): RawOp[] {
  const rows = safe(
    () =>
      all<any>(
        `SELECT id, author, title, body, url, COALESCE(likes,0) AS likes,
                COALESCE(comments,0) AS comments, COALESCE(sentiment,0) AS senti, stance, created_utc AS created
           FROM gr_post
          WHERE source = 'xueqiu' AND ticker = ? AND created_utc >= ?
          ORDER BY (likes + comments) DESC, created_utc DESC
          LIMIT ${limit | 0}`,
        symbol,
        since
      ),
    []
  );
  return rows.map((r) => {
    const title = stripHtml(String(r.title || ""));
    const body = stripHtml(String(r.body || "")); // 去掉雪球富文本的 HTML 标签
    const full = [title, body].filter(Boolean).join("\n"); // 完整原文（标题+正文，已清洗）
    const short = title || body.slice(0, 280); // 短文本（图表气泡/兜底用）
    return {
      id: "xq-" + r.id,
      day: dayOf(r.created),
      source: "xueqiu" as KolSource,
      author: r.author || "雪球",
      interactions: (r.likes || 0) + (r.comments || 0),
      stance: stanceOf(r.stance, r.senti),
      zh: short,
      en: short,
      url: r.url || "#",
      avatarKey: "", // 雪球（WAF）暂不爬头像 → 兜底
      refKey: String(r.id), // kol_refined: xueqiu:<gr_post id>
      orig: full || short, // 原文 = 完整中文标题+正文（去 HTML）
    };
  });
}

// X / Twitter（云端 tw_* 拉进本地 x_opinion；pipeline/ingest/x_pull.py）。无情绪标注 → 中性。
function xOps(symbol: string, since: string, limit = 40): RawOp[] {
  const rows = safe(
    () =>
      all<any>(
        `SELECT tweet_id, handle, text, COALESCE(likes,0) AS likes, COALESCE(retweets,0) AS retweets,
                COALESCE(replies,0) AS replies, created, url
           FROM x_opinion
          WHERE ticker = ? AND created >= ? AND text NOT GLOB 'RT @*'
          ORDER BY (likes + retweets + replies) DESC
          LIMIT ${limit | 0}`,
        symbol,
        since
      ),
    []
  );
  return rows.map((r) => ({
    id: "x-" + r.tweet_id,
    day: dayOf(r.created),
    source: "x" as KolSource,
    author: r.handle ? "@" + r.handle : "@—",
    interactions: (r.likes || 0) + (r.retweets || 0) + (r.replies || 0),
    stance: "neutral" as Stance, // X 推文无情绪标注
    zh: r.text || "",
    en: r.text || "",
    url: r.url || "#",
    avatarKey: r.handle || "", // X 头像走 unavatar/twitter（见 getKolFlowReal）
    refKey: String(r.tweet_id), // kol_refined: x:<tweet_id>
    orig: r.text || "", // 原文 = 推文全文
  }));
}

export function getKolFlowReal(symbol: string): KolFlow | null {
  const days = priceDays(symbol);
  if (days.length < 4) return null; // 价格历史不足 → 回退 mock
  const tradingDays = days.map((d) => d.day);
  const since = tradingDays[0];

  const raw = [
    ...redditOps(symbol, since),
    ...youtubeOps(symbol, since),
    ...xueqiuOps(symbol, since),
    ...xOps(symbol, since),
  ];
  const refined = refinedMap(symbol);
  const vpMap = viewpointMap(symbol);
  const avatars = avatarMap();
  const opinions: KolOpinion[] = [];
  for (const r of raw) {
    const day = snapToTradingDay(r.day, tradingDays);
    if (!day) continue;

    // 提炼结果：YouTube 已在 youtubeOps 里带上（yt_analysis）；其余源 join kol_refined。
    let reason = r.reason;
    let points = r.points;
    let stance = r.stance;
    let trans: Bi | undefined;
    let quote: Bi | undefined;
    if (r.source !== "youtube") {
      const ref = refined.get(`${r.source}:${r.refKey}`);
      if (ref) {
        reason = ref.reason;
        points = ref.points;
        trans = ref.trans && (ref.trans.zh || ref.trans.en) ? ref.trans : undefined;
        quote = ref.quote && (ref.quote.zh || ref.quote.en) ? ref.quote : undefined;
        // X 无原生情绪 → 用提炼立场；reddit/雪球 原生中性时也用提炼立场补足
        if (r.source === "x" || stance === "neutral") stance = ref.stance;
      }
    }
    // 提炼后判定为「无明确观点」（新闻转述/过度匹配标的）→ 不当作 KOL 观点展示
    if (isNoThesis(reason)) continue;
    const hasReason = !!(reason && (reason.zh || reason.en));
    if (!hasReason && !r.zh && !r.en) continue; // 既无提炼也无原文 → 丢弃

    opinions.push({
      id: r.id,
      day,
      source: r.source,
      author: r.author,
      interactions: r.interactions,
      stance,
      text: { zh: r.zh || r.en, en: r.en || r.zh },
      orig: r.orig,
      trans,
      quote,
      reason: hasReason ? { zh: reason!.zh || reason!.en, en: reason!.en || reason!.zh } : undefined,
      points: points && (points.zh.length || points.en.length) ? points : undefined,
      url: r.url,
      avatar:
        avatars.get(`${r.source}:${r.avatarKey}`) ||
        (r.source === "x" && r.avatarKey ? `https://unavatar.io/twitter/${r.avatarKey}` : undefined),
      viewpoints: vpMap.get(`${r.source}:${r.refKey}`),
    });
  }
  if (!opinions.length) return null;
  return { days, opinions };
}

// kol_relevance（pipeline kol-relevance 产出）：source:item_id -> 0-100 相关度分。
function relevanceMap(symbol: string): Map<string, number> {
  const rows = safe(
    () => all<{ source: string; item_id: string; score: number }>(
      `SELECT source, item_id, score FROM kol_relevance WHERE ticker = ?`, symbol),
    []
  );
  const m = new Map<string, number>();
  for (const r of rows) m.set(`${r.source}:${r.item_id}`, r.score);
  return m;
}

// kol_quality（pipeline kol-quality 产出）：source:item_id -> 0-100 帖子质量分。与标的无关，故不按 ticker 过滤。
function qualityMap(): Map<string, number> {
  const rows = safe(
    () => all<{ source: string; item_id: string; score: number }>(`SELECT source, item_id, score FROM kol_quality`),
    []
  );
  const m = new Map<string, number>();
  for (const r of rows) m.set(`${r.source}:${r.item_id}`, r.score);
  return m;
}

// 标的页「观点浏览器」（OpinionExplorer，筛选+主从阅读）的扁平观点池。
// 与折线图的 getKolFlowReal 不同：① 取近 ~32 天（覆盖最大 1 个月时间窗）② 不 snap 到交易日（用真实发布日）
// ③ 每条带 relevance（kol_relevance）。源/立场/视角/时间/语言/相关性 的筛选全在前端做。
export function getKolOpinions(symbol: string): KolOpinion[] {
  return safe(() => {
    const since = new Date(Date.now() - 32 * 864e5).toISOString().slice(0, 10);
    const raw = [
      ...redditOps(symbol, since, 200),
      ...youtubeOps(symbol, since, 80),
      ...xueqiuOps(symbol, since, 200),
      ...xOps(symbol, since, 200),
    ];
    const refined = refinedMap(symbol);
    const vpMap = viewpointMap(symbol);
    const avatars = avatarMap();
    const relMap = relevanceMap(symbol);
    const qualMap = qualityMap();
    const out: KolOpinion[] = [];
    for (const r of raw) {
      if (!r.day) continue;
      let reason = r.reason;
      let points = r.points;
      let stance = r.stance;
      let trans: Bi | undefined;
      let quote: Bi | undefined;
      if (r.source !== "youtube") {
        const ref = refined.get(`${r.source}:${r.refKey}`);
        if (ref) {
          reason = ref.reason;
          points = ref.points;
          trans = ref.trans && (ref.trans.zh || ref.trans.en) ? ref.trans : undefined;
          quote = ref.quote && (ref.quote.zh || ref.quote.en) ? ref.quote : undefined;
          if (r.source === "x" || stance === "neutral") stance = ref.stance;
        }
      }
      if (isNoThesis(reason)) continue;
      const hasReason = !!(reason && (reason.zh || reason.en));
      if (!hasReason && !r.zh && !r.en) continue;
      out.push({
        id: r.id,
        day: r.day,
        source: r.source,
        author: r.author,
        interactions: r.interactions,
        stance,
        text: { zh: r.zh || r.en, en: r.en || r.zh },
        orig: r.orig,
        trans,
        quote,
        reason: hasReason ? { zh: reason!.zh || reason!.en, en: reason!.en || reason!.zh } : undefined,
        points: points && (points.zh.length || points.en.length) ? points : undefined,
        url: r.url,
        avatar:
          avatars.get(`${r.source}:${r.avatarKey}`) ||
          (r.source === "x" && r.avatarKey ? `https://unavatar.io/twitter/${r.avatarKey}` : undefined),
        viewpoints: vpMap.get(`${r.source}:${r.refKey}`),
        relevance: relMap.get(`${r.source}:${r.refKey}`),
        quality: qualMap.get(`${r.source}:${r.refKey}`),
      });
    }
    return out;
  }, []);
}

// ===================== 论点综合（kol_argument，标的页『按视角』视图）=====================
// pipeline kol-argument 把同一(标的×视角×立场)下的观点聚成 1-3 个论点，supporters 回指 source+item_id。
// 这一层**与时间轴滑块解耦**：展示「当前整体争论」，故独立取数、不按价格窗口过滤。
export type LensKey =
  | "valuation" | "growth" | "competition" | "management" | "macro" | "catalyst" | "flows";

export interface ArgSupporter {
  source: KolSource;
  author: string;
  avatar?: string;
  url: string;
  interactions: number;
  stance: Stance;
  day?: string; // 发布日（时效排序 + 展示）
  orig?: string; // 原帖原文（native 语言、未翻译；卡片默认展示）
  text?: Bi; // 当前语言显示文本（reddit/youtube 双语；x/雪球为原文）
  trans?: Bi; // 原帖完整忠实翻译（逐句、不压缩；「译」选项首选）
  quote?: Bi; // 本人忠实原话（一句 soundbite，译文回退用）
  reason?: Bi; // AI 提炼（旧观点视图回退用）
}
export interface KolArgument {
  lens: LensKey;
  stance: Stance;
  claim: Bi; // 一句话主张
  detail?: Bi; // 一句支撑推理
  supportCount: number;
  supporters: ArgSupporter[];
}
export interface Narrative { lead?: Bi; points: { text: Bi; supporters: ArgSupporter[] }[] }
export interface StanceGroup { narrative?: Narrative; args: KolArgument[] }
export interface LensArgGroup { bull: StanceGroup; neutral: StanceGroup; bear: StanceGroup }
export type KolArguments = Partial<Record<LensKey, LensArgGroup>>;
export type WindowedArguments = Record<string, KolArguments>; // 时间窗 key（24h|3d|7d|14d|1mo）-> 该窗论点

// 浮现分（方案A 排序核心）：互动量（对数）为主，叠加「具体性」（含数字/$/%/催化词→更可读、更可证伪）
// 与「时效」（近期略加权），把值得先读的原帖顶到前面。纯启发式、零 LLM。
const SPEC_RE = /[0-9$%＄％]|\b(beat|miss|guidance|guide|earnings|catalyst|fda|deal|buyback|margin|revenue|eps)\b|财报|催化|业绩|回购|毛利|营收|交付|订单/i;
function supporterScore(s: ArgSupporter): number {
  const eng = Math.log10((s.interactions || 0) + 1); // 0 ~ 5+
  const txt = `${s.text?.zh || ""} ${s.text?.en || ""} ${s.quote?.zh || ""}`;
  const spec = SPEC_RE.test(txt) ? 0.6 : 0;
  const rec = s.day ? Math.max(0, 1 - (Date.now() - Date.parse(s.day + "T00:00:00Z")) / (30 * 864e5)) * 0.5 : 0;
  return eng + spec + rec;
}

export function getKolArguments(symbol: string): WindowedArguments {
  return safe(() => {
    const rows = all<any>(
      `SELECT window, lens, stance, claim_zh, claim_en, detail_zh, detail_en, supporters, support_count
         FROM kol_argument WHERE ticker = ? ORDER BY window, lens, stance, rank`,
      symbol
    );
    if (!rows.length) return {};

    // 该标的观点索引（source:item_id -> 展示信息），用于把 supporters 解析成头像/原话/原帖。
    // 用较宽窗口（~30 天，覆盖 refine 的 20 天）以确保 supporters 可解析，与滑块无关。
    const cutoff = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10);
    const rawIdx = new Map<string, RawOp>();
    for (const op of [
      ...redditOps(symbol, cutoff, 200),
      ...youtubeOps(symbol, cutoff, 80),
      ...xueqiuOps(symbol, cutoff, 200),
      ...xOps(symbol, cutoff, 200),
    ]) rawIdx.set(`${op.source}:${op.refKey}`, op);
    const refined = refinedMap(symbol);
    const avatars = avatarMap();

    const resolve = (s: { source: string; item_id: string }): ArgSupporter | null => {
      const key = `${s.source}:${s.item_id}`;
      const raw = rawIdx.get(key);
      const ref = refined.get(key);
      if (!raw && !ref) return null;
      const source = (raw?.source || s.source) as KolSource;
      const avatar =
        (raw ? avatars.get(`${source}:${raw.avatarKey}`) : undefined) ||
        (source === "x" && raw?.avatarKey ? `https://unavatar.io/twitter/${raw.avatarKey}` : undefined);
      const quote = ref?.quote && (ref.quote.zh || ref.quote.en) ? ref.quote : undefined;
      const trans = ref?.trans && (ref.trans.zh || ref.trans.en) ? ref.trans : undefined;
      const reason = ref?.reason && (ref.reason.zh || ref.reason.en) ? ref.reason : raw?.reason;
      return {
        source,
        author: raw?.author || (source === "xueqiu" ? "雪球" : source),
        avatar,
        url: raw?.url || "#",
        interactions: raw?.interactions || 0,
        stance: ref?.stance || raw?.stance || "neutral",
        day: raw?.day,
        orig: raw?.orig,
        text: raw && (raw.zh || raw.en) ? { zh: raw.zh || raw.en, en: raw.en || raw.zh } : quote,
        trans,
        quote,
        reason,
      };
    };

    const out: WindowedArguments = {};
    for (const r of rows) {
      const w = String(r.window || "14d");
      const lens = r.lens as LensKey;
      const stance = ((r.stance as Stance) || "neutral") as Stance;
      const claim: Bi = { zh: r.claim_zh || r.claim_en || "", en: r.claim_en || r.claim_zh || "" };
      if (!claim.zh && !claim.en) continue;
      const supporters = parseJSON<{ source: string; item_id: string }[]>(r.supporters, [])
        .map(resolve)
        .filter((x): x is ArgSupporter => !!x)
        .sort((a, b) => supporterScore(b) - supporterScore(a));
      const arg: KolArgument = {
        lens,
        stance,
        claim,
        detail: r.detail_zh || r.detail_en ? { zh: r.detail_zh || r.detail_en, en: r.detail_en || r.detail_zh } : undefined,
        supportCount: r.support_count || supporters.length,
        supporters,
      };
      const ow = (out[w] ||= {});
      const g = (ow[lens] ||= { bull: { args: [] }, neutral: { args: [] }, bear: { args: [] } });
      (stance === "bull" ? g.bull : stance === "bear" ? g.bear : g.neutral).args.push(arg);
    }
    // 叙事（kol_narrative）：每条 point 的 refs → 支持者头像/原帖角标，按 (窗口,视角,立场) 挂上
    for (const n of safe(
      () => all<any>("SELECT window, lens, stance, lead_zh, lead_en, points FROM kol_narrative WHERE ticker = ?", symbol),
      [] as any[]
    )) {
      const ow = out[String(n.window || "14d")];
      if (!ow) continue;
      const g = ow[n.lens as LensKey];
      if (!g) continue;
      const lead = n.lead_zh || n.lead_en ? { zh: n.lead_zh || n.lead_en, en: n.lead_en || n.lead_zh } : undefined;
      const points = parseJSON<any[]>(n.points, []).map((p) => ({
        text: { zh: p.zh || p.en || "", en: p.en || p.zh || "" } as Bi,
        supporters: ((p.refs || []) as { source: string; item_id: string }[])
          .map(resolve)
          .filter((x): x is ArgSupporter => !!x)
          .sort((a, b) => supporterScore(b) - supporterScore(a)),
      }));
      const stance = (n.stance as Stance) || "neutral";
      (stance === "bull" ? g.bull : stance === "bear" ? g.bear : g.neutral).narrative = { lead, points };
    }
    return out;
  }, {});
}
