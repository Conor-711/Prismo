import { all, get, parseJSON } from "./db";

export interface MoodRow {
  mood_score: number; label: string; bull_pct: number; bear_pct: number;
  neutral_pct: number; total_mentions: number; total_posts: number; bucket_ts: string;
}
export interface MindRow {
  ticker: string; name: string; sector: string | null; mindshare: number;
  sentiment: number; mentions: number; posts: number; authors: number;
  bull: number; bear: number; neutral: number;
}
export interface TrendRow {
  ticker: string; name: string; rank: number; mentions: number; zscore: number;
  sentiment: number; spike: number; baseline: number;
}
export interface FeedRow {
  id: string; title: string; title_zh: string; selftext: string; permalink: string; subreddit: string;
  flair: string | null; score: number; comments: number; created: string; author: string | null;
  stance: string; sentiment: number; quality: number; tldr: string; tldr_zh: string;
  themes: string[]; tickers: { ticker: string; relevance: number }[];
}
export interface NarrativeRow {
  id: number; slug: string; name: string; summary: string; post_count: number;
  ticker_count: number; heat: number; sentiment: number; tickers: { ticker: string; weight: number }[];
}
export interface SentLeader {
  ticker: string; name: string; sentiment: number; mentions: number; bull: number; bear: number;
}

export function getMeta(market = "us") {
  const m = get<{ ts: string }>(
    "SELECT bucket_ts AS ts FROM market_mood WHERE bucket='window' AND market=? LIMIT 1",
    market
  );
  const counts = get<{ posts: number; mentions: number; tickers: number }>(
    `SELECT (SELECT COUNT(*) FROM posts WHERE market=? AND source='scan') AS posts,
            (SELECT COUNT(*) FROM mentions mm JOIN posts p ON p.id=mm.item_id WHERE p.market=? AND p.source='scan') AS mentions,
            (SELECT COUNT(DISTINCT ticker) FROM ticker_rollup WHERE bucket='window' AND market=?) AS tickers`,
    market, market, market
  );
  return { lastUpdated: m?.ts ?? null, ...(counts ?? { posts: 0, mentions: 0, tickers: 0 }) };
}

// 首页「数据可信度」模块用：全站真实数据规模（不分 market），每天 08:00 分析后刷新。
// 用真实计数（已分析帖子 / 评论 / 提及 / 标的 / 社区 / 作者）增强网站可信度。
export interface DataStats {
  posts: number; analyzedPosts: number; comments: number; mentions: number;
  tickers: number; communities: number; authors: number; lastUpdated: string | null;
}
export function getDataStats(): DataStats {
  const c = get<Omit<DataStats, "lastUpdated">>(
    `SELECT (SELECT COUNT(*) FROM posts) AS posts,
            (SELECT COUNT(*) FROM item_analysis WHERE item_type='post') AS analyzedPosts,
            (SELECT COUNT(*) FROM comments) AS comments,
            (SELECT COUNT(*) FROM mentions) AS mentions,
            (SELECT COUNT(DISTINCT ticker) FROM mentions) AS tickers,
            (SELECT COUNT(*) FROM subreddits WHERE COALESCE(tracked,1)=1) AS communities,
            (SELECT COUNT(DISTINCT author_id) FROM posts WHERE author_id IS NOT NULL) AS authors`
  );
  const upd = get<{ ts: string }>("SELECT MAX(bucket_ts) AS ts FROM market_mood WHERE bucket='window'");
  return {
    posts: c?.posts ?? 0, analyzedPosts: c?.analyzedPosts ?? 0, comments: c?.comments ?? 0,
    mentions: c?.mentions ?? 0, tickers: c?.tickers ?? 0, communities: c?.communities ?? 0,
    authors: c?.authors ?? 0, lastUpdated: upd?.ts ?? null,
  };
}

export function getMarketMood(market = "us"): MoodRow | undefined {
  return get<MoodRow>("SELECT * FROM market_mood WHERE bucket='window' AND market=? LIMIT 1", market);
}

export function getMindshare(limit = 24, market = "us"): MindRow[] {
  return all<MindRow>(
    `SELECT r.ticker, COALESCE(tm.company_name,'') AS name, tm.sector AS sector,
            r.mindshare_pct AS mindshare, r.sentiment_avg AS sentiment,
            r.mention_count AS mentions, r.post_count AS posts, r.unique_authors AS authors,
            r.bull_count AS bull, r.bear_count AS bear, r.neutral_count AS neutral
       FROM ticker_rollup r LEFT JOIN ticker_meta tm ON tm.ticker = r.ticker
      WHERE r.bucket='window' AND r.market=?
      ORDER BY r.mindshare_pct DESC LIMIT ?`,
    market, limit
  );
}

// 多空风向标：窗口内情绪最强（最看多）与最负（最看空）的标的，过滤样本过少的噪音。
export function getSentimentLeaders(market = "us", n = 5, minMentions = 2): { bullish: SentLeader[]; bearish: SentLeader[] } {
  const base =
    `SELECT r.ticker, COALESCE(tm.company_name,'') AS name, r.sentiment_avg AS sentiment,
            r.mention_count AS mentions, r.bull_count AS bull, r.bear_count AS bear
       FROM ticker_rollup r LEFT JOIN ticker_meta tm ON tm.ticker = r.ticker
      WHERE r.bucket='window' AND r.market=? AND r.mention_count >= ?`;
  const bullish = all<SentLeader>(
    base + " AND r.sentiment_avg > 0.05 ORDER BY r.sentiment_avg DESC, r.mention_count DESC LIMIT ?",
    market, minMentions, n
  );
  const bearish = all<SentLeader>(
    base + " AND r.sentiment_avg < -0.05 ORDER BY r.sentiment_avg ASC, r.mention_count DESC LIMIT ?",
    market, minMentions, n
  );
  return { bullish, bearish };
}

