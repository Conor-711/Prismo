import type { Bi } from "./marketMock";

// =====================================================================
// 第 1 块：个体观点（主观 × KOL）—— 日 K 线 + 每日 KOL 观点气泡（mock）
// 来源 X / YouTube / Reddit / 雪球 / Toss / Yahoo JP；气泡大小 ∝ 互动数。真实管线到位后替换。
// =====================================================================
export type KolSource = "x" | "youtube" | "reddit" | "xueqiu" | "toss" | "yahoojp";
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
  authorRefId?: string; // user_collections(kind=author) 的稳定键：source:id/handle/author
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
  opinionId?: string; // 对应 OpinionExplorer 里的观点 id，用于图表点击后在站内打开正文
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
