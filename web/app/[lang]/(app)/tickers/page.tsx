import type { Metadata } from "next";
import { PageHeader, Panel } from "@/components/ui";
import { TickerSignalBoards, TickerTable } from "@/features/ticker";
import { getGrTickers } from "@/server/queries/globalQueries";
import { getKolBullBearBoards, getKolSentimentSwings } from "@/server/queries/kolQueries";
import { getSmartVoiceTickerBoards } from "@/server/queries/smartVoiceQueries";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return { title: zh ? "标的总览 · bSmart" : "Tickers · bSmart" };
}

export default function TickersPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const rows = getGrTickers();
  const { bullish, bearish } = getKolBullBearBoards();
  const swings = getKolSentimentSwings();
  const svBoards = getSmartVoiceTickerBoards();

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow={zh ? "bSmart · 标的" : "bSmart · Tickers"}
        title={zh ? "标的总览" : "Tickers"}
        subtitle={
          zh
            ? `${rows.length} 支美股标的 · 已接入 12 个月本地 X/Twitter 原始帖文。点表头排序、上方框筛选。`
            : `${rows.length} US tickers with 12 months of local X/Twitter posts. Click headers to sort.`
        }
      />
      <TickerSignalBoards
        kolBullish={bullish}
        kolBearish={bearish}
        kolSwings={swings}
        svBullish={svBoards.bullish}
        svBearish={svBoards.bearish}
        svContrast={svBoards.contrast}
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
