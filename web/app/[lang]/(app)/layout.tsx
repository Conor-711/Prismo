import { Sidebar } from "@/components/Sidebar";
import { Topbar } from "@/components/Topbar";
import { TopBanner } from "@/components/TopBanner";
import { BookmarkHint } from "@/components/BookmarkHint";
import { AnalyticsTracker } from "@/components/AnalyticsTracker";
import { MobileTabBar } from "@/components/MobileTabBar";
import { InstallPrompt } from "@/components/InstallPrompt";
import { OnboardingGate } from "@/components/OnboardingGate";
import { getDictionary, defaultLocale, isLocale, type Locale } from "@/lib/i18n";

// 应用外壳：侧栏 + 顶栏 + 移动底栏（登录后/进入产品的所有页面）。
// 语言上下文由父级 [lang]/layout 的 LocaleProvider 提供；这里只取 lang/dict 给 chrome 件。
export default function AppLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: { lang: string };
}) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const dict = getDictionary(lang);

  return (
    <>
      <Sidebar lang={lang} dict={dict} />
      <div className="app-main lg:pl-[232px]">
        <TopBanner />
        <Topbar lang={lang} dict={dict} />
        {/* pb-24：给移动端底部 Tab 栏留出空间（桌面端无 Tab 栏，恢复常规留白）。 */}
        <main className="px-4 sm:px-6 lg:px-8 pt-5 pb-24 lg:pb-8 max-w-[1480px] mx-auto">{children}</main>
      </div>
      <MobileTabBar />
      <InstallPrompt />
      <BookmarkHint />
      <AnalyticsTracker />
      <OnboardingGate />
    </>
  );
}
