import { all, get, parseJSON } from "./db";

// 亚洲散户舆情实验（隐藏页 /[lang]/lab/asia-pulse）取数层。
// 隔离表 asia_*（由 pipeline 的 asia-crawl/analyze/summarize 产出）。
// 关键：所有查询用 try/catch 包裹——若 dev.db 是未含 asia 表的云端快照，返回空而非让构建崩溃。

export interface AsiaSummary {
  market: string; ticker: string; source: string;
  post_count: number; analyzed_count: number;
  bull_pct: number; bear_pct: number; neutral_pct: number;
  mood_score: number; mood_label: string;
  overview_zh: string; overview_en: string;
  top_bull_zh: string[]; top_bull_en: string[];
  top_bear_zh: string[]; top_bear_en: string[];
  top_themes: string[];
}

export interface AsiaPostRow {
  id: string; market: string; ticker: string; source: string; origin: string;
  author: string; title: string; body: string; label: string | null; url: string;
  likes: number; dislikes: number; views: number; comments: number; images: number; verified: number;
  created: string;
  stance: string; sentiment: number; quality: number;
  tldr_zh: string; tldr_en: string; themes: string[];
}

export interface AsiaMeta {
  posts: number; analyzed: number; markets: number; tickers: number; lastUpdated: string | null;
  firstDay: string | null; lastDay: string | null;
}

function safe<T>(fn: () => T, fallback: T): T {
  try {
    return fn();
  } catch {
    // 表不存在（云端快照未含 asia_*）→ 返回空，页面显示「暂无数据」。
    return fallback;
  }
}

export function getAsiaSummaries(): AsiaSummary[] {
  return safe(() => {
    const rows = all<any>(
      `SELECT market, ticker, source, post_count, analyzed_count,
              bull_pct, bear_pct, neutral_pct, mood_score, mood_label,
              overview_zh, overview_en, top_bull_zh, top_bull_en,
              top_bear_zh, top_bear_en, top_themes
         FROM asia_ticker_summary`
    );
    return rows.map((r) => ({
      market: r.market, ticker: r.ticker, source: r.source ?? "",
      post_count: r.post_count ?? 0, analyzed_count: r.analyzed_count ?? 0,
      bull_pct: r.bull_pct ?? 0, bear_pct: r.bear_pct ?? 0, neutral_pct: r.neutral_pct ?? 0,
      mood_score: r.mood_score ?? 0, mood_label: r.mood_label ?? "neutral",
      overview_zh: r.overview_zh ?? "", overview_en: r.overview_en ?? "",
      top_bull_zh: parseJSON<string[]>(r.top_bull_zh, []), top_bull_en: parseJSON<string[]>(r.top_bull_en, []),
      top_bear_zh: parseJSON<string[]>(r.top_bear_zh, []), top_bear_en: parseJSON<string[]>(r.top_bear_en, []),
      top_themes: parseJSON<string[]>(r.top_themes, []),
    }));
  }, []);
}

export function getAsiaPosts(market: string, ticker: string, limit = 4): AsiaPostRow[] {
  return safe(() => {
    const rows = all<any>(
      `SELECT p.id, p.market, p.ticker, p.source, p.origin, p.author, p.title, p.body,
              p.label, p.url, p.likes, p.dislikes,
              COALESCE(p.views,0) AS views, COALESCE(p.comments,0) AS comments,
              COALESCE(p.images,0) AS images, COALESCE(p.verified,0) AS verified,
              p.created_utc AS created,
              COALESCE(a.stance,'neutral') AS stance, COALESCE(a.sentiment_score,0) AS sentiment,
              COALESCE(a.quality_score,0) AS quality, COALESCE(a.tldr_zh,'') AS tldr_zh,
              COALESCE(a.tldr_en,'') AS tldr_en, a.themes AS themes
         FROM asia_posts p
         LEFT JOIN asia_analysis a ON a.post_id = p.id
        WHERE p.market = ? AND p.ticker = ?
        ORDER BY (a.post_id IS NOT NULL) DESC,
                 CASE WHEN a.stance IN ('bull','bear') THEN 0 ELSE 1 END,
                 a.quality_score DESC, (p.likes + p.comments) DESC, p.created_utc DESC
        LIMIT ?`,
      market, ticker, limit
    );
    return rows.map((r) => ({
      id: r.id, market: r.market, ticker: r.ticker, source: r.source, origin: r.origin ?? "live",
      author: r.author ?? "", title: r.title ?? "", body: r.body ?? "", label: r.label ?? null,
      url: r.url ?? "", likes: r.likes ?? 0, dislikes: r.dislikes ?? 0,
      views: r.views ?? 0, comments: r.comments ?? 0, images: r.images ?? 0, verified: r.verified ?? 0,
      created: r.created ?? "", stance: r.stance, sentiment: r.sentiment, quality: r.quality,
      tldr_zh: r.tldr_zh, tldr_en: r.tldr_en, themes: parseJSON<string[]>(r.themes, []),
    }));
  }, []);
}

