import { SOURCE } from "@/shared/market/kolPresentation";

export interface VolStackItem {
  key: string;
  zh: string;
  en: string;
  color: string;
}

// KOL 视图：X / YouTube / Reddit / 雪球。Toss/Yahoo JP 属于散户社区，观点检索单独展示；讨论度仍走整体散户。
export const KOL_VOL_STACK: VolStackItem[] = [
  { key: "reddit", zh: "Reddit", en: "Reddit", color: SOURCE.reddit.color },
  { key: "x", zh: "X", en: "X", color: SOURCE.x.color },
  { key: "xueqiu", zh: "雪球", en: "Xueqiu", color: SOURCE.xueqiu.color },
  { key: "youtube", zh: "YouTube", en: "YouTube", color: SOURCE.youtube.color },
];

// 整体散户视图：X / Reddit / 雪球 + 本土散户论坛 Naver / Yahoo JP / PTT / Toss。不含 YouTube。
export const RETAIL_VOL_STACK: VolStackItem[] = [
  { key: "reddit", zh: "Reddit", en: "Reddit", color: SOURCE.reddit.color },
  { key: "x", zh: "X", en: "X", color: SOURCE.x.color },
  { key: "xueqiu", zh: "雪球", en: "Xueqiu", color: SOURCE.xueqiu.color },
  { key: "naver", zh: "Naver", en: "Naver", color: "#5FA86E" },
  { key: "yahoojp", zh: "Yahoo JP", en: "Yahoo JP", color: "#C77B9A" },
  { key: "ptt", zh: "PTT", en: "PTT", color: "#9B8ECF" },
  { key: "toss", zh: "Toss", en: "Toss", color: "#D6A24A" },
];

// 每日新增散户：整体散户口径，但不含 X（云端无作者列）、不含 YouTube（创作者非散户）。
export const RETAIL_NEW_STACK: VolStackItem[] = [
  { key: "reddit", zh: "Reddit", en: "Reddit", color: SOURCE.reddit.color },
  { key: "xueqiu", zh: "雪球", en: "Xueqiu", color: SOURCE.xueqiu.color },
  { key: "naver", zh: "Naver", en: "Naver", color: "#5FA86E" },
  { key: "yahoojp", zh: "Yahoo JP", en: "Yahoo JP", color: "#C77B9A" },
  { key: "ptt", zh: "PTT", en: "PTT", color: "#9B8ECF" },
  { key: "toss", zh: "Toss", en: "Toss", color: "#D6A24A" },
];

// 每日新增 KOL：仅 X / YouTube / 雪球（有显著身份、粉丝数象征的平台）。
export const KOL_NEW_STACK: VolStackItem[] = [
  { key: "x", zh: "X", en: "X", color: SOURCE.x.color },
  { key: "youtube", zh: "YouTube", en: "YouTube", color: SOURCE.youtube.color },
  { key: "xueqiu", zh: "雪球", en: "Xueqiu", color: SOURCE.xueqiu.color },
];
