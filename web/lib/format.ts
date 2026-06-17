// 数字 / 时间 / 语义色 格式化助手。
import type { Locale } from "./i18n";

export function fmtInt(n: number): string {
  return new Intl.NumberFormat("en-US").format(Math.round(n || 0));
}

export function fmtCompact(n: number): string {
  if (!n) return "0";
  const a = Math.abs(n);
  if (a >= 1e9) return (n / 1e9).toFixed(a >= 1e10 ? 0 : 1) + "B";
  if (a >= 1e6) return (n / 1e6).toFixed(a >= 1e7 ? 0 : 1) + "M";
  if (a >= 1e3) return (n / 1e3).toFixed(a >= 1e4 ? 0 : 1) + "K";
  return String(Math.round(n));
}

export function fmtPct(n: number, digits = 1): string {
  return `${(n || 0).toFixed(digits)}%`;
}

export function fmtSignedPct(n: number, digits = 0): string {
  const v = (n || 0).toFixed(digits);
  return (n > 0 ? "+" : "") + v + "%";
}

export function parseUTC(s: string): Date {
  // SQLite 里是 "YYYY-MM-DD HH:MM:SS(.ffffff)"，按 UTC 解析。
  if (!s) return new Date(0);
  return new Date(s.replace(" ", "T").replace(/(\.\d+)?$/, "") + "Z");
}

export function timeAgo(s: string, lang: Locale = "zh"): string {
  const then = parseUTC(s).getTime();
  const mins = Math.max(0, Math.floor((Date.now() - then) / 60000));
  const hrs = Math.floor(mins / 60);
  const days = Math.floor(hrs / 24);
  if (lang === "ja") {
    if (mins < 60) return `${mins}分前`;
    if (hrs < 24) return `${hrs}時間前`;
    return `${days}日前`;
  }
  if (lang === "ko") {
    if (mins < 60) return `${mins}분 전`;
    if (hrs < 24) return `${hrs}시간 전`;
    return `${days}일 전`;
  }
  if (lang === "en") {
    if (mins < 60) return `${mins}m ago`;
    if (hrs < 24) return `${hrs}h ago`;
    return `${days}d ago`;
  }
  if (mins < 60) return `${mins} 分钟前`;
  if (hrs < 24) return `${hrs} 小时前`;
  return `${days} 天前`;
}

// 情绪 → 颜色（图表用 hex）
export function sentHex(score: number): string {
  if (score > 0.15) return "#57D7BA";
  if (score < -0.15) return "#fe5555";
  return "#8A8A93";
}

// 情绪 → 文本色类
export function sentTextClass(score: number): string {
  if (score > 0.15) return "text-bull";
  if (score < -0.15) return "text-bear";
  return "text-neutral-400";
}

export function stanceLabel(stance: string, lang: Locale = "zh"): string {
  const map = {
    zh: { bull: "看多", bear: "看空", neutral: "中性" },
    en: { bull: "Bullish", bear: "Bearish", neutral: "Neutral" },
    ja: { bull: "強気", bear: "弱気", neutral: "中立" },
    ko: { bull: "강세", bear: "약세", neutral: "중립" },
  } as const;
  const m = (map[lang] ?? map.en) as Record<string, string>;
  return m[stance] ?? m.neutral;
}

// 向后兼容（默认中文）；新代码请用 stanceLabel(stance, lang)
export function stanceCN(stance: string): string {
  return stanceLabel(stance, "zh");
}

export function moodColor(score: number): string {
  return sentHex(score);
}

export function hhmm(s: string): string {
  return parseUTC(s).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export const REDDIT = "https://www.reddit.com";

// subreddit 小圆标配色（按名字确定性取色）
const SUB_PALETTE = ["#FF4500", "#0079D3", "#24B47E", "#E6B450", "#7193FF", "#F0556E", "#46D160", "#FF8717"];
export function subColor(name: string): string {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0;
  return SUB_PALETTE[h % SUB_PALETTE.length];
}
