import { all, parseJSON } from "@/lib/db";
import type { Bi, KolJudgment, TweetReply, YtChannel, YtDigest } from "@/shared/market/mockDetail";
import { bucketHorizon, currentPrice, parseRange, safe, stanceOf, type Refined } from "./shared";

export function refinedMap(symbol: string): Map<string, Refined> {
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
export function viewpointMap(symbol: string): Map<string, string[]> {
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

// author_avatar（pipeline/platforms/author_assets/avatars.py 爬取）→ "source:handle" -> url
export function avatarMap(): Map<string, string> {
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

// yt_channel（pipeline/platforms/youtube/channels.py 爬取）→ channel_id -> 作者基础信息（粉丝/视频/简介/@handle）
export function ytChannelMap(): Map<string, YtChannel> {
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

// yt_digest（pipeline/domain/opinions/youtube_digest.py 产出）→ video_id -> 投资者摘要 + 内容目录(章节)
export function ytDigestMap(): Map<string, YtDigest> {
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

export function relevanceMap(symbol: string): Map<string, number> {
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
export function qualityMap(): Map<string, number> {
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
export function judgmentMap(symbol: string): Map<string, KolJudgment> {
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
  // reddit / x / 雪球 / Toss / Yahoo JP：kol_judgment（买入/卖出 各 lo/hi + bucket 来自 LLM）
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

// x_reply（pipeline/platforms/x/cloud_pull.py 产出）：parent tweet_id -> 该推文下点赞最高的前 K 条评论。
// 只 join 本标的的 x_opinion 取该 ticker 下的评论；头像走 unavatar/twitter 兜底（同主推文）。
export function repliesByTweet(symbol: string): Map<string, TweetReply[]> {
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
