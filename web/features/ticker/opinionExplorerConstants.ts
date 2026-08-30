import type { KolJudgment, KolSource, Stance } from "@/shared/market/mockDetail";
import type {
  LensKey,
  PersonalPrefs,
  PersonalStyle,
  SvPreset,
  SvRangeFilter,
} from "./opinionExplorerTypes";

export const LENSES: { k: LensKey; zh: string; en: string }[] = [
  { k: "valuation", zh: "估值", en: "Valuation" },
  { k: "growth", zh: "业务成长", en: "Growth" },
  { k: "competition", zh: "竞争", en: "Competition" },
  { k: "management", zh: "管理层", en: "Management" },
  { k: "macro", zh: "宏观", en: "Macro" },
  { k: "catalyst", zh: "催化剂", en: "Catalyst" },
  { k: "flows", zh: "资金盘面", en: "Flows" },
  { k: "other", zh: "其他", en: "Other" },
];

export const LENS_LABEL: Record<string, { zh: string; en: string }> = Object.fromEntries(
  LENSES.map((l) => [l.k, { zh: l.zh, en: l.en }])
);

export const PLATFORMS: KolSource[] = ["x", "youtube", "reddit", "xueqiu", "toss", "yahoojp"];

export const WINDOWS: { k: string; days: number; zh: string; en: string }[] = [
  { k: "24h", days: 1, zh: "24 小时", en: "24h" },
  { k: "3d", days: 3, zh: "3 天", en: "3d" },
  { k: "7d", days: 7, zh: "7 天", en: "7d" },
  { k: "14d", days: 14, zh: "14 天", en: "14d" },
  { k: "1mo", days: 31, zh: "1 个月", en: "1mo" },
  { k: "3mo", days: 93, zh: "3 个月", en: "3mo" },
  { k: "6mo", days: 186, zh: "6 个月", en: "6mo" },
  { k: "12mo", days: 365, zh: "12 个月", en: "12mo" },
];

export const DEFAULT_WIN_DAYS = 31;

export const QUALITY_MIN_BY_SOURCE: Record<KolSource, number> = {
  youtube: 65,
  reddit: 80,
  x: 80,
  xueqiu: 80,
  toss: 80,
  yahoojp: 80,
};

export const LANGS: { k: string; zh: string; en: string }[] = [
  { k: "zh-Hans", zh: "简体中文", en: "简" },
  { k: "en", zh: "英文", en: "EN" },
  { k: "ja", zh: "日语", en: "JA" },
  { k: "ko", zh: "韩文", en: "KO" },
  { k: "zh-Hant", zh: "繁体中文", en: "繁" },
];

export const STANCE_FILTERS: Stance[] = ["bull", "neutral", "bear"];

export const EMPTY_PERSONAL_PREFS: PersonalPrefs = {
  direction: "",
  style: "",
  costLow: "",
  costHigh: "",
  positionLow: "",
  positionHigh: "",
  targetPrice: "",
  stopLoss: "",
};

export const DEFAULT_SV_FILTER: SvRangeFilter = { enabled: false, low: 0, high: 25, preset: "off" };

export const SV_PRESETS: {
  key: SvPreset;
  low: number;
  high: number;
  zh: string;
  en: string;
  enabled: boolean;
}[] = [
  { key: "off", low: 0, high: 100, zh: "全部 Score", en: "All Score", enabled: false },
  { key: "top25", low: 0, high: 25, zh: "头部 25%", en: "Top 25%", enabled: true },
  { key: "middle50", low: 25, high: 75, zh: "中部 50%", en: "Middle 50%", enabled: true },
  { key: "bottom25", low: 75, high: 100, zh: "尾部 25%", en: "Bottom 25%", enabled: true },
];

export const STYLE_BUCKET: Record<Exclude<PersonalStyle, "">, NonNullable<KolJudgment["bucket"]>> = {
  shortterm: "short",
  swing: "mid",
  longterm: "long",
  dca: "long",
};

export const STYLE_LABEL: Record<Exclude<PersonalStyle, "">, { zh: string; en: string }> = {
  shortterm: { zh: "短线", en: "Short-term" },
  swing: { zh: "波段", en: "Swing" },
  longterm: { zh: "长线", en: "Long-term" },
  dca: { zh: "定投", en: "DCA" },
};
