"use client";

import { useEffect, useMemo, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { fmtCompact } from "@/shared/formatting/format";
import type { SmartVoiceEvidenceCall, SmartVoiceInvestorEvidence } from "@/server/queries/smartVoiceInvestorQueries";

type ImpactFilter = "all" | "positive" | "negative";
type ResultFilter = "all" | "hit" | "miss";
type SortMode = "newest" | "impact";

const PAGE_SIZE = 25;

function pct(value: number | null | undefined) {
  if (typeof value !== "number" || Number.isNaN(value)) return "—";
  return `${value >= 0 ? "+" : ""}${(value * 100).toFixed(1)}%`;
}

function contribution(call: SmartVoiceEvidenceCall) {
  const value = call.contribution ?? 0;
  return `${value >= 0 ? "+" : ""}${value.toFixed(2)}`;
}

function directionalExcess(call: SmartVoiceEvidenceCall) {
  if (call.excessReturnPct == null) return null;
  return call.direction === "bear" ? -call.excessReturnPct : call.excessReturnPct;
}

function sourceLabel(source: string) {
  if (source === "youtube") return "YT";
  if (source === "reddit") return "Reddit";
  if (source === "xueqiu") return "雪球";
  if (source === "toss") return "Toss";
  return "X";
}

function directionLabel(direction: SmartVoiceEvidenceCall["direction"], zh: boolean) {
  if (direction === "bull") return zh ? "看多" : "Bull";
  if (direction === "bear") return zh ? "看空" : "Bear";
  return zh ? "中性" : "Neutral";
}

function summaryOf(call: SmartVoiceEvidenceCall, zh: boolean) {
  return (zh ? call.summaryZh : call.summaryEn) || call.evidenceSpan || call.text || "—";
}

function Stat({ label, value, detail, tone = "text-cream" }: { label: string; value: string; detail?: string; tone?: string }) {
  return (
    <div className="min-w-0 border-r border-line/70 px-3 py-1 last:border-r-0 first:pl-0">
      <div className="text-[9.5px] uppercase tracking-wide text-neutral-600">{label}</div>
      <div className={`mt-1 font-mono text-[17px] font-bold leading-none tabular ${tone}`}>{value}</div>
      {detail && <div className="mt-1 truncate text-[9.5px] text-neutral-700">{detail}</div>}
    </div>
  );
}

export function SmartVoicePerformanceLedger({ evidence, zh }: { evidence: SmartVoiceInvestorEvidence; zh: boolean }) {
  const calls = evidence.allCalls;
  const stats = evidence.performance;
  const [impact, setImpact] = useState<ImpactFilter>("all");
  const [result, setResult] = useState<ResultFilter>("all");
  const [ticker, setTicker] = useState("all");
  const [horizon, setHorizon] = useState("all");
  const [sort, setSort] = useState<SortMode>("newest");
  const [page, setPage] = useState(1);

  const tickers = useMemo(() => {
    const counts = new Map<string, number>();
    for (const call of calls) counts.set(call.ticker, (counts.get(call.ticker) ?? 0) + 1);
    return [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  }, [calls]);
  const horizons = useMemo(() => [...new Set(calls.map((call) => call.horizon).filter(Boolean))].sort((a, b) => Number.parseInt(a) - Number.parseInt(b)), [calls]);
  const filtered = useMemo(() => {
    const scoped = calls.filter((call) => {
      if (impact === "positive" && (call.contribution ?? 0) <= 0) return false;
      if (impact === "negative" && (call.contribution ?? 0) >= 0) return false;
      if (result === "hit" && call.actualHit !== 1) return false;
      if (result === "miss" && call.actualHit !== 0) return false;
      if (ticker !== "all" && call.ticker !== ticker) return false;
      if (horizon !== "all" && call.horizon !== horizon) return false;
      return true;
    });
    return scoped.sort((a, b) => sort === "impact"
      ? Math.abs(b.contribution ?? 0) - Math.abs(a.contribution ?? 0) || b.day.localeCompare(a.day)
      : b.day.localeCompare(a.day) || Math.abs(b.contribution ?? 0) - Math.abs(a.contribution ?? 0));
  }, [calls, horizon, impact, result, sort, ticker]);

  useEffect(() => setPage(1), [horizon, impact, result, sort, ticker]);
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);
  const rows = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const firstRow = filtered.length ? (safePage - 1) * PAGE_SIZE + 1 : 0;
  const lastRow = Math.min(safePage * PAGE_SIZE, filtered.length);

  if (!calls.length) {
    return <div className="py-8 text-center text-[12px] text-neutral-500">{zh ? "暂无已结算战绩。" : "No settled performance record."}</div>;
  }

  return (
    <div>
      <div className="grid grid-cols-2 gap-y-3 border-b border-line/70 pb-4 sm:grid-cols-3 xl:grid-cols-6">
        <Stat label={zh ? "已结算" : "Settled"} value={fmtCompact(stats.settledCalls)} detail={stats.firstDay && stats.lastDay ? `${stats.firstDay} → ${stats.lastDay}` : undefined} />
        <Stat label={zh ? "可判定命中率" : "Graded hit rate"} value={stats.hitRate == null ? "—" : `${(stats.hitRate * 100).toFixed(1)}%`} detail={`${fmtCompact(stats.gradedCalls)} ${zh ? "条可判定" : "graded"}`} tone={stats.hitRate != null && stats.hitRate >= 0.5 ? "text-bull" : "text-bear"} />
        <Stat label={zh ? "方向超额中位" : "Median dir. excess"} value={pct(stats.medianDirectionalExcess)} tone={(stats.medianDirectionalExcess ?? 0) >= 0 ? "text-bull" : "text-bear"} />
        <Stat label={zh ? "净 SV 贡献" : "Net SV contribution"} value={`${stats.netContribution >= 0 ? "+" : ""}${stats.netContribution.toFixed(2)}`} tone={stats.netContribution >= 0 ? "text-bull" : "text-bear"} />
        <Stat label={zh ? "加分 / 扣分" : "Positive / negative"} value={`${fmtCompact(stats.positiveCalls)} / ${fmtCompact(stats.negativeCalls)}`} />
        <Stat label={zh ? "覆盖标的" : "Tickers covered"} value={fmtCompact(stats.coveredTickers)} />
      </div>

      <div className="flex flex-wrap items-center gap-2 border-b border-line/70 py-3">
        <div className="flex h-8 items-center rounded-md p-0.5 ring-1 ring-inset ring-line">
          {(["all", "positive", "negative"] as ImpactFilter[]).map((value) => (
            <button
              key={value}
              type="button"
              onClick={() => setImpact(value)}
              className={`h-7 min-w-[62px] rounded px-2 text-[10.5px] font-semibold transition ${impact === value ? "bg-reddit/12 text-reddit" : "text-neutral-600 hover:text-neutral-300"}`}
            >
              {value === "all" ? (zh ? "全部" : "All") : value === "positive" ? (zh ? "加分" : "Positive") : (zh ? "扣分" : "Negative")}
            </button>
          ))}
        </div>
        <select value={ticker} onChange={(event) => setTicker(event.target.value)} className="h-8 min-w-[132px] rounded-md bg-card px-2 text-[10.5px] text-neutral-300 outline-none ring-1 ring-inset ring-line focus:ring-reddit/60" aria-label={zh ? "筛选标的" : "Filter ticker"}>
          <option value="all">{zh ? `全部标的 (${tickers.length})` : `All tickers (${tickers.length})`}</option>
          {tickers.map(([symbol, count]) => <option key={symbol} value={symbol}>{symbol} · {count}</option>)}
        </select>
        <select value={horizon} onChange={(event) => setHorizon(event.target.value)} className="h-8 min-w-[104px] rounded-md bg-card px-2 text-[10.5px] text-neutral-300 outline-none ring-1 ring-inset ring-line focus:ring-reddit/60" aria-label={zh ? "筛选周期" : "Filter horizon"}>
          <option value="all">{zh ? "全部周期" : "All horizons"}</option>
          {horizons.map((value) => <option key={value} value={value}>{value}</option>)}
        </select>
        <select value={result} onChange={(event) => setResult(event.target.value as ResultFilter)} className="h-8 min-w-[104px] rounded-md bg-card px-2 text-[10.5px] text-neutral-300 outline-none ring-1 ring-inset ring-line focus:ring-reddit/60" aria-label={zh ? "筛选结果" : "Filter result"}>
          <option value="all">{zh ? "全部结果" : "All results"}</option>
          <option value="hit">{zh ? "命中" : "Hit"}</option>
          <option value="miss">{zh ? "未命中" : "Miss"}</option>
        </select>
        <div className="ml-auto flex h-8 items-center rounded-md p-0.5 ring-1 ring-inset ring-line">
          {(["newest", "impact"] as SortMode[]).map((value) => (
            <button key={value} type="button" onClick={() => setSort(value)} className={`h-7 rounded px-2.5 text-[10.5px] transition ${sort === value ? "bg-white/[.07] text-cream" : "text-neutral-600 hover:text-neutral-300"}`}>
              {value === "newest" ? (zh ? "最新" : "Newest") : (zh ? "贡献" : "Impact")}
            </button>
          ))}
        </div>
      </div>

      <div className="overflow-x-auto">
        <div className="min-w-[980px]">
          <div className="grid grid-cols-[76px_62px_58px_54px_66px_78px_60px_minmax(260px,1fr)_36px] gap-2 border-b border-line/70 px-2 py-2 text-[9.5px] font-semibold uppercase tracking-wide text-neutral-700">
            <span>{zh ? "日期" : "Date"}</span><span>{zh ? "标的" : "Ticker"}</span><span>{zh ? "方向" : "Side"}</span><span>{zh ? "周期" : "Term"}</span><span className="text-right">{zh ? "贡献" : "Impact"}</span><span className="text-right">{zh ? "方向超额" : "Dir. excess"}</span><span className="text-center">{zh ? "结果" : "Result"}</span><span>{zh ? "观点" : "Call"}</span><span />
          </div>
          {rows.map((call) => {
            const adds = (call.contribution ?? 0) >= 0;
            const excess = directionalExcess(call);
            return (
              <div key={`${call.candidateId}:${call.horizon}`} className="grid min-h-[43px] grid-cols-[76px_62px_58px_54px_66px_78px_60px_minmax(260px,1fr)_36px] items-center gap-2 border-b border-line/50 px-2 text-[10.5px] transition hover:bg-white/[.018]">
                <span className="font-mono text-neutral-600">{call.day}</span>
                <LocaleLink href={`/tickers/${call.ticker}`} className="font-mono font-bold text-neutral-300 hover:text-reddit">{call.ticker}</LocaleLink>
                <span className={call.direction === "bull" ? "text-bull" : call.direction === "bear" ? "text-bear" : "text-neutral-500"}>{directionLabel(call.direction, zh)}</span>
                <span className="font-mono text-neutral-500">{call.horizon}</span>
                <span className={`text-right font-mono font-bold ${adds ? "text-bull" : "text-bear"}`}>{contribution(call)}</span>
                <span className={`text-right font-mono ${excess == null ? "text-neutral-700" : excess >= 0 ? "text-bull" : "text-bear"}`}>{pct(excess)}</span>
                <span className={`text-center ${call.actualHit === 1 ? "text-bull" : call.actualHit === 0 ? "text-bear" : "text-neutral-700"}`}>{call.actualHit === 1 ? (zh ? "命中" : "Hit") : call.actualHit === 0 ? (zh ? "未中" : "Miss") : "—"}</span>
                <span className="truncate text-neutral-400" title={summaryOf(call, zh)}>{summaryOf(call, zh)}</span>
                {call.url ? <a href={call.url} target="_blank" rel="noopener noreferrer" title={zh ? "查看原观点" : "Open source"} className="grid h-7 w-7 place-items-center rounded text-neutral-600 transition hover:bg-white/[.05] hover:text-reddit">↗</a> : <span />}
              </div>
            );
          })}
        </div>
      </div>

      <div className="flex items-center justify-between pt-3 text-[10.5px] text-neutral-600">
        <span>{firstRow}–{lastRow} / {fmtCompact(filtered.length)}</span>
        <div className="flex items-center gap-2">
          <button type="button" onClick={() => setPage((value) => Math.max(1, value - 1))} disabled={safePage <= 1} title={zh ? "上一页" : "Previous page"} className="grid h-7 w-7 place-items-center rounded ring-1 ring-inset ring-line transition hover:text-cream disabled:cursor-not-allowed disabled:opacity-30">←</button>
          <span className="min-w-[72px] text-center font-mono">{safePage} / {totalPages}</span>
          <button type="button" onClick={() => setPage((value) => Math.min(totalPages, value + 1))} disabled={safePage >= totalPages} title={zh ? "下一页" : "Next page"} className="grid h-7 w-7 place-items-center rounded ring-1 ring-inset ring-line transition hover:text-cream disabled:cursor-not-allowed disabled:opacity-30">→</button>
        </div>
      </div>
    </div>
  );
}
