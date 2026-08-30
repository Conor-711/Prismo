import { all } from "@/lib/db";
import type { Bi, KolSource, KolTargetData, TargetMark } from "@/shared/market/mockDetail";
import {
  bucketHorizon,
  currentPrice,
  parseRange,
  safe,
  svHorizon,
  YOUTUBE_MIN_DISPLAY_DURATION_SECONDS,
  YOUTUBE_MIN_DISPLAY_SUBSCRIBERS,
} from "./shared";
import { refinedMap } from "./lookups";

function priceWindow(symbol: string, days: number): { day: string; close: number }[] {
  const cutoff = new Date(Date.now() - days * 864e5).toISOString().slice(0, 10);
  return safe(
    () => all<{ day: string; close: number }>(
      `SELECT day, close FROM price_daily WHERE ticker = ? AND day >= ? ORDER BY day`, symbol, cutoff),
    []
  );
}

type SvAuthorRank = Pick<TargetMark, "svScore" | "svPlatformScore" | "svPercentile" | "svRank" | "svPopulation">;

let svAuthorRanksCache: Map<string, SvAuthorRank> | null = null;

const normalizedAuthor = (value: string) => String(value || "")
  .trim()
  .replace(/^@/, "")
  .replace(/^u\//, "")
  .toLowerCase();

function svAuthorRanks(): Map<string, SvAuthorRank> {
  if (svAuthorRanksCache) return svAuthorRanksCache;
  const rows = safe(
    () => all<{
      source: KolSource;
      handle: string;
      sv_score: number;
      platform_sv: number;
      platform_rank: number;
      platform_population: number;
      platform_percentile: number;
    }>(
      `WITH scored AS (
         SELECT investor_id, source, handle, sv AS sv_score,
                COALESCE(json_extract(platform_scores_json, '$.' || source), sv, 100) AS platform_sv
           FROM sv_investor_score
          WHERE source IN ('x','youtube','reddit','xueqiu')
       ),
       ranked AS (
         SELECT *,
                ROW_NUMBER() OVER (
                  PARTITION BY source
                  ORDER BY platform_sv DESC, sv_score DESC, investor_id
                ) AS platform_rank,
                COUNT(*) OVER (PARTITION BY source) AS platform_population
           FROM scored
       )
       SELECT source, handle, sv_score, platform_sv, platform_rank, platform_population,
              CASE WHEN platform_population <= 1 THEN 0
                   ELSE 100.0 * (platform_rank - 1) / (platform_population - 1)
              END AS platform_percentile
         FROM ranked`
    ),
    []
  );
  svAuthorRanksCache = new Map();
  for (const row of rows) {
    const key = `${row.source}|${normalizedAuthor(row.handle)}`;
    if (key.endsWith("|")) continue;
    svAuthorRanksCache.set(key, {
      svScore: Number(row.sv_score),
      svPlatformScore: Number(row.platform_sv),
      svPercentile: Number(row.platform_percentile),
      svRank: Number(row.platform_rank),
      svPopulation: Number(row.platform_population),
    });
  }
  return svAuthorRanksCache;
}

function rankFor(source: KolSource, author: string): SvAuthorRank {
  return svAuthorRanks().get(`${source}|${normalizedAuthor(author)}`) ?? {};
}

// 「整体数据 · 目标价时间线」取数：近 3 个月 kol_judgment(reddit/x/雪球/Toss/Yahoo JP) + yt_judgment(youtube)，
// 每条判断的买入侧/卖出侧各出一个 TargetMark(日期×价位区间)；叠真实股价折线 + 现价。作者/链接 join 源表，
// 简单依据(reason)取 kol_refined(reddit/x/雪球/Toss/Yahoo JP) 或 yt_analysis.summary(youtube)；价格按现价 band 二次剔噪。
// 作者按平台关联当前 Score 排名，前端可组合「近 1/3/7/14/30/60/90 天 × Score 分位」过滤噪音。
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
      const opinionId = (source: KolSource, itemId: string | number) => {
        const id = String(itemId);
        if (source === "reddit") return `rd-${id}`;
        if (source === "youtube") return `yt-${id}`;
        if (source === "xueqiu") return `xq-${id}`;
        if (source === "toss") return `toss-${id}`;
        if (source === "yahoojp") return `yj-${id}`;
        return `x-${id}`;
      };
      const marks: TargetMark[] = [];

      const SRC: { s: KolSource; sql: string; name: (a: string) => string }[] = [
        { s: "reddit", name: (a) => (a && a !== "[deleted]" ? "u/" + a : "u/—"),
          sql: `SELECT kj.*, p.author_id AS author, p.permalink AS url
                  FROM kol_judgment kj JOIN posts p ON p.id = kj.item_id
                 WHERE kj.source='reddit' AND kj.ticker=? AND kj.created>=?` },
        { s: "x", name: (a) => (a ? "@" + a : "@—"),
          sql: `SELECT kj.*, x.handle AS author, x.url AS url
                  FROM kol_judgment kj
                  JOIN x_opinion x ON x.tweet_id = kj.item_id AND x.ticker = kj.ticker
                 WHERE kj.source='x' AND kj.ticker=? AND kj.created>=?` },
        { s: "xueqiu", name: (a) => a || "雪球",
          sql: `SELECT kj.*, g.author AS author, g.url AS url
                  FROM kol_judgment kj JOIN gr_post g ON g.id = kj.item_id
                 WHERE kj.source='xueqiu' AND kj.ticker=? AND kj.created>=?` },
        { s: "toss", name: (a) => a || "Toss",
          sql: `SELECT kj.*, g.author AS author, g.url AS url
                  FROM kol_judgment kj JOIN gr_post g ON g.id = kj.item_id
                 WHERE kj.source='toss' AND kj.ticker=? AND kj.created>=?` },
        { s: "yahoojp", name: (a) => a || "Yahoo JP",
          sql: `SELECT kj.*, g.author AS author, g.url AS url
                  FROM kol_judgment kj JOIN gr_post g ON g.id = kj.item_id
                 WHERE kj.source='yahoojp' AND kj.ticker=? AND kj.created>=?` },
      ];
      for (const cfg of SRC) {
        const rows = safe(() => all<any>(cfg.sql, symbol, cutoff), []);
        for (const r of rows) {
          const ref = refined.get(`${cfg.s}:${r.item_id}`);
          const reason = ref?.reason && (ref.reason.zh || ref.reason.en) ? ref.reason : undefined;
          const base = {
            source: cfg.s, opinionId: opinionId(cfg.s, r.item_id), author: cfg.name(r.author), priceRaw: r.price_raw || undefined,
            horizon: bi(r.horizon_zh || "", r.horizon_en || ""), bucket: bk(r.horizon_bucket || ""),
            reason, date: String(r.created || "").slice(0, 10), url: r.url || "#",
            ...rankFor(cfg.s, r.author || ""),
          };
          if (r.buy_lo != null && inBand((r.buy_lo + (r.buy_hi ?? r.buy_lo)) / 2))
            marks.push({ ...base, kind: "buy", lo: r.buy_lo, hi: r.buy_hi ?? r.buy_lo });
          if (r.sell_lo != null && inBand((r.sell_lo + (r.sell_hi ?? r.sell_lo)) / 2))
            marks.push({ ...base, kind: "sell", lo: r.sell_lo, hi: r.sell_hi ?? r.sell_lo });
        }
      }
      // Score X call：直接使用结构化出的 target_price / horizon_bucket，补齐 x_opinion 未覆盖的推特目标价点。
      const svTargets = safe(
        () => all<any>(
          `SELECT cc.tweet_id AS tweet_id, cc.author_handle AS author, cc.url AS url,
                  COALESCE(cc.created_day, substr(cc.created_at,1,10)) AS day,
                  c.target_price AS target_price, c.horizon_bucket AS horizon_bucket,
                  COALESCE(c.summary_zh,'') AS summary_zh, COALESCE(c.summary_en,'') AS summary_en
             FROM sv_call_candidate cc
             JOIN sv_call c ON c.candidate_id = cc.candidate_id
            WHERE cc.ticker = ? AND COALESCE(cc.created_day, substr(cc.created_at,1,10)) >= ?
              AND c.is_actionable_call = 1 AND c.target_price IS NOT NULL`,
          symbol,
          cutoff
        ),
        []
      );
      for (const r of svTargets) {
        const target = Number(r.target_price);
        if (!Number.isFinite(target) || target <= 0 || !inBand(target)) continue;
        const h = svHorizon(r.horizon_bucket);
        marks.push({
          source: "x",
          opinionId: opinionId("x", r.tweet_id),
          author: r.author ? "@" + String(r.author).replace(/^@/, "") : "@—",
          kind: "sell",
          lo: target,
          hi: target,
          priceRaw: `$${target}`,
          horizon: h.horizon,
          bucket: h.bucket,
          reason: bi(r.summary_zh || "", r.summary_en || ""),
          date: String(r.day || "").slice(0, 10),
          url: r.url || "#",
          ...rankFor("x", r.author || ""),
        });
      }
      // youtube：yt_judgment ⋈ yt_video / yt_analysis → 卖出/目标侧
      const yt = safe(
        () => all<any>(
          `SELECT yj.target AS target, COALESCE(yj.horizon_zh,'') AS hz, COALESCE(yj.horizon_en,'') AS he,
                  yj.video_id AS video_id,
                  v.channel AS author, c.handle AS author_handle, v.url AS url, v.published_utc AS created,
                  COALESCE(a.summary_zh,'') AS sz, COALESCE(a.summary_en,'') AS se
             FROM yt_judgment yj JOIN yt_video v ON v.id = yj.video_id
             JOIN yt_channel c ON c.channel_id = v.channel_id
             LEFT JOIN yt_analysis a ON a.video_id = yj.video_id
            WHERE yj.ticker=? AND v.published_utc>=?
              AND COALESCE(v.duration_s,0) > ?
              AND COALESCE(c.subscriber_count,-1) >= ?`,
          symbol,
          cutoff,
          YOUTUBE_MIN_DISPLAY_DURATION_SECONDS,
          YOUTUBE_MIN_DISPLAY_SUBSCRIBERS
        ),
        []
      );
      for (const r of yt) {
        const rng = parseRange(r.target);
        if (!rng || !inBand((rng[0] + rng[1]) / 2)) continue;
        const horizon = bi(r.hz, r.he);
        marks.push({
          source: "youtube", opinionId: opinionId("youtube", r.video_id), author: r.author || "YouTube", kind: "sell", lo: rng[0], hi: rng[1],
          priceRaw: r.target || undefined, horizon, bucket: horizon ? bucketHorizon(`${r.hz} ${r.he}`) : undefined,
          reason: bi(r.sz, r.se), date: String(r.created || "").slice(0, 10), url: r.url || "#",
          ...rankFor("youtube", r.author_handle || r.author || ""),
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