export function getAsiaMeta(): AsiaMeta {
  return safe(() => {
    const c = get<any>(
      `SELECT (SELECT COUNT(*) FROM asia_posts) AS posts,
              (SELECT COUNT(*) FROM asia_analysis) AS analyzed,
              (SELECT COUNT(DISTINCT market) FROM asia_posts) AS markets,
              (SELECT COUNT(DISTINCT ticker) FROM asia_posts) AS tickers,
              (SELECT MIN(created_utc) FROM asia_posts) AS firstDay,
              (SELECT MAX(created_utc) FROM asia_posts) AS lastDay`
    );
    const u = get<{ ts: string }>("SELECT MAX(updated_at) AS ts FROM asia_ticker_summary");
    return {
      posts: c?.posts ?? 0, analyzed: c?.analyzed ?? 0, markets: c?.markets ?? 0,
      tickers: c?.tickers ?? 0, lastUpdated: u?.ts ?? null,
      firstDay: c?.firstDay ?? null, lastDay: c?.lastDay ?? null,
    };
  }, { posts: 0, analyzed: 0, markets: 0, tickers: 0, lastUpdated: null, firstDay: null, lastDay: null });
}

// ----- 维度：每标的×市场的声量与互动聚合（帖数/赞/评论/浏览/认证/带图）-----
export interface AsiaVolumeRow {
  market: string; ticker: string; n: number;
  likes: number; comments: number; views: number; verified: number; withImage: number;
}
export function getAsiaVolume(): AsiaVolumeRow[] {
  return safe(() => all<AsiaVolumeRow>(
    `SELECT market, ticker, COUNT(*) AS n,
            COALESCE(SUM(likes),0) AS likes, COALESCE(SUM(comments),0) AS comments,
            COALESCE(SUM(views),0) AS views, COALESCE(SUM(verified),0) AS verified,
            COALESCE(SUM(CASE WHEN images>0 THEN 1 ELSE 0 END),0) AS withImage
       FROM asia_posts GROUP BY market, ticker`
  ), []);
}

// ----- 时间序列：每标的×每日 的声量 + 加权情绪（来自全量 flash 打分 asia_posts.sentiment）-----
export interface AsiaDayTicker {
  ticker: string; day: string; vol: number; jpVol: number; krVol: number; senti: number; sentiN: number;
}
export function getAsiaDailyByTicker(): AsiaDayTicker[] {
  return safe(() => {
    const rows = all<{ ticker: string; day: string; market: string; n: number; ssum: number; sn: number }>(
      `SELECT ticker, substr(created_utc,1,10) AS day, market, COUNT(*) AS n,
              COALESCE(SUM(sentiment),0) AS ssum, COUNT(sentiment) AS sn
         FROM asia_posts WHERE created_utc IS NOT NULL
        GROUP BY ticker, day, market`
    );
    const m = new Map<string, AsiaDayTicker & { _ssum: number }>();
    for (const r of rows) {
      const k = `${r.ticker}:${r.day}`;
      const e = m.get(k) ?? { ticker: r.ticker, day: r.day, vol: 0, jpVol: 0, krVol: 0, senti: 0, sentiN: 0, _ssum: 0 };
      e.vol += r.n;
      if (r.market === "jp") e.jpVol += r.n; else if (r.market === "kr") e.krVol += r.n;
      e._ssum += r.ssum; e.sentiN += r.sn;
      m.set(k, e);
    }
    return [...m.values()].map(({ _ssum, ...e }) => ({ ...e, senti: e.sentiN ? +(_ssum / e.sentiN).toFixed(3) : 0 }));
  }, []);
}

