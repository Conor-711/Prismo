import { LocaleLink } from "@/components/i18n/LocaleLink";
import { AsiaHeatmap } from "@/components/asia/AsiaCharts";
import { ViewportWorkspace } from "@/shared/layout/ViewportWorkspace";
import { TickerLogo } from "@/shared/market/TickerLogo";
import { SentScore, StanceBar } from "@/shared/ui/prismoBits";
import { fmtCompact, fmtInt, timeAgo } from "@/shared/formatting/format";
import { regionLabel } from "@/shared/market/regions";
import { smartVoiceInvestorHref } from "@/features/smart-voice";
import type { Locale } from "@/lib/i18n";
import type { DashboardModel } from "../types";
import { DashboardSignalPanel } from "./DashboardSignalPanel";

function PanelShell({
  title,
  meta,
  right,
  children,
  bodyClassName = "min-h-0 flex-1",
  className = "",
}: {
  title: string;
  meta?: string;
  right?: React.ReactNode;
  children: React.ReactNode;
  bodyClassName?: string;
  className?: string;
}) {
  return (
    <section className={`panel flex min-h-0 flex-col overflow-hidden rounded-lg ${className}`}>
      <div className="flex h-11 shrink-0 items-center gap-2.5 border-b border-line px-3">
        <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-reddit" />
        <h2 className="min-w-0 flex-1 truncate font-display text-[14px] font-bold text-cream">{title}</h2>
        {meta && <span className="shrink-0 text-[10px] text-neutral-600">{meta}</span>}
        {right}
      </div>
      <div className={bodyClassName}>{children}</div>
    </section>
  );
}

function KpiStrip({ model, zh }: { model: DashboardModel; zh: boolean }) {
  const { topGainer, topLoser, topDivergence } = model.market;
  const items = [
    {
      label: zh ? "覆盖标的" : "Tickers",
      value: fmtInt(model.meta.tickers),
      sub: zh ? `${model.meta.regions} 个社区` : `${model.meta.regions} communities`,
      tone: "text-cream",
    },
    {
      label: zh ? "讨论样本" : "Discussions",
      value: fmtCompact(model.meta.posts),
      sub: zh ? "跨社区合计" : "cross-community",
      tone: "text-cream",
    },
    {
      label: zh ? "社区覆盖" : "Coverage",
      value: `${model.meta.regions}/5`,
      sub: "US · CN · JP · KR · TW",
      tone: "text-cream",
    },
    {
      label: zh ? "今日领涨" : "Top gainer",
      value: topGainer ? `+${topGainer.changePct.toFixed(2)}%` : "—",
      sub: topGainer?.ticker ?? "—",
      tone: "text-bull",
    },
    {
      label: zh ? "今日领跌" : "Top loser",
      value: topLoser ? `${topLoser.changePct.toFixed(2)}%` : "—",
      sub: topLoser?.ticker ?? "—",
      tone: "text-bear",
    },
    {
      label: zh ? "最大分歧" : "Top divergence",
      value: topDivergence ? `Δ${topDivergence.spread.toFixed(2)}` : "—",
      sub: topDivergence?.ticker ?? "—",
      tone: "text-reddit",
    },
  ];

  return (
    <section className="panel grid shrink-0 grid-cols-3 divide-x divide-y divide-line overflow-hidden rounded-lg lg:grid-cols-6 lg:divide-y-0">
      {items.map((item) => (
        <div key={item.label} className="min-w-0 px-3 py-2.5">
          <div className="truncate text-[9.5px] font-medium uppercase text-neutral-600">{item.label}</div>
          <div className={`mt-1 truncate font-display text-[18px] font-extrabold leading-none tabular ${item.tone}`}>
            {item.value}
          </div>
          <div className="mt-1 truncate text-[9.5px] text-neutral-600">{item.sub}</div>
        </div>
      ))}
    </section>
  );
}

