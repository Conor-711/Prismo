import { all } from "@/lib/db";
import { safe } from "./shared";

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