export function getTreemap(limit = 30, market = "us") {
  return getMindshare(limit, market).map((r) => ({
    ticker: r.ticker, name: r.name, value: r.mindshare,
    sentiment: r.sentiment, sector: r.sector ?? "其他", mentions: r.mentions,
  }));
}

export function getTrending(limit = 12, onlySpikes = false, market = "us"): TrendRow[] {
  return all<TrendRow>(
    `SELECT t.ticker, COALESCE(tm.company_name,'') AS name, t.rank, t.mention_count AS mentions,
            t.zscore, t.sentiment_avg AS sentiment, t.is_spike AS spike, t.baseline_mean AS baseline
       FROM trending t LEFT JOIN ticker_meta tm ON tm.ticker = t.ticker
      WHERE t.window='24h' AND t.market=? ${onlySpikes ? "AND t.is_spike=1" : ""}
      ORDER BY t.rank LIMIT ?`,
    market, limit
  );
}

export function getNarratives(limit = 12, market = "us"): NarrativeRow[] {
  const narrs = all<Omit<NarrativeRow, "tickers">>(
    `SELECT n.id, n.slug, n.name, n.summary, n.post_count, n.ticker_count, n.heat,
            COALESCE((SELECT AVG(ia.sentiment_score) FROM narrative_posts np
                      JOIN item_analysis ia ON ia.item_id = np.post_id AND ia.item_type='post'
                      WHERE np.narrative_id = n.id), 0) AS sentiment
       FROM narratives n WHERE n.market=? ORDER BY n.heat DESC LIMIT ?`,
    market, limit
  );
  const links = all<{ narrative_id: number; ticker: string; weight: number }>(
    "SELECT narrative_id, ticker, weight FROM narrative_tickers ORDER BY weight DESC"
  );
  return narrs.map((n) => ({
    ...n,
    tickers: links.filter((l) => l.narrative_id === n.id).map((l) => ({ ticker: l.ticker, weight: l.weight })),
  }));
}

function mapFeed(rows: any[]): FeedRow[] {
  return rows.map((r) => ({
    id: r.id, title: r.title, title_zh: r.title_zh ?? "", selftext: r.selftext ?? "", permalink: r.permalink,
    subreddit: r.subreddit_id, flair: r.flair, score: r.score, comments: r.num_comments,
    created: r.created_utc, author: r.author_id, stance: r.stance ?? "neutral",
    sentiment: r.sentiment_score ?? 0, quality: r.quality_score ?? 0, tldr: r.tldr ?? "", tldr_zh: r.tldr_zh ?? "",
    themes: parseJSON<string[]>(r.themes, []),
    tickers: parseJSON<{ ticker: string; relevance: number }[]>(r.tickers, []),
  }));
}

export function getFeed(opts: { limit?: number; ticker?: string; subreddit?: string; stance?: string; market?: string } = {}): FeedRow[] {
  const { limit = 30, ticker, subreddit, stance, market = "us" } = opts;
  // p.source='scan'：作者库历史帖（source='author'）只进作者页，不进实时舆情 feed。
  const where: string[] = ["ia.item_type='post'", "p.market = ?", "p.source='scan'"];
  const params: unknown[] = [market];
  if (subreddit) { where.push("p.subreddit_id = ?"); params.push(subreddit); }
  if (stance) { where.push("ia.stance = ?"); params.push(stance); }
  if (ticker) {
    where.push("p.id IN (SELECT item_id FROM mentions WHERE item_type='post' AND ticker = ?)");
    params.push(ticker);
  }
  params.push(limit);
  const rows = all(
    `SELECT p.id, p.title, p.title_zh, p.selftext, p.permalink, p.subreddit_id, p.flair, p.score,
            p.num_comments, p.created_utc, p.author_id,
            ia.stance, ia.sentiment_score, ia.quality_score, ia.tldr, ia.tldr_zh, ia.themes, ia.tickers
       FROM posts p JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
      WHERE ${where.join(" AND ")}
      ORDER BY ia.quality_score DESC, p.score DESC LIMIT ?`,
    ...params
  );
  return mapFeed(rows);
}