function BuzzPanel({ model, lang }: { model: DashboardModel; lang: Locale }) {
  const zh = lang === "zh";
  return (
    <PanelShell
      title={zh ? "全球热度榜" : "Global buzz"}
      meta="Top 10"
      right={(
        <LocaleLink href="/tickers" className="ml-1 shrink-0 text-[10px] font-semibold text-reddit hover:text-cream">
          {zh ? "全部" : "All"} →
        </LocaleLink>
      )}
      bodyClassName="min-h-0 flex-1 overflow-y-auto"
    >
      <div className="sticky top-0 z-10 grid grid-cols-[22px_minmax(0,1fr)_52px_48px] gap-2 border-b border-line bg-card px-3 py-1 text-[9px] uppercase text-neutral-600">
        <span>#</span>
        <span>{zh ? "标的 / 多空" : "Ticker / stance"}</span>
        <span className="text-right">{zh ? "讨论" : "Posts"}</span>
        <span className="text-right">{zh ? "情绪" : "Sent"}</span>
      </div>
      {model.buzz.map((item, index) => (
        <div
          key={item.ticker}
          className="grid min-h-[38px] grid-cols-[22px_minmax(0,1fr)_52px_48px] items-center gap-2 border-b border-line/70 px-3 py-1.5 last:border-b-0 hover:bg-white/[.03]"
        >
          <span className="font-mono text-[10px] tabular text-neutral-600">{index + 1}</span>
          <div className="min-w-0">
            <LocaleLink href={`/tickers/${item.ticker}`} className="flex min-w-0 items-center gap-2 hover:text-reddit">
              <TickerLogo ticker={item.ticker} size={20} />
              <span className="font-mono text-[11px] font-bold text-cream">{item.ticker}</span>
              <span className="truncate text-[9.5px] text-neutral-600">
                {zh ? item.nameZh || item.nameEn : item.nameEn || item.nameZh}
              </span>
            </LocaleLink>
            <div className="mt-1 max-w-[132px]"><StanceBar bull={item.bull} bear={item.bear} neutral={item.neutral} /></div>
          </div>
          <div className="text-right">
            <div className="font-mono text-[10.5px] tabular text-neutral-300">{fmtCompact(item.posts)}</div>
            <div className="text-[8.5px] text-neutral-600">{item.regions} {zh ? "社区" : "communities"}</div>
          </div>
          <SentScore score={item.sentiment} className="text-right text-[10.5px]" />
        </div>
      ))}
    </PanelShell>
  );
}

function VoicePanel({ model, lang }: { model: DashboardModel; lang: Locale }) {
  const zh = lang === "zh";
  const sourceColor = (source: "x" | "youtube" | "reddit" | "xueqiu" | "toss") => {
    if (source === "youtube") return "#E0A33E";
    if (source === "reddit") return "#E07A55";
    if (source === "xueqiu") return "#5BA3C4";
    if (source === "toss") return "#D6A24A";
    return "#8C96A2";
  };
  const scoreTone = (score: number) => score >= 120 ? "text-bull" : score < 95 ? "text-bear" : "text-cream";
  const confidence = (value: string) => {
    if (!zh) return value === "high" ? "High" : value === "medium" ? "Medium" : value === "low" ? "Low" : "Observe";
    return value === "high" ? "高置信" : value === "medium" ? "中置信" : value === "low" ? "低置信" : "观察中";
  };

  return (
    <PanelShell
      title={zh ? "Smart Voice 投资者" : "Smart Voice investors"}
      meta={`${fmtCompact(model.voicePool)} ${zh ? "样本" : "pool"}`}
      className="h-full"
      right={(
        <LocaleLink href="/smart-voice" className="ml-1 shrink-0 text-[10px] font-semibold text-reddit hover:text-cream">
          {zh ? "工作台" : "Workspace"} →
        </LocaleLink>
      )}
      bodyClassName="flex min-h-0 flex-1 flex-col"
    >
      <div className="grid min-h-0 flex-1 overflow-y-auto" style={{ gridAutoRows: "minmax(52px, 1fr)" }}>
        {model.voices.map((voice, index) => {
          const color = sourceColor(voice.source);
          const initial = (voice.name || voice.handle || "?").replace(/^@/, "").charAt(0).toUpperCase();
          return (
            <div
              key={voice.id}
              className="grid min-h-[52px] grid-cols-[22px_26px_minmax(0,1fr)_38px] items-center gap-2 border-b border-line/70 px-3 py-1.5 last:border-b-0 hover:bg-white/[.03]"
            >
              <span className="font-mono text-[10px] font-bold tabular text-neutral-600">#{index + 1}</span>
              <span
                className="grid h-[26px] w-[26px] place-items-center rounded-full text-[10px] font-bold"
                style={{ color, background: `${color}1f` }}
              >
                {initial}
              </span>
              <div className="min-w-0">
                <LocaleLink href={smartVoiceInvestorHref(voice.id)} className="flex min-w-0 items-center gap-1.5 hover:text-reddit">
                  <span className="truncate text-[11px] font-semibold text-cream">{voice.name}</span>
                  <span className="shrink-0 rounded px-1 py-px text-[8.5px] font-semibold" style={{ color, background: `${color}18` }}>
                    {voice.source === "youtube" ? "YT" : voice.source === "reddit" ? "RD" : voice.source === "xueqiu" ? "雪球" : voice.source === "toss" ? "Toss" : "X"}
                  </span>
                </LocaleLink>
                <div className="mt-1 flex min-w-0 items-center gap-1">
                  {voice.topTickers.map((ticker) => (
                    <LocaleLink key={ticker} href={`/tickers/${ticker}`} className="rounded bg-white/[.04] px-1 py-px font-mono text-[8.5px] text-neutral-500 hover:text-cream">
                      {ticker}
                    </LocaleLink>
                  ))}
                  <span className="truncate text-[8.5px] text-neutral-600">{confidence(voice.confidence)} · {fmtCompact(voice.settledCalls)}</span>
                </div>
              </div>
              <div className="text-right">
                <div className="text-[8px] font-bold uppercase tracking-wider text-neutral-600">SV</div>
                <div className={`font-display text-[16px] font-extrabold leading-none tabular ${scoreTone(voice.score)}`}>{voice.score}</div>
              </div>
            </div>
          );
        })}
      </div>
      <div className="shrink-0 border-t border-line px-3 py-2">
        <div className="mb-1.5 text-[9px] font-medium uppercase text-neutral-600">{zh ? "当前叙事权重" : "Narrative weights"}</div>
        <div className="grid grid-cols-2 gap-x-3 gap-y-1">
          {model.narratives.slice(0, 4).map((narrative) => (
            <div key={narrative.key} className="flex min-w-0 items-center justify-between gap-2 text-[9px]">
              <span className="truncate text-neutral-500">{zh ? narrative.zh : narrative.en}</span>
              <span className="font-mono font-semibold tabular text-reddit">{narrative.weight}%</span>
            </div>
          ))}
        </div>
      </div>
    </PanelShell>
  );
}

