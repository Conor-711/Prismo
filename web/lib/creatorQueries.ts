// 「YouTube 作者页」取数层：聚合单个频道的 ① 含权标的表现 ② 代表性标的 ③ 互动最高视频。
// 真实数据：yt_channel(档案) + yt_video(视频) + yt_analysis(立场/笃定) + price_daily(算表现/超额) + author_avatar(头像)。
// 表现 = 自「表态日」起的收益（数据仅近一个月 → 短窗）；超额 = 相对 SPY。诚实定位：近期表态兑现，非长期战绩。
// 与 kolQueries/investorQueries 同范式：build-time 直读 dev.db（node:sqlite，见 db.ts），缺数据降级空态。
import { all } from "./db";
import type { Stance } from "./mockDetail";

function safe<T>(fn: () => T, fb: T): T {
  try {
    return fn();
  } catch {
    return fb;
  }
}

const dayOf = (s: string) => (s || "").slice(0, 10);
const ytUrl = (id: string, url?: string) => (url && url.trim()) || `https://www.youtube.com/watch?v=${id}`;
const asStance = (s: string | null | undefined): Stance =>
  s === "bull" || s === "bear" || s === "neutral" ? s : "neutral";
// key_points 以 JSON 文本存（["论点1","论点2"]）→ 解析成字符串数组；坏数据降级空数组。
const parsePoints = (raw: string | null | undefined): string[] => {
  if (!raw) return [];
  try {
    const a = JSON.parse(raw);
    return Array.isArray(a) ? a.map((x) => String(x).trim()).filter(Boolean) : [];
  } catch {
    return [];
  }
};
// price_target 是自由文本（"$800" / "1200-1600" / null）→ 原样展示（作者口径），剔除空/"null"。
const cleanTarget = (s: string | null | undefined): string | undefined => {
  const t = (s || "").trim();
  return !t || t.toLowerCase() === "null" ? undefined : t;
};

export interface CreatorProfile {
  channelId: string;
  name: string;
  handle?: string; // @handle
  avatar?: string;
  url: string; // YouTube 频道主页
  subscribers?: number; // 粉丝数（隐藏则 undefined）
  channelVideos?: number; // 频道总视频数（YouTube 全量）
  channelViews?: number; // 频道总播放
  bio?: string;
  trackedVideos: number; // 我们收录并分析的视频数
  trackedTickers: number; // 覆盖标的数
}

// ① 一条「含权调用」= 一条有方向(看多/看空)的视频对某标的的表态 + 其后表现。
export interface TrackCall {
  videoId: string;
  ticker: string;
  stance: Stance; // bull | bear（仅方向性）
  day: string; // 表态日 YYYY-MM-DD
  entry: number; // 表态日(或次交易日)收盘
  latest: number; // 最新收盘
  latestDay: string;
  heldDays: number;
  ret: number; // 标的原始收益（小数，0.05=+5%）
  signedRet: number; // 按立场修正后的收益（看空时取反；>0=方向对）
  excess: number; // 相对 SPY 的超额（按立场修正）
  hit: boolean; // signedRet > 0
  title: string;
  views: number;
  url: string;
}
export interface TrackRecord {
  calls: TrackCall[]; // 按日期倒序
  count: number; // 可评估的方向性调用数
  hitRate: number; // 0..1
  avgSignedRet: number; // 平均（小数）
  avgExcess: number; // 平均（小数）
  avgHeldDays: number;
  hasBenchmark: boolean; // 是否有 SPY 基准（无则 UI 隐藏「跑赢大盘」列，excess 退化为原始收益）
  priceFrom?: string; // 价格数据窗（诚实标注用）
  priceTo?: string;
}