// 今日 Reddit Alpha：过去 24 小时（以库内最新帖为基准）社区含金量最高的信号。
// 取有明确标的、有 TL;DR、且带多空论点的高质量帖；附最强的一条多/空论点作为「核心 alpha」。
export interface AlphaRow extends FeedRow {
  bull: string[];
  bear: string[];
  edge: string; // 最具代表性的一条论点（多优先，其次空）
  title_zh: string;
  bull_zh: string[];
  bear_zh: string[];
  edge_zh: string;
}
export function getTodaysAlpha(limit = 3, market = "us"): AlphaRow[] {
  const rows = all(
    `SELECT p.id, p.title, p.title_zh, p.selftext, p.permalink, p.subreddit_id, p.flair, p.score,
            p.num_comments, p.created_utc, p.author_id,
            ia.stance, ia.sentiment_score, ia.quality_score, ia.tldr, ia.tldr_zh, ia.themes, ia.tickers,
            ia.bull_points, ia.bear_points, ia.bull_points_zh, ia.bear_points_zh
       FROM posts p JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
      WHERE p.market = ? AND p.source='scan'
        AND p.created_utc >= datetime((SELECT MAX(created_utc) FROM posts WHERE market=?), '-1 day')
        AND ia.tldr IS NOT NULL AND ia.tldr <> ''
        AND json_array_length(COALESCE(NULLIF(ia.tickers,''),'[]')) > 0
      ORDER BY ia.quality_score DESC, p.score DESC
      LIMIT ?`,
    market, market, limit * 8
  );
  // 去重：同一篇 DD 常被 crosspost 到 wsb/investing/valueinvesting 等多个版块（标题相同）→
  // 只保留质量最高的一条，保证三条 Alpha 是三个不同的故事，而非同一帖的多个副本。
  const seen = new Set<string>();
  const picked: any[] = [];
  for (const r of rows) {
    const key = String(r.title || "").trim().toLowerCase().replace(/\s+/g, " ");
    if (key && seen.has(key)) continue;
    seen.add(key);
    picked.push(r);
    if (picked.length >= limit) break;
  }
  return mapFeed(picked).map((f, i) => {
    const r = picked[i] as any;
    const bull = parseJSON<string[]>(r.bull_points, []);
    const bear = parseJSON<string[]>(r.bear_points, []);
    const edge = (f.stance === "bear" ? bear[0] : bull[0]) || bull[0] || bear[0] || f.tldr;
    const bull_zh = parseJSON<string[]>(r.bull_points_zh, []);
    const bear_zh = parseJSON<string[]>(r.bear_points_zh, []);
    const title_zh = r.title_zh || "";
    const edge_zh = (f.stance === "bear" ? bear_zh[0] : bull_zh[0]) || bull_zh[0] || bear_zh[0] || f.tldr_zh;
    return { ...f, bull, bear, edge, title_zh, bull_zh, bear_zh, edge_zh };
  });
}

export function getAllTickerSymbols(): string[] {
  // 美股个股页只为美股标的建静态页（排除中概/港股专属标的）。
  return all<{ ticker: string }>(
    "SELECT ticker FROM ticker_meta WHERE market IS NULL OR market <> 'cn'"
  ).map((r) => r.ticker);
}

// 中概·港股个股页静态参数：在 cn 窗口内有讨论（rollup 行）的标的。
export function getAllCnTickerSymbols(): string[] {
  // generateStaticParams 用：必须在「有任何 cn 数据」时非空，否则 output:export 会把
  // 空数组的动态路由当成「缺 generateStaticParams」而构建失败（Railway 上 cn 窗口为空即触发）。
  // 取并集：① 策划的中概/港股/A 股字典(ticker_meta.market='cn') ② cn 市场帖子里被提及的标的(含 ADR)。
  return all<{ ticker: string }>(
    `SELECT ticker FROM ticker_meta WHERE market='cn'
     UNION
     SELECT DISTINCT m.ticker FROM mentions m
       JOIN posts p ON p.id = m.item_id AND p.market='cn'`
  ).map((r) => r.ticker);
}

// 搜索页用：真正「有数据」的标的（在该市场至少被一篇帖子提及）。
// 既是输入校验集（搜不到/数据不足 → 跳提示页），也是「猜你想搜」建议与名称映射来源。
export interface SearchableTicker { ticker: string; name: string; posts: number }
export function getSearchableTickers(market = "us"): SearchableTicker[] {
  return all<SearchableTicker>(
    `SELECT m.ticker, COALESCE(tm.company_name,'') AS name, COUNT(DISTINCT m.item_id) AS posts
       FROM mentions m
       JOIN posts p ON p.id = m.item_id AND p.market = ? AND p.source='scan'
       LEFT JOIN ticker_meta tm ON tm.ticker = m.ticker
      WHERE m.item_type='post'
      GROUP BY m.ticker
      ORDER BY posts DESC`,
    market
  );
}

// 排行榜兜底：未配置 Supabase（或全局搜索榜为空）时，用真实社区热度（被讨论的帖子数 + 情绪）。
export interface HeatRow { ticker: string; name: string; mentions: number; sentiment: number }
export function getSearchHeat(limit = 10, market = "us"): HeatRow[] {
  return all<HeatRow>(
    `SELECT m.ticker, COALESCE(tm.company_name,'') AS name,
            COUNT(DISTINCT m.item_id) AS mentions,
            COALESCE(AVG(ia.sentiment_score), 0) AS sentiment
       FROM mentions m
       JOIN posts p ON p.id = m.item_id AND p.market = ? AND p.source='scan'
       LEFT JOIN ticker_meta tm ON tm.ticker = m.ticker
       LEFT JOIN item_analysis ia ON ia.item_id = m.item_id AND ia.item_type='post'
      WHERE m.item_type='post'
      GROUP BY m.ticker
      ORDER BY mentions DESC
      LIMIT ?`,
    market, limit
  );
}

// ---------- 全站搜索（合并美股 + 中概/港股/A 股，一个入口搜全部） ----------
// 每个标的按「实际存在的个股页」打 market 标，路由到 /ticker（美股）或 /cn/ticker（中概港股），
// 避免把仅有中概页的标的（如 BABA/NIO，ticker_meta.market='cn'）错误指向不存在的美股页而 404。
export interface GlobalTicker { ticker: string; name: string; posts: number; market: string }
export interface GlobalHeat extends HeatRow { market: string }

// 选出该标的应落在哪个市场的个股页（页面真实存在才返回；prefer 决定同名时优先哪边）。
function _pageMarket(ticker: string, usPages: Set<string>, cnPages: Set<string>, prefer: "us" | "cn"): string | null {
  if (prefer === "us") return usPages.has(ticker) ? "us" : cnPages.has(ticker) ? "cn" : null;
  return cnPages.has(ticker) ? "cn" : usPages.has(ticker) ? "us" : null;
}

