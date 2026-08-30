import { AnalyticsTracker } from "@/components/AnalyticsTracker";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export default function PublicLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: { lang: string };
}) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";

  return (
    <div className="flex min-h-screen flex-col bg-ink">
      <header className="z-30 h-14 shrink-0 border-b border-line bg-surface/95">
        <div className="mx-auto flex h-full w-full max-w-[1800px] items-center gap-4 px-4 sm:px-6 xl:px-8">
          <LocaleLink href="/" className="flex min-w-0 items-center gap-2.5">
            <span
              className="grid h-8 w-8 shrink-0 place-items-center rounded-md font-display text-sm font-extrabold text-white ring-1 ring-inset ring-white/15"
              style={{ backgroundImage: "var(--grad-brand)" }}
            >
              b
            </span>
            <span className="font-display text-[17px] font-extrabold text-cream">bSmart</span>
          </LocaleLink>

          <span className="h-5 w-px bg-line" />
          <div className="min-w-0">
            <div className="truncate text-[11px] font-bold uppercase tracking-[0.14em] text-reddit">Smart Account</div>
            <div className="truncate text-[10px] text-neutral-600">{zh ? "公开投资者榜" : "Public investor ranking"}</div>
          </div>

          <div className="ml-auto flex items-center gap-2 sm:gap-3">
            <LanguageSwitcher />
            <LocaleLink
              href="/smart-account"
              className="inline-flex h-8 items-center rounded-md bg-reddit px-3 text-[11.5px] font-bold text-[#12201d] transition hover:brightness-110"
            >
              {zh ? "进入 bSmart" : "Open bSmart"}
              <span aria-hidden className="ml-1.5">→</span>
            </LocaleLink>
          </div>
        </div>
      </header>

      <main className="min-h-0 flex-1">{children}</main>
      <AnalyticsTracker />
    </div>
  );
}
