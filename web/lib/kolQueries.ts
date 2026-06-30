// 第 1 块「个体观点 · KOL」的**真实数据**取数层（替换 mock）。
//   - 价格：price_daily（pipeline/ingest/price_daily.py，Yahoo 日 OHLC）。
//   - 观点：Reddit（posts+mentions+item_analysis）+ YouTube（yt_video+yt_analysis）+ 雪球（gr_post source=xueqiu）。
//   - X/Twitter：x_opinion + x_reply（pipeline/ingest/x_pull.py 从云端 tw_* 拉进本地；含逐项互动数 + 热门评论）。
// 数据不足（无价格历史/无观点）时返回 null → 详情页回退 getKolFlow(mock)，保证不空。
import { all, parseJSON } from "./db";
import type { KolFlow, KolOpinion, KolCandle, KolSource, Stance, Bi, TweetMetrics, TweetReply, YtSeg, YtChannel, YtDigest, KolJudgment, KolTargetData, TargetMark } from "./mockDetail";

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

// 现价（散点基准线 + 目标价剔噪锚点）：price_daily 最新收盘优先，缺则 gr_quote。
function currentPrice(symbol: string): number | null {
  const d = priceDays(symbol);
  const last = d.length ? d[d.length - 1].close : 0;
  if (last > 0) return last;
  const gr = safe(() => all<{ price: number }>(`SELECT price FROM gr_quote WHERE ticker = ?`, symbol), []);
  return gr.length && gr[0].price > 0 ? gr[0].price : null;
}

