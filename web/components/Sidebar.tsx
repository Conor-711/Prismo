import { LocaleLink } from "./i18n/LocaleLink";
import { NavLinks } from "./NavLinks";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { ThemeToggle } from "./ThemeToggle";
import type { Locale, Dictionary } from "@/lib/i18n";

export function Sidebar({ dict }: { lang: Locale; dict: Dictionary }) {
  return (
    <aside className="app-sidebar hidden lg:flex fixed inset-y-0 left-0 w-[232px] flex-col border-r border-line bg-surface/60 backdrop-blur z-40">
      {/* 品牌（占位 P 标，正式 Logo 待设计） */}
      <LocaleLink href="/" className="sb-row flex items-center gap-2.5 px-4 h-16 border-b border-line shrink-0">
        <span
          className="grid place-items-center w-10 h-10 rounded-xl text-white font-display font-extrabold text-lg ring-1 ring-inset ring-white/15 shrink-0"
          style={{ backgroundImage: "var(--grad-brand)" }}
        >
          P
        </span>
        <span className="sb-label font-display font-extrabold text-cream text-[22px] tracking-tight">Prismo</span>
      </LocaleLink>

      <div className="flex-1 overflow-y-auto overflow-x-hidden">
        <NavLinks />

        {/* 商务联系方式 */}
        <div className="px-3 pb-4 mt-2 pt-4 border-t border-line/60">
          <div className="sb-hide flex items-center gap-2 px-2 mb-2">
            <span className="w-[3px] h-3.5 rounded-full bg-neutral-600 shrink-0" />
            <span className="font-display text-[13px] font-bold text-neutral-400 tracking-tight">{dict.chrome.contact}</span>
          </div>
          <div className="space-y-1">
            <a
              href="https://x.com/Connor_7s"
              target="_blank"
              rel="noreferrer noopener"
              title="@Connor_7s"
              className="sb-row group flex items-center gap-3 rounded-lg px-3 py-2 text-[13.5px] font-medium text-neutral-500 hover:text-neutral-200 hover:bg-white/[.04] transition"
            >
              <svg viewBox="0 0 24 24" fill="currentColor" className="w-[17px] h-[17px] shrink-0 text-neutral-500 group-hover:text-current transition" aria-hidden>
                <path d="M18.244 2H21.5l-7.5 8.57L23 22h-6.844l-5.36-7.01L4.66 22H1.4l8.02-9.17L1 2h7.02l4.84 6.4L18.244 2zm-1.2 18h1.9L7.04 4H5.02l12.024 16z" />
              </svg>
              <span className="sb-label">@Connor_7s</span>
            </a>
            <a
              href="mailto:zfy3712z@gmail.com"
              title="zfy3712z@gmail.com"
              className="sb-row group flex items-center gap-3 rounded-lg px-3 py-2 text-[13.5px] font-medium text-neutral-500 hover:text-neutral-200 hover:bg-white/[.04] transition"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" className="w-[17px] h-[17px] shrink-0 text-neutral-500 group-hover:text-current transition" aria-hidden>
                <rect x="3" y="5" width="18" height="14" rx="2" />
                <path d="m3 7 9 6 9-6" />
              </svg>
              <span className="sb-label truncate">zfy3712z@gmail.com</span>
            </a>
          </div>
        </div>
      </div>

      {/* 控制区：语言 + 主题切换 */}
      <div className="sb-row px-4 py-3 border-t border-line flex items-center justify-between gap-2 shrink-0">
        <span className="sb-label">
          <LanguageSwitcher />
        </span>
        <ThemeToggle variant="inline" />
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
