"use client";

import { useMemo, useState } from "react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { ViewportWorkspace } from "@/shared/layout/ViewportWorkspace";
import { TickerLogo } from "@/shared/market/TickerLogo";
import type { PrivateSmartVoiceExperimentData } from "@/server/queries/privateSmartVoiceExperiment";
import type { PrivateSmartVoiceTicker } from "@/server/queries/privateSmartVoiceExperiment";
import type { SmartVoiceRepresentativeShowcase } from "@/server/queries/smartVoiceInvestorQueries";
import { PrivateSmartVoiceCallTable } from "./PrivateSmartVoiceCallTable";
import { SmartVoicePortfolioView } from "./SmartVoicePortfolioView";
import {
  PrivateSmartVoiceTickerRail,
  type PrivateTickerSort,
} from "./PrivateSmartVoiceTickerRail";
import { SmartVoiceRepresentativeChart } from "./SmartVoiceRepresentativeChart";

type DirectionFilter = "all" | "bull" | "bear";
type ExperimentView = "calls" | "portfolio";

function compact(value: number) {
  return new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 }).format(value);
}

function percent(value: number | null, digits = 1) {
  if (value == null) return "—";
  return `${value >= 0 ? "+" : ""}${value.toFixed(digits)}%`;
}

function confidenceLabel(value: string, zh: boolean) {
  if (value === "high") return zh ? "高置信" : "High";
  if (value === "medium") return zh ? "中置信" : "Medium";
  return zh ? "低置信" : "Low";
}

function sortedTickers(
  tickers: PrivateSmartVoiceTicker[],
  query: string,
  sort: PrivateTickerSort,
) {
  const normalized = query.trim().toLowerCase();
  return tickers
    .filter((item) => {
      if (!normalized) return true;
      return [item.ticker, item.companyName, item.sector].some((value) =>
        value.toLowerCase().includes(normalized),
      );
    })
    .sort((a, b) => {
      if (sort === "excess") {
        return b.meanDirectionalSpyExcessPct - a.meanDirectionalSpyExcessPct;
      }
      if (sort === "hit") return b.hitRate - a.hitRate;
      return b.settledCalls - a.settledCalls;
    });
}