// 价格短语 → 数字（区间取中点；含 % 的相对幅度 → undefined）。供 YouTube yt_judgment.target 字符串解析。
function parseRange(s?: string | null): [number, number] | null {
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
function bucketHorizon(text: string): "short" | "mid" | "long" | undefined {
  const t = (text || "").toLowerCase();
  if (!t.trim()) return undefined;
  if (/长期|长线|数年|两到三年|多年|\d+\s*年|year|202[7-9]|2030|12-18|18-24|long[- ]?term/.test(t)) return "long";
  if (/日内|几天|数天|几周|数周|swing|波段|反弹|短期|短线|day trade|this week|next week|\bdays?\b|\bweeks?\b|short[- ]?term/.test(t)) return "short";
  if (/个月|月底|季度|quarter|months?\b|到年底|半年|下半年/.test(t)) return "mid";
  return undefined;
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
  metrics?: TweetMetrics; // X 逐项互动数（赞/转/评/引/看/藏）
  ytSegments?: YtSeg[]; // YouTube 完整口播段落（yt_fulltext.segments；多人带说话人）
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

// yt_channel（pipeline/ingest/youtube_channels.py 爬取）→ channel_id -> 作者基础信息（粉丝/视频/简介/@handle）
function ytChannelMap(): Map<string, YtChannel> {
  const rows = safe(
    () => all<any>(
      `SELECT channel_id, subscriber_count, video_count, description, handle FROM yt_channel`
    ),
    []
  );
  const m = new Map<string, YtChannel>();
  for (const r of rows) {
    m.set(String(r.channel_id), {
      subscribers: typeof r.subscriber_count === "number" ? r.subscriber_count : undefined,
      videos: typeof r.video_count === "number" ? r.video_count : undefined,
      bio: (r.description || "").trim() || undefined,
      handle: (r.handle || "").trim() || undefined,
    });
  }
  return m;
}

// yt_digest（pipeline/analyze/youtube_digest.py 产出）→ video_id -> 投资者摘要 + 内容目录(章节)
function ytDigestMap(): Map<string, YtDigest> {
  const rows = safe(
    () => all<any>(`SELECT video_id, summary_zh, summary_en, chapters FROM yt_digest`),
    []
  );
  const m = new Map<string, YtDigest>();
  for (const r of rows) {
    const sz = parseJSON<string[]>(r.summary_zh, []);
    const se = parseJSON<string[]>(r.summary_en, []);
    const summary: Bi[] = sz.map((zh, i) => ({ zh, en: se[i] || zh })).filter((b) => b.zh || b.en);
    const chRaw = parseJSON<any[]>(r.chapters, []);
    const chapters = (Array.isArray(chRaw) ? chRaw : [])
      .map((c) => ({ title: { zh: String(c.t_zh || c.t_en || ""), en: String(c.t_en || c.t_zh || "") }, seg: +c.seg || 0 }))
      .filter((c) => c.title.zh || c.title.en);
    if (summary.length || chapters.length) m.set(String(r.video_id), { summary, chapters });
  }
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

// yt_fulltext（pipeline youtube-fulltext 产出）：video_id -> {flat 口播全文, segments 有序口播段落(多人视频带说话人)}。
// 单独查询并 try/catch 兜底——缺表则返回空，YouTube 观点照常工作、只是没有「完整口播」。
interface YtFull {
  flat: string;
  segments: YtSeg[];
}
function ytFulltextMap(symbol: string): Map<string, YtFull> {
  const rows = safe(
    () => all<any>(`SELECT video_id, content_zh, segments FROM yt_fulltext WHERE ticker = ?`, symbol),
    []
  );
  const m = new Map<string, YtFull>();
  for (const r of rows) {
    const flat = String(r.content_zh || "").trim();
    const segs = parseJSON<YtSeg[]>(r.segments, []);
    if (flat || (Array.isArray(segs) && segs.length)) {
      m.set(r.video_id, { flat, segments: Array.isArray(segs) ? segs : [] });
    }
  }
  return m;
}

function youtubeOps(symbol: string, since: string, limit = 20): RawOp[] {
  const fulltext = ytFulltextMap(symbol);
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
      orig: fulltext.get(r.id)?.flat || undefined, // 完整口播全文（兜底/搜索）；有 ytSegments 时前端用结构化渲染
      ytSegments: fulltext.get(r.id)?.segments?.length ? fulltext.get(r.id)!.segments : undefined,
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
                COALESCE(replies,0) AS replies, COALESCE(quotes,0) AS quotes, COALESCE(views,0) AS views,
                COALESCE(bookmarks,0) AS bookmarks, created, url
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
    metrics: {
      replies: r.replies || 0, retweets: r.retweets || 0, likes: r.likes || 0,
      quotes: r.quotes || 0, views: r.views || 0, bookmarks: r.bookmarks || 0,
    } as TweetMetrics,
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

// kol_judgment（pipeline kol-judgment）+ yt_judgment（youtube-judgment）：source:item_id -> 买卖价位(区间)+周期。
// 价格以区间**中点**做现价 0.2–5× band 剔噪（penny-pump / 假设估值 / $1225 这类数量级离谱的丢弃）。供正文提炼行。
function judgmentMap(symbol: string): Map<string, KolJudgment> {
  const cur = currentPrice(symbol);
  // 一侧价位(lo,hi) → 规整 [lo,hi]；中点过 band 才保留，否则 undefined
  const side = (lo?: number, hi?: number): [number, number] | undefined => {
    if (lo == null || !(lo > 0)) return undefined;
    const h = hi != null && hi > 0 ? hi : lo;
    const mid = (lo + h) / 2;
    if (cur && (mid < cur * 0.2 || mid > cur * 5)) return undefined;
    return [Math.min(lo, h), Math.max(lo, h)];
  };
  const bi = (zh: string, en: string): Bi | undefined => (zh || en ? { zh: zh || en, en: en || zh } : undefined);
  const bk = (b: string) => (["short", "mid", "long"].includes(b) ? b : undefined) as KolJudgment["bucket"];
  const m = new Map<string, KolJudgment>();
  // reddit / x / 雪球：kol_judgment（买入/卖出 各 lo/hi + bucket 来自 LLM）
  const rows = safe(
    () =>
      all<any>(
        `SELECT source, item_id, buy_lo, buy_hi, sell_lo, sell_hi, COALESCE(price_raw,'') AS pr,
                COALESCE(horizon_zh,'') AS hz, COALESCE(horizon_en,'') AS he, COALESCE(horizon_bucket,'') AS bk
           FROM kol_judgment WHERE ticker = ?`,
        symbol
      ),
    []
  );
  for (const r of rows) {
    const b = side(r.buy_lo, r.buy_hi), s = side(r.sell_lo, r.sell_hi);
    const horizon = bi(r.hz, r.he), bucket = bk(r.bk);
    if (!b && !s && !horizon && !bucket) continue;
    m.set(`${r.source}:${r.item_id}`, {
      buyLo: b?.[0], buyHi: b?.[1], sellLo: s?.[0], sellHi: s?.[1], priceRaw: r.pr || undefined, horizon, bucket,
    });
  }
  // youtube：yt_judgment（单一 target 字符串 → 卖出/目标侧；周期文本 → bucket 启发式）
  const yt = safe(
    () =>
      all<any>(
        `SELECT video_id, COALESCE(target,'') AS target, COALESCE(horizon_zh,'') AS hz, COALESCE(horizon_en,'') AS he
           FROM yt_judgment WHERE ticker = ?`,
        symbol
      ),
    []
  );
  for (const r of yt) {
    const rng = parseRange(r.target);
    const s = rng ? side(rng[0], rng[1]) : undefined;
    const horizon = bi(r.hz, r.he);
    if (!s && !horizon) continue;
    m.set(`youtube:${r.video_id}`, {
      sellLo: s?.[0], sellHi: s?.[1], priceRaw: r.target || undefined,
      horizon, bucket: horizon ? bucketHorizon(`${r.hz} ${r.he}`) : undefined,
    });
  }
  return m;
}

// x_reply（pipeline x_pull 产出）：parent tweet_id -> 该推文下点赞最高的前 K 条评论。
// 只 join 本标的的 x_opinion 取该 ticker 下的评论；头像走 unavatar/twitter 兜底（同主推文）。
function repliesByTweet(symbol: string): Map<string, TweetReply[]> {
  const rows = safe(
    () =>
      all<any>(
        `SELECT r.parent_tweet_id AS pid, r.handle, r.text, COALESCE(r.likes,0) AS likes, r.url
           FROM x_reply r JOIN x_opinion o ON o.tweet_id = r.parent_tweet_id
          WHERE o.ticker = ?
          ORDER BY r.parent_tweet_id, r.rank`,
        symbol
      ),
    []
  );
  const m = new Map<string, TweetReply[]>();
  for (const r of rows) {
    const arr = m.get(r.pid) || [];
    arr.push({
      author: r.handle ? "@" + r.handle : "@—",
      text: r.text || "",
      likes: r.likes || 0,
      url: r.url || undefined,
      avatar: r.handle ? `https://unavatar.io/twitter/${r.handle}` : undefined,
    });
    m.set(r.pid, arr);
  }
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
    const repMap = repliesByTweet(symbol); // 仅 X：tweet_id -> 热门评论
    const ytChans = ytChannelMap(); // 仅 YouTube：channel_id -> 作者基础信息
    const ytDigests = ytDigestMap(); // 仅 YouTube：video_id -> 投资者摘要 + 目录
    const jMap = judgmentMap(symbol); // 目标价+周期（kol_judgment / yt_judgment；价格已剔噪）
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
        metrics: r.source === "x" ? r.metrics : undefined,
        replies: r.source === "x" ? repMap.get(r.refKey) : undefined,
        ytSegments: r.source === "youtube" ? r.ytSegments : undefined,
        channel: r.source === "youtube" ? ytChans.get(r.avatarKey) : undefined,
        ytDigest: r.source === "youtube" ? ytDigests.get(r.refKey) : undefined,
        judgment: jMap.get(`${r.source}:${r.refKey}`),
      });
    }
    return out;
  }, []);
}

