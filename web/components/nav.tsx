import { IconGrid, IconTrend, IconLayers, IconSearch, IconStar, IconTrophy, IconDoc } from "./icons";
import type { Dictionary } from "@/lib/i18n";

export type NavItem = {
  href: string;
  key: keyof Dictionary["nav"];
  Icon: (p: { className?: string }) => JSX.Element;
};

export type NavGroup = {
  id: "us" | "cn";
  labelKey: keyof Dictionary["nav"];
  items: NavItem[];
};

// Prismo 主导航：总览 / 叙事 / 标的 / 投资者 / 追踪 / 区域 / 搜索（5 社区聚合）。
export const NAV_GROUPS: NavGroup[] = [
  {
    id: "us",
    labelKey: "usSection",
    items: [
      { href: "/dashboard", key: "overview", Icon: IconGrid },
      { href: "/narratives", key: "narratives", Icon: IconDoc },
      { href: "/tickers", key: "tickers", Icon: IconTrend },
      { href: "/investors", key: "investors", Icon: IconTrophy },
      { href: "/tracking", key: "tracking", Icon: IconStar },
      { href: "/regions", key: "regions", Icon: IconLayers },
      { href: "/search", key: "search", Icon: IconSearch },
    ],
  },
];

// 移动端底栏暂不扩容；叙事页先只进桌面侧栏，避免底栏过挤。
export const NAV_MOBILE: NavItem[] = NAV_GROUPS[0].items.filter((item) => item.key !== "narratives");

// 高亮判定：精确/前缀匹配；首页(/) 仅在根路径高亮。
export function navActive(rest: string, href: string): boolean {
  const r = rest.length > 1 ? rest.replace(/\/+$/, "") : rest;
  if (href === "/") return r === "/" || r === "";
  return r === href || r.startsWith(href + "/");
}
