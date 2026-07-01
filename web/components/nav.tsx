import { IconGrid, IconTrend, IconLayers, IconStar, IconTrophy, IconDoc } from "./icons";
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

// Prismo 主导航：搜索框单独置顶；其余入口按 SaaS 工作台优先级排列。
export const NAV_GROUPS: NavGroup[] = [
  {
    id: "us",
    labelKey: "usSection",
    items: [
      { href: "/dashboard", key: "overview", Icon: IconGrid },
      { href: "/tickers", key: "tickers", Icon: IconTrend },
      { href: "/narratives", key: "narratives", Icon: IconDoc },
      { href: "/investors", key: "investors", Icon: IconTrophy },
      { href: "/regions", key: "regions", Icon: IconLayers },
      { href: "/tracking", key: "tracking", Icon: IconStar },
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