// 「标的判断」：一条判断 = 一条已分析视频对某标的的表态（含中性）+ 观点/论据/目标价 + 自表态日起的回测。
export interface Judgment {
  videoId: string;
  day: string; // 表态日 YYYY-MM-DD
  stance: Stance; // bull | bear | neutral（中性也保留）
  conviction: number; // 0..1 笃定度
  summaryZh: string; // 大致观点（中）
  summaryEn: string;
  pointsZh: string[]; // 论据（中）
  pointsEn: string[];
  target?: string; // 目标价（yt_judgment 结构化优先，回退 yt_analysis.price_target 原话）
  horizonZh?: string; // 时间周期（yt_judgment，AI 从观点/论据抽；缺则无）
  horizonEn?: string;
  keyLevelsZh?: string; // 关键位置（yt_judgment）
  keyLevelsEn?: string;
  title: string;
  views: number;
  url: string;
  // 回测（price_daily 覆盖该标的、且表态日早于最新价才有；否则 hasPrice=false）
  hasPrice: boolean;
  entry?: number; // 表态日(或次交易日)收盘
  latest?: number; // 最新收盘
  latestDay?: string;
  heldDays?: number;
  ret?: number; // 标的原始涨跌（中性也有意义）
  signedRet?: number; // 按立场修正（仅多空）
  excess?: number; // 相对 SPY 超额（仅多空）
  hit?: boolean; // 方向是否兑现（仅多空且有价）
}
// 按标的归组：刻画作者对每只标的的判断 —— 主导立场 + 几点关键判断（综合）+ 底层判断（链接/回测/chip 用）。
export interface TickerJudgments {
  ticker: string;
  netStance: Stance; // 综合立场（yt_creator_view 优先，回退多数立场）
  bull: number;
  bear: number;
  neutral: number;
  count: number;
  // 综合关键判断（yt_creator_view，把该作者对该标的的多条视频判断合并去重成几点；缺则回退最新判断的 key_points）
  pointsZh: string[];
  pointsEn: string[];
  judgments: Judgment[]; // 底层逐条判断（按表态日倒序）——不再整条铺开，仅用于代表性 chip/回测 + 原视频链接
}

// ② 互动最高视频。
export interface CreatorVideo {
  videoId: string;
  ticker: string;
  title: string;
  stance: Stance;
  day: string;
  views: number;
  likes: number;
  comments: number;
  thumbnail?: string;
  url: string;
}

export interface YoutubeCreator {
  profile: CreatorProfile;
  trackRecord: TrackRecord;
  tickerJudgments: TickerJudgments[]; // ①「标的判断」：按标的归组的综合判断 + 回测
  topVideos: CreatorVideo[]; // ② 互动最高视频
}

interface VidRow {
  id: string;
  ticker: string;
  channel: string;
  title: string;
  view_count: number;
  like_count: number;
  comment_count: number;
  thumbnail: string;
  url: string;
  published_utc: string;
  stance: string | null;
  conviction: number | null;
  summary_zh: string | null;
  summary_en: string | null;
  key_points_zh: string | null;
  key_points_en: string | null;
  price_target: string | null;
}
// yt_judgment 行（Phase 2 结构化抽取；多为 null）
interface JudgmentRow {
  video_id: string;
  horizon_zh: string | null;
  horizon_en: string | null;
  target: string | null;
  key_levels_zh: string | null;
  key_levels_en: string | null;
}

// price_daily 全量（数百行，极小）→ Map<ticker, {day,close}[]>（按日升序）+ 数据窗。
function priceMap(): { map: Map<string, { day: string; close: number }[]>; from?: string; to?: string } {
  const rows = safe(
    () =>
      all<{ ticker: string; day: string; close: number }>(
        `SELECT ticker, day, close FROM price_daily WHERE close IS NOT NULL ORDER BY ticker, day`
      ),
    []
  );
  const map = new Map<string, { day: string; close: number }[]>();
  let from: string | undefined;
  let to: string | undefined;
  for (const r of rows) {
    let a = map.get(r.ticker);
    if (!a) map.set(r.ticker, (a = []));
    a.push({ day: r.day, close: r.close });
    if (!from || r.day < from) from = r.day;
    if (!to || r.day > to) to = r.day;
  }
  return { map, from, to };
}

// 自 callDay 起的收益：entry=表态日(或次交易日)收盘，latest=最新收盘。无法评估（无价/窗口为 0）返回 null。
function evalReturn(
  series: { day: string; close: number }[] | undefined,
  callDay: string
): { entry: number; latest: number; latestDay: string; heldDays: number; ret: number } | null {
  if (!series || series.length === 0) return null;
  const entryPt = series.find((p) => p.day >= callDay);
  const latestPt = series[series.length - 1];
  if (!entryPt || !latestPt || latestPt.day <= entryPt.day || entryPt.close <= 0) return null;
  const ret = (latestPt.close - entryPt.close) / entryPt.close;
  const heldDays = Math.round((Date.parse(latestPt.day) - Date.parse(entryPt.day)) / 864e5);
  return { entry: entryPt.close, latest: latestPt.close, latestDay: latestPt.day, heldDays, ret };
}

// generateStaticParams 用：所有有视频的频道 id（= 可被链接到作者页的全集）。
export function getYoutubeChannelIds(): string[] {
  return safe(
    () =>
      all<{ channel_id: string }>(`SELECT DISTINCT channel_id FROM yt_video WHERE channel_id <> ''`).map(
        (r) => r.channel_id
      ),
    []
  );
}

