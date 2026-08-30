import type { Metadata } from "next";
import { OpinionExplorer, TickerDetailHeader, TickerOverviewLoader } from "@/features/ticker";
import { ViewportWorkspace } from "@/shared/layout/ViewportWorkspace";
import { getGrTickerSymbols, getGrTickerDetail, getGrQuote } from "@/server/queries/globalQueries";
import { getTickerMock, getKolFlow } from "@/shared/market/mockDetail";
import { getKolOpinions, getKolPriceDays } from "@/server/queries/kolQueries";
import { getTickerSmartVoice, getTickerSmartVoicePool } from "@/features/smart-account/svMock";
import { TICKER_UNIVERSE } from "@/shared/market/tickerMeta";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

function timed<T>(symbol: string, label: string, load: () => T): T {
  const startedAt = performance.now();
  const value = load();
  const elapsedMs = performance.now() - startedAt;
  if (process.env.NODE_ENV === "development" && elapsedMs >= 50) {
    console.info(`[ticker:${symbol}] ${label} ${elapsedMs.toFixed(0)}ms`);
  }
  return value;
}

export const dynamicParams = false;
export function generateStaticParams() {
  // 有 gr 数据用真实标的；为空（云端快照未含 gr_*）回退到固定全集，避免 output:export 因空数组报错。
  const syms = getGrTickerSymbols();
  return (syms.length ? syms : TICKER_UNIVERSE).map((symbol) => ({ symbol }));
}
export function generateMetadata({ params }: { params: { lang: string; symbol: string } }): Metadata {
  const zh = params.lang === "zh";
  return { title: `${params.symbol} · ${zh ? "标的详情" : "Ticker"} · bSmart` };
}

export default function TickerDetail({ params }: { params: { lang: string; symbol: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const sym = params.symbol.toUpperCase();
  // gr 数据缺失时（如云端快照未含 gr_*）用占位行：静态导出不崩，页面优雅降级（详情模块为 mock，照常渲染）。
  const ticker = timed(sym, "detail", () => getGrTickerDetail(params.symbol)).ticker ?? {
    ticker: sym, name_en: sym, name_zh: sym,
    regions_present: 0, total_posts: 0, avg_sentiment: 0,
    consensus: "sparse", spread: 0, divergent_region: "",
  };

  const name = zh ? ticker.name_zh || ticker.name_en : ticker.name_en || ticker.name_zh;
  const quote = timed(sym, "quote", () => getGrQuote(ticker.ticker));
  const m = getTickerMock(ticker.ticker);
  // 价格走势（真实优先，不足回退 mock）：页头迷你折线 + KOL 模块共用
  const mockFlow = getKolFlow(ticker.ticker);
  const priceDays = timed(sym, "price-days", () => getKolPriceDays(ticker.ticker));
  const flowDays = priceDays.length >= 4 ? priceDays : mockFlow.days;
  // 观点检索池：真实近 ~30 天扁平池优先，不足回退图表 opinions
  const kolPool = timed(sym, "opinion-previews", () => getKolOpinions(ticker.ticker, { preview: true }));
  const explorerPool = kolPool && kolPool.length ? kolPool : mockFlow.opinions;
  const smartVoice = getTickerSmartVoice(ticker.ticker);
  const smartVoicePool = getTickerSmartVoicePool(ticker.ticker);
  const topDim = [...m.anomaly.dims].sort((a, b) => b.sigma - a.sigma)[0];

  return (
    <ViewportWorkspace className="grid min-h-0 grid-rows-[auto_minmax(0,1fr)] gap-4 overflow-hidden" bottomOffset={16}>
      <TickerDetailHeader
        ticker={ticker}
        name={name}
        lang={lang}
        quote={quote}
        flowDays={flowDays}
        mock={m}
        topDim={topDim}
      />

      <div className="min-h-0 overflow-hidden">
        <OpinionExplorer
          symbol={ticker.ticker}
          opinions={explorerPool}
          zh={zh}
          fill
          currentPrice={quote?.price ?? null}
          svBoard={smartVoicePool}
          overview={
            <TickerOverviewLoader
              zh={zh}
              symbol={ticker.ticker}
              flowDays={flowDays}
              smartVoice={smartVoice}
            />
          }
        />
      </div>
    </ViewportWorkspace>
  );
}
