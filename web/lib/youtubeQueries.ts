import { all, get, parseJSON } from "./db";

// 「YouTube 观点」取数层：隔离表 yt_*（pipeline youtube-crawl / youtube-tag 产出）。
// 与其它隐藏表一样 try/catch 兜底——快照缺表 → 返回空，标的页该模块不渲染，构建不崩。

function safe<T>(fn: () => T, fallback: T): T {
  try { return fn(); } catch { return fallback; }
}

export interface YtSummaryRow {
  ticker: string; video_count: number; analyzed_count: number;
  bull_count: number; bear_count: number; neutral_count: number;
  net_sentiment: number; mood_label: string; total_views: number; updated_at: string;
}
export function getYtSummary(ticker: string, market = "us"): YtSummaryRow | null {
  return safe(() => get<YtSummaryRow>(
    `SELECT ticker, video_count, analyzed_count, bull_count, bear_count, neutral_count,
            net_sentiment, mood_label, total_views, updated_at
       FROM yt_ticker_summary WHERE ticker = ? AND market = ?`, ticker, market) ?? null, null);
}

export interface YtVideoRow {
  id: string; channel: string; title: string; lang: string; duration_s: number;
  view_count: number; like_count: number; thumbnail: string; url: string; published: string;
  stance: string; sentiment: number; conviction: number; summary_zh: string; summary_en: string;
  key_points_zh: string[]; key_points_en: string[]; price_target: string | null; mode: string;
}
export function getYtVideos(ticker: string, limit = 8): YtVideoRow[] {
  return safe(() => all<any>(
    `SELECT v.id, v.channel, v.title, v.lang, v.duration_s, v.view_count, v.like_count,
            v.thumbnail, v.url, v.published_utc AS published,
            a.stance, a.sentiment, a.conviction, a.summary_zh, a.summary_en,
            a.key_points_zh, a.key_points_en, a.price_target, a.mode
       FROM yt_video v JOIN yt_analysis a ON a.video_id = v.id
      WHERE v.ticker = ?
      ORDER BY v.view_count DESC LIMIT ?`, ticker, limit
  ).map((r) => ({
    id: r.id, channel: r.channel ?? "", title: r.title ?? "", lang: r.lang ?? "",
    duration_s: r.duration_s ?? 0, view_count: r.view_count ?? 0, like_count: r.like_count ?? 0,
    thumbnail: r.thumbnail ?? "", url: r.url ?? "", published: r.published ?? "",
    stance: r.stance ?? "neutral", sentiment: r.sentiment ?? 0, conviction: r.conviction ?? 0,
    summary_zh: r.summary_zh ?? "", summary_en: r.summary_en ?? "",
    key_points_zh: parseJSON<string[]>(r.key_points_zh, []),
    key_points_en: parseJSON<string[]>(r.key_points_en, []),
    price_target: r.price_target ?? null, mode: r.mode ?? "video",
  })), []);
}
