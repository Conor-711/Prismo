import { all, parseJSON } from "@/lib/db";
import type { Bi, KolJudgment, KolSource, Stance, TweetMetrics, YtSeg } from "@/shared/market/mockDetail";
import {
  dayOf,
  safe,
  stanceOf,
  stripHtml,
  YOUTUBE_MIN_DISPLAY_DURATION_SECONDS,
  YOUTUBE_MIN_DISPLAY_SUBSCRIBERS,
  type RawOp,
} from "./shared";

export function redditOps(symbol: string, since: string, limit = 5000): RawOp[] {
  const safeLimit = Math.max(1, Math.min(Math.floor(limit), 5000));
  const rows = safe(
    () =>
      all<any>(
        `SELECT p.id AS id, p.author_id AS author, p.title AS title, p.title_zh AS title_zh,
                COALESCE(p.selftext,'') AS selftext, COALESCE(p.selftext_zh,'') AS selftext_zh,
                p.permalink AS url, COALESCE(p.score,0) AS score, COALESCE(p.num_comments,0) AS comments,
                p.created_utc AS created, a.stance AS stance, COALESCE(a.sentiment_score,0) AS senti,
                COALESCE(a.quality_score,0) AS quality, COALESCE(m.confidence,0) AS relevance
           FROM mentions m
           JOIN posts p ON p.id = m.item_id AND m.item_type = 'post'
           LEFT JOIN item_analysis a ON a.item_id = p.id AND a.item_type = 'post'
          WHERE m.ticker = ? AND p.created_utc >= ?
          ORDER BY p.created_utc DESC, (p.score + p.num_comments) DESC
          LIMIT ${safeLimit}`,
        symbol,
        since
      ),
    []
  );
  return rows.map((r) => {
    const title = String(r.title || "").trim();
    const body = String(r.selftext || "").trim();
    const titleZh = String(r.title_zh || "").trim();
    const bodyZh = String(r.selftext_zh || "").trim();
    const orig = [title, body].filter(Boolean).join("\n\n");
    const zhText = [titleZh || title, bodyZh].filter(Boolean).join("\n\n");
    return {
      id: "rd-" + r.id,
      day: dayOf(r.created),
      source: "reddit" as KolSource,
      author: r.author && r.author !== "[deleted]" ? "u/" + r.author : "u/—",
      interactions: (r.score || 0) + (r.comments || 0),
      stance: stanceOf(r.stance, r.senti),
      zh: zhText || title,
      en: orig || title,
      url: r.url || "#",
      avatarKey: r.author || "", // reddit 头像按 author_id join
      refKey: r.id, // kol_refined: reddit:<post id>
      orig: orig || title, // 原文 = 英文标题 + 正文；避免高质量长帖只显示标题
      relevance: Math.round(Math.max(0, Math.min(1, Number(r.relevance) || 0)) * 100),
      quality: Math.round(Math.max(0, Math.min(1, Number(r.quality) || 0)) * 100),
    };
  });
}

