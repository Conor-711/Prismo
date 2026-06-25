import type { Metadata } from "next";
import { PageHeader } from "@/components/ui";
import { TrackingView } from "@/components/prismo/TrackingView";
import { getGrTickers, getGrTickerRegions } from "@/lib/globalQueries";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";

// 追踪页（私密）。页面是薄壳：服务端把全部标的摘要烤进去，登录态/过滤在客户端的 TrackingView。
// [lang] 的 generateStaticParams 由 layout 提供，与 output:export 兼容。
export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const t = getDictionary(params.lang).tracking;
  return { title: `${t.title} · Prismo` };
}

export default function TrackingPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).tracking;
  const rows = getGrTickers();
  const regions = getGrTickerRegions();

  return (
    <div className="space-y-6">
      <PageHeader eyebrow="PRISMO" title={t.title} subtitle={t.subtitle} />
      <TrackingView rows={rows} regions={regions} lang={lang} />
    </div>
  );
}
