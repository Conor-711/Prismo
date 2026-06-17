import { all, get } from "./db";

// 全球散户多区看板（隐藏页 /[lang]/lab/global-retail）取数层。
// 隔离表 gr_*（pipeline 的 gr-crawl/gr-tag/gr-rollup 产出）；US 区由 rollup 读现有 Reddit。
// 所有查询 try/catch 兜表缺失（云端快照未含 gr_* → 返回空，不让构建崩）。

export const GR_REGIONS = ["us", "cn", "jp", "kr", "tw"] as const;
export type GrRegion = (typeof GR_REGIONS)[number];

function safe<T>(fn: () => T, fallback: T): T {
  try { return fn(); } catch { return fallback; }
}

export interface GrTickerRow {
  ticker: string; name_en: string; name_zh: string;
  regions_present: number; total_posts: number; avg_sentiment: number;
  consensus: string; spread: number; divergent_region: string;
}
export function getGrTickers(): GrTickerRow[] {
  return safe(() => all<GrTickerRow>(
    `SELECT ticker, name_en, name_zh, regions_present, total_posts, avg_sentiment,
            consensus, spread, divergent_region
       FROM gr_ticker`
  ), []);
}

export interface GrRegionCell {
  region: string; ticker: string; post_count: number; sentiment_avg: number; mood_label: string;
  bull_pct: number; bear_pct: number; neutral_pct: number; engagement: number;
}
export function getGrTickerRegions(): GrRegionCell[] {
  return safe(() => all<GrRegionCell>(
    `SELECT region, ticker, post_count, sentiment_avg, mood_label,
            bull_pct, bear_pct, neutral_pct, engagement
       FROM gr_ticker_region`
  ), []);
}

export interface GrMeta { tickers: number; posts: number; regions: number; lastUpdated: string | null; }
export function getGrMeta(): GrMeta {
  return safe(() => {
    const c = get<any>(
      `SELECT (SELECT COUNT(*) FROM gr_ticker) AS tickers,
              (SELECT COUNT(*) FROM gr_post) AS posts,
              (SELECT COUNT(DISTINCT region) FROM gr_ticker_region) AS regions`
    );
    const u = get<{ ts: string }>("SELECT MAX(updated_at) AS ts FROM gr_ticker");
    return { tickers: c?.tickers ?? 0, posts: c?.posts ?? 0, regions: c?.regions ?? 0, lastUpdated: u?.ts ?? null };
  }, { tickers: 0, posts: 0, regions: 0, lastUpdated: null });
}

export interface GrPostRow {
  region: string; ticker: string; source: string; author: string; title: string; body: string;
  url: string; likes: number; comments: number; views: number; sentiment: number; stance: string;
  created: string; lang: string;
}

// 日韩台代表帖（来自 gr_post，已 flash 打标）。优先有方向(bull/bear) + 高互动。
export function getGrPosts(region: string, ticker: string, limit = 3): GrPostRow[] {
  return safe(() => {
    const rows = all<any>(
      `SELECT region, ticker, source, author, title, body, url, lang,
              COALESCE(likes,0) likes, COALESCE(comments,0) comments, COALESCE(views,0) views,
              COALESCE(sentiment,0) sentiment, COALESCE(stance,'neutral') stance, created_utc created
         FROM gr_post
        WHERE region = ? AND ticker = ?
        ORDER BY CASE WHEN stance IN ('bull','bear') THEN 0 ELSE 1 END,
                 (likes + comments) DESC, created_utc DESC
        LIMIT ?`,
      region, ticker, limit
    );
    return rows.map((r) => ({
      region: r.region, ticker: r.ticker, source: r.source ?? "", author: r.author ?? "",
      title: r.title ?? "", body: r.body ?? "", url: r.url ?? "", lang: r.lang ?? "",
      likes: r.likes ?? 0, comments: r.comments ?? 0, views: r.views ?? 0,
      sentiment: r.sentiment ?? 0, stance: r.stance ?? "neutral", created: r.created ?? "",
    }));
  }, []);
}

// 美国(US)代表帖：只读现有 Reddit posts/mentions/item_analysis（不污染主管线）。
export function getGrUsPosts(ticker: string, limit = 3): GrPostRow[] {
  return safe(() => {
    const rows = all<any>(
      `SELECT p.id, p.title, p.selftext AS body, p.permalink AS url,
              COALESCE(p.score,0) AS likes, COALESCE(p.num_comments,0) AS comments,
              p.created_utc AS created,
              COALESCE(a.stance,'neutral') AS stance, COALESCE(a.sentiment_score,0) AS sentiment,
              COALESCE(a.tldr_zh, a.tldr, '') AS tldr
         FROM mentions m
         JOIN posts p ON p.id = m.item_id AND m.item_type = 'post' AND p.market = 'us'
         LEFT JOIN item_analysis a ON a.item_id = p.id AND a.item_type = 'post'
        WHERE m.ticker = ?
        ORDER BY p.score DESC
        LIMIT ?`,
      ticker, limit
    );
    return rows.map((r) => ({
      region: "us", ticker, source: "reddit", author: "",
      title: r.title ?? "", body: (r.tldr || r.body || "") as string,
      url: r.url ? `https://www.reddit.com${r.url}` : "",
      likes: r.likes ?? 0, comments: r.comments ?? 0, views: 0,
      sentiment: r.sentiment ?? 0, stance: r.stance ?? "neutral", created: r.created ?? "", lang: "en",
    }));
  }, []);
}