// yt_fulltext（pipeline youtube-fulltext 产出）：video_id -> {flat 口播全文, segments 有序口播段落(多人视频带说话人)}。
// 单独查询并 try/catch 兜底——缺表则返回空，YouTube 观点照常工作、只是没有「完整口播」。
interface YtFull {
  flat: string;
  segments: YtSeg[];
}
function ytFulltextMap(symbol: string, since: string): Map<string, YtFull> {
  const rows = safe(
    () => all<any>(
      `SELECT f.video_id, f.content_zh, f.segments
         FROM yt_fulltext f
         JOIN yt_video v ON v.id = f.video_id
        WHERE f.ticker = ? AND v.published_utc >= ?`,
      symbol,
      since
    ),
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

export function youtubeOps(symbol: string, since: string, limit = 20): RawOp[] {
  const safeLimit = Math.max(1, Math.min(Math.floor(limit), 5000));
  const fulltext = ytFulltextMap(symbol, since);
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
           JOIN yt_channel c ON c.channel_id = v.channel_id
           LEFT JOIN yt_analysis a ON a.video_id = v.id
          WHERE v.ticker = ? AND v.published_utc >= ?
            AND COALESCE(v.duration_s,0) > ?
            AND COALESCE(c.subscriber_count,-1) >= ?
          ORDER BY v.published_utc DESC,
                   (COALESCE(v.like_count,0) + COALESCE(v.comment_count,0)) DESC
          LIMIT ${safeLimit}`,
        symbol,
        since,
        YOUTUBE_MIN_DISPLAY_DURATION_SECONDS,
        YOUTUBE_MIN_DISPLAY_SUBSCRIBERS
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

export function xueqiuOps(symbol: string, since: string, limit = 40): RawOp[] {
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

export function tossOps(symbol: string, since: string, limit = 40): RawOp[] {
  const rows = safe(
    () =>
      all<any>(
        `SELECT id, author, title, body, url, COALESCE(likes,0) AS likes,
                COALESCE(comments,0) AS comments, COALESCE(views,0) AS views,
                COALESCE(sentiment,0) AS senti, stance, created_utc AS created
           FROM gr_post
          WHERE source = 'toss' AND ticker = ? AND created_utc >= ?
          ORDER BY (likes + comments + views * 0.02) DESC, created_utc DESC
          LIMIT ${limit | 0}`,
        symbol,
        since
      ),
    []
  );
  return rows.map((r) => {
    const title = stripHtml(String(r.title || ""));
    const body = stripHtml(String(r.body || ""));
    const full = [title, body].filter(Boolean).join("\n");
    const short = title || body.slice(0, 280);
    return {
      id: "toss-" + r.id,
      day: dayOf(r.created),
      source: "toss" as KolSource,
      author: r.author || "Toss",
      interactions: (r.likes || 0) + (r.comments || 0) + Math.round((r.views || 0) * 0.02),
      stance: stanceOf(r.stance, r.senti),
      zh: short,
      en: short,
      url: r.url || "#",
      avatarKey: "",
      refKey: String(r.id),
      orig: full || short,
    };
  });
}

export function yahooJpOps(symbol: string, since: string, limit = 40): RawOp[] {
  const rows = safe(
    () =>
      all<any>(
        `SELECT id, author, title, body, url, COALESCE(likes,0) AS likes,
                COALESCE(dislikes,0) AS dislikes, COALESCE(comments,0) AS comments,
                COALESCE(sentiment,0) AS senti, stance, created_utc AS created, label
           FROM gr_post
          WHERE source = 'yahoo_jp' AND ticker = ? AND created_utc >= ?
          ORDER BY (likes + dislikes + comments) DESC, created_utc DESC
          LIMIT ${limit | 0}`,
        symbol,
        since
      ),
    []
  );
  return rows.map((r) => {
    const title = stripHtml(String(r.title || ""));
    const body = stripHtml(String(r.body || ""));
    const label = stripHtml(String(r.label || ""));
    const full = [title, body].filter(Boolean).join("\n");
    const short = title || body.slice(0, 280);
    return {
      id: "yj-" + r.id,
      day: dayOf(r.created),
      source: "yahoojp" as KolSource,
      author: r.author || "Yahoo JP",
      interactions: (r.likes || 0) + (r.dislikes || 0) + (r.comments || 0),
      stance: stanceOf(r.stance || label, r.senti),
      zh: short,
      en: short,
      url: r.url || "#",
      avatarKey: "",
      refKey: String(r.id),
      orig: full || short,
    };
  });
}

// X / Twitter（云端 tw_* 拉进本地 x_opinion；pipeline/platforms/x/cloud_pull.py）。无情绪标注 → 中性。
export function xOps(symbol: string, since: string, limit = 40): RawOp[] {
  const rows = safe(
    () =>
      all<any>(
        `SELECT tweet_id, handle, text, COALESCE(likes,0) AS likes, COALESCE(retweets,0) AS retweets,
                COALESCE(replies,0) AS replies, COALESCE(quotes,0) AS quotes, COALESCE(views,0) AS views,
                COALESCE(bookmarks,0) AS bookmarks, x.created, x.url,
                COALESCE(q.score,0) AS quality, COALESCE(rel.score,0) AS relevance
           FROM x_opinion x
           JOIN kol_refined kr
             ON kr.source = 'x' AND kr.item_id = x.tweet_id AND kr.ticker = x.ticker
           LEFT JOIN kol_quality q
             ON q.source = 'x' AND q.item_id = x.tweet_id
           LEFT JOIN kol_relevance rel
             ON rel.source = 'x' AND rel.item_id = x.tweet_id AND rel.ticker = x.ticker
          WHERE x.ticker = ? AND x.created >= ? AND x.text NOT GLOB 'RT @*'
          ORDER BY COALESCE(q.score,0) DESC, COALESCE(rel.score,0) DESC,
                   (x.likes + x.retweets + x.replies) DESC, x.created DESC
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
    relevance: Number(r.relevance) || 0,
    quality: Number(r.quality) || 0,
  }));
}

function svDirectionToStance(direction?: string | null): Stance {
  const d = String(direction || "").toLowerCase();
  if (d === "bull") return "bull";
  if (d === "bear") return "bear";
  return "neutral";
}

