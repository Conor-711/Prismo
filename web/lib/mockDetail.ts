// 标的详情页 / 地区详情页的「模块化看板」演示数据（mock）。
// 真实管线尚未产出这些维度（基线/偏离/传导路径/期权占比…），此处用确定性伪随机生成
// 占位数据，纯为前端模块/图表的视觉与交互原型。后续接真实数据时替换本文件即可。
//
// 确定性：同一 symbol / region 每次构建生成相同结果（seed = 字符串哈希），避免快照漂移。

import { REGION_ORDER } from "./regions";

export type Bi = { zh: string; en: string };

// ---- 确定性伪随机 ----
function rng(strSeed: string) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < strSeed.length; i++) {
    h ^= strSeed.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return () => {
    h += 0x6d2b79f5;
    let t = Math.imul(h ^ (h >>> 15), 1 | h);
    t ^= t + Math.imul(t ^ (t >>> 7), 61 | t);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const r2 = (n: number, d = 2) => Math.round(n * 10 ** d) / 10 ** d;

// ---- 文案池 ----
const TOPICS: Bi[] = [
  { zh: "财报指引上调", en: "Raised guidance" },
  { zh: "数据中心需求强劲", en: "Data-center demand" },
  { zh: "供应链 / 产能瓶颈", en: "Supply / capacity" },
  { zh: "估值偏高担忧", en: "Valuation concern" },
  { zh: "新品发布预期", en: "Product launch" },
  { zh: "监管审查风险", en: "Regulatory risk" },
  { zh: "大客户订单", en: "Major customer order" },
  { zh: "毛利率改善", en: "Margin improvement" },
  { zh: "竞争格局恶化", en: "Competition risk" },
  { zh: "回购 / 分红", en: "Buyback / dividend" },
  { zh: "宏观利率压力", en: "Rate pressure" },
  { zh: "AI 叙事降温", en: "AI narrative cooling" },
  { zh: "内部人减持", en: "Insider selling" },
  { zh: "做空报告", en: "Short report" },
];
const EVENTS: { t: Bi; type: "earnings" | "product" | "macro" | "regulatory" }[] = [
  { t: { zh: "Q2 财报", en: "Q2 earnings" }, type: "earnings" },
  { t: { zh: "新品发布会", en: "Product keynote" }, type: "product" },
  { t: { zh: "FOMC 利率决议", en: "FOMC decision" }, type: "macro" },
  { t: { zh: "反垄断听证", en: "Antitrust hearing" }, type: "regulatory" },
  { t: { zh: "投资者日", en: "Investor day" }, type: "product" },
  { t: { zh: "CPI 数据", en: "CPI print" }, type: "macro" },
];
// 地区本地化背景注解
const LOCAL_NOTE: Record<string, Bi> = {
  us: { zh: "期权 / 0DTE 文化浓", en: "Heavy options / 0DTE culture" },
  cn: { zh: "估值锚 + 政策预期主导", en: "Valuation anchor + policy bets" },
  jp: { zh: "NISA 长线 + 円安买美股", en: "NISA long-hold + weak-yen buying" },
  kr: { zh: "서학개미 + 杠杆ETF + 汇率敏感", en: "Seohak-ant + leveraged ETF + FX-sensitive" },
  tw: { zh: "供应链视角 + 當沖客", en: "Supply-chain lens + day-traders" },
};
const PERSONA: Record<string, Bi> = {
  us: { zh: "WSB 投机派", en: "WSB punters" },
  cn: { zh: "雪球价值党", en: "Xueqiu value crowd" },
  jp: { zh: "NISA 长线族", en: "NISA long-holders" },
  kr: { zh: "서학개미", en: "Seohak-ant" },
  tw: { zh: "PTT 當沖族", en: "PTT day-traders" },
};
const SECTORS: Bi[] = [
  { zh: "AI / 半导体", en: "AI / Semis" },
  { zh: "新能源车", en: "EV" },
  { zh: "加密相关", en: "Crypto-linked" },
  { zh: "云 / 软件", en: "Cloud / SaaS" },
  { zh: "金融", en: "Financials" },
  { zh: "迷因股", en: "Meme stocks" },
  { zh: "中概", en: "China ADRs" },
];

function pick<T>(arr: T[], rnd: () => number): T {
  return arr[Math.floor(rnd() * arr.length)];
}
function pickN<T>(arr: T[], n: number, rnd: () => number): T[] {
  const pool = [...arr];
  const out: T[] = [];
  for (let i = 0; i < n && pool.length; i++) out.push(pool.splice(Math.floor(rnd() * pool.length), 1)[0]);
  return out;
}
function trend(rnd: () => number, base: number, vol: number, len = 14, drift = 0) {
  const out: number[] = [];
  let v = base;
  for (let i = 0; i < len; i++) {
    v += (rnd() - 0.5) * vol + drift;
    out.push(r2(Math.max(0, v)));
  }
  return out;
}

// =====================================================================
// 标的详情（纵切一只票）
// =====================================================================
export function getTickerMock(symbol: string) {
  const rnd = rng("T:" + symbol);
  const regions = REGION_ORDER as readonly string[];

  // 1. 异动：4 维度
  const dimDefs: { key: string; label: Bi; unit: string; baseSpan: [number, number] }[] = [
    { key: "volume", label: { zh: "讨论量", en: "Volume" }, unit: "", baseSpan: [120, 600] },
    { key: "sentiment", label: { zh: "情绪", en: "Sentiment" }, unit: "", baseSpan: [-0.2, 0.3] },
    { key: "divergence", label: { zh: "分歧度", en: "Divergence" }, unit: "", baseSpan: [0.3, 0.6] },
    { key: "newtopic", label: { zh: "新话题", en: "New topics" }, unit: "", baseSpan: [1, 4] },
  ];
  const anomalyDims = dimDefs.map((d) => {
    const base = r2(d.baseSpan[0] + rnd() * (d.baseSpan[1] - d.baseSpan[0]), d.key === "sentiment" || d.key === "divergence" ? 2 : 0);
    const sigma = r2(1.4 + rnd() * 3.6, 1);
    const up = rnd() > 0.42;
    const mult = d.key === "volume" ? r2(1.3 + rnd() * 2.5, 1) : 0;
    const cur = d.key === "volume"
      ? Math.round(base * mult)
      : d.key === "newtopic"
      ? Math.round(base + (up ? 1 : -1) * (1 + rnd() * 3))
      : r2(base + (up ? 1 : -1) * (0.1 + rnd() * 0.25), 2);
    return {
      key: d.key,
      label: d.label,
      current: cur,
      baseline: base,
      sigma,
      multiple: mult || null,
      direction: up ? "up" : "down",
      sinceHours: Math.round(2 + rnd() * 40),
      durationHours: Math.round(3 + rnd() * 30),
      intensity: sigma > 4 ? 3 : sigma > 2.5 ? 2 : 1,
      spark: trend(rnd, d.key === "volume" ? base : Math.max(0.1, base + 0.5), d.key === "volume" ? base * 0.4 : 0.18, 14, up ? (d.key === "volume" ? base * 0.06 : 0.02) : -(d.key === "volume" ? base * 0.04 : 0.015)),
    };
  });
  const regionContrib = regions
    .map((rg) => ({ region: rg, pct: r2(rnd(), 2) }))
    .sort((a, b) => b.pct - a.pct);
  const csum = regionContrib.reduce((s, x) => s + x.pct, 0) || 1;
  regionContrib.forEach((x) => (x.pct = Math.round((x.pct / csum) * 100)));

  // 2. 跨区域视角 ×5
  const regionViews = regions.map((rg) => {
    const baseVol = Math.round(60 + rnd() * 500);
    const mult = r2(0.6 + rnd() * 2.2, 1);
    const senti = r2(-0.5 + rnd() * 1.0, 2);
    const bull = Math.round(30 + rnd() * 45);
    const lead = Math.round((rnd() - 0.5) * 48); // 小时
    return {
      region: rg,
      posts: Math.round(baseVol * mult),
      vsBaseline: mult,
      share: 0, // 下面归一
      sentiment: senti,
      sentimentChange: r2((rnd() - 0.5) * 0.4, 2),
      bullPct: bull,
      bearPct: Math.round((100 - bull) * (0.5 + rnd() * 0.4)),
      topics: pickN(TOPICS, 3, rnd),
      hasUnique: rnd() > 0.6,
      leadHours: lead,
      riskAppetite: Math.round(10 + rnd() * 60), // 期权+杠杆占比 %
    };
  });
  const vsum = regionViews.reduce((s, x) => s + x.posts, 0) || 1;
  regionViews.forEach((x) => (x.share = Math.round((x.posts / vsum) * 100)));

  // 3. 海外信息差（传导路径）
  const infoGap = pickN(TOPICS, 2, rnd).map((tp) => {
    const order = pickN([...regions], 5, rnd);
    let acc = 0;
    const path = order.map((rg, i) => {
      acc += i === 0 ? 0 : Math.round(2 + rnd() * 30);
      return { region: rg, offsetHours: acc, isCn: rg === "cn" };
    });
    const cnIdx = path.findIndex((p) => p.isCn);
    return {
      topic: tp,
      firstRegion: order[0],
      firstSeen: `${Math.round(1 + rnd() * 5)}d ago`,
      path,
      cnPresent: cnIdx >= 0,
      cnLagHours: cnIdx > 0 ? path[cnIdx].offsetHours : 0,
      leadHours: cnIdx > 0 ? path[cnIdx].offsetHours : Math.round(12 + rnd() * 40),
      growth: Math.round(20 + rnd() * 180), // %
      novel: rnd() > 0.5,
    };
  });

  // 4. 地区独有叙事
  const uniqueNarratives = pickN([...regions], 2, rnd).map((rg) => ({
    region: rg,
    topic: pick(TOPICS, rnd),
    heatVsBase: r2(1.2 + rnd() * 2.5, 1),
    sentiment: r2(-0.4 + rnd() * 0.9, 2),
    firstSeen: `${Math.round(1 + rnd() * 8)}d ago`,
    isNewVar: rnd() > 0.5,
    note: LOCAL_NOTE[rg],
    diff: {
      zh: `仅 ${rg.toUpperCase()} 区在讨论，全球主线仍聚焦${pick(TOPICS, rnd).zh}`,
      en: `Only ${rg.toUpperCase()} talks this; global mainline still on ${pick(TOPICS, rnd).en}`,
    } as Bi,
  }));

  // 5. 多空 & 共识分歧
  const bull = Math.round(38 + rnd() * 30);
  const bullBear = {
    bullPct: bull,
    bearPct: 100 - bull,
    willChange: r2((rnd() - 0.5) * 16, 1), // 多空意愿变化（多头占比 Δ）
    divergence: r2(0.4 + rnd() * 0.45, 2),
    divergenceChange: r2((rnd() - 0.5) * 0.3, 2),
    consensus: Math.round(40 + rnd() * 50), // 共识强度 0..100
    bullThesis: pick(TOPICS, rnd),
    bearThesis: pick(TOPICS, rnd),
    authorBull: Math.round(40 + rnd() * 35), // 高质量作者多头占比
  };

  // 6. 最强反方
  const counter = {
    bull: { thesis: pick(TOPICS, rnd), region: pick([...regions], rnd), support: Math.round(45 + rnd() * 40) },
    bear: { thesis: pick(TOPICS, rnd), region: pick([...regions], rnd), support: Math.round(35 + rnd() * 45) },
    counterDiscussed: Math.round(15 + rnd() * 50), // 反方被讨论度 %
    counterStrength: Math.round(30 + rnd() * 60),
    counterSources: pickN([...regions], 2, rnd),
  };

  // 7. 风险温度 / 阶段
  const temp = Math.round(20 + rnd() * 70);
  const risk = {
    temp,
    optionsPct: r2(8 + rnd() * 30, 1),
    optionsBase: r2(6 + rnd() * 10, 1),
    callPct: Math.round(45 + rnd() * 40),
    leveragedPct: r2(4 + rnd() * 18, 1),
    leveragedBase: r2(3 + rnd() * 6, 1),
    memePct: r2(3 + rnd() * 22, 1),
    memeBase: r2(2 + rnd() * 5, 1),
    newcomers: Math.round(20 + rnd() * 240),
    newcomersBase: Math.round(15 + rnd() * 60),
    breadth: Math.round(120 + rnd() * 900),
    breadthChange: Math.round((rnd() - 0.4) * 200),
    stage: temp > 70 ? { zh: "过热", en: "Overheated" } : temp > 45 ? { zh: "升温", en: "Heating" } : { zh: "早期", en: "Early" },
  };

  // 8. 大家在等什么
  const waiting = pickN(EVENTS, 2, rnd).map((e) => ({
    event: e.t,
    type: e.type,
    daysOut: Math.round(2 + rnd() * 40),
    focus: pick(TOPICS, rnd),
    heat: Math.round(30 + rnd() * 65),
    regionAttention: regions.map((rg) => ({ region: rg, pct: Math.round(5 + rnd() * 35) })),
    preLean: r2(-0.4 + rnd() * 0.8, 2),
  }));

  return {
    anomaly: {
      dims: anomalyDims,
      attribution: pick(
        [
          { zh: "讨论量飙升主要由「财报指引上调」驱动，韩台两区贡献过半。", en: "Volume spike driven by 'raised guidance', with KR+TW contributing over half." },
          { zh: "情绪转弱由「做空报告」与「估值担忧」叠加引发，美区领跌。", en: "Sentiment drop from a short report + valuation worry; US leads the decline." },
          { zh: "分歧度走阔：多头押注产能，空头担心需求见顶。", en: "Divergence widening: bulls bet on capacity, bears fear peak demand." },
        ],
        rnd
      ) as Bi,
      regionContrib,
      newTopic: {
        topic: pick(TOPICS, rnd),
        firstSeen: `${Math.round(3 + rnd() * 30)}h ago`,
        growth: Math.round(60 + rnd() * 240),
        regions: pickN([...regions], 2, rnd),
      },
    },
    regionViews,
    infoGap,
    uniqueNarratives,
    bullBear,
    counter,
    risk,
    waiting,
  };
}

export type TickerMock = ReturnType<typeof getTickerMock>;

// =====================================================================
// 地区详情（横切一个房间）
// =====================================================================
export function getRegionMock(region: string) {
  const rnd = rng("R:" + region);
  const regions = REGION_ORDER as readonly string[];
  const TICKERS = ["NVDA", "TSLA", "MSFT", "AVGO", "MU", "GOOGL", "PLTR", "INTC", "MSTR", "SMCI", "AMD", "META", "COIN", "HOOD", "ARM"];

  // 1. 地区脉搏
  const senti = r2(-0.4 + rnd() * 0.8, 2);
  const pulse = {
    sentiment: senti,
    sentimentChange: r2((rnd() - 0.5) * 0.4, 2),
    activity: r2(0.7 + rnd() * 1.8, 1), // vs 常态倍数
    activityChange: r2((rnd() - 0.4) * 0.6, 1),
    riskIndex: Math.round(20 + rnd() * 70),
    bullPct: Math.round(35 + rnd() * 35),
    humanPct: Math.round(55 + rnd() * 40), // 真人占比 / 信噪比
    spark: trend(rnd, 1, 0.4, 16, 0.02),
  };

  // 2. 热榜 & 发现（三类榜单）
  const mkRow = (t: string, kind: "abs" | "surge" | "new", rnk: number) => {
    const bull = Math.round(30 + rnd() * 45);
    return {
      ticker: t,
      rank: rnk,
      posts: Math.round((kind === "abs" ? 500 : 120) - rnk * (kind === "abs" ? 35 : 8) + rnd() * 40),
      vsBaseline: r2(kind === "surge" ? 2 + rnd() * 6 : 1 + rnd() * 1.5, 1),
      sentiment: r2(-0.4 + rnd() * 0.9, 2),
      sentimentChange: r2((rnd() - 0.5) * 0.5, 2),
      bullPct: bull,
      bearPct: 100 - bull,
      isNew: kind === "new",
    };
  };
  const hot = {
    abs: pickN(TICKERS, 6, rnd).map((t, i) => mkRow(t, "abs", i + 1)),
    surge: pickN(TICKERS, 6, rnd).map((t, i) => mkRow(t, "surge", i + 1)).sort((a, b) => b.vsBaseline - a.vsBaseline),
    fresh: pickN(TICKERS, 4, rnd).map((t, i) => mkRow(t, "new", i + 1)),
  };

  // 3. 地区异动
  const anomalies = pickN(TICKERS, 3, rnd).map((t) => ({
    target: t,
    dim: pick([{ zh: "讨论量", en: "Volume" }, { zh: "情绪", en: "Sentiment" }, { zh: "分歧度", en: "Divergence" }, { zh: "新话题", en: "New topic" }] as Bi[], rnd),
    sigma: r2(1.5 + rnd() * 4, 1),
    direction: rnd() > 0.5 ? "up" : "down",
    sinceHours: Math.round(2 + rnd() * 36),
    attribution: pick(TOPICS, rnd),
  }));

  // 4. 地区独有叙事
  const uniqueNarratives = pickN(TOPICS, 3, rnd).map((tp) => ({
    topic: tp,
    heatVsBase: r2(1.3 + rnd() * 2.6, 1),
    sentiment: r2(-0.4 + rnd() * 0.9, 2),
    note: LOCAL_NOTE[region] ?? { zh: "本地视角", en: "Local lens" },
    isNewVar: rnd() > 0.5,
    tickers: pickN(TICKERS, 2, rnd),
  }));

  // 5. 本区 vs 全球（差值）
  const dims: Bi[] = [
    { zh: "情绪", en: "Sentiment" },
    { zh: "风险偏好", en: "Risk appetite" },
    { zh: "AI/半导体关注", en: "AI/Semis focus" },
    { zh: "中概关注", en: "China-ADR focus" },
    { zh: "多空倾向", en: "Bull tilt" },
  ];
  const vsGlobal = dims.map((d) => {
    const local = Math.round(20 + rnd() * 70);
    const global = Math.round(30 + rnd() * 45);
    return { dim: d, local, global, diff: local - global };
  });
  const standout = pick(
    [
      { zh: "几乎不碰中概股（关注度远低于全球均值）", en: "Barely touches China ADRs (far below global avg)" },
      { zh: "风险偏好显著高于全球（杠杆 / 期权偏好）", en: "Risk appetite well above global (leverage / options)" },
      { zh: "AI/半导体关注度领先全球", en: "AI/Semis focus leads the globe" },
    ],
    rnd
  ) as Bi;

  // 6. 地区性格画像（雷达）
  const persona = {
    leverage: Math.round(10 + rnd() * 80),
    meme: Math.round(10 + rnd() * 80),
    shortTerm: Math.round(20 + rnd() * 75), // 越高越短线/当冲
    quality: Math.round(20 + rnd() * 70), // DD/真人占比
    concentration: Math.round(20 + rnd() * 75), // 注意力集中度
    persona: PERSONA[region] ?? { zh: "本地散户", en: "Local retail" },
  };

  // 7. 注意力轮动
  const rotation = pickN(SECTORS, 5, rnd).map((s) => {
    const ch = r2((rnd() - 0.45) * 80, 0);
    return { sector: s, heat: Math.round(20 + rnd() * 70), change: ch, flow: ch >= 0 ? "in" : "out" };
  });
  const rotateFrom = pick(SECTORS, rnd);
  const rotateTo = pick(SECTORS.filter((s) => s.zh !== rotateFrom.zh), rnd);

  // 8. 今日引爆
  const trigger = {
    headline: pick(
      [
        { zh: "某大行上调目标价，引爆 AI 板块讨论", en: "A bank raised PT, igniting AI-sector chatter" },
        { zh: "汇率急贬，散户涌入杠杆多头", en: "Sharp FX move; retail piles into leveraged longs" },
        { zh: "做空机构报告刷屏，情绪急转", en: "Short-seller report goes viral; mood flips" },
      ],
      rnd
    ) as Bi,
    targets: pickN(TICKERS, 3, rnd),
    volumeDelta: Math.round(80 + rnd() * 320), // %
    sentimentShift: r2((rnd() - 0.5) * 0.6, 2),
    scope: rnd() > 0.5 ? "global" : "local",
  };

  return { region, pulse, hot, anomalies, uniqueNarratives, vsGlobal, standout, persona, rotation, rotateFrom, rotateTo, trigger, allRegions: regions };
}

export type RegionMock = ReturnType<typeof getRegionMock>;

// =====================================================================
// 第 1 块：个体观点（主观 × KOL）—— 日 K 线 + 每日 KOL 观点气泡（mock）
// 来源 X / YouTube / Reddit / 雪球；气泡大小 ∝ 互动数。真实管线到位后替换。
// =====================================================================
export type KolSource = "x" | "youtube" | "reddit" | "xueqiu";
export type Stance = "bull" | "bear" | "neutral";

// X/Twitter 推文的逐项互动数（用于卡片底部的图标行；其他源仍只用合计 interactions）。
export interface TweetMetrics {
  replies?: number;
  retweets?: number;
  likes?: number;
  quotes?: number;
  views?: number;
  bookmarks?: number;
}
// 帖文下的高互动评论（X：按点赞取 top-N；x_reply 表）。
export interface TweetReply {
  author: string; // @handle
  text: string;
  likes: number;
  url?: string;
  avatar?: string;
}

// YouTube 完整口播的「投资者摘要 + 内容目录」（yt_digest 表，AI 提炼）。
export interface YtChapter {
  title: Bi; // 章节短标题
  seg: number; // 起始 speech 段落下标（YtFullContent 在此埋锚点）
}
export interface YtDigest {
  summary: Bi[]; // 投资者摘要分点（每点 zh/en）
  chapters: YtChapter[]; // 内容目录（有序章节）
}

// YouTube 频道（作者）基础信息（yt_channel 表）：头像旁展示粉丝数/视频数/简介。
export interface YtChannel {
  subscribers?: number; // 粉丝数；-1 = 频道隐藏了订阅数
  videos?: number; // 视频总数
  bio?: string; // 个人简介（频道描述）
  handle?: string; // @handle（customUrl）
}

export interface KolOpinion {
  id: string;
  day: string; // YYYY-MM-DD
  source: KolSource;
  author: string;
  interactions: number; // 点赞 / 转发 / 评论合计
  stance: Stance;
  text: Bi; // 当前语言显示文本（原文/标题；x/雪球=原文，reddit/youtube=双语）
  orig?: string; // 原帖原文（native 语言、未翻译；卡片默认展示）
  trans?: Bi; // 原帖完整忠实翻译（逐句、不压缩；「译」选项首选）
  quote?: Bi; // 本人忠实原话（soundbite，译文回退）
  reason?: Bi; // AI 提炼（不再当原帖卡正文；图表 tooltip 仍用 opinionText）
  points?: { zh: string[]; en: string[] }; // 2-3 条要点（催化剂/数据/目标价/风险）
  url: string;
  avatar?: string; // 作者头像 URL（真实爬取；缺则 UI 用来源色首字母圆形兜底）
  viewpoints?: string[]; // 视角分类键（kol_viewpoint）：有序、首个为主视角；空/缺=other
  relevance?: number; // 与该标的的相关度 0-100（kol_relevance）；缺=未打分
  quality?: number; // 帖子质量 0-100（kol_quality，与标的无关）；缺=未打分
  metrics?: TweetMetrics; // X 推文逐项互动数（赞/转/评/引/看/藏）；仅 source=x
  replies?: TweetReply[]; // 帖文下高互动评论（X，按点赞 top-N）；仅 source=x
  ytSegments?: YtSeg[]; // YouTube「完整口播」：有序段落(书面化口播；多人视频带说话人)；仅 source=youtube
  channel?: YtChannel; // YouTube 频道作者基础信息（粉丝/视频/简介）；仅 source=youtube
  ytDigest?: YtDigest; // YouTube「投资者摘要 + 内容目录」（AI 提炼）；仅 source=youtube
  judgment?: KolJudgment; // 目标价+操作周期（kol_judgment / youtube=yt_judgment；价格已按现价剔噪）
}

// KOL 对该标的的「买入/卖出(目标)价位 + 操作周期」结构化判断（pipeline kol_judgment / yt_judgment，只抽明说）。
// 两侧各支持**区间**(lo/hi，确切价 lo==hi)；"目标价"并入卖出侧。价格在取数层已按现价 0.2–5× band 剔噪。
export interface KolJudgment {
  buyLo?: number; // 买入价位 区间下界（确切价 = buyHi）
  buyHi?: number;
  sellLo?: number; // 卖出/目标价位 区间下界
  sellHi?: number;
  priceRaw?: string; // 价格原话（保留区间/货币符号）
  horizon?: Bi; // 操作周期原话（双语短语）
  bucket?: "short" | "mid" | "long"; // 归一周期档
}

// 「整体数据 · 目标价时间线」一个标记（一条判断的买入侧或卖出侧）：日期 × 价格(区间)。
export interface TargetMark {
  source: KolSource;
  author: string;
  kind: "buy" | "sell"; // 买入 / 卖出·目标
  lo: number; // 价格区间下界（确切价 hi==lo）
  hi: number;
  priceRaw?: string;
  horizon?: Bi; // 操作周期原话
  bucket?: "short" | "mid" | "long"; // 周期档
  reason?: Bi; // 简单依据（hover tooltip）
  date: string; // 下达日 YYYY-MM-DD（x 轴）
  url: string;
}
export interface KolTargetData {
  current: number | null; // 现价基准线
  priceLine: { day: string; close: number }[]; // 股价折线（叠加）
  marks: TargetMark[]; // 买/卖价位标记（按日期落位）
}

// YouTube 视频口播转录的有序段落（yt_fulltext.segments）。
// speech：书面化口播；speaker 仅多人(访谈/播客)有、独白为空。visual 为旧档遗留(现不展示)。
export type YtSeg =
  | { type: "speech"; text: string; speaker?: string }
  | { type: "visual"; caption: string; frame: string };
export interface KolCandle {
  day: string;
  open: number;
  high: number;
  low: number;
  close: number;
}
export interface KolFlow {
  days: KolCandle[];
  opinions: KolOpinion[];
}

const KOL_AUTHORS: Record<KolSource, string[]> = {
  x: ["@DeepValueDan", "@ChartFanatic", "@MacroMaverick", "@OptionsOwl", "@TheRoaringKid"],
  youtube: ["Meet Kevin", "Tom Nash", "Joseph Carlson", "Ticker Symbol YOU", "Graham Stephan"],
  reddit: ["u/DeepFvalue", "u/wsb_oracle", "u/value_DD_guy", "u/SemiAnalyst", "u/macro_monk"],
  xueqiu: ["不明真相的群众", "梁宏", "云蒙", "Ricky", "处镜如初"],
};

function kolText(topic: Bi, stance: Stance): Bi {
  if (stance === "bull") return { zh: `${topic.zh}——继续看多，逢低加仓`, en: `${topic.en} — staying long, adding on dips` };
  if (stance === "bear") return { zh: `${topic.zh}——短线见顶，先减仓观望`, en: `${topic.en} — topping near-term, trimming here` };
  return { zh: `${topic.zh}——先观望，等方向确认`, en: `${topic.en} — sidelined, waiting for confirmation` };
}

export function getKolFlow(symbol: string): KolFlow {
  const rnd = rng("KOL:" + symbol);
  const SOURCES: KolSource[] = ["x", "youtube", "reddit", "xueqiu"];
  const WINDOW_DAYS = 16; // 自然日窗口，跳周末后约 11 个交易日（近 2 周）
  const today = new Date("2026-06-22T00:00:00Z"); // 固定参照 → 快照不漂移
  const days: KolCandle[] = [];
  const opinions: KolOpinion[] = [];

  let prevClose = 60 + Math.floor(rnd() * 900); // 标的基价
  const drift = (rnd() - 0.45) * 0.6; // 轻微趋势

  for (let i = WINDOW_DAYS - 1; i >= 0; i--) {
    const d = new Date(today);
    d.setUTCDate(today.getUTCDate() - i);
    const dow = d.getUTCDay();
    if (dow === 0 || dow === 6) continue; // 跳过周末
    const day = d.toISOString().slice(0, 10);

    const vol = prevClose * (0.012 + rnd() * 0.03);
    const open = r2(prevClose + (rnd() - 0.5) * vol * 0.4);
    const close = r2(Math.max(1, open + (rnd() - 0.5) * vol * 2 + drift * prevClose * 0.01));
    const high = r2(Math.max(open, close) + rnd() * vol);
    const low = r2(Math.max(0.5, Math.min(open, close) - rnd() * vol));
    days.push({ day, open, high, low, close });
    prevClose = close;

    // 当天观点数 0..6（偶尔爆量）；立场略与当日涨跌相关
    const up = close >= open;
    const n = Math.floor(rnd() * 4) + (rnd() > 0.7 ? Math.floor(rnd() * 4) : 0);
    for (let k = 0; k < n; k++) {
      const source = pick(SOURCES, rnd);
      const sb = rnd();
      const stance: Stance = sb < (up ? 0.55 : 0.3) ? "bull" : sb < (up ? 0.8 : 0.7) ? "neutral" : "bear";
      const topic = pick(TOPICS, rnd);
      const viral = rnd() > 0.86;
      const interactions = Math.floor(viral ? 8000 + rnd() * 58000 : 80 + rnd() * 4200);
      // mock 视角：1-2 个（首个为主视角），让 mock 兜底时「按视角」视图也有内容
      const VK = ["valuation", "growth", "competition", "management", "macro", "catalyst", "flows"];
      const v1 = pick(VK, rnd);
      const viewpoints = rnd() > 0.78 ? ["other"] : rnd() > 0.55 ? [v1, pick(VK.filter((x) => x !== v1), rnd)] : [v1];
      opinions.push({
        id: `${symbol}-${day}-${k}`,
        day,
        source,
        author: pick(KOL_AUTHORS[source], rnd),
        interactions,
        stance,
        text: kolText(topic, stance),
        url: "#",
        viewpoints,
      });
    }
  }
  return { days, opinions };
}
