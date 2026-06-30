import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Consensus, PriceTag } from "@/components/prismo/Bits";
import { TickerLogo } from "@/components/prismo/TickerLogo";
import { KolModule } from "@/components/prismo/KolModule";
import { OpinionExplorer } from "@/components/prismo/OpinionExplorer";
import { TopInvestors } from "@/components/prismo/TopInvestors";
import { PriceSparkline } from "@/components/prismo/PriceSparkline";
import { Module, StageBadge } from "@/components/prismo/DetailBits";
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

  return (
    <div className="space-y-5">
      <LocaleLink href="/tickers" className="inline-flex items-center gap-1 text-xs text-neutral-500 hover:text-reddit transition">
        ← {zh ? "标的总览" : "All tickers"}
      </LocaleLink>

      {/* 页头 · 基础信息单行：logo/名称 + 紧凑指标（原第二行上移、缩小）+ 右侧迷你折线&价格 */}
      <div className="panel rounded-xl px-4 sm:px-5 py-3.5">
        <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
          {/* logo + 名称 + 代码/badges */}
          <div className="flex shrink-0 items-center gap-3 min-w-0">
            <TickerLogo ticker={ticker.ticker} size={44} />
            <div className="min-w-0">
              <h1 className="font-display font-extrabold text-cream text-xl sm:text-2xl tracking-tight leading-none truncate">{name}</h1>
              <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[12.5px]">
                <span className="font-mono font-semibold text-neutral-300">{ticker.ticker}</span>
                {tickerExchange(ticker.ticker) && <span className="text-neutral-600">· {tickerExchange(ticker.ticker)}</span>}
                <Consensus value={ticker.consensus} lang={lang} />
                <StageBadge stage={m.risk.stage} lang={lang} />
              </div>
            </div>
          </div>

          {/* 紧凑指标条（原大数字 KPI 缩小并上移） */}
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5">
            {[
              { label: zh ? "平均情绪" : "Sentiment", value: (ticker.avg_sentiment > 0 ? "+" : "") + ticker.avg_sentiment.toFixed(2), tone: ticker.avg_sentiment >= 0 ? "text-bull" : "text-bear" },
              { label: zh ? "风险温度" : "Risk temp", value: String(m.risk.temp), tone: m.risk.temp > 66 ? "text-bear" : m.risk.temp > 40 ? "text-amber" : "text-bull" },
              { label: zh ? "多空比" : "Bull/bear", value: `${m.bullBear.bullPct}%`, tone: m.bullBear.bullPct >= 50 ? "text-bull" : "text-bear" },
              { label: zh ? "共识强度" : "Consensus", value: String(m.bullBear.consensus), tone: "text-cream" },
              { label: zh ? "最强异动" : "Top anomaly", value: `${topDim.sigma}σ`, tone: topDim.sigma >= 4 ? "text-bear" : topDim.sigma >= 2.5 ? "text-amber" : "text-cream" },
              { label: zh ? "讨论帖" : "Posts", value: fmtCompact(ticker.total_posts), tone: "text-cream" },
            ].map((s) => (
              <div key={s.label} className="px-1">
                <div className="text-[10px] uppercase tracking-wide text-neutral-500">{s.label}</div>
                <div className={`mt-0.5 font-display font-bold text-[17px] leading-none tabular ${s.tone}`}>{s.value}</div>
              </div>
            ))}
          </div>

          {/* 右侧：迷你价格走势（更小）+ 价格 */}
          <div className="ml-auto flex shrink-0 items-center gap-3">
            <div className="w-[84px] sm:w-[116px]"><PriceSparkline days={flow.days} height={34} /></div>
            {quote && (
              <div className="text-right">
                <PriceTag price={quote.price} change={quote.price - quote.prev_close} changePct={quote.change_pct} />
                {quote.asof && <div className="mt-0.5 text-[10px] text-neutral-600">{zh ? "截至 " : "As of "}{quote.asof}</div>}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* ① 整体数据（KOL ↔ 整体散户）：每日净情绪折线 + 每日讨论度 + 每日新增散户（整体散户视图）。
          命名「整体数据」：本模块后续不仅情绪/讨论度，还反映标的整体形势。价格走势已上移页头；观点浏览独立为模块 ③ */}
      <Module
        title={zh ? "整体数据" : "Overview"}
        icon="trend"
        accent="reddit"
        hint={zh
          ? "聪明钱↔散户分歧 · 每日净情绪/讨论度/新增(⚑ AI 异动归因) · 可切 KOL/整体散户"
          : "smart-money↔retail divergence · sentiment/volume/new (⚑ AI anomalies) · toggle KOL/all-retail"}
      >
        {/* 真实数据优先（kol / retail 各 daily 表）；不足时回退确定性 mock，保证不空 */}
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
      </Module>

      {/* ② 观点检索（已从情绪/讨论度模块独立出来）：按平台 / 立场 / 视角 / 时间 / 语言 / 相关性 浏览 KOL 原文 */}
      <Module
        title={zh ? "观点检索" : "Opinion explorer"}
        icon="layers"
        accent="reddit"
        hint={zh
          ? "X / YouTube / Reddit / 雪球 的 KOL 原文 · 按平台 / 时间 / 语言 / 质量 筛选,逐条精读"
          : "KOL posts from X / YouTube / Reddit / Xueqiu · filter by platform / time / language / quality"}
      >
        <OpinionExplorer opinions={explorerPool} zh={zh} />
      </Module>

      {/* 该标的值得参考的投资者（移到最底部）：简单排行榜 —— 覆盖本标的的博主按「跨标的选股技能 z」排名 */}
      {topInv && topInv.investors.length > 0 && (
        <Module
          title={zh ? "该标的值得参考的投资者" : "Investors worth following on this ticker"}
          icon="pulse"
          accent="amber"
          hint={zh
            ? "覆盖本标的的博主 · 按「跨标的选股技能（样本外验证，非单票运气）」排名"
            : "authors covering this ticker · ranked by cross-ticker stock-picking skill (out-of-sample validated)"}
        >
          <TopInvestors board={topInv} zh={zh} />
        </Module>
      )}

      <p className="text-[11px] text-neutral-600 text-center pt-1">
        {zh ? "异动 / 信号 / 风险等模块为演示数据（mock），用于展示模块设计；接入真实管线后替换。" : "Modules use mock demo data to showcase the design; to be wired to the real pipeline."}
      </p>
    </div>
  );
}
