// 引导(onboarding)状态 + 选项常量。全部走 localStorage，纯前端，
// 不依赖后端/Supabase——「游客登录」走这里即可体验个性化。
// 静态导出下，dashboard 在客户端读这里的选择来做个性化。

export type Intent = "find" | "manage" | "both";
export type Experience = "beginner" | "crossover" | "expert";

export interface OnboardingState {
  intent: Intent | null;
  experience: Experience | null;
  sectors: string[]; // 英文 sector key，对应 ticker_meta.sector
  tickers: string[]; // 持仓标的代码
  completedAt: number | null;
}

const KEY = "prismo:onboarding";
const GUEST_KEY = "prismo:guest";
export const ONBOARDING_EVENT = "prismo:onboarding-changed";

export const EMPTY_ONBOARDING: OnboardingState = {
  intent: null,
  experience: null,
  sectors: [],
  tickers: [],
  completedAt: null,
};

function browser(): boolean {
  return typeof window !== "undefined";
}

export function getOnboarding(): OnboardingState | null {
  if (!browser()) return null;
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return null;
    return { ...EMPTY_ONBOARDING, ...(JSON.parse(raw) as Partial<OnboardingState>) };
  } catch {
    return null;
  }
}

export function saveOnboarding(patch: Partial<OnboardingState>): OnboardingState {
  const next = { ...(getOnboarding() ?? EMPTY_ONBOARDING), ...patch };
  if (browser()) {
    try {
      window.localStorage.setItem(KEY, JSON.stringify(next));
      window.dispatchEvent(new CustomEvent(ONBOARDING_EVENT));
    } catch {
      /* ignore quota / privacy mode */
    }
  }
  return next;
}

export function clearOnboarding() {
  if (!browser()) return;
  window.localStorage.removeItem(KEY);
  window.dispatchEvent(new CustomEvent(ONBOARDING_EVENT));
}

export function hasCompletedOnboarding(): boolean {
  return Boolean(getOnboarding()?.completedAt);
}

export function isGuest(): boolean {
  return browser() && window.localStorage.getItem(GUEST_KEY) === "1";
}

export function setGuest(on: boolean) {
  if (!browser()) return;
  if (on) window.localStorage.setItem(GUEST_KEY, "1");
  else window.localStorage.removeItem(GUEST_KEY);
}

// ---------------- 选项常量 ----------------

export const INTENTS: { id: Intent; label: string; tagline: string; desc: string; emoji: string }[] = [
  {
    id: "find",
    label: "找股票投",
    tagline: "发现新机会",
    desc: "看看 Reddit 正在热议、值得上车的标的。",
    emoji: "🔭",
  },
  {
    id: "manage",
    label: "看手中的股票",
    tagline: "盯住我的持仓",
    desc: "我已经持有一些股票，想知道社区怎么看、该怎么操作。",
    emoji: "📌",
  },
  {
    id: "both",
    label: "都要",
    tagline: "发现 + 盯盘",
    desc: "既要挖掘新机会，也要跟踪现有持仓。",
    emoji: "🎯",
  },
];

export const EXPERIENCES: { id: Experience; label: string; desc: string; emoji: string }[] = [
  { id: "beginner", label: "投资小白", desc: "刚起步，想先看懂别人在聊什么。", emoji: "🌱" },
  { id: "crossover", label: "跨界老手", desc: "在 crypto 或其他市场投过，迁移到美股。", emoji: "🧭" },
  { id: "expert", label: "投资高手", desc: "只要原始信号、深度论点和异动。", emoji: "⚡" },
];

// 英文 sector → 友好「领域」展示。dashboard 个性化按英文 key 匹配 ticker_meta.sector。
export const SECTOR_META: Record<string, { label: string; emoji: string; blurb: string }> = {
  Technology: { label: "科技 · 半导体", emoji: "🤖", blurb: "AI、芯片、软件" },
  "Communication Services": { label: "互联网 · 通信", emoji: "🌐", blurb: "谷歌、Meta、流媒体" },
  "Consumer Discretionary": { label: "可选消费", emoji: "🛍️", blurb: "特斯拉、亚马逊" },
  Financials: { label: "金融", emoji: "🏦", blurb: "银行、券商、保险" },
  Industrials: { label: "工业 · 航天", emoji: "🚀", blurb: "制造、国防、航天" },
  "Health Care": { label: "医疗健康", emoji: "🧬", blurb: "药企、生物科技" },
  Energy: { label: "能源", emoji: "🛢️", blurb: "石油、天然气" },
  Utilities: { label: "公用事业 · 电力", emoji: "🔌", blurb: "电力、核能" },
  "Consumer Staples": { label: "必需消费", emoji: "🧺", blurb: "食品、日用" },
  ETF: { label: "指数 · ETF", emoji: "📊", blurb: "宽基与主题基金" },
};

export function sectorLabel(key: string): string {
  return SECTOR_META[key]?.label ?? key;
}
export function sectorEmoji(key: string): string {
  return SECTOR_META[key]?.emoji ?? "📈";
}

export function intentLabel(id: Intent | null): string {
  return INTENTS.find((i) => i.id === id)?.label ?? "";
}
export function experienceLabel(id: Experience | null): string {
  return EXPERIENCES.find((e) => e.id === id)?.label ?? "";
}
