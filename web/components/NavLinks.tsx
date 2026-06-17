"use client";

import { usePathname } from "next/navigation";
import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { stripLang } from "@/lib/i18n";
import { NAV_GROUPS, navActive } from "./nav";

export function NavLinks() {
  const { rest } = stripLang(usePathname() || "/");
  const { dict } = useLocale();
  const items = NAV_GROUPS.flatMap((g) => g.items);

  return (
    <nav className="px-3 py-4 space-y-1">
      {items.map(({ href, key, Icon }) => {
        const active = navActive(rest, href);
        return (
          <LocaleLink
            key={href}
            href={href}
            title={dict.nav[key]}
            className={`sb-row group relative flex items-center gap-3 rounded-lg px-3 py-2.5 text-[14.5px] transition ${
              active
                ? "bg-reddit/15 text-reddit font-semibold ring-1 ring-inset ring-reddit/30"
                : "font-medium text-neutral-300 hover:text-cream hover:bg-white/[.05]"
            }`}
          >
            {active && (
              <span className="absolute left-0 top-1/2 -translate-y-1/2 h-5 w-[3px] rounded-r-full bg-reddit" />
            )}
            <Icon
              className={`shrink-0 w-[19px] h-[19px] transition ${
                active ? "text-reddit" : "text-neutral-500 group-hover:text-current"
              }`}
            />
            <span className="sb-label">{dict.nav[key]}</span>
          </LocaleLink>
        );
      })}
    </nav>
  );
}