export function getGlobalSearchableTickers(): GlobalTicker[] {
  const usPages = new Set(getAllTickerSymbols());
  const cnPages = new Set(getAllCnTickerSymbols());
  const byTicker = new Map<string, GlobalTicker>();
  const reg = (x: SearchableTicker, prefer: "us" | "cn") => {
    const market = _pageMarket(x.ticker, usPages, cnPages, prefer);
    if (!market) return; // 没有对应个股页 → 不放进可搜集合（避免点进去 404）
    const ex = byTicker.get(x.ticker);
    if (!ex) byTicker.set(x.ticker, { ticker: x.ticker, name: x.name, posts: x.posts, market });
    else ex.posts += x.posts; // 跨市场讨论量累加；市场口径保留首次选定（页面存在）
  };
  for (const x of getSearchableTickers("us")) reg(x, "us");
  for (const x of getSearchableTickers("cn")) reg(x, "cn");
  return [...byTicker.values()].sort((a, b) => b.posts - a.posts);
}

export function getGlobalSearchHeat(limit = 10): GlobalHeat[] {
  const usPages = new Set(getAllTickerSymbols());
  const cnPages = new Set(getAllCnTickerSymbols());
  const byTicker = new Map<string, GlobalHeat>();
  const add = (x: HeatRow, prefer: "us" | "cn") => {
    const market = _pageMarket(x.ticker, usPages, cnPages, prefer);
    if (!market) return;
    const ex = byTicker.get(x.ticker);
    if (!ex) { byTicker.set(x.ticker, { ...x, market }); return; }
    const total = ex.mentions + x.mentions;
    ex.sentiment = total ? (ex.sentiment * ex.mentions + x.sentiment * x.mentions) / total : 0;
    ex.mentions = total;
  };
  for (const x of getSearchHeat(200, "us")) add(x, "us");
  for (const x of getSearchHeat(200, "cn")) add(x, "cn");
  return [...byTicker.values()].sort((a, b) => b.mentions - a.mentions).slice(0, limit);
}

export interface CommentRow {
  id: string; author: string | null; body: string; body_zh: string; score: number; created: string; parent: string | null;
}

export function getAllPostIds(): string[] {
  return all<{ id: string }>("SELECT id FROM posts").map((r) => r.id);
}

// 站内帖子详情：正文 + AI 摘要 + 评论（按分数排，含父子关系）。供 /post/[id] 渲染，不跳 Reddit。
export function getPostDetail(id: string) {
  const post = get<{
    id: string; title: string; title_zh: string; selftext: string; selftext_zh: string; selftext_fmt: string; permalink: string; subreddit: string;
    author: string | null; score: number; comments: number; created: string; flair: string | null; upvote_ratio: number;
  }>(
    `SELECT p.id, p.title, p.title_zh, p.selftext, p.selftext_zh, p.selftext_fmt, p.permalink, p.subreddit_id AS subreddit, p.author_id AS author,
            p.score, p.num_comments AS comments, p.created_utc AS created, p.flair, p.upvote_ratio
       FROM posts p WHERE p.id = ?`,
    id
  );
  if (!post) return null;

  const a = get<{
    stance: string; sentiment_score: number; quality_score: number; tldr: string; tldr_zh: string;
    themes: string; tickers: string; bull_points: string; bear_points: string; bull_points_zh: string; bear_points_zh: string;
  }>(
    `SELECT stance, sentiment_score, quality_score, tldr, tldr_zh, themes, tickers, bull_points, bear_points, bull_points_zh, bear_points_zh
       FROM item_analysis WHERE item_id = ? AND item_type='post'`,
    id
  );
  const analysis = a
    ? {
        stance: a.stance ?? "neutral",
        sentiment: a.sentiment_score ?? 0,
        quality: a.quality_score ?? 0,
        tldr: a.tldr ?? "",
        tldr_zh: a.tldr_zh ?? "",
        themes: parseJSON<string[]>(a.themes, []),
        tickers: parseJSON<{ ticker: string; relevance: number }[]>(a.tickers, []),
        bull: parseJSON<string[]>(a.bull_points, []),
        bear: parseJSON<string[]>(a.bear_points, []),
        bull_zh: parseJSON<string[]>(a.bull_points_zh, []),
        bear_zh: parseJSON<string[]>(a.bear_points_zh, []),
      }
    : null;

  const comments = all<CommentRow>(
    `SELECT id, author_id AS author, body, body_zh, score, created_utc AS created, parent_id AS parent
       FROM comments WHERE post_id = ? ORDER BY score DESC`,
    id
  );

  return { post, analysis, comments };
}

export function getTickerList(market = "us"): { ticker: string; name: string; mindshare: number }[] {
  return all(
    `SELECT r.ticker, COALESCE(tm.company_name,'') AS name, r.mindshare_pct AS mindshare
       FROM ticker_rollup r LEFT JOIN ticker_meta tm ON tm.ticker=r.ticker
      WHERE r.bucket='window' AND r.market=? ORDER BY r.mindshare_pct DESC`,
    market
  );
}