export function PrivateSmartVoiceExperiment({
  data,
}: {
  data: PrivateSmartVoiceExperimentData;
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const [selectedTicker, setSelectedTicker] = useState(data.tickers[0]?.ticker ?? "");
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<PrivateTickerSort>("calls");
  const [direction, setDirection] = useState<DirectionFilter>("all");
  const [view, setView] = useState<ExperimentView>("calls");
  const tickers = useMemo(
    () => sortedTickers(data.tickers, query, sort),
    [data.tickers, query, sort],
  );
  const selected =
    data.tickers.find((item) => item.ticker === selectedTicker)
    ?? tickers[0]
    ?? data.tickers[0];
  const calls = useMemo(
    () => selected?.calls.filter((call) => direction === "all" || call.direction === direction) ?? [],
    [direction, selected],
  );
  const showcase: SmartVoiceRepresentativeShowcase | null = selected && calls.length
    ? {
        ticker: selected.ticker,
        kind: selected.focusContribution >= 0 ? "best" : "weak",
        focusContribution: calls.reduce((sum, call) => sum + call.contribution, 0),
        focusCallCount: calls.length,
        calls,
      }
    : null;
  const hitRate = data.performance.spyExcessHitRate;

  return (
    <ViewportWorkspace className="flex min-h-0 flex-col" bottomOffset={16}>
      <header className="shrink-0 border-b border-line pb-3">
        <div className="flex flex-col justify-between gap-4 xl:flex-row xl:items-end">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <span className="rounded-sm bg-reddit/10 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-[0.1em] text-reddit ring-1 ring-inset ring-reddit/25">
                {zh ? "实验" : "Experiment"}
              </span>
              <span className="text-[10px] uppercase tracking-[0.13em] text-neutral-600">
                Private Smart Voice
              </span>
            </div>
            <div className="mt-2 flex items-center gap-3">
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-md bg-[#229ED9]/15 font-mono text-[12px] font-bold text-[#55B7E7] ring-1 ring-inset ring-[#229ED9]/30">
                TG
              </span>
              <div className="min-w-0">
                <h1 className="truncate font-display text-[22px] font-extrabold leading-tight text-cream">
                  {data.channel.title}
                </h1>
                <div className="mt-0.5 flex items-center gap-2 text-[10.5px] text-neutral-500">
                  <span>@{data.channel.handle}</span>
                  <span>·</span>
                  <span>{compact(data.channel.subscriberCount)} {zh ? "订阅者" : "subscribers"}</span>
                  <a
                    href={data.channel.publicUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-semibold text-reddit hover:text-cream"
                  >
                    {zh ? "公开频道 ↗" : "Public channel ↗"}
                  </a>
                </div>
              </div>
            </div>
          </div>

          <dl className="grid grid-cols-3 divide-x divide-line sm:grid-cols-6">
            {[
              [zh ? "Private SE/SV" : "Private SE/SV", String(data.score.sv), "text-reddit"],
              [zh ? "参考位置" : "Reference rank", zh ? `前 ${data.score.referencePercentile.toFixed(1)}%` : `Top ${data.score.referencePercentile.toFixed(1)}%`, "text-cream"],
              [zh ? "有效喊单" : "Settled calls", String(data.score.settledCalls), "text-cream"],
              [zh ? "方向命中" : "Directional hit", hitRate == null ? "—" : `${(hitRate * 100).toFixed(1)}%`, "text-cream"],
              [zh ? "平均超额" : "Mean excess", percent(data.performance.meanDirectionalSpyExcessPct), data.performance.meanDirectionalSpyExcessPct != null && data.performance.meanDirectionalSpyExcessPct >= 0 ? "text-bull" : "text-bear"],
              [zh ? "置信度" : "Confidence", confidenceLabel(data.score.confidence, zh), "text-neutral-300"],
            ].map(([label, value, tone]) => (
              <div key={label} className="min-w-[92px] px-3 py-1 first:pl-0 last:pr-0">
                <dt className="text-[8.5px] uppercase tracking-[0.08em] text-neutral-600">{label}</dt>
                <dd className={`mt-1 font-mono text-[13px] font-bold leading-none ${tone}`}>{value}</dd>
              </div>
            ))}
          </dl>
        </div>
      </header>

      <nav className="flex h-11 shrink-0 items-end gap-1 border-b border-line">
        {([
          ["calls", zh ? "观点证据" : "Call evidence", data.score.settledCalls],
          ["portfolio", zh ? "组合回测" : "Portfolio backtest", data.portfolioBacktest.base.tradeCount],
        ] as [ExperimentView, string, number][]).map(([key, label, count]) => (
          <button
            key={key}
            type="button"
            onClick={() => setView(key)}
            className={`relative flex h-10 items-center gap-2 px-4 text-[11.5px] font-semibold transition ${
              view === key ? "text-cream" : "text-neutral-600 hover:text-cream"
            }`}
          >
            <span>{label}</span>
            <span className={`font-mono text-[9px] ${view === key ? "text-reddit" : "text-neutral-700"}`}>{count}</span>
            {view === key ? <span className="absolute inset-x-3 bottom-0 h-0.5 bg-reddit" /> : null}
          </button>
        ))}
        <div className="ml-auto hidden pb-2.5 text-[9.5px] text-neutral-600 sm:block">
          {view === "calls"
            ? (zh ? "原帖可追溯 · 复权收盘价" : "Source-linked · adjusted close")
            : (zh ? "等权跟随 · SPY 对照" : "Equal-weight follow · SPY benchmark")}
        </div>
      </nav>

      <main className={`mt-3 min-h-0 flex-1 overflow-hidden rounded-lg bg-card/55 ring-1 ring-inset ring-line ${
        view === "calls"
          ? "grid grid-rows-[360px_minmax(0,1fr)] lg:grid-cols-[270px_minmax(0,1fr)] lg:grid-rows-[minmax(0,1fr)]"
          : "block"
      }`}>
        {view === "portfolio" ? (
          <SmartVoicePortfolioView
            backtest={data.portfolioBacktest}
            zh={zh}
          />
        ) : (
          <>
            <PrivateSmartVoiceTickerRail
          tickers={tickers}
          selectedTicker={selected?.ticker ?? ""}
          query={query}
          sort={sort}
          onQueryChange={setQuery}
          onSortChange={setSort}
          onSelect={(ticker) => {
            setSelectedTicker(ticker);
            setDirection("all");
          }}
          zh={zh}
        />

            {selected ? (
              <section className="flex min-h-0 min-w-0 flex-col">
            <header className="flex shrink-0 flex-wrap items-center gap-3 border-b border-line px-4 py-3">
              <TickerLogo ticker={selected.ticker} size={36} />
              <div className="min-w-0">
                <div className="flex items-baseline gap-2">
                  <h2 className="font-mono text-[16px] font-bold text-cream">{selected.ticker}</h2>
                  <span className="truncate text-[10.5px] text-neutral-600">
                    {selected.companyName || selected.sector}
                  </span>
                </div>
                <div className="mt-1 flex items-center gap-3 font-mono text-[9.5px] text-neutral-600">
                  <span>{selected.settledCalls} {zh ? "条已结算" : "settled"}</span>
                  <span>{zh ? "多 / 空" : "Bull / bear"} {selected.bullCalls} / {selected.bearCalls}</span>
                  <span>{zh ? "命中" : "Hit"} {(selected.hitRate * 100).toFixed(1)}%</span>
                </div>
              </div>
              <div className="ml-auto flex h-8 items-center rounded-md bg-white/[.025] p-0.5 ring-1 ring-inset ring-line">
                {([
                  ["all", zh ? "全部" : "All"],
                  ["bull", zh ? "看多" : "Bull"],
                  ["bear", zh ? "看空" : "Bear"],
                ] as [DirectionFilter, string][]).map(([key, label]) => (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setDirection(key)}
                    className={`flex h-7 items-center gap-1.5 rounded-sm px-2.5 text-[10.5px] font-semibold transition ${
                      direction === key
                        ? "bg-reddit/10 text-cream ring-1 ring-inset ring-reddit/25"
                        : "text-neutral-600 hover:text-cream"
                    }`}
                  >
                    {key !== "all" ? (
                      <span className={`h-1.5 w-1.5 rounded-full ${key === "bull" ? "bg-bull" : "bg-bear"}`} />
                    ) : null}
                    {label}
                  </button>
                ))}
              </div>
            </header>

            <div className="min-h-0 flex-1 overflow-y-auto">
              <div className="px-4 py-3">
                {showcase ? (
                  <SmartVoiceRepresentativeChart
                    showcase={showcase}
                    prices={selected.prices}
                    zh={zh}
                    height={360}
                  />
                ) : (
                  <div className="grid h-[360px] place-items-center text-[11px] text-neutral-600">
                    {zh ? "该方向暂无可视化观点" : "No calls for this direction"}
                  </div>
                )}
              </div>
              <div className="grid border-t border-line md:grid-cols-4">
                {[
                  [zh ? "消息历史" : "Message history", `${data.channel.firstMessageAt.slice(0, 10)} → ${data.channel.lastMessageAt.slice(0, 10)}`],
                  [zh ? "抓取消息" : "Messages crawled", data.dataQuality.messages.toLocaleString()],
                  [zh ? "候选组合" : "Ticker candidates", data.dataQuality.candidateTickerPairs.toLocaleString()],
                  [zh ? "公开参考池" : "Public reference", `${data.score.referencePopulation} ${zh ? "位作者" : "authors"}`],
                ].map(([label, value]) => (
                  <div key={label} className="border-b border-line/75 px-4 py-3 md:border-b-0 md:border-r last:border-r-0">
                    <div className="text-[9px] uppercase tracking-[0.08em] text-neutral-600">{label}</div>
                    <div className="mt-1 font-mono text-[11px] font-semibold text-neutral-300">{value}</div>
                  </div>
                ))}
              </div>
              <PrivateSmartVoiceCallTable calls={calls} zh={zh} />
            </div>
              </section>
            ) : (
              <div className="grid min-h-[420px] place-items-center text-[11px] text-neutral-600">
                {zh ? "暂无可视化数据" : "No experiment data available"}
              </div>
            )}
          </>
        )}
      </main>
    </ViewportWorkspace>
  );
}
