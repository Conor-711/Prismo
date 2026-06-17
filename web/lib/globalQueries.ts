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

// 全部标的代码（标的详情页 generateStaticParams 用），按热度排序。
export function getGrTickerSymbols(): string[] {
  return safe(
    () => all<{ ticker: string }>("SELECT ticker FROM gr_ticker ORDER BY total_posts DESC").map((r) => r.ticker),
    []
  );
}

// 按地区聚合（总览 + 区域总览用）：帖数、覆盖标的、帖数加权情绪/多空、互动合计。
export interface GrRegionSummary {
  region: string;
  posts: number;
  tickers: number;
  avg_sentiment: number;
  bull_pct: number;
  bear_pct: number;
  engagement: number;
}
export function getGrRegionSummary(): GrRegionSummary[] {
  return safe(
    () =>
      all<GrRegionSummary>(
        `SELECT region,
                SUM(post_count) AS posts,
                COUNT(DISTINCT ticker) AS tickers,
                CASE WHEN SUM(post_count) > 0 THEN SUM(sentiment_avg * post_count) / SUM(post_count) ELSE 0 END AS avg_sentiment,
                CASE WHEN SUM(post_count) > 0 THEN SUM(bull_pct * post_count) / SUM(post_count) ELSE 0 END AS bull_pct,
                CASE WHEN SUM(post_count) > 0 THEN SUM(bear_pct * post_count) / SUM(post_count) ELSE 0 END AS bear_pct,
                SUM(COALESCE(engagement, 0)) AS engagement
           FROM gr_ticker_region
          GROUP BY region`
      ),
    []
  );
}

// 单个标的：gr_ticker 主行 + 其各地区分解（标的详情页）。
export interface GrTickerDetail {
  ticker: GrTickerRow | null;
  regions: GrRegionCell[];
}
export function getGrTickerDetail(symbol: string): GrTickerDetail {
  return safe(
    () => {
      const t = get<GrTickerRow>(
        `SELECT ticker, name_en, name_zh, regions_present, total_posts, avg_sentiment, consensus, spread, divergent_region
           FROM gr_ticker WHERE ticker = ?`,
        symbol
      );
      const regions = all<GrRegionCell>(
        `SELECT region, ticker, post_count, sentiment_avg, mood_label, bull_pct, bear_pct, neutral_pct, engagement
           FROM gr_ticker_region WHERE ticker = ? ORDER BY post_count DESC`,
        symbol
      );
      return { ticker: t ?? null, regions };
    },
    { ticker: null, regions: [] }
  );
}

// 单个地区：该区各标的（join 名称），按帖数排序（区域详情页）。
export interface GrRegionTickerRow extends GrRegionCell {
  name_en: string;
  name_zh: string;
}
export function getGrRegionDetail(region: string): GrRegionTickerRow[] {
  return safe(
    () =>
      all<GrRegionTickerRow>(
        `SELECT r.region, r.ticker, r.post_count, r.sentiment_avg, r.mood_label,
                r.bull_pct, r.bear_pct, r.neutral_pct, r.engagement,
                COALESCE(t.name_en, '') AS name_en, COALESCE(t.name_zh, '') AS name_zh
           FROM gr_ticker_region r
           LEFT JOIN gr_ticker t ON t.ticker = r.ticker
          WHERE r.region = ?
          ORDER BY r.post_count DESC`,
        region
      ),
    []
  );
}

// 最新行情（构建期由 pipeline `gr-quote` 从 Yahoo 抓 → gr_quote 表；纯静态站随构建刷新）。
export interface GrQuoteRow {
  ticker: string;
  price: number;
  prev_close: number;
  change_pct: number;
  asof: string | null;
}
export function getGrQuotes(): GrQuoteRow[] {
  return safe(
    () => all<GrQuoteRow>("SELECT ticker, price, prev_close, change_pct, asof FROM gr_quote"),
    []
  );
}
export function getGrQuote(ticker: string): GrQuoteRow | null {
  return safe(
    () => get<GrQuoteRow>(
      "SELECT ticker, price, prev_close, change_pct, asof FROM gr_quote WHERE ticker = ?",
      ticker
    ) ?? null,
    null
  );
}