export function DashboardWorkspace({ model, lang }: { model: DashboardModel; lang: Locale }) {
  const zh = lang === "zh";
  const heatX = model.heatmap.regionCodes.map((region) => regionLabel(region, lang));

  return (
    <ViewportWorkspace className="overflow-y-auto lg:overflow-hidden" bottomOffset={16}>
      <div data-testid="dashboard-workspace" className="flex h-full min-h-0 flex-col gap-2.5">
        <header className="flex min-h-9 shrink-0 items-center justify-between gap-4 border-b border-line pb-2">
          <div className="flex min-w-0 items-center gap-3">
            <div className="shrink-0">
              <div className="text-[9.5px] font-bold uppercase tracking-[0.14em] text-reddit">PRISMO · MARKET INTELLIGENCE</div>
              <h1 className="mt-0.5 font-display text-[20px] font-extrabold leading-none text-cream">
                {zh ? "总览看板" : "Market overview"}
              </h1>
            </div>
            <span className="hidden h-7 w-px bg-line xl:block" />
            <p className="hidden truncate text-[11px] text-neutral-500 xl:block">
              {zh ? "跨社区信号、市场热度与 Smart Voice 的统一工作台" : "Cross-community signals, market activity and Smart Voice in one workspace"}
            </p>
          </div>
          <div className="flex shrink-0 items-center gap-2 text-[10px] text-neutral-500">
            <span className="h-1.5 w-1.5 rounded-full bg-bull" />
            <span>{model.meta.lastUpdated ? `${zh ? "更新于 " : "Updated "}${timeAgo(model.meta.lastUpdated, lang)}` : (zh ? "等待数据更新" : "Awaiting data")}</span>
          </div>
        </header>

        {model.empty ? (
          <div className="panel grid min-h-0 flex-1 place-items-center rounded-lg p-8 text-center">
            <div>
              <p className="text-sm text-neutral-400">{zh ? "暂无跨社区数据" : "No cross-community data yet"}</p>
              <p className="mt-2 text-[11px] text-neutral-600">
                {zh ? "运行 make gr 后重新构建站点。" : "Run make gr locally, then rebuild the site."}
              </p>
            </div>
          </div>
        ) : (
          <>
            <KpiStrip model={model} zh={zh} />

            <div className="grid min-h-0 flex-1 gap-2.5 lg:grid-cols-[minmax(210px,0.78fr)_minmax(360px,1.65fr)_minmax(220px,0.9fr)] lg:overflow-hidden">
              <div className="min-h-[520px] min-w-0 lg:min-h-0">
                <DashboardSignalPanel signals={model.signals} lang={lang} />
              </div>

              <div className="grid min-h-[620px] min-w-0 grid-rows-[minmax(0,1.35fr)_minmax(0,0.85fr)] gap-2.5 lg:min-h-0">
                <PanelShell
                  title={zh ? "跨社区情绪热力" : "Cross-community sentiment"}
                  meta={`${model.heatmap.tickers.length} ${zh ? "标的" : "tickers"} · ${heatX.length} ${zh ? "社区" : "communities"}`}
                  bodyClassName="min-h-0 flex-1 p-1.5"
                >
                  {model.heatmap.cells.length ? (
                    <AsiaHeatmap x={heatX} y={model.heatmap.tickers} cells={model.heatmap.cells} rawX height="100%" />
                  ) : (
                    <div className="grid h-full place-items-center text-[11px] text-neutral-600">{zh ? "暂无热力数据" : "No heatmap data"}</div>
                  )}
                </PanelShell>
                <BuzzPanel model={model} lang={lang} />
              </div>

              <div className="min-h-[560px] min-w-0 lg:min-h-0">
                <VoicePanel model={model} lang={lang} />
              </div>
            </div>
          </>
        )}
      </div>
    </ViewportWorkspace>
  );
}