export function getTickerDetail(symbol: string, market = "us") {
  const ticker = symbol.toUpperCase();
  const meta = get<{ ticker: string; company_name: string; sector: string; exchange: string }>(
    "SELECT ticker, company_name, sector, exchange FROM ticker_meta WHERE ticker = ?",
    ticker
  );
  const roll = get<MindRow & { weighted: number; engagement: number }>(
    `SELECT r.ticker, COALESCE(tm.company_name,'') AS name, tm.sector,
            r.mindshare_pct AS mindshare, r.sentiment_avg AS sentiment, r.mention_count AS mentions,
            r.post_count AS posts, r.unique_authors AS authors, r.bull_count AS bull,
            r.bear_count AS bear, r.neutral_count AS neutral, r.weighted_mentions AS weighted,
            r.engagement_sum AS engagement
       FROM ticker_rollup r LEFT JOIN ticker_meta tm ON tm.ticker=r.ticker
      WHERE r.bucket='window' AND r.market=? AND r.ticker = ?`,
    market, ticker
  );
  const series = all<{ ts: string; mentions: number; sentiment: number }>(
    `SELECT bucket_ts AS ts, mention_count AS mentions, sentiment_avg AS sentiment
       FROM ticker_rollup WHERE bucket='hour' AND market=? AND ticker = ? ORDER BY bucket_ts ASC`,
    market, ticker
  );
  const bySub = all<{ subreddit: string; n: number }>(
    `SELECT m.subreddit_id AS subreddit, COUNT(*) AS n FROM mentions m
       JOIN posts p ON p.id=m.item_id AND p.market=? AND p.source='scan'
      WHERE m.item_type='post' AND m.ticker = ? GROUP BY m.subreddit_id ORDER BY n DESC`,
    market, ticker
  );
  const posts = mapFeed(
    all(
      `SELECT p.id, p.title, p.title_zh, p.selftext, p.permalink, p.subreddit_id, p.flair, p.score,
              p.num_comments, p.created_utc, p.author_id,
              ia.stance, ia.sentiment_score, ia.quality_score, ia.tldr, ia.tldr_zh, ia.themes, ia.tickers
         FROM posts p JOIN mentions m ON m.item_id=p.id AND m.item_type='post'
         LEFT JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
        WHERE m.ticker = ? AND p.market=? AND p.source='scan' ORDER BY p.created_utc DESC LIMIT 48`,
      ticker, market
    )
  );
  // 多空论点：**按标的归属**汇集，杜绝跨标的错配（如把 GOOG 抢份额当成 AAPL 看多）。
  // 优先用 AI 给出的 per-ticker 论据（tickers JSON 内每只股票自带的 bull/bear_points）；
  // 仅当帖子是单标的、且尚无 per-ticker 拆分（旧数据）时，才回退到帖级论点（此时无歧义）。
  type Point = { id: string; point: string; point_zh: string; permalink: string; title: string };
  const bull: Point[] = [];
  const bear: Point[] = [];
  const push = (arr: Point[], pts: string[], zhs: string[], p: { id: string; permalink: string; title: string }) =>
    pts.forEach((pt, i) => pt && arr.push({ id: p.id, point: pt, point_zh: zhs[i] || "", permalink: p.permalink, title: p.title }));
  for (const p of posts) {
    const a = get<{ tickers: string; bull_points: string; bear_points: string; bull_points_zh: string; bear_points_zh: string }>(
      "SELECT tickers, bull_points, bear_points, bull_points_zh, bear_points_zh FROM item_analysis WHERE item_id=? AND item_type='post'",
      p.id
    );
    const entries = parseJSON<any[]>(a?.tickers, []);
    const entry = entries.find((e) => e && e.ticker === ticker);
    const hasPerTicker = entry && (Array.isArray(entry.bull_points) || Array.isArray(entry.bear_points));
    if (hasPerTicker) {
      // 该标的专属论据（AI 已逐条归属到本股票）
      push(bull, (entry.bull_points || []) as string[], (entry.bull_points_zh || []) as string[], p);
      push(bear, (entry.bear_points || []) as string[], (entry.bear_points_zh || []) as string[], p);
    } else if (entries.length <= 1) {
      // 旧数据 + 单标的：帖级论点必然属于该标的，无错配风险
      push(bull, parseJSON<string[]>(a?.bull_points, []), parseJSON<string[]>(a?.bull_points_zh, []), p);
      push(bear, parseJSON<string[]>(a?.bear_points, []), parseJSON<string[]>(a?.bear_points_zh, []), p);
    }
    // 否则（多标的且无 per-ticker 拆分）：跳过，宁缺毋错
  }
  const narrs = all<NarrativeRow>(
    `SELECT n.id, n.slug, n.name, n.summary, n.post_count, n.ticker_count, n.heat
       FROM narratives n JOIN narrative_tickers nt ON nt.narrative_id=n.id
      WHERE nt.ticker = ? AND n.market = ? ORDER BY n.heat DESC`,
    ticker, market
  ).map((n) => ({ ...n, tickers: [] as { ticker: string; weight: number }[] }));

  // 可信声音：讨论该标的的作者，按内容质量 × 影响力排（类比 TipRanks 排分析师）
  const voices = all<{ author: string; posts: number; score: number; quality: number; sentiment: number }>(
    `SELECT p.author_id AS author, COUNT(*) AS posts, COALESCE(SUM(p.score),0) AS score,
            AVG(ia.quality_score) AS quality, AVG(ia.sentiment_score) AS sentiment
       FROM posts p JOIN mentions m ON m.item_id=p.id AND m.item_type='post' AND m.ticker = ?
       LEFT JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
      WHERE p.author_id IS NOT NULL AND p.market = ? AND p.source='scan'
      GROUP BY p.author_id
      ORDER BY AVG(ia.quality_score) DESC, SUM(p.score) DESC
      LIMIT 6`,
    ticker, market
  ).map((v) => ({ ...v, quality: v.quality ?? 0, sentiment: v.sentiment ?? 0 }));

  // 催化剂 / 主题：从相关帖聚合（社区在盯什么）
  const themeCount = new Map<string, number>();
  for (const p of posts) for (const t of p.themes) themeCount.set(t, (themeCount.get(t) || 0) + 1);
  const themes = [...themeCount.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([name, count]) => ({ name, count }));

  return { ticker, meta, roll, series, bySub, posts, bull: bull.slice(0, 6), bear: bear.slice(0, 6), narratives: narrs, voices, themes };
}

