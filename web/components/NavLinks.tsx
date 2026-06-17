"use client";

import { usePathname } from "next/navigation";
import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { stripLang } from "@/lib/i18n";
import { NAV_GROUPS, navActive } from "./nav";

export function NavLinks() {
  const { rest } = stripLang(usePathname() || "/");
  const { dict } = useLocale();

  return (
    <nav className="px-3 py-4 space-y-1">
      {NAV_GROUPS.map((group, gi) => {
        const primary = group.id === "us";
        return (
          <div key={group.id} className={gi > 0 ? "mt-5 pt-4 border-t border-line/60" : ""}>
            {/* 段标题：更大更清晰；美股=主块（更大更亮 + 橙色重音条），中概=次块（偏小偏暗） */}
            <div className="sb-hide flex items-center gap-2 px-2 mb-2">
              <span
                className={`rounded-full shrink-0 ${
                  primary ? "w-[3px] h-4 bg-reddit" : "w-[3px] h-3.5 bg-neutral-600"
                }`}
              />
              <span
                className={`font-display tracking-tight ${
                  primary ? "text-[15px] font-extrabold text-cream" : "text-[13px] font-bold text-neutral-400"
                }`}
              >
                {dict.nav[group.labelKey]}
              </span>
            </div>

            <div className="space-y-1">
              {group.items.map(({ href, key, Icon }) => {
                const active = navActive(rest, href);
                return (
                  <LocaleLink
                    key={href}
                    href={href}
                    title={dict.nav[key]}
                    className={`sb-row group relative flex items-center gap-3 rounded-lg transition ${
                      primary ? "px-3 py-2.5 text-[14.5px]" : "px-3 py-2 text-[13.5px]"
                    } ${
                      active
                        ? "bg-reddit/15 text-reddit font-semibold ring-1 ring-inset ring-reddit/30"
                        : primary
                        ? "font-medium text-neutral-300 hover:text-cream hover:bg-white/[.05]"
                        : "font-medium text-neutral-500 hover:text-neutral-200 hover:bg-white/[.04]"
                    }`}
                  >
                    {/* 选中态：左侧品牌色高亮条 */}
                    {active && (
                      <span className="absolute left-0 top-1/2 -translate-y-1/2 h-5 w-[3px] rounded-r-full bg-reddit" />
                    )}
                    <Icon
                      className={`shrink-0 transition ${primary ? "w-[19px] h-[19px]" : "w-[17px] h-[17px]"} ${
                        active ? "text-reddit" : "text-neutral-500 group-hover:text-current"
                      }`}
                    />
                    <span className="sb-label">{dict.nav[key]}</span>
                  </LocaleLink>
                );
              })}
            </div>
          </div>
        );
      })}
    </nav>
  );
}