function svHorizon(bucket?: string | null): { horizon?: Bi; bucket?: KolJudgment["bucket"] } {
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

function svFallbackRelevance(heuristic: number, conviction: number, specificity: number): number {
  const h = Math.max(0, Math.min(1, (heuristic - 46) / 12));
  return Math.round(Math.max(62, Math.min(96, 62 + h * 18 + conviction * 10 + specificity * 6)));
}

function svFallbackQuality(conviction: number, evidence: number, specificity: number): number {
  return Math.round(Math.max(50, Math.min(95, 45 + evidence * 22 + specificity * 18 + conviction * 12)));
}

// SV v0 结构化池中的 X/Twitter call：它来自更长周期的历史推文结构化结果。
// 在产品层仍按 X 展示；只作为 x_opinion 的补充，不暴露 SV 中间概念。
export function xSvOps(symbol: string, since: string, limit = 400): RawOp[] {
  const rows = safe(
    () =>
      all<any>(
        `SELECT cc.candidate_id, cc.tweet_id, cc.author_handle AS handle, cc.text,
                COALESCE(cc.like_count,0) AS likes, COALESCE(cc.retweet_count,0) AS retweets,
                COALESCE(cc.reply_count,0) AS replies, COALESCE(cc.quote_count,0) AS quotes,
                COALESCE(cc.view_count,0) AS views, COALESCE(cc.bookmark_count,0) AS bookmarks,
                COALESCE(cc.interactions,0) AS interactions, COALESCE(cc.heuristic_score,50) AS heuristic_score,
                cc.created_at AS created, COALESCE(cc.created_day, substr(cc.created_at,1,10)) AS day,
                cc.url, c.direction, c.horizon_bucket, c.target_price,
                COALESCE(c.conviction_score,0) AS conviction_score,
                COALESCE(c.evidence_score,0) AS evidence_score,
                COALESCE(c.specificity_score,0) AS specificity_score,
                COALESCE(c.summary_zh,'') AS summary_zh, COALESCE(c.summary_en,'') AS summary_en
           FROM sv_call_candidate cc
           JOIN sv_call c ON c.candidate_id = cc.candidate_id
          WHERE cc.source = 'x'
            AND cc.ticker = ? AND COALESCE(cc.created_day, substr(cc.created_at,1,10)) >= ?
            AND c.is_actionable_call = 1
            AND COALESCE(cc.text,'') NOT GLOB 'RT @*'
          ORDER BY COALESCE(cc.interactions,0) DESC, cc.created_at DESC
          LIMIT ${limit | 0}`,
        symbol,
        since
      ),
    []
  );
  return rows.map((r) => {
    const handle = String(r.handle || "").replace(/^@/, "");
    const text = String(r.text || "");
    const summary: Bi | undefined =
      r.summary_zh || r.summary_en ? { zh: r.summary_zh || r.summary_en, en: r.summary_en || r.summary_zh } : undefined;
    const { horizon, bucket } = svHorizon(r.horizon_bucket);
    const target = Number(r.target_price);
    const judgment: KolJudgment | undefined =
      (Number.isFinite(target) && target > 0)
        ? { sellLo: target, sellHi: target, priceRaw: `$${target}`, horizon, bucket }
        : (horizon ? { horizon, bucket } : undefined);
    const interactions =
      Number(r.interactions) ||
      (Number(r.likes) || 0) + (Number(r.retweets) || 0) + (Number(r.replies) || 0) + (Number(r.quotes) || 0);
    return {
      id: "x-" + r.tweet_id,
      day: String(r.day || dayOf(r.created)),
      source: "x" as KolSource,
      author: handle ? "@" + handle : "@—",
      interactions,
      stance: svDirectionToStance(r.direction),
      zh: summary?.zh || text,
      en: summary?.en || text,
      url: r.url || (handle && r.tweet_id ? `https://x.com/${handle}/status/${r.tweet_id}` : "#"),
      avatarKey: handle,
      refKey: String(r.tweet_id),
      orig: text,
      reason: summary,
      relevance: svFallbackRelevance(Number(r.heuristic_score) || 50, Number(r.conviction_score) || 0, Number(r.specificity_score) || 0),
      quality: svFallbackQuality(Number(r.conviction_score) || 0, Number(r.evidence_score) || 0, Number(r.specificity_score) || 0),
      judgment,
      metrics: {
        replies: Number(r.replies) || 0,
        retweets: Number(r.retweets) || 0,
        likes: Number(r.likes) || 0,
        quotes: Number(r.quotes) || 0,
        views: Number(r.views) || 0,
        bookmarks: Number(r.bookmarks) || 0,
      } as TweetMetrics,
    };
  });
}

function mergeRawOps(ops: RawOp[], limit?: number): RawOp[] {
  const seen = new Set<string>();
  const out: RawOp[] = [];
  for (const op of ops) {
    const key = `${op.source}:${op.refKey || op.id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(op);
  }
  out.sort((a, b) =>
    (b.quality || 0) - (a.quality || 0) ||
    (b.relevance || 0) - (a.relevance || 0) ||
    (b.interactions || 0) - (a.interactions || 0) ||
    (a.day < b.day ? 1 : a.day > b.day ? -1 : 0)
  );
  return typeof limit === "number" ? out.slice(0, limit) : out;
}

export function xMergedOps(symbol: string, since: string, limit = 500): RawOp[] {
  return mergeRawOps([...xSvOps(symbol, since, limit), ...xOps(symbol, since, limit)], limit);
}
