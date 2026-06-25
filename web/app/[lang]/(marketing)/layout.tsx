import { LocaleLink } from "@/components/i18n/LocaleLink";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { AnalyticsTracker } from "@/components/AnalyticsTracker";
import { getDictionary, defaultLocale, isLocale, type Locale } from "@/lib/i18n";

// 落地页（营销）极简外壳：无侧栏/无应用顶栏 —— 只有品牌头(logo + 语言 + 登录/注册) 与页脚。
// 与 (app) 同处 [lang] 之下、共享 LocaleProvider；进入产品(/dashboard 等)才套用 (app) 的侧栏壳。
export default function MarketingLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: { lang: string };
}) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const h = getDictionary(lang).home;

  return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-30 border-b border-line bg-ink/70 backdrop-blur">
        <div className="mx-auto flex h-16 w-full max-w-[1180px] items-center justify-between gap-3 px-5 sm:px-8">
          <LocaleLink href="/" className="flex items-center gap-2.5">
            <span
              className="grid h-9 w-9 place-items-center rounded-xl font-display text-base font-extrabold text-white ring-1 ring-inset ring-white/15"
              style={{ backgroundImage: "var(--grad-brand)" }}
            >
              P
            </span>
            <span className="font-display text-xl font-extrabold tracking-tight text-cream">Prismo</span>
          </LocaleLink>
          <div className="flex items-center gap-2 sm:gap-3">
            <LanguageSwitcher />
            <LocaleLink
              href="/login"
              className="hidden rounded-full px-3.5 py-1.5 text-sm font-semibold text-neutral-300 transition hover:text-cream sm:inline-flex"
            >
              {h.login}
            </LocaleLink>
            <LocaleLink
              href="/signup"
              className="inline-flex rounded-full bg-reddit px-3.5 py-1.5 text-sm font-semibold text-white transition hover:bg-reddit/90"
            >
              {h.ctaSecondary}
            </LocaleLink>
          </div>
        </div>
      </header>

      <main className="mx-auto w-full max-w-[1180px] flex-1 px-5 py-10 sm:px-8 sm:py-14">{children}</main>

      <footer className="border-t border-line">
        <div className="mx-auto flex w-full max-w-[1180px] flex-wrap items-center justify-between gap-3 px-5 py-7 text-xs text-neutral-600 sm:px-8">
          <span>© Prismo</span>
          <span className="flex items-center gap-4">
            <a href="https://x.com/Connor_7s" target="_blank" rel="noreferrer noopener" className="transition hover:text-neutral-300">
              @Connor_7s
            </a>
            <a href="mailto:zfy3712z@gmail.com" className="transition hover:text-neutral-300">
              zfy3712z@gmail.com
            </a>
          </span>
        </div>
      </footer>

      <AnalyticsTracker />
    </div>
  );
}
