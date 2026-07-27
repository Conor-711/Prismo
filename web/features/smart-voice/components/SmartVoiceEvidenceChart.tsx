"use client";

import { useEffect, useMemo, useState } from "react";
import ReactECharts from "echarts-for-react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { fmtCompact } from "@/shared/formatting/format";
import type { SmartVoiceEvidenceCall, SmartVoiceEvidencePriceBar, SmartVoiceInvestorEvidence } from "@/server/queries/smartVoiceInvestorQueries";
import { EvidencePill } from "./SmartVoicePrimitives";

const POSITIVE = "#57D7BA";
const NEGATIVE = "#FF5C6C";
const CREAM = "#F2F0E7";
const MUTED = "#707780";

function pct(value: number | null | undefined) {
  if (typeof value !== "number" || Number.isNaN(value)) return "—";
  return `${value >= 0 ? "+" : ""}${(value * 100).toFixed(1)}%`;
}

function money(value: number | null | undefined) {
  if (typeof value !== "number" || Number.isNaN(value)) return "—";
  return `$${value.toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
}

function directionLabel(direction: SmartVoiceEvidenceCall["direction"], zh: boolean) {
  if (direction === "bull") return zh ? "看多" : "Bull";
  if (direction === "bear") return zh ? "看空" : "Bear";
  return zh ? "中性" : "Neutral";
}

function movingAverage(prices: SmartVoiceEvidencePriceBar[], window: number) {
  return prices.map((_, index) => {
    if (index < window - 1) return null;
    const slice = prices.slice(index - window + 1, index + 1);
    return Number((slice.reduce((sum, item) => sum + item.close, 0) / window).toFixed(3));
  });
}

function nearestTradingDay(call: SmartVoiceEvidenceCall, prices: SmartVoiceEvidencePriceBar[]) {
  const target = call.entryDay || call.day;
  return prices.find((price) => price.day === target)?.day
    ?? prices.find((price) => price.day >= target)?.day
    ?? prices.at(-1)?.day
    ?? target;
}

function evidenceKey(call: SmartVoiceEvidenceCall) {
  return `${call.candidateId}:${call.horizon}`;
}

function EvidenceChart({
  ticker,
  prices,
  calls,
  selectedKey,
  onSelect,
  zh,
}: {
  ticker: string;
  prices: SmartVoiceEvidencePriceBar[];
  calls: SmartVoiceEvidenceCall[];
  selectedKey: string;
  onSelect: (call: SmartVoiceEvidenceCall) => void;
  zh: boolean;
}) {
  const option = useMemo(() => {
    const priceByDay = new Map(prices.map((price) => [price.day, price]));
    const stacks = new Map<string, number>();
    const marker = (call: SmartVoiceEvidenceCall) => {
      const day = nearestTradingDay(call, prices);
      const price = priceByDay.get(day);
      const positive = (call.contribution ?? 0) >= 0;
      const stackKey = `${day}:${positive ? "positive" : "negative"}`;
      const stack = stacks.get(stackKey) ?? 0;
      stacks.set(stackKey, stack + 1);
      const anchor = positive ? price?.high ?? call.entryPrice ?? 0 : price?.low ?? call.entryPrice ?? 0;
      const offset = 0.035 + stack * 0.045;
      return {
        value: [day, positive ? anchor * (1 + offset) : anchor * (1 - offset)],
        call,
        symbolSize: Math.min(23, 14 + Math.abs(call.contribution ?? 0) * 16),
        itemStyle: {
          color: positive ? POSITIVE : NEGATIVE,
          borderColor: evidenceKey(call) === selectedKey ? CREAM : "#121416",
          borderWidth: evidenceKey(call) === selectedKey ? 2.5 : 1.5,
          shadowBlur: evidenceKey(call) === selectedKey ? 8 : 0,
          shadowColor: positive ? POSITIVE : NEGATIVE,
        },
        label: {
          show: true,
          formatter: positive ? "+" : "−",
          color: "#111315",
          fontSize: 11,
          fontWeight: 900,
        },
      };
    };
    const positiveCalls = calls.filter((call) => (call.contribution ?? 0) >= 0).map(marker);
    const negativeCalls = calls.filter((call) => (call.contribution ?? 0) < 0).map(marker);

    return {
      animation: false,
      backgroundColor: "transparent",
      grid: [
        { left: 12, right: 58, top: 24, height: "67%", containLabel: true },
        { left: 12, right: 58, top: "78%", height: "11%", containLabel: true },
      ],
      axisPointer: { link: [{ xAxisIndex: [0, 1] }], label: { backgroundColor: "#30353B" } },
      tooltip: {
        trigger: "axis",
        axisPointer: { type: "cross", crossStyle: { color: "#59616B" } },
        backgroundColor: "#202328",
        borderColor: "#3A4149",
        padding: 10,
        textStyle: { color: CREAM, fontSize: 11 },
        formatter: (raw: any) => {
          const params = Array.isArray(raw) ? raw : [raw];
          const evidence = params.filter((item: any) => item.data?.call);
          const candle = params.find((item: any) => item.seriesType === "candlestick");
          const lines: string[] = [];
          const day = evidence[0]?.axisValue ?? candle?.axisValue ?? "";
          if (day) lines.push(`<b>${ticker} · ${day}</b>`);
          if (candle?.data) {
            const value = candle.data as number[];
            lines.push(`O ${money(value[0])} · H ${money(value[3])} · L ${money(value[2])} · C ${money(value[1])}`);
          }
          for (const item of evidence) {
            const call = item.data.call as SmartVoiceEvidenceCall;
            const positive = (call.contribution ?? 0) >= 0;
            lines.push(
              `<span style="color:${positive ? POSITIVE : NEGATIVE}"><b>${positive ? "+" : "−"} ${zh ? "SV 贡献" : "SV contribution"} ${Math.abs(call.contribution ?? 0).toFixed(2)}</b></span> · ${directionLabel(call.direction, zh)} · ${call.horizon}`,
            );
          }
          return lines.join("<br/>");
        },
      },
      xAxis: [
        {
          type: "category",
          data: prices.map((price) => price.day),
          boundaryGap: true,
          axisTick: { show: false },
          axisLine: { lineStyle: { color: "#343A42" } },
          axisLabel: { show: false },
          splitLine: { show: false },
        },
        {
          type: "category",
          gridIndex: 1,
          data: prices.map((price) => price.day),
          boundaryGap: true,
          axisTick: { show: false },
          axisLine: { lineStyle: { color: "#343A42" } },
          axisLabel: {
            color: MUTED,
            fontSize: 9,
            hideOverlap: true,
            formatter: (value: string) => value.slice(5).replace("-", "/"),
          },
        },
      ],
      yAxis: [
        {
          type: "value",
          scale: true,
          position: "right",
          axisLabel: { color: MUTED, fontSize: 9, formatter: (value: number) => `$${value.toLocaleString()}` },
          splitLine: { lineStyle: { color: "rgba(112,119,128,.12)" } },
        },
        {
          type: "value",
          gridIndex: 1,
          scale: true,
          position: "right",
          axisLabel: { show: false },
          splitLine: { show: false },
        },
      ],
      dataZoom: [{ type: "slider", xAxisIndex: [0, 1], height: 14, bottom: 2, borderColor: "#343A42", fillerColor: "rgba(87,215,186,.10)", handleStyle: { color: POSITIVE }, textStyle: { color: MUTED, fontSize: 9 } }],
      series: [
        {
          name: zh ? "日 K" : "Daily candle",
          type: "candlestick",
          data: prices.map((price) => [price.open, price.close, price.low, price.high]),
          itemStyle: {
            color: POSITIVE,
            color0: NEGATIVE,
            borderColor: POSITIVE,
            borderColor0: NEGATIVE,
          },
          z: 2,
        },
        {
          name: "MA10",
          type: "line",
          data: movingAverage(prices, 10),
          symbol: "none",
          smooth: 0.15,
          lineStyle: { color: "#F2B84B", width: 1, opacity: 0.72 },
          z: 3,
        },
        {
          name: zh ? "加分观点" : "Positive evidence",
          type: "scatter",
          data: positiveCalls,
          symbol: "circle",
          z: 8,
        },
        {
          name: zh ? "扣分观点" : "Negative evidence",
          type: "scatter",
          data: negativeCalls,
          symbol: "circle",
          z: 8,
        },
        {
          name: zh ? "成交量" : "Volume",
          type: "bar",
          xAxisIndex: 1,
          yAxisIndex: 1,
          data: prices.map((price) => ({
            value: price.volume,
            itemStyle: { color: price.close >= price.open ? "rgba(87,215,186,.34)" : "rgba(255,92,108,.34)" },
          })),
          barMaxWidth: 8,
          z: 1,
        },
      ],
    };
  }, [calls, prices, selectedKey, ticker, zh]);

  if (!prices.length) {
    return <div className="grid h-[340px] place-items-center text-[12px] text-neutral-600">{zh ? "该标的暂无可用日 K 数据" : "No daily OHLC data for this ticker"}</div>;
  }

  return (
    <ReactECharts
      option={option}
      style={{ height: 390, width: "100%" }}
      opts={{ renderer: "canvas" }}
      onEvents={{
        click: (params: any) => {
          const call = params?.data?.call as SmartVoiceEvidenceCall | undefined;
          if (call) onSelect(call);
        },
      }}
      notMerge
    />
  );
}

export function SmartVoiceEvidenceChart({ evidence, zh }: { evidence: SmartVoiceInvestorEvidence; zh: boolean }) {
  const allCalls = useMemo(() => {
    const calls = new Map<string, SmartVoiceEvidenceCall>();
    for (const call of [...evidence.bestCalls, ...evidence.weakCalls]) calls.set(evidenceKey(call), call);
    return [...calls.values()];
  }, [evidence.bestCalls, evidence.weakCalls]);
  const tickers = useMemo(() => {
    const grouped = new Map<string, SmartVoiceEvidenceCall[]>();
    for (const call of allCalls) {
      const tickerCalls = grouped.get(call.ticker);
      if (tickerCalls) tickerCalls.push(call);
      else grouped.set(call.ticker, [call]);
    }
    return [...grouped.entries()]
      .map(([ticker, calls]) => ({
        ticker,
        calls,
        contribution: calls.reduce((sum, call) => sum + (call.contribution ?? 0), 0),
        magnitude: calls.reduce((sum, call) => sum + Math.abs(call.contribution ?? 0), 0),
      }))
      .sort((a, b) => b.magnitude - a.magnitude || b.calls.length - a.calls.length || a.ticker.localeCompare(b.ticker));
  }, [allCalls]);
  const [ticker, setTicker] = useState(tickers[0]?.ticker ?? "");
  const active = tickers.find((item) => item.ticker === ticker) ?? tickers[0];
  const [selectedKey, setSelectedKey] = useState(() => active?.calls[0] ? evidenceKey(active.calls[0]) : "");

  useEffect(() => {
    if (!tickers.some((item) => item.ticker === ticker)) setTicker(tickers[0]?.ticker ?? "");
  }, [ticker, tickers]);
  useEffect(() => {
    if (!active?.calls.some((call) => evidenceKey(call) === selectedKey)) {
      const strongest = [...(active?.calls ?? [])].sort((a, b) => Math.abs(b.contribution ?? 0) - Math.abs(a.contribution ?? 0))[0];
      setSelectedKey(strongest ? evidenceKey(strongest) : "");
    }
  }, [active, selectedKey]);

  if (!active) {
    return <div className="rounded-lg bg-card p-5 text-[12px] text-neutral-500 ring-1 ring-inset ring-line">{zh ? "暂无可展示的已结算样本。" : "No settled examples to show yet."}</div>;
  }

  const selected = active.calls.find((call) => evidenceKey(call) === selectedKey) ?? active.calls[0];
  const summary = (zh ? selected.summaryZh : selected.summaryEn) || selected.evidenceSpan || selected.text;
  const positive = (selected.contribution ?? 0) >= 0;

  return (
    <div>
      <div className="flex items-center justify-between gap-4 border-b border-line/70 pb-3">
        <div className="min-w-0 overflow-x-auto">
          <div className="flex min-w-max gap-1.5">
            {tickers.map((item) => {
              const on = item.ticker === active.ticker;
              const up = item.contribution >= 0;
              return (
                <button
                  key={item.ticker}
                  type="button"
                  onClick={() => setTicker(item.ticker)}
                  aria-pressed={on}
                  className={`flex h-9 items-center gap-2 rounded-md px-3 text-[11.5px] font-semibold ring-1 ring-inset transition ${on ? "bg-reddit/10 text-cream ring-reddit/55" : "text-neutral-500 ring-line hover:text-neutral-300"}`}
                >
                  <span className="font-mono">{item.ticker}</span>
                  <span className={up ? "text-bull" : "text-bear"}>{up ? "+" : "−"}{Math.abs(item.contribution).toFixed(2)}</span>
                  <span className="text-neutral-700">{item.calls.length}</span>
                </button>
              );
            })}
          </div>
        </div>
        <div className="hidden shrink-0 items-center gap-3 text-[10.5px] sm:flex">
          <span className="flex items-center gap-1.5 text-neutral-500"><i className="grid h-4 w-4 place-items-center rounded-full bg-bull not-italic font-black text-[#111315]">+</i>{zh ? "加分" : "Positive"}</span>
          <span className="flex items-center gap-1.5 text-neutral-500"><i className="grid h-4 w-4 place-items-center rounded-full bg-bear not-italic font-black text-[#111315]">−</i>{zh ? "扣分" : "Negative"}</span>
        </div>
      </div>

      <EvidenceChart
        ticker={active.ticker}
        prices={evidence.priceByTicker[active.ticker] ?? []}
        calls={active.calls}
        selectedKey={selectedKey}
        onSelect={(call) => setSelectedKey(evidenceKey(call))}
        zh={zh}
      />

      <div className="border-t border-line/70 pt-3">
        <div className="mb-3 flex gap-1.5 overflow-x-auto pb-1">
          {[...active.calls].sort((a, b) => b.day.localeCompare(a.day)).map((call) => {
            const on = evidenceKey(call) === evidenceKey(selected);
            const adds = (call.contribution ?? 0) >= 0;
            return (
              <button
                key={evidenceKey(call)}
                type="button"
                onClick={() => setSelectedKey(evidenceKey(call))}
                className={`h-7 shrink-0 rounded px-2 font-mono text-[10px] ring-1 ring-inset transition ${on ? (adds ? "bg-bull/10 text-bull ring-bull/45" : "bg-bear/10 text-bear ring-bear/45") : "text-neutral-600 ring-line hover:text-neutral-300"}`}
              >
                {call.day.slice(5)} {adds ? "+" : "−"}{Math.abs(call.contribution ?? 0).toFixed(2)}
              </button>
            );
          })}
        </div>

        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-start">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <LocaleLink href={`/tickers/${selected.ticker}`} className="font-mono text-[13px] font-bold text-cream hover:text-reddit">{selected.ticker}</LocaleLink>
              <span className={`rounded px-1.5 py-px text-[10.5px] font-bold ${positive ? "bg-bull/10 text-bull" : "bg-bear/10 text-bear"}`}>
                {positive ? (zh ? "SV 加分" : "SV positive") : (zh ? "SV 扣分" : "SV negative")} {positive ? "+" : "−"}{Math.abs(selected.contribution ?? 0).toFixed(2)}
              </span>
              <span className="rounded bg-white/[.04] px-1.5 py-px text-[10.5px] text-neutral-400">{directionLabel(selected.direction, zh)} · {selected.horizon}</span>
              <span className="text-[10.5px] text-neutral-600">{selected.day}</span>
              {selected.url && <a href={selected.url} target="_blank" rel="noopener noreferrer" className="text-[10.5px] text-reddit hover:text-cream">{zh ? "查看原观点 ↗" : "Open source ↗"}</a>}
            </div>
            <p className="mt-2 max-w-5xl text-[12.5px] leading-relaxed text-neutral-300">{summary}</p>
          </div>
          <div className="flex flex-wrap gap-1.5 lg:max-w-[360px] lg:justify-end">
            <EvidencePill label={zh ? "入场" : "Entry"} value={`${selected.entryDay || selected.day} · ${money(selected.entryPrice)}`} />
            <EvidencePill label={zh ? "结算" : "Exit"} value={selected.exitDay ? `${selected.exitDay} · ${money(selected.exitPrice)}` : "—"} />
            <EvidencePill label={zh ? "收益" : "Return"} value={pct(selected.returnPct)} />
            <EvidencePill label={zh ? "超额" : "Excess"} value={pct(selected.excessReturnPct)} />
            <EvidencePill label={zh ? "互动" : "Interactions"} value={fmtCompact(selected.interactions)} />
            {selected.actualHit != null && <EvidencePill label={zh ? "命中" : "Hit"} value={selected.actualHit ? (zh ? "是" : "Yes") : (zh ? "否" : "No")} />}
          </div>
        </div>
      </div>
    </div>
  );
}