// 近 N 天股价折线（叠加用；price_daily 现仅 ~2 周，待 price_daily.py 拉到 3 个月后自动变长）。
function priceWindow(symbol: string, days: number): { day: string; close: number }[] {
  const cutoff = new Date(Date.now() - days * 864e5).toISOString().slice(0, 10);
  return safe(
    () => all<{ day: string; close: number }>(
      `SELECT day, close FROM price_daily WHERE ticker = ? AND day >= ? ORDER BY day`, symbol, cutoff),
    []
  );
}

// 「整体数据 · 目标价时间线」取数：近 ~3 个月 kol_judgment(reddit/x/雪球) + yt_judgment(youtube)，
// 每条判断的买入侧/卖出侧各出一个 TargetMark(日期×价位区间)；叠真实股价折线 + 现价。作者/链接 join 源表，
// 简单依据(reason)取 kol_refined(reddit/x/雪球) 或 yt_analysis.summary(youtube)；价格按现价 band 二次剔噪。
export function getKolTargetPrices(symbol: string): KolTargetData {
  return safe(
    () => {
      const current = currentPrice(symbol);
      const priceLine = priceWindow(symbol, 95);
      const cutoff = new Date(Date.now() - 95 * 864e5).toISOString().slice(0, 10);
      const refined = refinedMap(symbol); // 简单依据
      const bi = (zh: string, en: string): Bi | undefined => (zh || en ? { zh: zh || en, en: en || zh } : undefined);
      const bk = (b: string) => (["short", "mid", "long"].includes(b) ? b : undefined) as TargetMark["bucket"];
      const inBand = (mid: number) => !current || (mid >= current * 0.2 && mid <= current * 5);
      const marks: TargetMark[] = [];

      const SRC: { s: KolSource; sql: string; name: (a: string) => string }[] = [
        { s: "reddit", name: (a) => (a && a !== "[deleted]" ? "u/" + a : "u/—"),
          sql: `SELECT kj.*, p.author_id AS author, p.permalink AS url
                  FROM kol_judgment kj JOIN posts p ON p.id = kj.item_id
                 WHERE kj.source='reddit' AND kj.ticker=? AND kj.created>=?` },
        { s: "x", name: (a) => (a ? "@" + a : "@—"),
          sql: `SELECT kj.*, x.handle AS author, x.url AS url
                  FROM kol_judgment kj JOIN x_opinion x ON x.tweet_id = kj.item_id
                 WHERE kj.source='x' AND kj.ticker=? AND kj.created>=?` },
        { s: "xueqiu", name: (a) => a || "雪球",
          sql: `SELECT kj.*, g.author AS author, g.url AS url
                  FROM kol_judgment kj JOIN gr_post g ON g.id = kj.item_id
                 WHERE kj.source='xueqiu' AND kj.ticker=? AND kj.created>=?` },
      ];
      for (const cfg of SRC) {
        const rows = safe(() => all<any>(cfg.sql, symbol, cutoff), []);
        for (const r of rows) {
          const ref = refined.get(`${cfg.s}:${r.item_id}`);
          const reason = ref?.reason && (ref.reason.zh || ref.reason.en) ? ref.reason : undefined;
          const base = {
            source: cfg.s, author: cfg.name(r.author), priceRaw: r.price_raw || undefined,
            horizon: bi(r.horizon_zh || "", r.horizon_en || ""), bucket: bk(r.horizon_bucket || ""),
            reason, date: String(r.created || "").slice(0, 10), url: r.url || "#",
          };
          if (r.buy_lo != null && inBand((r.buy_lo + (r.buy_hi ?? r.buy_lo)) / 2))
            marks.push({ ...base, kind: "buy", lo: r.buy_lo, hi: r.buy_hi ?? r.buy_lo });
          if (r.sell_lo != null && inBand((r.sell_lo + (r.sell_hi ?? r.sell_lo)) / 2))
            marks.push({ ...base, kind: "sell", lo: r.sell_lo, hi: r.sell_hi ?? r.sell_lo });
        }
      }
      // youtube：yt_judgment ⋈ yt_video / yt_analysis → 卖出/目标侧
      const yt = safe(
        () => all<any>(
          `SELECT yj.target AS target, COALESCE(yj.horizon_zh,'') AS hz, COALESCE(yj.horizon_en,'') AS he,
                  v.channel AS author, v.url AS url, v.published_utc AS created,
                  COALESCE(a.summary_zh,'') AS sz, COALESCE(a.summary_en,'') AS se
             FROM yt_judgment yj JOIN yt_video v ON v.id = yj.video_id
             LEFT JOIN yt_analysis a ON a.video_id = yj.video_id
            WHERE yj.ticker=? AND v.published_utc>=?`, symbol, cutoff),
        []
      );
      for (const r of yt) {
        const rng = parseRange(r.target);
        if (!rng || !inBand((rng[0] + rng[1]) / 2)) continue;
        const horizon = bi(r.hz, r.he);
        marks.push({
          source: "youtube", author: r.author || "YouTube", kind: "sell", lo: rng[0], hi: rng[1],
          priceRaw: r.target || undefined, horizon, bucket: horizon ? bucketHorizon(`${r.hz} ${r.he}`) : undefined,
          reason: bi(r.sz, r.se), date: String(r.created || "").slice(0, 10), url: r.url || "#",
        });
      }
      // 去重：同一作者同日同侧同价位（重复推文 / join 扇出）只留一条，避免图上叠成一团
      const seen = new Set<string>();
      const deduped = marks.filter((m) => {
        const k = `${m.source}|${m.author}|${m.kind}|${m.lo}|${m.hi}|${m.date}`;
        if (seen.has(k)) return false;
        seen.add(k);
        return true;
      });
      return { current, priceLine, marks: deduped };
    },
    { current: null, priceLine: [], marks: [] }
  );
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

// 每日净情绪（kol_sentiment_daily，pipeline `make kol-sentiment`）：折线图下方绿/红面积子面板用。
// 跨平台 情绪×ln(1+互动)×相关性 加权净值；表缺失→空数组（子面板自降级不崩）。
export interface DailyNet { day: string; net: number; nPosts: number; nBull: number; nBear: number }
export function getKolSentimentDaily(symbol: string): DailyNet[] {
  return safe(
    () =>
      all<any>(
        `SELECT day, net, n_posts AS nPosts, n_bull AS nBull, n_bear AS nBear
           FROM kol_sentiment_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ).map((r) => ({ day: r.day, net: +r.net || 0, nPosts: +r.nPosts || 0, nBull: +r.nBull || 0, nBear: +r.nBear || 0 })),
    []
  );
}

// 每日讨论度（kol_volume_daily，pipeline kol-volume 产出）：每 (ticker,day) 跨平台帖子/视频**计数**。
// 供 KOL 模块「每日讨论度」堆叠条形子面板（VolumePanel）。按 day 升序。
export interface DailyVol { day: string; total: number; reddit: number; x: number; xueqiu: number; youtube: number; [key: string]: number | string }
export function getKolVolumeDaily(symbol: string): DailyVol[] {
  return safe(
    () =>
      all<any>(
        `SELECT day, COALESCE(n_total,0) AS total, COALESCE(n_reddit,0) AS reddit, COALESCE(n_x,0) AS x,
                COALESCE(n_xueqiu,0) AS xueqiu, COALESCE(n_youtube,0) AS youtube
           FROM kol_volume_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ).map((r) => ({ day: r.day, total: +r.total || 0, reddit: +r.reddit || 0, x: +r.x || 0, xueqiu: +r.xueqiu || 0, youtube: +r.youtube || 0 })),
    []
  );
}

// ===================== 整体散户（retail_*_daily，pipeline retail-sentiment / retail-volume）=====================
// 与 KOL 同形状、不同人群口径：全量散户 + 本土论坛（Naver/Yahoo JP/PTT/Toss），不含 YouTube。
// 标的页 KOL 模块顶部的「KOL ↔ 整体散户」切换：复用 SentimentPanel/VolumePanel，仅换数据源。表缺失→空数组（降级不崩）。

// 每日净情绪（retail_sentiment_daily）：复用 DailyNet 形状（SentimentPanel 只读 net）。
export function getRetailSentimentDaily(symbol: string): DailyNet[] {
  return safe(
    () =>
      all<any>(
        `SELECT day, net, n_posts AS nPosts, n_bull AS nBull, n_bear AS nBear
           FROM retail_sentiment_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ).map((r) => ({ day: r.day, net: +r.net || 0, nPosts: +r.nPosts || 0, nBull: +r.nBull || 0, nBear: +r.nBear || 0 })),
    []
  );
}

// 每日讨论度（retail_volume_daily）：7 个平台键（toss 暂为 0，待 Toss 爬虫上线）。供 VolumePanel + RETAIL_VOL_STACK 堆叠。
export interface RetailVol { day: string; total: number; reddit: number; x: number; xueqiu: number; naver: number; yahoojp: number; ptt: number; toss: number; [key: string]: number | string }
export function getRetailVolumeDaily(symbol: string): RetailVol[] {
  return safe(
    () =>
      all<any>(
        `SELECT day, COALESCE(n_total,0) AS total, COALESCE(n_reddit,0) AS reddit, COALESCE(n_x,0) AS x,
                COALESCE(n_xueqiu,0) AS xueqiu, COALESCE(n_naver,0) AS naver, COALESCE(n_yahoojp,0) AS yahoojp,
                COALESCE(n_ptt,0) AS ptt, COALESCE(n_toss,0) AS toss
           FROM retail_volume_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ).map((r) => ({
        day: r.day, total: +r.total || 0, reddit: +r.reddit || 0, x: +r.x || 0, xueqiu: +r.xueqiu || 0,
        naver: +r.naver || 0, yahoojp: +r.yahoojp || 0, ptt: +r.ptt || 0, toss: +r.toss || 0,
      })),
    []
  );
}

// 每日『新增散户』（retail_newcomers_daily，pipeline retail-newcomers）：各平台**首次参与该标的讨论**的去重作者数。
// 6 平台键（不含 X：云端无作者列；不含 YouTube）。供 VolumePanel + RETAIL_NEW_STACK 堆叠（仅整体散户视图显示）。
export interface RetailNew { day: string; total: number; reddit: number; xueqiu: number; naver: number; yahoojp: number; ptt: number; toss: number; [key: string]: number | string }
export function getRetailNewcomersDaily(symbol: string): RetailNew[] {
  return safe(
    () =>
      all<any>(
        `SELECT day, COALESCE(n_total,0) AS total, COALESCE(n_reddit,0) AS reddit,
                COALESCE(n_xueqiu,0) AS xueqiu, COALESCE(n_naver,0) AS naver, COALESCE(n_yahoojp,0) AS yahoojp,
                COALESCE(n_ptt,0) AS ptt, COALESCE(n_toss,0) AS toss
           FROM retail_newcomers_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ).map((r) => ({
        day: r.day, total: +r.total || 0, reddit: +r.reddit || 0, xueqiu: +r.xueqiu || 0,
        naver: +r.naver || 0, yahoojp: +r.yahoojp || 0, ptt: +r.ptt || 0, toss: +r.toss || 0,
      })),
    []
  );
}

// 每日『新增 KOL』（kol_newcomers_daily，pipeline kol-newcomers）：X / YouTube / 雪球（有身份/粉丝象征的平台）
// **首次参与该标的讨论**的去重作者数。供 VolumePanel + KOL_NEW_STACK 堆叠（仅 KOL 视图显示）。
export interface KolNew { day: string; total: number; x: number; youtube: number; xueqiu: number; [key: string]: number | string }
export function getKolNewcomersDaily(symbol: string): KolNew[] {
  return safe(
    () =>
      all<any>(
        `SELECT day, COALESCE(n_total,0) AS total, COALESCE(n_x,0) AS x,
                COALESCE(n_youtube,0) AS youtube, COALESCE(n_xueqiu,0) AS xueqiu
           FROM kol_newcomers_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ).map((r) => ({
        day: r.day, total: +r.total || 0, x: +r.x || 0, youtube: +r.youtube || 0, xueqiu: +r.xueqiu || 0,
      })),
    []
  );
}

// ===================== KOL 看多/看空 标的排行榜（标的总览页）=====================
// 跨标的把 KOL 每日净情绪（kol_sentiment_daily.net = 情绪×热度×相关性 加权）按**近 14 天**聚合，
// 排出 KOL「最看多 / 最看空」的标的（各前 N）。net 是全站统一的 KOL 信号，故榜单与详情页折线同源、口径一致。
// 仅限**已跟踪标的全集**（join gr_ticker，避免 X 带进数百无关 symbol）；要求最少方向性帖数，过滤低样本噪音。
export interface KolRank {
  ticker: string; nameZh: string; nameEn: string;
  net: number; nBull: number; nBear: number; nPosts: number;
}
export function getKolBullBearBoards(limit = 5, minDirectional = 30): { bullish: KolRank[]; bearish: KolRank[] } {
  return safe(
    () => {
      const rows = all<any>(
        `SELECT s.ticker AS ticker, g.name_zh AS nameZh, g.name_en AS nameEn,
                ROUND(SUM(s.net), 2) AS net, SUM(s.n_bull) AS nBull, SUM(s.n_bear) AS nBear, SUM(s.n_posts) AS nPosts
           FROM kol_sentiment_daily s
           JOIN gr_ticker g ON upper(g.ticker) = s.ticker
          WHERE s.day >= (SELECT date(MAX(day), '-14 day') FROM kol_sentiment_daily)
          GROUP BY s.ticker, g.name_zh, g.name_en
         HAVING (SUM(s.n_bull) + SUM(s.n_bear)) >= ?`,
        minDirectional
      ).map((r) => ({
        ticker: String(r.ticker), nameZh: r.nameZh || "", nameEn: r.nameEn || "",
        net: +r.net || 0, nBull: +r.nBull || 0, nBear: +r.nBear || 0, nPosts: +r.nPosts || 0,
      }));
      const byNet = [...rows].sort((a, b) => b.net - a.net);
      return { bullish: byNet.slice(0, limit), bearish: [...byNet].reverse().slice(0, limit) };
    },
    { bullish: [], bearish: [] }
  );
}

// KOL「情绪变化最大」标的（近 14 天）：把窗口劈成 前 7 天 / 后 7 天，比**看多占比**(n_bull/(n_bull+n_bear))
// 的变化（百分点 pp）。**用占比、不用 net**——net 受声量主导会只剩大票(与看多榜重复)；占比已归一、跨标的可比，
// 真正反映「KOL 情绪翻没翻」(如 NIO 51%→83% 转多、JPM 68%→39% 转空)。按 |Δ| 取前 N；两半各需够帖数滤噪。
export interface KolSwing {
  ticker: string; nameZh: string; nameEn: string;
  priorShare: number; recentShare: number; delta: number; // 看多占比(%) 与变化(pp，+ 转多 / − 转空)
  recentNet: number;
}
export function getKolSentimentSwings(limit = 5, minPerHalf = 15): KolSwing[] {
  return safe(
    () => {
      const raw = all<any>(
        `WITH mx AS (SELECT MAX(day) AS m FROM kol_sentiment_daily),
              s AS (
                SELECT k.ticker AS ticker, g.name_zh AS nameZh, g.name_en AS nameEn,
                       CASE WHEN k.day > date((SELECT m FROM mx), '-7 day') THEN 1 ELSE 0 END AS recent,
                       k.n_bull AS b, k.n_bear AS be, k.net AS net
                  FROM kol_sentiment_daily k
                  JOIN gr_ticker g ON upper(g.ticker) = k.ticker
                 WHERE k.day > date((SELECT m FROM mx), '-14 day')
              )
         SELECT ticker, nameZh, nameEn,
                SUM(CASE WHEN recent = 0 THEN b ELSE 0 END)  AS pb,
                SUM(CASE WHEN recent = 0 THEN be ELSE 0 END) AS pbe,
                SUM(CASE WHEN recent = 1 THEN b ELSE 0 END)  AS rb,
                SUM(CASE WHEN recent = 1 THEN be ELSE 0 END) AS rbe,
                SUM(CASE WHEN recent = 1 THEN net ELSE 0 END) AS rnet
           FROM s GROUP BY ticker, nameZh, nameEn`
      ).map((r) => {
        const pb = +r.pb || 0, pbe = +r.pbe || 0, rb = +r.rb || 0, rbe = +r.rbe || 0;
        const pd = pb + pbe, rd = rb + rbe;
        const ps = pd ? (100 * pb) / pd : 0;
        const rs = rd ? (100 * rb) / rd : 0;
        return {
          ticker: String(r.ticker), nameZh: r.nameZh || "", nameEn: r.nameEn || "",
          priorShare: Math.round(ps), recentShare: Math.round(rs), delta: Math.round(rs - ps),
          recentNet: +r.rnet || 0, pd, rd,
        };
      });
      return raw
        .filter((x) => x.pd >= minPerHalf && x.rd >= minPerHalf && x.delta !== 0)
        .sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta))
        .slice(0, limit)
        .map((x) => ({
          ticker: x.ticker, nameZh: x.nameZh, nameEn: x.nameEn,
          priorShare: x.priorShare, recentShare: x.recentShare, delta: x.delta, recentNet: x.recentNet,
        }));
    },
    []
  );
}
