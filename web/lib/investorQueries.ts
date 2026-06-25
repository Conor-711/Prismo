// 「投资者榜单」取数层：聚合各平台作者，按影响力（互动/播放）排名。真实数据，无 mock。
//   - X：x_opinion 按 handle 聚合（先 DISTINCT tweet，避免同一推被多标的重复计数）；头像走 unavatar/twitter。
//   - YouTube：yt_video 按 channel_id 聚合，主指标=播放量；头像取 author_avatar(source=youtube)。
//   - Reddit：posts ⋈ mentions 的作者，按帖子互动(score+评论)聚合（去重帖，一帖多标的不重复计数）。
//   - 雪球：gr_post(source=xueqiu) 按 author 聚合；只有昵称无 uid → 无外链，头像受 WAF 限制暂缺。
// 库缺失/缺表时各平台返回空数组 → 页面渲染空态（与 output:export 兼容，见 db.ts 兜底）。
import { all } from "./db";
import type { KolSource } from "./mockDetail";

function safe<T>(fn: () => T, fb: T): T {
  try {
    return fn();
  } catch {
    return fb;
  }
}

export interface Investor {
  source: KolSource;
  id: string; // 稳定唯一键（handle / channel_id / author）
  name: string; // 展示名（@handle、频道名、u/name、雪球昵称）
  handle?: string; // 原始 handle/id（拼外链/头像用）
  avatar?: string; // 头像 URL（可空 → 卡片回退首字母）
  url?: string; // 平台主页外链（雪球无 uid → 空）
  metric: number; // 主排名指标：X/Reddit/雪球=互动；YouTube=播放
  posts: number; // 内容条数（帖/视频）
  tickers: string[]; // 覆盖标的（按权重降序，最多 6）
  tickerCount: number; // 覆盖标的总数
}
export interface InvestorBoard {
  x: Investor[];
  youtube: Investor[];
  reddit: Investor[];
  xueqiu: Investor[];
}

interface BaseRow {
  id: string;
  name: string;
  handle?: string;
  url?: string;
  avatar?: string;
  metric: number;
  posts: number;
}
interface BdRow {
  id: string;
  ticker: string;
  weight: number;
}

// 合并「按作者聚合的主指标」与「按作者×标的的权重明细」，按指标降序取前 limit。
function build(source: KolSource, base: BaseRow[], breakdown: BdRow[], limit: number): Investor[] {
  const tk = new Map<string, Map<string, number>>();
  for (const b of breakdown) {
    if (!b.ticker) continue;
    let m = tk.get(b.id);
    if (!m) tk.set(b.id, (m = new Map()));
    m.set(b.ticker, (m.get(b.ticker) ?? 0) + (b.weight || 0));
  }
  return base
    .filter((b) => b.id && b.metric > 0)
    .sort((a, b) => b.metric - a.metric)
    .slice(0, limit)
    .map((b) => {
      const tickers = [...(tk.get(b.id)?.entries() ?? [])].sort((a, c) => c[1] - a[1]).map(([t]) => t);
      return {
        source,
        id: b.id,
        name: b.name,
        handle: b.handle,
        avatar: b.avatar,
        url: b.url,
        metric: b.metric,
        posts: b.posts,
        tickers: tickers.slice(0, 6),
        tickerCount: tickers.length,
      };
    });
}

const LIMIT = 24;

function xInvestors(): Investor[] {
  // 先 DISTINCT tweet（同一条推可能映射到多只标的）→ 真实的「去重互动总量 / 推文数」
  const base = safe(
    () =>
      all<BaseRow>(
        `SELECT handle AS id, ('@' || handle) AS name, handle AS handle,
                SUM(likes + retweets + replies) AS metric, COUNT(*) AS posts
           FROM (SELECT DISTINCT tweet_id, handle, likes, retweets, replies
                   FROM x_opinion WHERE handle IS NOT NULL AND handle <> '')
          GROUP BY handle`
      ),
    []
  );
  const bd = safe(
    () =>
      all<BdRow>(
        `SELECT handle AS id, ticker, SUM(likes + retweets + replies) AS weight
           FROM x_opinion WHERE handle IS NOT NULL AND handle <> '' GROUP BY handle, ticker`
      ),
    []
  );
  for (const b of base) {
    b.url = `https://x.com/${b.handle}`;
    b.avatar = `https://unavatar.io/twitter/${b.handle}`;
  }
  return build("x", base, bd, LIMIT);
}