export function getDailyBrief() {
  const b = get<{ brief_date: string; title: string; markdown: string; highlights: string; model: string }>(
    "SELECT brief_date, title, markdown, highlights, model FROM daily_briefs ORDER BY brief_date DESC LIMIT 1"
  );
  if (!b) return undefined;
  return { ...b, highlights: parseJSON<string[]>(b.highlights, []) };
}

// 作者「实力榜」——发掘下一个 Reddit 股神。
// Alpha Score(0-100) = 综合四维实力：
//   ① DD 质量 (AI quality_score 均值, 30%) —— 研究有多深、多靠谱
//   ② 社区影响力 (赞 + 2×评论，取对数后归一, 30%) —— 社区有多买账
//   ③ 立场鲜明度 ((看多+看空)/总帖, 20%) —— 敢不敢下明确判断(股神特质)
//   ④ 持续产出 (帖子数取对数后归一, 20%) —— 战绩样本/活跃度
// 仅基于「内容质量 + 社区验证」，非真实盈亏(无价格回测)。
export interface AuthorRow {
  author: string;
  posts: number;
  upvotes: number;
  comments: number;
  quality: number; // 0-1
  sentiment: number;
  bull: number;
  bear: number;
  neutral: number;
  conviction: number; // 0-1
  tickers: number;
  topTickers: string[];
  topPostId: string | null;
  score: number; // 0-100
  cQuality: number; // 四维分量(0-1)，给进度条用
  cInfluence: number;
  cConviction: number;
  cOutput: number;
  tier: number; // 0..3
}

// 全体作者打分（作者维度——含作者库帖 source='author'，不按 source 过滤）。
// 构建期 memo 一次：榜单页 + 2336 个作者页 O(1) 复用同一份归一化结果。
let _scoredCache: AuthorRow[] | null = null;
let _scoredMap: Map<string, AuthorRow> | null = null;

function allAuthorsScored(): AuthorRow[] {
  if (_scoredCache) return _scoredCache;
  const agg = all<{
    author: string; posts: number; upvotes: number; comments: number;
    quality: number | null; sentiment: number | null;
    bull: number; bear: number; neutral: number; topPostId: string | null;
  }>(
    `SELECT p.author_id AS author,
            COUNT(*) AS posts,
            COALESCE(SUM(p.score),0) AS upvotes,
            COALESCE(SUM(p.num_comments),0) AS comments,
            AVG(ia.quality_score) AS quality,
            AVG(ia.sentiment_score) AS sentiment,
            SUM(CASE WHEN ia.stance='bull' THEN 1 ELSE 0 END) AS bull,
            SUM(CASE WHEN ia.stance='bear' THEN 1 ELSE 0 END) AS bear,
            SUM(CASE WHEN ia.stance='neutral' THEN 1 ELSE 0 END) AS neutral,
            (SELECT p2.id FROM posts p2 WHERE p2.author_id=p.author_id ORDER BY p2.score DESC LIMIT 1) AS topPostId
       FROM posts p JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
      WHERE p.author_id IS NOT NULL
      GROUP BY p.author_id`
  );
  if (!agg.length) {
    _scoredCache = [];
    _scoredMap = new Map();
    return _scoredCache;
  }

  // 每位作者的标的覆盖（distinct + top）
  const tk = all<{ author: string; ticker: string; n: number }>(
    `SELECT author_id AS author, ticker, COUNT(*) AS n
       FROM mentions WHERE item_type='post' AND author_id IS NOT NULL
      GROUP BY author_id, ticker`
  );
  const tmap = new Map<string, { ticker: string; n: number }[]>();
  for (const r of tk) {
    const arr = tmap.get(r.author) ?? [];
    arr.push({ ticker: r.ticker, n: r.n });
    tmap.set(r.author, arr);
  }

  // 原始分量
  const raw = agg.map((a) => {
    const q = Math.max(0, Math.min(1, a.quality ?? 0));
    const infl = Math.log10(1 + (a.upvotes || 0) + 2 * (a.comments || 0));
    const out = Math.log10(1 + a.posts);
    const conv = a.posts ? (a.bull + a.bear) / a.posts : 0;
    return { a, q, infl, out, conv };
  });
  const inflVals = raw.map((r) => r.infl);
  const outVals = raw.map((r) => r.out);
  const minI = Math.min(...inflVals), maxI = Math.max(...inflVals);
  const minO = Math.min(...outVals), maxO = Math.max(...outVals);
  const norm = (v: number, mn: number, mx: number) => (mx > mn ? (v - mn) / (mx - mn) : 0);

  const scored: AuthorRow[] = raw.map(({ a, q, infl, out, conv }) => {
    const cInfluence = norm(infl, minI, maxI);
    const cOutput = norm(out, minO, maxO);
    const alpha = 0.3 * q + 0.3 * cInfluence + 0.2 * conv + 0.2 * cOutput;
    const score = Math.round(alpha * 100);
    const tier = score >= 80 ? 3 : score >= 66 ? 2 : score >= 50 ? 1 : 0;
    const tks = (tmap.get(a.author) ?? []).sort((x, y) => y.n - x.n);
    return {
      author: a.author, posts: a.posts, upvotes: a.upvotes || 0, comments: a.comments || 0,
      quality: q, sentiment: a.sentiment ?? 0, bull: a.bull, bear: a.bear, neutral: a.neutral,
      conviction: conv, tickers: tks.length, topTickers: tks.slice(0, 4).map((x) => x.ticker),
      topPostId: a.topPostId, score,
      cQuality: q, cInfluence, cConviction: conv, cOutput, tier,
    };
  });
  scored.sort((x, y) => y.score - x.score || y.upvotes - x.upvotes);
  _scoredCache = scored;
  _scoredMap = new Map(scored.map((r) => [r.author, r]));
  return _scoredCache;
}

