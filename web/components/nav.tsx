import { IconGrid } from "./icons";
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

// 重构期：Reddit 单站导航（看板/作者榜/中概/搜索）已移除。
// 暂以 5 地区看板（/lab/global-retail）作为唯一主入口；围绕 5 社区重建 UI 时再扩充。
export const NAV_GROUPS: NavGroup[] = [
  {
    id: "us",
    labelKey: "usSection",
    items: [{ href: "/lab/global-retail", key: "dashboard", Icon: IconGrid }],
  },
];

// 移动端底栏：暂只保留主看板入口。
export const NAV_MOBILE: NavItem[] = [
  { href: "/lab/global-retail", key: "dashboard", Icon: IconGrid },
];

// 高亮判定：精确/前缀匹配；占位首页(/)也让主看板入口高亮。
export function navActive(rest: string, href: string): boolean {
  const r = rest.length > 1 ? rest.replace(/\/+$/, "") : rest;
  return r === href || r.startsWith(href + "/") || (href === "/lab/global-retail" && r === "/");
}
