import { LocaleLink } from "./i18n/LocaleLink";
import { NavLinks } from "./NavLinks";
import { getCommunities } from "@/lib/queries";
import { fmtCompact } from "@/lib/format";
import { RedditMark } from "./reddit";
import { CommunityIcon } from "./CommunityIcon";
import { IconChevron } from "./icons";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { ThemeToggle } from "./ThemeToggle";
import { SaveButton } from "./favorites/SaveButton";
import type { Locale, Dictionary } from "@/lib/i18n";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

export function Sidebar({ dict }: { lang: Locale; dict: Dictionary }) {
  const communities = getCommunities();
  return (
    <aside className="app-sidebar hidden lg:flex fixed inset-y-0 left-0 w-[232px] flex-col border-r border-line bg-surface/60 backdrop-blur z-40">
      <LocaleLink href="/" className="sb-row flex items-center gap-2.5 px-4 h-16 border-b border-line shrink-0">
        <span className="w-11 h-11 rounded-xl overflow-hidden bg-white shrink-0 ring-1 ring-white/10">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={`${BASE}/logo.png`} alt="RedditAlpha logo" className="w-full h-full object-contain rounded-xl" />
        </span>
        <span className="sb-label font-display font-extrabold text-cream text-[22px] tracking-tight">
          reddit<span className="text-reddit">alpha</span>
        </span>
      </LocaleLink>

      <div className="flex-1 overflow-y-auto overflow-x-hidden">
        <NavLinks />

        {/* 追踪社区：可折叠模块（native <details>，静态导出零 JS） */}
        <details className="group px-3 pb-3 mt-5 pt-4 border-t border-line/60">
          <summary className="sb-hide list-none cursor-pointer select-none flex items-center gap-2 px-2 py-1 mb-1.5 text-neutral-400 hover:text-neutral-200 transition [&::-webkit-details-marker]:hidden">
            <span className="w-[3px] h-3.5 rounded-full bg-neutral-600 shrink-0" />
            <span className="font-display text-[13px] font-bold tracking-tight">{dict.chrome.communities}</span>
            <IconChevron className="ml-auto w-3.5 h-3.5 transition-transform group-open:rotate-180" />
          </summary>
          <div className="space-y-0.5 mt-1">
            {communities.map((c) => (
              <div key={c.id} className="sb-row flex items-center gap-2.5 px-3 py-1.5 rounded-lg">
                <CommunityIcon id={c.id} size={20} className="text-[10px]" />
                <span className="sb-label text-sm text-neutral-300 truncate flex-1">r/{c.id}</span>
                {c.subscribers > 0 && (
                  <span className="sb-label text-[10px] text-neutral-600 tabular shrink-0">{fmtCompact(c.subscribers)}</span>
                )}
                <span className="sb-label shrink-0">
                  <SaveButton kind="subreddit" refId={c.id} variant="follow" size="xs" />
                </span>
              </div>
            ))}
          </div>
        </details>

        {/* 商务联系方式：与侧边栏其它入口保持一致的行式样式 */}
        <div className="px-3 pb-4">
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

      {/* 控制区（侧边栏下半部分）：语言 + 主题切换；折叠时只留主题图标 */}
      <div className="sb-row px-4 py-3 border-t border-line flex items-center justify-between gap-2 shrink-0">
        <span className="sb-label">
          <LanguageSwitcher />
        </span>
        <ThemeToggle variant="inline" />
      </div>

      <div className="sb-hide px-5 py-4 border-t border-line text-[11px] text-neutral-600 leading-relaxed shrink-0">
        <div className="flex items-center gap-2 mb-2">
          <RedditMark size={18} />
          <span className="text-neutral-500">{dict.chrome.dataFrom}</span>
        </div>
        <div className="flex items-center gap-1.5 mb-1">
          <span className="w-1.5 h-1.5 rounded-full bg-bull animate-pulse" />
          <span className="text-neutral-500">{dict.chrome.liveDemo}</span>
        </div>
        {dict.chrome.disclaimer}
      </div>

    </aside>
  );
}
