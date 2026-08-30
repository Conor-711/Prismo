import type { KolSource, TargetMark } from "@/shared/market/mockDetail";

export const TARGET_BUY_COLOR = "#57D7BA";
export const TARGET_SELL_COLOR = "#FF5C6C";
export const TARGET_LINE_COLOR = "#343A42";
export const TARGET_TOOLTIP_BACKGROUND = "#20242A";
export const TARGET_CHART_BACKGROUND = "#17191C";
export const DEFAULT_PRICE_ZOOM = 2;
export const TARGET_BUCKETS = ["short", "mid", "long"] as const;
export const TARGET_PLATFORM_ORDER: KolSource[] = ["x", "youtube", "reddit", "xueqiu", "toss", "yahoojp"];
export const TARGET_RECENCY_OPTIONS = [1, 3, 7, 14, 30, 60, 90] as const;
export const TARGET_BUCKET_ZH: Record<string, string> = { short: "短线", mid: "中线", long: "长线" };
export const TARGET_BUCKET_EN: Record<string, string> = { short: "short", mid: "mid", long: "long" };

export type TargetBucketFilter = "all" | (typeof TARGET_BUCKETS)[number];
export type TargetSourceFilter = "all" | KolSource;
export type TargetRecencyFilter = (typeof TARGET_RECENCY_OPTIONS)[number];
export type TargetScoreFilter = "top5" | "top10" | "top25" | "top50" | "scored" | "all";

export const formatTargetPrice = (value: number) => (
  value >= 10 ? Math.round(value).toLocaleString() : String(+value.toFixed(2))
);

export const formatTargetRange = (low: number, high: number) => (
  high > low ? `$${formatTargetPrice(low)}–$${formatTargetPrice(high)}` : `$${formatTargetPrice(low)}`
);

export const formatTargetDay = (day: string) => {
  const [, month, date] = (day || "").split("-");
  return month ? `${+month}/${+date}` : day;
};

export function shiftTargetDay(day: string, delta: number) {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return date.toISOString().slice(0, 10);
}

// Stable horizontal jitter prevents same-day calls from rendering as one mark.
export function targetMarkJitterMs(mark: TargetMark): number {
  const key = `${mark.author}${mark.kind}${mark.lo}`;
  let hash = 0;
  for (let index = 0; index < key.length; index += 1) {
    hash = (hash * 31 + key.charCodeAt(index)) >>> 0;
  }
  return ((hash % 1000) / 1000 - 0.5) * 0.3 * 864e5;
}
