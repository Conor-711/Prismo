import { IconGrid, IconSearch, IconTrophy, IconYuan } from "./icons";
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

// 侧边栏分两段：主块=美股（看板/作者榜），次块=中概·港股·A 股（看板）。
// 搜索已合并为「全站搜索」，统一入口放在侧边栏顶部（见 Sidebar），两段内不再各自重复搜索项。
export const NAV_GROUPS: NavGroup[] = [
  {
    id: "us",
    labelKey: "usSection",
    items: [
      { href: "/dashboard", key: "dashboard", Icon: IconGrid },
      { href: "/leaderboard", key: "leaderboard", Icon: IconTrophy },
    ],
  },
  {
    id: "cn",
    labelKey: "cnSection",
    items: [
      { href: "/cn", key: "dashboard", Icon: IconGrid },
    ],
  },
];

// 移动端底栏：扁平的关键入口（标签互不重复）。
export const NAV_MOBILE: NavItem[] = [
  { href: "/dashboard", key: "dashboard", Icon: IconGrid },
  { href: "/cn", key: "cnstocks", Icon: IconYuan },
  { href: "/search", key: "search", Icon: IconSearch },
  { href: "/leaderboard", key: "leaderboard", Icon: IconTrophy },
];

// 高亮判定：看板入口在其个股页(/ticker、/cn/ticker)上也保持高亮；其余精确/前缀匹配。
// 注意：next.config 开了 trailingSlash:true，usePathname() 会带尾斜杠（如 /dashboard/），
// 故先归一化去尾斜杠，否则 /dashboard、/cn 这类精确匹配会失效（侧边栏不高亮）。
export function navActive(rest: string, href: string): boolean {
  const r = rest.length > 1 ? rest.replace(/\/+$/, "") : rest;
  if (href === "/dashboard") return r === "/dashboard" || r === "/" || r.startsWith("/ticker");
  if (href === "/cn") return r === "/cn" || r.startsWith("/cn/ticker");
  return r === href || r.startsWith(href + "/");
}
