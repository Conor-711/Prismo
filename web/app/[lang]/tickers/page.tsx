import type { Metadata } from "next";
import { PageHeader, Panel } from "@/components/ui";
import { TickerTable } from "@/components/prismo/TickerTable";
import { getGrTickers } from "@/lib/globalQueries";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return { title: zh ? "标的总览 · Prismo" : "Tickers · Prismo" };
}

export default function TickersPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const rows = getGrTickers();

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow={zh ? "PRISMO · 标的" : "PRISMO · Tickers"}
        title={zh ? "标的总览" : "Tickers"}
        subtitle={
          zh
            ? `${rows.length} 支跨区美股 · 五社区平均情绪、覆盖地区与跨区分歧。点表头排序、上方框筛选。`
            : `${rows.length} cross-region US tickers — avg sentiment, regions covered and cross-region spread. Click headers to sort.`
        }
      />
      {rows.length ? (
        <TickerTable rows={rows} lang={lang} />
      ) : (
        <Panel className="p-10 text-center">
          <p className="text-sm text-neutral-400">{zh ? "暂无标的数据。" : "No ticker data yet."}</p>
          <p className="mt-2 text-xs text-neutral-600">
            {zh ? "运行 " : "Run "}
            <code className="px-1.5 py-0.5 rounded bg-white/[.06] text-reddit font-mono">make gr</code>
            {zh ? " 后重新构建。" : " then rebuild."}
          </p>
        </Panel>
      )}
    </div>
  );
}
