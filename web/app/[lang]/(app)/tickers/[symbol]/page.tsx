import type { Metadata } from "next";
import { Consensus, PriceTag } from "@/components/prismo/Bits";
import { TickerLogo } from "@/components/prismo/TickerLogo";
import { KolModule } from "@/components/prismo/KolModule";
import { OpinionExplorer } from "@/components/prismo/OpinionExplorer";
import { TopInvestors } from "@/components/prismo/TopInvestors";
import { PriceSparkline } from "@/components/prismo/PriceSparkline";
import { ViewportWorkspace } from "@/components/prismo/ViewportWorkspace";
import { StageBadge } from "@/components/prismo/DetailBits";
import { getGrTickerSymbols, getGrTickerDetail, getGrQuote } from "@/lib/globalQueries";
import { getTickerMock, getKolFlow } from "@/lib/mockDetail";
import { getKolFlowReal, getKolOpinions, getKolSentimentDaily, getKolVolumeDaily, getRetailSentimentDaily, getRetailVolumeDaily, getRetailNewcomersDaily, getKolTargetPrices } from "@/lib/kolQueries";
import { getTopInvestors } from "@/lib/topInvestors";
import { getOverallData } from "@/lib/overallData";
import { tickerExchange, TICKER_UNIVERSE } from "@/lib/tickerMeta";
import { fmtCompact } from "@/lib/format";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export const dynamicParams = false;
export function generateStaticParams() {
  // 有 gr 数据用真实标的；为空（云端快照未含 gr_*）回退到固定全集，避免 output:export 因空数组报错。
  const syms = getGrTickerSymbols();
  return (syms.length ? syms : TICKER_UNIVERSE).map((symbol) => ({ symbol }));
}
export function generateMetadata({ params }: { params: { lang: string; symbol: string } }): Metadata {
  const zh = params.lang === "zh";
  return { title: `${params.symbol} · ${zh ? "标的详情" : "Ticker"} · Prismo` };
}

function InfoHint({ text }: { text: string }) {
  return (
    <span className="group relative inline-flex">
      <span
        tabIndex={0}
        aria-label={text}
        className="grid h-4 w-4 cursor-help place-items-center rounded-full text-[10px] font-bold text-neutral-500 ring-1 ring-inset ring-neutral-500/70 transition hover:text-cream hover:ring-neutral-300 focus:text-cream focus:outline-none focus:ring-neutral-300"
      >
        i
      </span>
      <span className="pointer-events-none absolute left-1/2 top-5 z-30 hidden w-72 -translate-x-1/2 rounded-lg bg-elevated px-3 py-2 text-[11px] font-normal leading-relaxed text-neutral-300 shadow-xl ring-1 ring-inset ring-line group-hover:block group-focus-within:block">
        {text}
      </span>
    </span>
  );
}

