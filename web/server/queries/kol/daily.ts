import { all } from "@/lib/db";
import { safe } from "./shared";

export interface DailyNet { day: string; net: number; nPosts: number; nBull: number; nBear: number }
function svSentimentDaily(symbol: string): DailyNet[] {
  return safe(
    () =>
      all<any>(
        `SELECT COALESCE(cc.created_day, substr(cc.created_at,1,10)) AS day,
                COUNT(*) AS nPosts,
                SUM(CASE WHEN c.direction='bull' THEN 1 ELSE 0 END) AS nBull,
                SUM(CASE WHEN c.direction='bear' THEN 1 ELSE 0 END) AS nBear,
                SUM((CASE WHEN c.direction='bull' THEN 1 WHEN c.direction='bear' THEN -1 ELSE 0 END) *
                    CASE WHEN COALESCE(c.call_weight,0) > 0 THEN c.call_weight ELSE 0.1 END) AS weightedNet,
                SUM(CASE WHEN COALESCE(c.call_weight,0) > 0 THEN c.call_weight ELSE 0.1 END) AS weight
           FROM sv_call_candidate cc
           JOIN sv_call c ON c.candidate_id = cc.candidate_id
          WHERE cc.ticker = ? AND c.is_actionable_call = 1
          GROUP BY day
          ORDER BY day`,
        symbol
      ).map((r) => ({
        day: r.day,
        net: r.weight ? +(r.weightedNet / r.weight).toFixed(3) : 0,
        nPosts: +r.nPosts || 0,
        nBull: +r.nBull || 0,
        nBear: +r.nBear || 0,
      })),
    []
  );
}
function mergeDailyNet(base: DailyNet[], extra: DailyNet[]): DailyNet[] {
  const m = new Map(base.map((r) => [r.day, { ...r }]));
  for (const e of extra) {
    const b = m.get(e.day);
    if (!b) {
      m.set(e.day, { ...e });
      continue;
    }
    const bWeight = Math.max(0, b.nPosts || 0);
    const eWeight = Math.max(0, e.nPosts || 0);
    const total = bWeight + eWeight;
    m.set(e.day, {
      day: e.day,
      net: total ? +(((b.net || 0) * bWeight + (e.net || 0) * eWeight) / total).toFixed(3) : 0,
      nPosts: (b.nPosts || 0) + (e.nPosts || 0),
      nBull: (b.nBull || 0) + (e.nBull || 0),
      nBear: (b.nBear || 0) + (e.nBear || 0),
    });
  }
  return [...m.values()].sort((a, b) => a.day.localeCompare(b.day));
}
export function getKolSentimentDaily(symbol: string): DailyNet[] {
  return safe(
    () => {
      const base = all<any>(
        `SELECT day, net, n_posts AS nPosts, n_bull AS nBull, n_bear AS nBear
           FROM kol_sentiment_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ).map((r) => ({ day: r.day, net: +r.net || 0, nPosts: +r.nPosts || 0, nBull: +r.nBull || 0, nBear: +r.nBear || 0 }));
      return mergeDailyNet(base, svSentimentDaily(symbol));
    },
    []
  );
}

// 每日讨论度（kol_volume_daily，pipeline kol-volume 产出）：每 (ticker,day) 跨平台帖子/视频**计数**。
// 供 KOL 模块「每日讨论度」堆叠条形子面板（VolumePanel）。按 day 升序。
export interface DailyVol { day: string; total: number; reddit: number; x: number; xueqiu: number; youtube: number; [key: string]: number | string }
function svVolumeDaily(symbol: string): DailyVol[] {
  return safe(
    () =>
      all<any>(
        `SELECT COALESCE(cc.created_day, substr(cc.created_at,1,10)) AS day, COUNT(*) AS n
           FROM sv_call_candidate cc
           JOIN sv_call c ON c.candidate_id = cc.candidate_id
          WHERE cc.ticker = ? AND c.is_actionable_call = 1
          GROUP BY day
          ORDER BY day`,
        symbol
      ).map((r) => ({
        day: r.day,
        total: +r.n || 0,
        reddit: 0,
        x: +r.n || 0,
        xueqiu: 0,
        youtube: 0,
      })),
    []
  );
}
function mergeDailyVol(base: DailyVol[], extra: DailyVol[]): DailyVol[] {
  const m = new Map(base.map((r) => [r.day, { ...r }]));
  for (const e of extra) {
    const b = m.get(e.day);
    if (!b) {
      m.set(e.day, { ...e });
      continue;
    }
    b.x = (+b.x || 0) + (+e.x || 0);
    b.total = (+b.total || 0) + (+e.total || 0);
    m.set(e.day, b);
  }
  return [...m.values()].sort((a, b) => a.day.localeCompare(b.day));
}
export function getKolVolumeDaily(symbol: string): DailyVol[] {
  return safe(
    () => {
      const base = all<any>(
        `SELECT day, COALESCE(n_total,0) AS total, COALESCE(n_reddit,0) AS reddit, COALESCE(n_x,0) AS x,
                COALESCE(n_xueqiu,0) AS xueqiu, COALESCE(n_youtube,0) AS youtube
           FROM kol_volume_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ).map((r) => ({ day: r.day, total: +r.total || 0, reddit: +r.reddit || 0, x: +r.x || 0, xueqiu: +r.xueqiu || 0, youtube: +r.youtube || 0 }));
      return mergeDailyVol(base, svVolumeDaily(symbol));
    },
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

// 每日讨论度（retail_volume_daily）：7 个平台键。供 VolumePanel + RETAIL_VOL_STACK 堆叠。
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
function svNewcomersDaily(symbol: string): KolNew[] {
  return safe(
    () =>
      all<any>(
        `WITH firsts AS (
           SELECT cc.author_handle AS handle, MIN(COALESCE(cc.created_day, substr(cc.created_at,1,10))) AS first_day
             FROM sv_call_candidate cc
             JOIN sv_call c ON c.candidate_id = cc.candidate_id
            WHERE cc.ticker = ? AND c.is_actionable_call = 1
              AND COALESCE(cc.author_handle,'') <> ''
            GROUP BY cc.author_handle
         )
         SELECT first_day AS day, COUNT(*) AS n
           FROM firsts
          GROUP BY first_day
          ORDER BY first_day`,
        symbol
      ).map((r) => ({
        day: r.day,
        total: +r.n || 0,
        x: +r.n || 0,
        youtube: 0,
        xueqiu: 0,
      })),
    []
  );
}
function mergeKolNew(base: KolNew[], extra: KolNew[]): KolNew[] {
  const m = new Map(base.map((r) => [r.day, { ...r }]));
  for (const e of extra) {
    const b = m.get(e.day);
    if (!b) {
      m.set(e.day, { ...e });
      continue;
    }
    b.x = (+b.x || 0) + (+e.x || 0);
    b.total = (+b.total || 0) + (+e.total || 0);
    m.set(e.day, b);
  }
  return [...m.values()].sort((a, b) => a.day.localeCompare(b.day));
}
export function getKolNewcomersDaily(symbol: string): KolNew[] {
  return safe(
    () => {
      const base = all<any>(
        `SELECT day, COALESCE(n_total,0) AS total, COALESCE(n_x,0) AS x,
                COALESCE(n_youtube,0) AS youtube, COALESCE(n_xueqiu,0) AS xueqiu
           FROM kol_newcomers_daily WHERE ticker = ? ORDER BY day`,
        symbol
      ).map((r) => ({
        day: r.day, total: +r.total || 0, x: +r.x || 0, youtube: +r.youtube || 0, xueqiu: +r.xueqiu || 0,
      }));
      return mergeKolNew(base, svNewcomersDaily(symbol));
    },
    []
  );
}
