import { LocaleLink } from "./i18n/LocaleLink";
import { getMeta, getDataStats } from "@/lib/queries";
import { timeAgo, fmtInt } from "@/lib/format";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { SidebarToggle } from "./SidebarToggle";
import type { Locale, Dictionary } from "@/lib/i18n";
import { UserMenu } from "./auth/UserMenu";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

export function Topbar({ lang, dict }: { lang: Locale; dict: Dictionary }) {
  const meta = getMeta();
  const stats = getDataStats();
  const c = dict.credibility;
  // 顶部 banner 的「依据模块」：用真实数据规模替代原 tagline，增强可信度。
  const bar = [
    { v: stats.analyzedPosts, label: c.postsShort },
    { v: stats.comments, label: c.commentsShort },
    { v: stats.mentions, label: c.mentionsShort },
    { v: stats.tickers, label: c.tickersShort },
    { v: stats.communities, label: c.communitiesShort },
  ];
  return (
    <header
      className="sticky top-0 z-30 border-b border-line bg-surface/70 backdrop-blur"
      style={{ paddingTop: "env(safe-area-inset-top)" }}
    >
      <div className="flex items-center justify-between gap-3 h-16 px-4 sm:px-6 lg:px-8">
        <div className="flex items-center gap-2 min-w-0">
          <SidebarToggle />
          <LocaleLink href="/" className="lg:hidden flex items-center gap-2">
            <span className="w-7 h-7 rounded-xl overflow-hidden bg-white shrink-0 ring-1 ring-white/10">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`${BASE}/logo.png`} alt="redditalpha logo" className="w-full h-full object-contain rounded-xl" />
            </span>
            <span className="font-display font-extrabold text-cream">
              reddit<span className="text-reddit">alpha</span>
            </span>
          </LocaleLink>
          {/* 依据模块（替代原 tagline）：基于真实数据 · N 帖 · N 评论 · … */}
          <div className="hidden lg:flex items-center gap-2.5 min-w-0" title={c.title}>
            <span className="flex items-center gap-1.5 shrink-0">
              <span className="relative flex h-1.5 w-1.5">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-bull opacity-60" />
                <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-bull" />
              </span>
              <span className="text-[10px] font-semibold uppercase tracking-wider text-reddit">{c.eyebrow}</span>
            </span>
            <span className="flex items-center gap-x-2 text-sm text-neutral-400 truncate">
              {bar.map((s, i) => (
                <span key={s.label} className="flex items-center gap-1 shrink-0">
                  {i > 0 && <span className="text-neutral-700">·</span>}
                  <span className="font-display font-bold text-cream tabular">{fmtInt(s.v)}</span>
                  <span className="text-xs text-neutral-500">{s.label}</span>
                </span>
              ))}
            </span>
          </div>
        </div>

        <div className="flex items-center gap-3 ml-auto">
          <div className="hidden md:flex items-center gap-1.5 text-xs text-neutral-500">
            <span className="w-1.5 h-1.5 rounded-full bg-bull animate-pulse" />
            {meta.lastUpdated ? `${dict.chrome.updatedPrefix}${timeAgo(meta.lastUpdated, lang)}` : dict.chrome.noData}
          </div>
          {/* 桌面端：语言/主题切换已移到侧边栏下半部分；此处仅移动端显示 */}
          <div className="lg:hidden">
            <LanguageSwitcher />
          </div>
          <UserMenu />
        </div>
      </div>
    </header>
  );
}