export default function TickerDetail({ params }: { params: { lang: string; symbol: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const sym = params.symbol.toUpperCase();
  // gr 数据缺失时（如云端快照未含 gr_*）用占位行：静态导出不崩，页面优雅降级（详情模块为 mock，照常渲染）。
  const ticker = getGrTickerDetail(params.symbol).ticker ?? {
    ticker: sym, name_en: sym, name_zh: sym,
    regions_present: 0, total_posts: 0, avg_sentiment: 0,
    consensus: "sparse", spread: 0, divergent_region: "",
  };

  const name = zh ? ticker.name_zh || ticker.name_en : ticker.name_en || ticker.name_zh;
  const quote = getGrQuote(ticker.ticker);
  const m = getTickerMock(ticker.ticker);
  // 价格走势（真实优先，不足回退 mock）：页头迷你折线 + KOL 模块共用
  const flow = getKolFlowReal(ticker.ticker) ?? getKolFlow(ticker.ticker);
  // 观点检索池：真实近 ~30 天扁平池优先，不足回退图表 opinions
  const kolPool = getKolOpinions(ticker.ticker);
  const explorerPool = kolPool && kolPool.length ? kolPool : flow.opinions;
  const topInv = getTopInvestors(ticker.ticker);
  // 整体数据派生信号：情绪/讨论度异动归因 + 近期 KOL 最密集讨论方面（离线 overall_signals 产出）
  const overall = getOverallData(ticker.ticker);
  const topDim = [...m.anomaly.dims].sort((a, b) => b.sigma - a.sigma)[0];

  const stats = [
    { label: zh ? "平均情绪" : "Sentiment", value: (ticker.avg_sentiment > 0 ? "+" : "") + ticker.avg_sentiment.toFixed(2), tone: ticker.avg_sentiment >= 0 ? "text-bull" : "text-bear" },
    { label: zh ? "风险温度" : "Risk temp", value: String(m.risk.temp), tone: m.risk.temp > 66 ? "text-bear" : m.risk.temp > 40 ? "text-amber" : "text-bull" },
    { label: zh ? "多空比" : "Bull/bear", value: `${m.bullBear.bullPct}%`, tone: m.bullBear.bullPct >= 50 ? "text-bull" : "text-bear" },
    { label: zh ? "共识强度" : "Consensus", value: String(m.bullBear.consensus), tone: "text-cream" },
    { label: zh ? "最强异动" : "Top anomaly", value: `${topDim.sigma}σ`, tone: topDim.sigma >= 4 ? "text-bear" : topDim.sigma >= 2.5 ? "text-amber" : "text-cream" },
    { label: zh ? "讨论帖" : "Posts", value: fmtCompact(ticker.total_posts), tone: "text-cream" },
  ];

  return (
    <ViewportWorkspace className="grid min-h-0 grid-rows-[auto_minmax(0,1fr)] gap-4 overflow-hidden" bottomOffset={16}>
      <div className="px-1 py-1">
        <div className="flex items-center gap-x-5 gap-y-3">
          <div className="flex min-w-[220px] shrink-0 items-center gap-3">
            <TickerLogo ticker={ticker.ticker} size={44} />
            <div className="min-w-0">
              <h1 className="truncate font-display text-2xl font-extrabold leading-none tracking-tight text-cream">{name}</h1>
              <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[12.5px]">
                <span className="font-mono font-semibold text-neutral-300">{ticker.ticker}</span>
                {tickerExchange(ticker.ticker) && <span className="text-neutral-600">· {tickerExchange(ticker.ticker)}</span>}
                <Consensus value={ticker.consensus} lang={lang} />
                <StageBadge stage={m.risk.stage} lang={lang} />
              </div>
            </div>
          </div>

          <div className="grid min-w-0 flex-1 grid-cols-6 divide-x divide-line overflow-hidden rounded-lg bg-white/[.012] ring-1 ring-inset ring-white/[.06]">
            {stats.map((s) => (
              <div key={s.label} className="min-w-0 px-3 py-2">
                <div className="truncate text-[10px] uppercase tracking-wide text-neutral-500">{s.label}</div>
                <div className={`mt-0.5 truncate font-display text-[17px] font-bold leading-none tabular ${s.tone}`}>{s.value}</div>
              </div>
            ))}
          </div>

          <div className="flex shrink-0 items-center gap-3">
            <div className="w-[116px]"><PriceSparkline days={flow.days} height={34} /></div>
            {quote && (
              <div className="text-right">
                <PriceTag price={quote.price} change={quote.price - quote.prev_close} changePct={quote.change_pct} />
                {quote.asof && <div className="mt-0.5 text-[10px] text-neutral-600">{zh ? "截至 " : "As of "}{quote.asof}</div>}
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="min-h-0 overflow-hidden">
        <OpinionExplorer
          opinions={explorerPool}
          zh={zh}
          fill
          overview={
            <div className="flex h-full min-h-0 flex-col overflow-hidden rounded-xl bg-card/45 ring-1 ring-inset ring-line">
              <div className="flex shrink-0 items-center justify-between gap-3 border-b border-line px-4 py-3">
                <div className="min-w-0">
                  <h2 className="flex items-center gap-1.5 font-display text-[15px] font-bold leading-none text-cream">
                    {zh ? "整体数据" : "Overview"}
                    <InfoHint
                      text={
                        zh
                          ? "展示该标的在近一年里的净情绪、讨论度、聪明钱与散户分歧，以及 AI 识别的异常波动归因。当前更早日期使用稳定 mock 补全，用于呈现一年尺度。"
                          : "Shows one-year net sentiment, discussion volume, smart-money vs retail divergence, and AI anomaly attribution. Earlier missing dates are filled with stable mock data for the one-year view."
                      }
                    />
                  </h2>
                </div>
                <span className="shrink-0 rounded-md bg-reddit/12 px-2 py-1 text-[11px] font-semibold text-reddit ring-1 ring-inset ring-reddit/25">
                  {zh ? "Overview" : "Overview"}
                </span>
              </div>
              <div className="min-h-0 flex-1 overflow-y-auto p-3">
                <KolModule
                  flow={flow}
                  sentiment={getKolSentimentDaily(ticker.ticker)}
                  volume={getKolVolumeDaily(ticker.ticker)}
                  retailSentiment={getRetailSentimentDaily(ticker.ticker)}
                  retailVolume={getRetailVolumeDaily(ticker.ticker)}
                  retailNewcomers={getRetailNewcomersDaily(ticker.ticker)}
                  overall={overall}
                  targetPrices={getKolTargetPrices(ticker.ticker)}
                />
                {topInv && topInv.investors.length > 0 && (
                  <div className="mt-4 overflow-hidden rounded-xl bg-ink/35 ring-1 ring-inset ring-line">
                    <div className="border-b border-line px-4 py-3">
                      <h3 className="flex items-center gap-1.5 font-display text-[14px] font-bold text-cream">
                        {zh ? "该标的值得参考的投资者" : "Investors worth following on this ticker"}
                        <InfoHint
                          text={
                            zh
                              ? "覆盖本标的的博主列表，按跨标的选股技能和相关覆盖质量排序。"
                              : "Authors covering this ticker, ranked by cross-ticker stock-picking skill and coverage quality."
                          }
                        />
                      </h3>
                    </div>
                    <div className="px-4 py-2">
                      <TopInvestors board={topInv} zh={zh} />
                    </div>
                  </div>
                )}
                <p className="mt-3 border-t border-line/70 pt-2 text-[10.5px] text-neutral-600">
                  {zh ? "异动 / 信号 / 风险等模块为演示数据（mock），用于展示模块设计；接入真实管线后替换。" : "Modules use mock demo data to showcase the design; to be wired to the real pipeline."}
                </p>
              </div>
            </div>
          }
        />
      </div>
    </ViewportWorkspace>
  );
}