export function getYoutubeCreator(channelId: string): YoutubeCreator | null {
  return safe<YoutubeCreator | null>(() => {
    const ch = all<any>(
      `SELECT channel_id, title, handle, subscriber_count, video_count, view_count, description
         FROM yt_channel WHERE channel_id = ?`,
      channelId
    )[0];
    const vids = all<VidRow>(
      `SELECT v.id, v.ticker, v.channel, v.title, v.view_count, v.like_count, v.comment_count,
              v.thumbnail, v.url, v.published_utc, a.stance, a.conviction,
              a.summary_zh, a.summary_en, a.key_points_zh, a.key_points_en, a.price_target
         FROM yt_video v LEFT JOIN yt_analysis a ON a.video_id = v.id
        WHERE v.channel_id = ? ORDER BY v.published_utc DESC`,
      channelId
    );
    // yt_judgment（Phase 2 结构化参数）单独取、各自 safe 兜底——表缺失/未跑也不影响主流程（同 author_avatar 范式）。
    const jrows = safe(
      () =>
        all<JudgmentRow>(
          `SELECT jj.video_id, jj.horizon_zh, jj.horizon_en, jj.target, jj.key_levels_zh, jj.key_levels_en
             FROM yt_judgment jj JOIN yt_video vv ON vv.id = jj.video_id
            WHERE vv.channel_id = ?`,
          channelId
        ),
      []
    );
    const jmap = new Map(jrows.map((r) => [r.video_id, r]));
    // yt_creator_view（作者×标的 综合判断）同样 safe 兜底——表缺失/未跑则回退到逐条判断的 key_points。
    const vrows = safe(
      () =>
        all<{ ticker: string; stance: string; points_zh: string | null; points_en: string | null }>(
          `SELECT ticker, stance, points_zh, points_en FROM yt_creator_view WHERE channel_id = ?`,
          channelId
        ),
      []
    );
    const vmap = new Map(vrows.map((r) => [r.ticker, r]));
    if (!ch && vids.length === 0) return null;

    const av = all<{ url: string }>(
      `SELECT url FROM author_avatar WHERE source = 'youtube' AND handle = ? AND url <> '' LIMIT 1`,
      channelId
    )[0];

    const subs = typeof ch?.subscriber_count === "number" && ch.subscriber_count >= 0 ? ch.subscriber_count : undefined;
    const profile: CreatorProfile = {
      channelId,
      name: (ch?.title || vids.find((v) => v.channel)?.channel || channelId).trim(),
      handle: (ch?.handle || "").trim() || undefined,
      avatar: av?.url || undefined,
      url: `https://www.youtube.com/channel/${channelId}`,
      subscribers: subs,
      channelVideos: typeof ch?.video_count === "number" ? ch.video_count : undefined,
      channelViews: typeof ch?.view_count === "number" ? ch.view_count : undefined,
      bio: (ch?.description || "").trim() || undefined,
      trackedVideos: vids.length,
      trackedTickers: new Set(vids.map((v) => v.ticker).filter(Boolean)).size,
    };

    // ① 含权标的表现（仅方向性调用 ⋈ price_daily；超额 vs SPY）
    const { map: pm, from, to } = priceMap();
    const spy = pm.get("SPY");
    const calls: TrackCall[] = [];
    for (const v of vids) {
      const st: Stance | null = v.stance === "bull" || v.stance === "bear" ? v.stance : null;
      if (!st || !v.ticker) continue;
      const day = dayOf(v.published_utc);
      const er = evalReturn(pm.get(v.ticker), day);
      if (!er) continue;
      const sign = st === "bull" ? 1 : -1;
      const signedRet = sign * er.ret;
      const sr = spy ? evalReturn(spy, day) : null;
      const excess = sr ? sign * (er.ret - sr.ret) : signedRet; // 无基准 → 回退原始 signedRet
      calls.push({
        videoId: v.id,
        ticker: v.ticker,
        stance: st,
        day,
        entry: er.entry,
        latest: er.latest,
        latestDay: er.latestDay,
        heldDays: er.heldDays,
        ret: er.ret,
        signedRet,
        excess,
        hit: signedRet > 0,
        title: v.title,
        views: v.view_count || 0,
        url: ytUrl(v.id, v.url),
      });
    }
    calls.sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : 0));
    const count = calls.length;
    const sum = (f: (c: TrackCall) => number) => calls.reduce((s, c) => s + f(c), 0);
    const trackRecord: TrackRecord = {
      calls,
      count,
      hitRate: count ? calls.filter((c) => c.hit).length / count : 0,
      avgSignedRet: count ? sum((c) => c.signedRet) / count : 0,
      avgExcess: count ? sum((c) => c.excess) / count : 0,
      avgHeldDays: count ? Math.round(sum((c) => c.heldDays) / count) : 0,
      hasBenchmark: !!(spy && spy.length),
      priceFrom: from,
      priceTo: to,
    };

    // ①「标的判断」：每条已分析视频 = 一条判断（含中性），按标的归组；回测复用 evalReturn（有价才算）。
    const judged: (Judgment & { ticker: string })[] = [];
    for (const v of vids) {
      if (v.stance == null || !v.ticker) continue; // 无 yt_analysis = 非判断
      const stance = asStance(v.stance);
      const day = dayOf(v.published_utc);
      const er = evalReturn(pm.get(v.ticker), day);
      const sr = er && spy ? evalReturn(spy, day) : null;
      const sign = stance === "bull" ? 1 : stance === "bear" ? -1 : 0; // 中性=0：无方向、不算命中
      const jr = jmap.get(v.id); // yt_judgment 结构化参数（多为空）
      judged.push({
        ticker: v.ticker,
        videoId: v.id,
        day,
        stance,
        conviction: v.conviction || 0,
        summaryZh: (v.summary_zh || "").trim(),
        summaryEn: (v.summary_en || "").trim(),
        pointsZh: parsePoints(v.key_points_zh),
        pointsEn: parsePoints(v.key_points_en),
        // 目标价：结构化抽取优先，回退 yt_analysis 原始 price_target
        target: cleanTarget(jr?.target) ?? cleanTarget(v.price_target),
        horizonZh: cleanTarget(jr?.horizon_zh),
        horizonEn: cleanTarget(jr?.horizon_en),
        keyLevelsZh: cleanTarget(jr?.key_levels_zh),
        keyLevelsEn: cleanTarget(jr?.key_levels_en),
        title: v.title,
        views: v.view_count || 0,
        url: ytUrl(v.id, v.url),
        hasPrice: !!er,
        entry: er?.entry,
        latest: er?.latest,
        latestDay: er?.latestDay,
        heldDays: er?.heldDays,
        ret: er?.ret,
        signedRet: er && sign !== 0 ? sign * er.ret : undefined,
        excess: er && sign !== 0 ? (sr ? sign * (er.ret - sr.ret) : sign * er.ret) : undefined,
        hit: er && sign !== 0 ? sign * er.ret > 0 : undefined,
      });
    }
    const byJudge = new Map<string, Judgment[]>();
    for (const { ticker, ...j } of judged) {
      let a = byJudge.get(ticker);
      if (!a) byJudge.set(ticker, (a = []));
      a.push(j);
    }
    const tickerJudgments: TickerJudgments[] = [...byJudge.entries()]
      .map(([ticker, js]) => {
        let bull = 0;
        let bear = 0;
        let neutral = 0;
        for (const j of js) j.stance === "bull" ? bull++ : j.stance === "bear" ? bear++ : neutral++;
        const majority: Stance = bull >= bear && bull >= neutral ? "bull" : bear >= neutral ? "bear" : "neutral";
        js.sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : 0)); // 表态日倒序
        // 综合：立场/几点关键判断取 yt_creator_view；缺则回退多数立场 + 最新一条判断的 key_points。
        const view = vmap.get(ticker);
        const vPointsZh = parsePoints(view?.points_zh);
        const vPointsEn = parsePoints(view?.points_en);
        return {
          ticker,
          netStance: view?.stance ? asStance(view.stance) : majority,
          bull,
          bear,
          neutral,
          count: js.length,
          pointsZh: vPointsZh.length ? vPointsZh : js[0].pointsZh,
          pointsEn: vPointsEn.length ? vPointsEn : js[0].pointsEn,
          judgments: js,
        };
      })
      // 判断次数多的标的优先；并列则最近表态者优先
      .sort((a, b) => b.count - a.count || (a.judgments[0].day < b.judgments[0].day ? 1 : -1));

    // ② 互动最高视频（播放为主，次级 赞+评，top 8）
    const topVideos: CreatorVideo[] = [...vids]
      .sort((a, b) => {
        const av2 = a.view_count || 0;
        const bv2 = b.view_count || 0;
        if (bv2 !== av2) return bv2 - av2;
        return (b.like_count || 0) + (b.comment_count || 0) - ((a.like_count || 0) + (a.comment_count || 0));
      })
      .slice(0, 8)
      .map((v) => ({
        videoId: v.id,
        ticker: v.ticker,
        title: v.title,
        stance: asStance(v.stance),
        day: dayOf(v.published_utc),
        views: v.view_count || 0,
        likes: v.like_count || 0,
        comments: v.comment_count || 0,
        thumbnail: (v.thumbnail || "").trim() || undefined,
        url: ytUrl(v.id, v.url),
      }));

    return { profile, trackRecord, tickerJudgments, topVideos };
  }, null);
}