export function getLeaderboard(limit = 24): AuthorRow[] {
  return allAuthorsScored().slice(0, limit);
}

// ----------------------------- 作者页（聚合分析） -----------------------------
export interface AuthorTickerStance {
  ticker: string; name: string; posts: number; bull: number; bear: number; sentiment: number;
}

// 所有「有帖」的作者名 → generateStaticParams（保证任意从帖/榜单点进来的作者都有页、不 404）。
export function getAuthorNames(): string[] {
  return all<{ author: string }>(
    `SELECT DISTINCT author_id AS author FROM posts WHERE author_id IS NOT NULL`
  ).map((r) => r.author);
}

export function getAuthorDetail(name: string) {
  const row = allAuthorsScored() && _scoredMap ? _scoredMap.get(name) : undefined; // 实力分/四维分量（可能 undefined）
  const profile = get<{
    comment_karma: number; link_karma: number; post_count: number; influence_score: number;
    created_utc: string | null; crawled_at: string | null; first_seen: string | null; last_seen: string | null;
  }>(
    `SELECT comment_karma, link_karma, post_count, influence_score, created_utc, crawled_at, first_seen, last_seen
       FROM authors WHERE id = ?`,
    name
  );
  // 基础数据：聚合该作者全部帖（含作者库 source='author'）
  const agg = get<{
    posts: number; upvotes: number; comments: number; tickers: number; quality: number | null;
    sentiment: number | null; bull: number; bear: number; neutral: number;
    first: string | null; last: string | null; lib: number;
  }>(
    `SELECT COUNT(*) AS posts, COALESCE(SUM(p.score),0) AS upvotes, COALESCE(SUM(p.num_comments),0) AS comments,
            AVG(ia.quality_score) AS quality, AVG(ia.sentiment_score) AS sentiment,
            SUM(CASE WHEN ia.stance='bull' THEN 1 ELSE 0 END) AS bull,
            SUM(CASE WHEN ia.stance='bear' THEN 1 ELSE 0 END) AS bear,
            SUM(CASE WHEN ia.stance='neutral' THEN 1 ELSE 0 END) AS neutral,
            MIN(p.created_utc) AS first, MAX(p.created_utc) AS last,
            SUM(CASE WHEN p.source='author' THEN 1 ELSE 0 END) AS lib,
            (SELECT COUNT(DISTINCT ticker) FROM mentions WHERE item_type='post' AND author_id = ?) AS tickers
       FROM posts p LEFT JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
      WHERE p.author_id = ?`,
    name, name
  );
  // 代表作：质量 × 热度 排序（含作者库帖）
  const posts = mapFeed(
    all(
      `SELECT p.id, p.title, p.title_zh, p.selftext, p.permalink, p.subreddit_id, p.flair, p.score,
              p.num_comments, p.created_utc, p.author_id,
              ia.stance, ia.sentiment_score, ia.quality_score, ia.tldr, ia.tldr_zh, ia.themes, ia.tickers
         FROM posts p JOIN item_analysis ia ON ia.item_id=p.id AND ia.item_type='post'
        WHERE p.author_id = ?
        ORDER BY (COALESCE(ia.quality_score,0) * (1 + p.score)) DESC, p.score DESC LIMIT 12`,
      name
    )
  );
  // 看好 / 看空标的：把作者每个 ticker 的帖子立场聚合
  const tkRows = all<{ ticker: string; name: string; n: number; bull: number; bear: number; sentiment: number | null }>(
    `SELECT m.ticker, COALESCE(tm.company_name,'') AS name, COUNT(*) AS n,
            SUM(CASE WHEN ia.stance='bull' THEN 1 ELSE 0 END) AS bull,
            SUM(CASE WHEN ia.stance='bear' THEN 1 ELSE 0 END) AS bear,
            AVG(ia.sentiment_score) AS sentiment
       FROM mentions m JOIN posts p ON p.id=m.item_id AND p.author_id = ?
       LEFT JOIN item_analysis ia ON ia.item_id=m.item_id AND ia.item_type='post'
       LEFT JOIN ticker_meta tm ON tm.ticker=m.ticker
      WHERE m.item_type='post'
      GROUP BY m.ticker`,
    name
  );
  const tickers: AuthorTickerStance[] = tkRows.map((t) => ({
    ticker: t.ticker, name: t.name, posts: t.n, bull: t.bull, bear: t.bear, sentiment: t.sentiment ?? 0,
  }));
  const bullish = tickers
    .filter((t) => t.bull > t.bear || (t.bull === t.bear && t.sentiment > 0.12))
    .sort((a, b) => b.bull - b.bear - (a.bull - a.bear) || b.posts - a.posts)
    .slice(0, 8);
  const bearish = tickers
    .filter((t) => t.bear > t.bull || (t.bull === t.bear && t.sentiment < -0.12))
    .sort((a, b) => b.bear - b.bull - (a.bear - a.bull) || b.posts - a.posts)
    .slice(0, 8);
  // 常驻社区
  const communities = all<{ subreddit: string; n: number }>(
    `SELECT subreddit_id AS subreddit, COUNT(*) AS n FROM posts WHERE author_id = ?
      GROUP BY subreddit_id ORDER BY n DESC LIMIT 6`,
    name
  );
  // 主题（从代表作聚合）
  const themeCount = new Map<string, number>();
  for (const p of posts) for (const t of p.themes) themeCount.set(t, (themeCount.get(t) || 0) + 1);
  const themes = [...themeCount.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10).map(([n, c]) => ({ name: n, count: c }));

  return {
    name,
    profile,
    stats: {
      posts: agg?.posts ?? 0, upvotes: agg?.upvotes ?? 0, comments: agg?.comments ?? 0,
      tickers: agg?.tickers ?? 0, quality: agg?.quality ?? 0, sentiment: agg?.sentiment ?? 0,
      bull: agg?.bull ?? 0, bear: agg?.bear ?? 0, neutral: agg?.neutral ?? 0,
      first: agg?.first ?? null, last: agg?.last ?? null, library: agg?.lib ?? 0,
      karma: (profile?.comment_karma ?? 0) + (profile?.link_karma ?? 0),
      score: row?.score ?? null, tier: row?.tier ?? 0,
      cQuality: row?.cQuality ?? 0, cInfluence: row?.cInfluence ?? 0,
      cConviction: row?.cConviction ?? 0, cOutput: row?.cOutput ?? 0,
    },
    posts,
    bullish,
    bearish,
    communities,
    themes,
  };
}

