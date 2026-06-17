import type { Locale } from "./i18n";

// 5 个本土社区/地区的展示元数据（标签 / 来源平台 / 强调色）。
// gr_* 数据用 region key（us/cn/jp/kr/tw）；这里集中映射，避免各页重复。
export const REGION_ORDER = ["us", "cn", "jp", "kr", "tw"] as const;
export type RegionKey = (typeof REGION_ORDER)[number];

type RegionMeta = { zh: string; en: string; source: string; color: string };

const META: Record<string, RegionMeta> = {
  us: { zh: "美国", en: "USA", source: "Reddit", color: "#3B82F6" },
  cn: { zh: "中国大陆", en: "China", source: "雪球 Xueqiu", color: "#EF4444" },
  jp: { zh: "日本", en: "Japan", source: "Yahoo Finance", color: "#A855F7" },
  kr: { zh: "韩国", en: "Korea", source: "Naver", color: "#22C55E" },
  tw: { zh: "台湾", en: "Taiwan", source: "PTT", color: "#F59E0B" },
};

export function regionLabel(region: string, lang: Locale): string {
  const m = META[region];
  if (!m) return region.toUpperCase();
  return lang === "zh" ? m.zh : m.en;
}
export function regionSource(region: string): string {
  return META[region]?.source ?? region.toUpperCase();
}
export function regionColor(region: string): string {
  return META[region]?.color ?? "#8A8A93";
}
export function isRegion(x: string): x is RegionKey {
  return (REGION_ORDER as readonly string[]).includes(x);
}