function youtubeInvestors(): Investor[] {
  const base = safe(
    () =>
      all<BaseRow>(
        `SELECT channel_id AS id, MAX(channel) AS name, channel_id AS handle,
                SUM(view_count) AS metric, COUNT(*) AS posts
           FROM yt_video WHERE channel_id IS NOT NULL AND channel_id <> ''
          GROUP BY channel_id`
      ),
    []
  );
  const bd = safe(
    () =>
      all<BdRow>(
        `SELECT channel_id AS id, ticker, SUM(view_count) AS weight
           FROM yt_video WHERE channel_id <> '' GROUP BY channel_id, ticker`
      ),
    []
  );
  const av = safe(
    () => all<{ handle: string; url: string }>(`SELECT handle, url FROM author_avatar WHERE source = 'youtube' AND url <> ''`),
    []
  );
  const avMap = new Map(av.map((a) => [a.handle, a.url]));
  for (const b of base) {
    b.url = `https://www.youtube.com/channel/${b.handle}`;
    b.avatar = avMap.get(b.handle ?? "");
  }
  return build("youtube", base, bd, LIMIT);
}

function redditInvestors(): Investor[] {
  // 仅计入提到目标标的的帖子；按 author 去重帖聚合互动（EXISTS 避免一帖多标的把互动翻倍）
  const base = safe(
    () =>
      all<BaseRow>(
        `SELECT p.author_id AS id, ('u/' || p.author_id) AS name, p.author_id AS handle,
                SUM(p.score + p.num_comments) AS metric, COUNT(*) AS posts
           FROM posts p
          WHERE p.author_id IS NOT NULL AND p.author_id <> '[deleted]'
            AND EXISTS (SELECT 1 FROM mentions m WHERE m.item_id = p.id AND m.item_type = 'post')
          GROUP BY p.author_id`
      ),
    []
  );
  const bd = safe(
    () =>
      all<BdRow>(
        `SELECT p.author_id AS id, m.ticker AS ticker, SUM(p.score + p.num_comments) AS weight
           FROM posts p JOIN mentions m ON m.item_id = p.id AND m.item_type = 'post'
          WHERE p.author_id IS NOT NULL AND p.author_id <> '[deleted]'
          GROUP BY p.author_id, m.ticker`
      ),
    []
  );
  for (const b of base) b.url = `https://www.reddit.com/user/${b.handle}`;
  return build("reddit", base, bd, LIMIT);
}

function xueqiuInvestors(): Investor[] {
  const base = safe(
    () =>
      all<BaseRow>(
        `SELECT author AS id, author AS name, author AS handle,
                SUM(likes + comments) AS metric, COUNT(*) AS posts
           FROM gr_post WHERE source = 'xueqiu' AND author <> '' GROUP BY author`
      ),
    []
  );
  const bd = safe(
    () =>
      all<BdRow>(
        `SELECT author AS id, ticker, SUM(likes + comments) AS weight
           FROM gr_post WHERE source = 'xueqiu' AND author <> '' GROUP BY author, ticker`
      ),
    []
  );
  return build("xueqiu", base, bd, LIMIT);
}

export function getInvestorBoard(): InvestorBoard {
  return {
    x: xInvestors(),
    youtube: youtubeInvestors(),
    reddit: redditInvestors(),
    xueqiu: xueqiuInvestors(),
  };
}
