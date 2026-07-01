import { LocaleLink } from "./i18n/LocaleLink";
import { NavLinks } from "./NavLinks";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { SidebarSearch } from "./SidebarSearch";
import { SidebarToggle } from "./SidebarToggle";
import { SidebarAccount } from "./auth/SidebarAccount";
import type { Locale, Dictionary } from "@/lib/i18n";

export function Sidebar({ dict }: { lang: Locale; dict: Dictionary }) {
  return (
    <aside className="app-sidebar hidden lg:flex fixed inset-y-0 left-0 w-[208px] flex-col border-r border-line bg-surface/60 backdrop-blur z-40">
      <SidebarToggle
        action="expand"
        label="展开侧边栏"
        className="sidebar-collapsed-expand-hitbox"
      >
        <span className="sr-only">展开侧边栏</span>
      </SidebarToggle>
      <div className="border-b border-line px-3 py-3 shrink-0">
        <div className="sidebar-brand flex items-center gap-2">
          {/* 品牌（占位 P 标，正式 Logo 待设计） */}
          <LocaleLink href="/" className="sidebar-brand-link sb-row flex min-w-0 flex-1 items-center gap-2.5 rounded-lg px-1 py-1">
            <span
              className="grid place-items-center w-10 h-10 rounded-xl text-white font-display font-extrabold text-lg ring-1 ring-inset ring-white/15 shrink-0"
              style={{ backgroundImage: "var(--grad-brand)" }}
            >
              P
            </span>
            <span className="sb-label font-display font-extrabold text-cream text-[22px] tracking-tight">Prismo</span>
          </LocaleLink>
          <SidebarToggle
            action="collapse"
            label="折叠侧边栏"
            className="sidebar-collapse-button grid h-8 w-8 shrink-0 place-items-center rounded-lg text-neutral-500 transition hover:bg-white/[.06] hover:text-cream"
          />
          <div
            aria-hidden="true"
            className="sidebar-collapsed-brand h-10 w-10 place-items-center rounded-xl text-neutral-400 transition"
          >
            <span
              className="sidebar-collapsed-brand-logo grid h-10 w-10 place-items-center rounded-xl text-white font-display font-extrabold text-lg ring-1 ring-inset ring-white/15"
              style={{ backgroundImage: "var(--grad-brand)" }}
            >
              P
            </span>
            <span className="sidebar-collapsed-brand-icon grid h-10 w-10 place-items-center rounded-xl">
              <svg viewBox="0 0 24 24" className="h-[18px] w-[18px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <rect x="3" y="4" width="18" height="16" rx="2" />
                <path d="M9 4v16" />
              </svg>
            </span>
          </div>
        </div>
        <div className="mt-2">
          <SidebarAccount />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto overflow-x-hidden py-3">
        <SidebarSearch />
        <NavLinks />
      </div>

      {/* 控制区：语言 */}
      <div className="sb-row px-4 py-3 border-t border-line flex items-center gap-2 shrink-0">
        <span className="sb-label">
          <LanguageSwitcher />
        </span>
      </div>

      <div className="sb-hide px-5 py-4 border-t border-line text-[11px] text-neutral-600 leading-relaxed shrink-0">
        <div className="flex items-center gap-1.5 mb-1">
          <span className="w-1.5 h-1.5 rounded-full bg-bull animate-pulse" />
          <span className="text-neutral-500">{dict.chrome.liveDemo}</span>
        </div>
        {dict.chrome.disclaimer}
      </div>
    </aside>
  );
}