// ----- 组合序列（单标的）：每日 声量 / 加权情绪 / 收盘价 —— 供「价格×情绪×声量」叠加指数图 -----
export interface AsiaComboPoint { day: string; vol: number; jpVol: number; krVol: number; senti: number | null; price: number | null; }
export function getAsiaTickerSeries(ticker: string, days = 10): AsiaComboPoint[] {
  return safe(() => {
    const disc = all<{ day: string; market: string; n: number; ssum: number; sn: number }>(
      `SELECT substr(created_utc,1,10) AS day, market, COUNT(*) AS n,
              COALESCE(SUM(sentiment),0) AS ssum, COUNT(sentiment) AS sn
         FROM asia_posts WHERE ticker=? AND created_utc IS NOT NULL GROUP BY day, market`, ticker
    );
    const price = all<{ day: string; close: number }>("SELECT day, close FROM asia_price WHERE ticker=?", ticker);
    const dayMap = new Map<string, { jpVol: number; krVol: number; ssum: number; sn: number }>();
    for (const r of disc) {
      const e = dayMap.get(r.day) ?? { jpVol: 0, krVol: 0, ssum: 0, sn: 0 };
      if (r.market === "jp") e.jpVol += r.n; else if (r.market === "kr") e.krVol += r.n;
      e.ssum += r.ssum; e.sn += r.sn;
      dayMap.set(r.day, e);
    }
    const priceMap = new Map(price.map((p) => [p.day, p.close]));
    const allDays = [...new Set([...dayMap.keys(), ...priceMap.keys()])].sort().slice(-days);
    return allDays.map((d) => {
      const e = dayMap.get(d);
      return {
        day: d, vol: (e?.jpVol ?? 0) + (e?.krVol ?? 0), jpVol: e?.jpVol ?? 0, krVol: e?.krVol ?? 0,
        senti: e && e.sn ? +(e.ssum / e.sn).toFixed(3) : null,
        price: priceMap.has(d) ? (priceMap.get(d) as number) : null,
      };
    });
  }, []);
}

// ----- 台湾 PTT Stock 板级专属：[類別] 分布 + 热门提及标的（综合板，无单一 ticker）-----
const TW_STOCKS: { name: string; aliases: string[] }[] = [
  { name: "台積電", aliases: ["台積電", "台積", "2330", "tsmc", "TSMC"] },
  { name: "聯發科", aliases: ["聯發科", "2454"] },
  { name: "鴻海", aliases: ["鴻海", "2317"] },
  { name: "廣達", aliases: ["廣達", "2382"] },
  { name: "台達電", aliases: ["台達電", "2308"] },
  { name: "大盤/加權", aliases: ["大盤", "加權", "台股", "指數"] },
  { name: "0050/ETF", aliases: ["0050", "0056", "00尾", "ETF"] },
  { name: "輝達 NVDA", aliases: ["輝達", "NVDA", "nvidia", "黃仁勳"] },
  { name: "聯電", aliases: ["聯電", "2303"] },
  { name: "記憶體", aliases: ["記憶體", "美光", "南亞科", "華邦", "DRAM"] },
];
export interface AsiaTwBreakdown { categories: { label: string; n: number }[]; stocks: { name: string; n: number }[]; }
export function getAsiaTwBreakdown(): AsiaTwBreakdown {
  return safe(() => {
    const categories = all<{ label: string; n: number }>(
      `SELECT COALESCE(NULLIF(label,''),'其他') AS label, COUNT(*) AS n
         FROM asia_posts WHERE market='tw' GROUP BY label ORDER BY n DESC LIMIT 8`
    );
    const rows = all<{ t: string }>("SELECT (title || ' ' || COALESCE(body,'')) AS t FROM asia_posts WHERE market='tw'");
    const blob = rows.map((r) => r.t).join("\n");
    const stocks = TW_STOCKS
      .map((s) => ({ name: s.name, n: s.aliases.reduce((acc, a) => acc + (blob.split(a).length - 1), 0) }))
      .filter((s) => s.n > 0).sort((a, b) => b.n - a.n).slice(0, 8);
    return { categories, stocks };
  }, { categories: [], stocks: [] });
}

// ----- 异动：最大单日「声量/情绪」环比变化（突变）-----
export interface AsiaMover { ticker: string; day: string; metric: "volume" | "sentiment"; prev: number; cur: number; delta: number; }
export function getAsiaMovers(perMetric = 4): { volume: AsiaMover[]; sentiment: AsiaMover[] } {
  const byTicker = new Map<string, AsiaDayTicker[]>();
  for (const r of getAsiaDailyByTicker()) {
    const arr = byTicker.get(r.ticker) ?? [];
    arr.push(r); byTicker.set(r.ticker, arr);
  }
  const vol: AsiaMover[] = [], sen: AsiaMover[] = [];
  for (const [ticker, arr] of byTicker) {
    arr.sort((a, b) => a.day.localeCompare(b.day));
    for (let i = 1; i < arr.length; i++) {
      const p = arr[i - 1], c = arr[i];
      vol.push({ ticker, day: c.day, metric: "volume", prev: p.vol, cur: c.vol, delta: c.vol - p.vol });
      if (p.sentiN >= 3 && c.sentiN >= 3) // 只在样本足够时算情绪变化
        sen.push({ ticker, day: c.day, metric: "sentiment", prev: p.senti, cur: c.senti, delta: +(c.senti - p.senti).toFixed(3) });
    }
  }
  vol.sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta));
  sen.sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta));
  return { volume: vol.slice(0, perMetric), sentiment: sen.slice(0, perMetric) };
}

