import type { Metadata } from "next";
import { PageHeader, Panel } from "@/components/ui";
import { TickerSearch } from "@/components/prismo/TickerSearch";
import { getGrTickers } from "@/lib/globalQueries";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return { title: zh ? "搜索 · Prismo" : "Search · Prismo" };
}

export default function SearchPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const rows = getGrTickers();

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow={zh ? "PRISMO · 搜索" : "PRISMO · Search"}
        title={zh ? "搜索" : "Search"}
        subtitle={zh ? "在五社区聚合的跨区美股里查找标的。" : "Find a ticker across the 5-community cross-region universe."}
      />
      {rows.length ? (
        <TickerSearch rows={rows} lang={lang} />
      ) : (
        <Panel className="p-10 text-center">
          <p className="text-sm text-neutral-400">{zh ? "暂无可搜索的标的。" : "No tickers to search yet."}</p>
        </Panel>
      )}
    </div>
  );
}
