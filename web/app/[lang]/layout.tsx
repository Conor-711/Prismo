import type { Metadata } from "next";
import { LocaleProvider } from "@/components/i18n/LocaleProvider";
import { getDictionary, locales, defaultLocale, isLocale, type Locale } from "@/lib/i18n";

// 语言段布局：只提供语言上下文（dict）+ 注册 locale 静态参数。
// 站点 chrome（侧栏/顶栏）在 (app)/layout.tsx；落地页用 (marketing)/layout.tsx 的极简壳。
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
      {children}
    </LocaleProvider>
  );
}