// ----- 维度：近 N 天每日声量（jp/kr 拆分），按日历日补零 -----
export interface AsiaDailyRow { day: string; jp: number; kr: number; total: number; }
export function getAsiaDaily(days = 7): AsiaDailyRow[] {
  return safe(() => {
    const rows = all<{ day: string; market: string; n: number }>(
      `SELECT substr(created_utc,1,10) AS day, market, COUNT(*) AS n
         FROM asia_posts WHERE created_utc IS NOT NULL
        GROUP BY day, market`
    );
    const byDay = new Map<string, { jp: number; kr: number }>();
    for (const r of rows) {
      const e = byDay.get(r.day) ?? { jp: 0, kr: 0 };
      if (r.market === "jp") e.jp += r.n; else if (r.market === "kr") e.kr += r.n;
      byDay.set(r.day, e);
    }
    // 取最近 N 个日历日（以数据最新日为基准），缺失补零
    const last = all<{ d: string }>("SELECT MAX(substr(created_utc,1,10)) AS d FROM asia_posts")[0]?.d;
    const anchor = last ? new Date(last + "T00:00:00Z") : new Date();
    const out: AsiaDailyRow[] = [];
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(anchor.getTime() - i * 86400000).toISOString().slice(0, 10);
      const e = byDay.get(d) ?? { jp: 0, kr: 0 };
      out.push({ day: d, jp: e.jp, kr: e.kr, total: e.jp + e.kr });
    }
    return out;
  }, []);
}

// ===================== 机构级指标（对标 Swaggy/Buzzberg/E*TRADE）=====================
// 下面这些查询专为「让每个抓取/分析维度都发挥作用」而加：净情绪、认证持仓、赞踩认可度、
// 干货质量、情绪日历热力、主题倾向、日本自评标签。各面板按数据可得性自动只显示有值的市场。

// ----- 情绪日历热力：每标的(行) × 每日(列) 的加权情绪（来自 flash 全量打分）-----
export interface AsiaHeat { tickers: string[]; days: string[]; cells: [number, number, number][]; }
export function getAsiaSentiHeat(days = 7): AsiaHeat {
  return safe(() => {
    const rows = all<{ ticker: string; day: string; ssum: number; sn: number }>(
      `SELECT ticker, substr(created_utc,1,10) AS day,
              COALESCE(SUM(sentiment),0) AS ssum, COUNT(sentiment) AS sn
         FROM asia_posts
        WHERE created_utc IS NOT NULL AND sentiment IS NOT NULL
        GROUP BY ticker, day`
    );
    const last = all<{ d: string }>("SELECT MAX(substr(created_utc,1,10)) AS d FROM asia_posts")[0]?.d;
    const anchor = last ? new Date(last + "T00:00:00Z") : new Date();
    const dayList: string[] = [];
    for (let i = days - 1; i >= 0; i--) dayList.push(new Date(anchor.getTime() - i * 86400000).toISOString().slice(0, 10));
    const totByT = new Map<string, number>();
    const valByKey = new Map<string, { ssum: number; sn: number }>();
    for (const r of rows) {
      totByT.set(r.ticker, (totByT.get(r.ticker) ?? 0) + r.sn);
      valByKey.set(`${r.ticker}:${r.day}`, { ssum: r.ssum, sn: r.sn });
    }
    const tickers = [...totByT.entries()].sort((a, b) => b[1] - a[1]).map(([tk]) => tk);
    const cells: [number, number, number][] = [];
    tickers.forEach((tk, yi) => dayList.forEach((d, xi) => {
      const e = valByKey.get(`${tk}:${d}`);
      if (e && e.sn) cells.push([xi, yi, +(e.ssum / e.sn).toFixed(3)]);
    }));
    return { tickers, days: dayList, cells };
  }, { tickers: [], days: [], cells: [] });
}

