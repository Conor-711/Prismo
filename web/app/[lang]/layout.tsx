import type { Metadata } from "next";
import { Sidebar } from "@/components/Sidebar";
import { Topbar } from "@/components/Topbar";
import { TopBanner } from "@/components/TopBanner";
import { TickerTape } from "@/components/TickerTape";
import { ThemeToggle } from "@/components/ThemeToggle";
import { BookmarkHint } from "@/components/BookmarkHint";
import { AnalyticsTracker } from "@/components/AnalyticsTracker";
import { MobileTabBar } from "@/components/MobileTabBar";
import { InstallPrompt } from "@/components/InstallPrompt";
import { LocaleProvider } from "@/components/i18n/LocaleProvider";
import { getDictionary, locales, defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const d = getDictionary(params.lang);
  return { title: d.meta.title, description: d.meta.description };
}

export default function LangLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: { lang: string };
}) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const dict = getDictionary(lang);

  return (
    <LocaleProvider lang={lang} dict={dict}>
      <Sidebar lang={lang} dict={dict} />
      <div className="app-main lg:pl-[232px]">
        <TopBanner />
        <Topbar lang={lang} dict={dict} />
        <TickerTape />
        {/* pb-24：给移动端底部 Tab 栏留出空间（桌面端无 Tab 栏，恢复常规留白）。 */}
        <main className="px-4 sm:px-6 lg:px-8 pt-5 pb-24 lg:pb-8 max-w-[1480px] mx-auto">{children}</main>
      </div>
      <ThemeToggle />
      <MobileTabBar />
      <InstallPrompt />
      <BookmarkHint />
      <AnalyticsTracker />
    </LocaleProvider>
  );
}
