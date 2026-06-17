"use client";

import { usePathname } from "next/navigation";
import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { stripLang } from "@/lib/i18n";
import { NAV_MOBILE, navActive } from "./nav";

// 移动端「App 式」底部 Tab 栏（替代原顶部横滑条）。固定底部、含刘海安全区、当前页高亮。
export function MobileTabBar() {
  const { rest } = stripLang(usePathname() || "/");
  const { dict } = useLocale();
  return (
    <nav
      aria-label="primary"
      className="lg:hidden fixed inset-x-0 bottom-0 z-40 border-t border-line bg-surface/90 backdrop-blur"
      style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
    >
      <ul className="flex items-stretch">
        {NAV_MOBILE.map(({ href, key, Icon }) => {
          const active = navActive(rest, href);
          return (
            <li key={href} className="flex-1">
              <LocaleLink
                href={href}
                aria-current={active ? "page" : undefined}
                className={`flex flex-col items-center justify-center gap-0.5 py-2 min-h-[54px] text-[10px] font-medium transition ${
                  active ? "text-reddit" : "text-neutral-500 active:text-cream hover:text-cream"
                }`}
              >
                <Icon className="w-[22px] h-[22px]" />
                <span className="leading-none">{dict.nav[key]}</span>
              </LocaleLink>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