// 给定一批作者名，返回其中「有作者页」（即有帖）的集合 → 评论区据此决定是否给作者加链接。
export function linkableAuthors(names: string[]): string[] {
  const uniq = [...new Set(names.filter(Boolean))];
  if (!uniq.length) return [];
  const ph = uniq.map(() => "?").join(",");
  return all<{ a: string }>(
    `SELECT DISTINCT author_id AS a FROM posts WHERE author_id IN (${ph})`,
    ...uniq
  ).map((r) => r.a);
}

export function getSubreddits() {
  return all<{ id: string; subscribers: number }>("SELECT id, subscribers FROM subreddits ORDER BY subscribers DESC");
}

export function getCommunities(market?: string) {
  // 只展示 tracked 社区（A 股关键词扫描的来源版块 tracked=0，不进侧栏）。
  const conds = ["COALESCE(s.tracked,1)=1"];
  const params: unknown[] = [];
  if (market) { conds.push("s.market = ?"); params.push(market); }
  return all<{ id: string; subscribers: number; posts: number }>(
    `SELECT s.id, s.subscribers,
            (SELECT COUNT(*) FROM posts p WHERE p.subreddit_id = s.id) AS posts
       FROM subreddits s WHERE ${conds.join(" AND ")} ORDER BY posts DESC`,
    ...params
  );
}

// 个性化看板用：所有在窗口内的标的(轻量字段) + 叙事，序列化给客户端按 onboarding 选择筛选。
export interface TickerLite {
  ticker: string; name: string; sector: string | null;
  mindshare: number; sentiment: number; mentions: number;
}
export function getDashboardBundle() {
  const tickers = all<TickerLite>(
    `SELECT r.ticker, COALESCE(tm.company_name,'') AS name, tm.sector,
            r.mindshare_pct AS mindshare, r.sentiment_avg AS sentiment, r.mention_count AS mentions
       FROM ticker_rollup r LEFT JOIN ticker_meta tm ON tm.ticker = r.ticker
      WHERE r.bucket='window' ORDER BY r.mindshare_pct DESC`
  );
  return { tickers, narratives: getNarratives(12) };
}

// Onboarding 用：可选「领域」(有数据的 sector) + 热门标的(供选持仓)，均为真实数据。
export function getOnboardingData() {
  const sectors = all<{ key: string; count: number }>(
    `SELECT tm.sector AS key, COUNT(DISTINCT r.ticker) AS count
       FROM ticker_rollup r JOIN ticker_meta tm ON tm.ticker = r.ticker
      WHERE r.bucket='window' AND tm.sector IS NOT NULL AND tm.sector <> ''
      GROUP BY tm.sector ORDER BY count DESC`
  );
  const tickers = all<{ ticker: string; name: string; sector: string | null }>(
    `SELECT r.ticker, COALESCE(tm.company_name,'') AS name, tm.sector
       FROM ticker_rollup r LEFT JOIN ticker_meta tm ON tm.ticker = r.ticker
      WHERE r.bucket='window' ORDER BY r.mindshare_pct DESC LIMIT 30`
  );
  return { sectors, tickers };
}

// Landing page 用：聚合真实数据做信任背书（社区数、总订阅、帖子、标的、作者）。
export function getLandingStats() {
  const subs = all<{ id: string; subscribers: number }>(
    "SELECT id, subscribers FROM subreddits ORDER BY subscribers DESC"
  );
  const meta = getMeta();
  const authors =
    get<{ n: number }>(
      "SELECT COUNT(DISTINCT author_id) AS n FROM posts WHERE author_id IS NOT NULL"
    )?.n ?? 0;
  const totalSubscribers = subs.reduce((s, c) => s + (c.subscribers || 0), 0);
  return { subs, totalSubscribers, posts: meta.posts, tickers: meta.tickers, authors };
}