// ----- 互动富维度聚合：每市场×标的 的赞/踩/浏览/评论/带图/认证 + 认可度 + 平均干货分 -----
export interface AsiaEng {
  market: string; ticker: string; n: number;
  likes: number; dislikes: number; views: number; comments: number; images: number; verified: number;
  approval: number | null; quality: number | null;
}
export function getAsiaEngagement(): AsiaEng[] {
  return safe(() => {
    const rows = all<any>(
      `SELECT p.market, p.ticker, COUNT(*) AS n,
              COALESCE(SUM(p.likes),0) AS likes, COALESCE(SUM(p.dislikes),0) AS dislikes,
              COALESCE(SUM(p.views),0) AS views, COALESCE(SUM(p.comments),0) AS comments,
              COALESCE(SUM(CASE WHEN p.images>0 THEN 1 ELSE 0 END),0) AS images,
              COALESCE(SUM(CASE WHEN p.verified THEN 1 ELSE 0 END),0) AS verified,
              AVG(a.quality_score) AS quality
         FROM asia_posts p LEFT JOIN asia_analysis a ON a.post_id = p.id
        GROUP BY p.market, p.ticker`
    );
    return rows.map((r) => {
      const ld = (r.likes ?? 0) + (r.dislikes ?? 0);
      return {
        market: r.market, ticker: r.ticker, n: r.n ?? 0,
        likes: r.likes ?? 0, dislikes: r.dislikes ?? 0, views: r.views ?? 0,
        comments: r.comments ?? 0, images: r.images ?? 0, verified: r.verified ?? 0,
        approval: ld > 0 ? +((r.likes ?? 0) / ld).toFixed(3) : null,
        quality: r.quality != null ? +Number(r.quality).toFixed(3) : null,
      };
    });
  }, []);
}

// ----- 聪明钱代理：持股认证用户 vs 普通用户 的平均情绪（Naver isHolderVerified）-----
export interface AsiaVerSplit { market: string; verN: number; verAvg: number | null; crowdN: number; crowdAvg: number | null; }
export function getAsiaVerifiedSplit(): AsiaVerSplit[] {
  return safe(() => {
    const rows = all<{ market: string; verified: number; n: number; avg: number }>(
      `SELECT market, verified, COUNT(*) AS n, AVG(sentiment) AS avg
         FROM asia_posts WHERE sentiment IS NOT NULL GROUP BY market, verified`
    );
    const m = new Map<string, AsiaVerSplit>();
    for (const r of rows) {
      const e = m.get(r.market) ?? { market: r.market, verN: 0, verAvg: null, crowdN: 0, crowdAvg: null };
      if (r.verified) { e.verN = r.n; e.verAvg = +Number(r.avg).toFixed(3); }
      else { e.crowdN = r.n; e.crowdAvg = +Number(r.avg).toFixed(3); }
      m.set(r.market, e);
    }
    return [...m.values()].filter((e) => e.verN > 0); // 只保留确有认证用户的市场（=韩国 Naver）
  }, []);
}

// ----- 日本散户自评标签（Yahoo JP 强买/买/观望/卖/强卖，类 Stocktwits 自评）-----
export interface AsiaSelfRate { label: string; n: number; }
export function getAsiaJpSelfRating(): AsiaSelfRate[] {
  return safe(() => all<AsiaSelfRate>(
    `SELECT label, COUNT(*) AS n FROM asia_posts
      WHERE market='jp' AND label IS NOT NULL AND label<>'' GROUP BY label`
  ), []);
}

// ----- 主题情绪倾向：AI 主题标签的多空分布（来自 asia_analysis.themes × stance）-----
export interface AsiaThemeStance { theme: string; n: number; bull: number; bear: number; }
export function getAsiaThemeStance(): AsiaThemeStance[] {
  return safe(() => {
    const rows = all<{ themes: string; stance: string }>(
      `SELECT themes, stance FROM asia_analysis
        WHERE themes IS NOT NULL AND themes<>'' AND themes<>'[]'`
    );
    const m = new Map<string, AsiaThemeStance>();
    for (const r of rows) {
      for (const th of parseJSON<string[]>(r.themes, [])) {
        const e = m.get(th) ?? { theme: th, n: 0, bull: 0, bear: 0 };
        e.n++; if (r.stance === "bull") e.bull++; else if (r.stance === "bear") e.bear++;
        m.set(th, e);
      }
    }
    return [...m.values()].sort((a, b) => b.n - a.n).slice(0, 12);
  }, []);
}
