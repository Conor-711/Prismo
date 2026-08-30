"use client";

import { useEffect, useMemo, useState } from "react";
import ReactECharts from "echarts-for-react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import type { SmartVoiceRepresentativeCall, SmartVoiceRepresentativePricePoint, SmartVoiceRepresentativeShowcase } from "@/server/queries/smartVoiceInvestorQueries";

const BULL = "#57D7BA";
const BEAR = "#FF5C6C";
const NEUTRAL = "#F2B84B";
const CREAM = "#F2F0E7";
const MUTED = "#707780";

function callKey(call: SmartVoiceRepresentativeCall) {
  return `${call.candidateId}:${call.horizon}`;
}

function signed(value: number, digits = 2) {
  return `${value >= 0 ? "+" : ""}${value.toFixed(digits)}`;
}

function pct(value: number | null | undefined) {
  if (typeof value !== "number" || Number.isNaN(value)) return null;
  return `${value >= 0 ? "+" : ""}${(value * 100).toFixed(1)}%`;
}

function directionLabel(direction: SmartVoiceRepresentativeCall["direction"], zh: boolean) {
  if (direction === "bull") return zh ? "看多" : "Bull";
  if (direction === "bear") return zh ? "看空" : "Bear";
  return zh ? "中性" : "Neutral";
}

function directionColor(direction: SmartVoiceRepresentativeCall["direction"]) {
  if (direction === "bull") return BULL;
  if (direction === "bear") return BEAR;
  return NEUTRAL;
}

function nearestTradingDay(call: SmartVoiceRepresentativeCall, prices: SmartVoiceRepresentativePricePoint[]) {
  const target = call.entryDay || call.day;
  return prices.find((price) => price[0] === target)?.[0]
    ?? prices.find((price) => price[0] >= target)?.[0]
    ?? prices.at(-1)?.[0]
    ?? target;
}

function directionalExcess(call: SmartVoiceRepresentativeCall) {
  if (call.excessReturnPct == null) return null;
  return call.direction === "bear" ? -call.excessReturnPct : call.excessReturnPct;
}

export function SmartVoiceRepresentativeChart({
  showcase,
  prices,
  zh,
  height = 260,
}: {
  showcase: SmartVoiceRepresentativeShowcase;
  prices: SmartVoiceRepresentativePricePoint[];
  zh: boolean;
  height?: number;
}) {
  const strongest = useMemo(
    () => [...showcase.calls].sort((a, b) => Math.abs(b.contribution) - Math.abs(a.contribution))[0],
    [showcase.calls],
  );
  const [selectedKey, setSelectedKey] = useState(strongest ? callKey(strongest) : "");

  useEffect(() => {
    setSelectedKey(strongest ? callKey(strongest) : "");
  }, [showcase.ticker, strongest]);

  const selected = showcase.calls.find((call) => callKey(call) === selectedKey) ?? strongest;
  const option = useMemo(() => {
    const priceByDay = new Map(prices.map((price) => [price[0], price]));
    const maxMagnitude = Math.max(0.01, ...showcase.calls.map((call) => Math.abs(call.contribution)));
    const stacks = new Map<string, number>();
    const markers = showcase.calls.map((call) => {
      const day = nearestTradingDay(call, prices);
      const price = priceByDay.get(day);
      const stackKey = `${day}:${call.direction}`;
      const stack = stacks.get(stackKey) ?? 0;
      stacks.set(stackKey, stack + 1);
      const offset = 0.03 + stack * 0.045;
      const anchor = call.direction === "bull"
        ? (price?.[1] ?? call.entryPrice ?? 0) * (1 - offset)
        : call.direction === "bear"
          ? (price?.[1] ?? call.entryPrice ?? 0) * (1 + offset)
          : price?.[1] ?? call.entryPrice ?? 0;
      const active = callKey(call) === selectedKey;
      return {
        value: [day, anchor],
        call,
        symbolSize: 13 + (Math.abs(call.contribution) / maxMagnitude) * 10,
        itemStyle: {
          color: directionColor(call.direction),
          borderColor: active ? CREAM : call.contribution >= 0 ? "rgba(242,240,231,.72)" : "#2A2F35",
          borderWidth: active ? 2.5 : 1.2,
          shadowBlur: active ? 8 : 0,
          shadowColor: directionColor(call.direction),
          opacity: call.contribution >= 0 ? 0.96 : 0.76,
        },
        label: {
          show: true,
          formatter: call.direction === "bull" ? "↑" : call.direction === "bear" ? "↓" : "·",
          color: "#111315",
          fontSize: 10,
          fontWeight: 900,
        },
      };
    });

    return {
      animation: false,
      backgroundColor: "transparent",
      grid: { left: 8, right: 52, top: 18, bottom: 34, containLabel: true },
      tooltip: {
        trigger: "axis",
        axisPointer: { type: "cross", crossStyle: { color: "#59616B" } },
        backgroundColor: "#202328",
        borderColor: "#3A4149",
        padding: 9,
        textStyle: { color: CREAM, fontSize: 10 },
        formatter: (raw: any) => {
          const params = Array.isArray(raw) ? raw : [raw];
          const priceLine = params.find((item: any) => item.seriesName === (zh ? "收盘价" : "Close"));
          const evidence = params.filter((item: any) => item.data?.call);
          const day = evidence[0]?.axisValue ?? priceLine?.axisValue ?? "";
          const lines = [`<b>${showcase.ticker} · ${day}</b>`];
          if (typeof priceLine?.data === "number") {
            lines.push(`${zh ? "收盘价" : "Close"} $${priceLine.data.toFixed(2)}`);
          }
          for (const item of evidence) {
            const call = item.data.call as SmartVoiceRepresentativeCall;
            lines.push(
              `<span style="color:${directionColor(call.direction)}"><b>${directionLabel(call.direction, zh)}</b></span> · ${call.horizon} · Score ${signed(call.contribution)}`,
            );
          }
          return lines.join("<br/>");
        },
      },
      xAxis: {
        type: "category",
        data: prices.map((price) => price[0]),
        boundaryGap: true,
        axisTick: { show: false },
        axisLine: { lineStyle: { color: "#343A42" } },
        axisLabel: {
          color: MUTED,
          fontSize: 9,
          hideOverlap: true,
          formatter: (value: string) => value.slice(5).replace("-", "/"),
        },
        splitLine: { show: false },
      },
      yAxis: {
        type: "value",
        scale: true,
        position: "right",
        axisLabel: { color: MUTED, fontSize: 9, formatter: (value: number) => `$${value.toLocaleString()}` },
        splitLine: { lineStyle: { color: "rgba(112,119,128,.12)" } },
      },
      dataZoom: [
        { type: "inside", start: 0, end: 100 },
        {
          type: "slider",
          height: 12,
          bottom: 2,
          borderColor: "#343A42",
          fillerColor: "rgba(87,215,186,.10)",
          handleStyle: { color: BULL },
          textStyle: { color: MUTED, fontSize: 8 },
        },
      ],
      series: [
        {
          name: zh ? "收盘价" : "Close",
          type: "line",
          data: prices.map((price) => price[1]),
          symbol: "none",
          smooth: 0.12,
          lineStyle: {
            color: "#C5CCD3",
            width: 1.8,
          },
          areaStyle: { color: "rgba(197,204,211,.045)" },
          z: 2,
        },
        {
          name: zh ? "作者观点" : "Author calls",
          type: "scatter",
          data: markers,
          symbol: "circle",
          z: 8,
        },
      ],
    };
  }, [prices, selectedKey, showcase.calls, showcase.ticker, zh]);

  if (!selected) return null;
  const summary = (zh ? selected.summaryZh : selected.summaryEn) || selected.summaryZh || selected.summaryEn;
  const performance = pct(directionalExcess(selected));

  return (
    <section className="border-t border-line pt-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-[10px] font-semibold uppercase tracking-[0.1em] text-neutral-500">
            {zh ? "价格走势代表作" : "Price showcase"}
          </h3>
          <div className="mt-1.5 flex items-center gap-2">
            <LocaleLink href={`/tickers/${showcase.ticker}`} className="font-mono text-[13px] font-bold text-cream hover:text-reddit">
              {showcase.ticker}
            </LocaleLink>
            <span className="text-[9.5px] text-neutral-600">
              {showcase.calls.length} {zh ? "条历史观点" : "historical calls"}
            </span>
          </div>
        </div>
        <div className="text-right">
          <div className={`text-[9.5px] font-semibold ${showcase.kind === "weak" ? "text-bear" : "text-bull"}`}>
            {showcase.kind === "weak" ? (zh ? "主要扣分" : "Largest drag") : (zh ? "主要加分" : "Largest lift")}
          </div>
          <div className={`mt-1 font-mono text-[13px] font-bold ${showcase.focusContribution >= 0 ? "text-bull" : "text-bear"}`}>
            Score {signed(showcase.focusContribution)}
          </div>
        </div>
      </div>

      <div className="mt-2 flex items-center gap-3 text-[9px] text-neutral-600">
        <span className="flex items-center gap-1"><i className="grid h-3.5 w-3.5 place-items-center rounded-full bg-bull not-italic font-black text-[#111315]">↑</i>{zh ? "看多" : "Bull"}</span>
        <span className="flex items-center gap-1"><i className="grid h-3.5 w-3.5 place-items-center rounded-full bg-bear not-italic font-black text-[#111315]">↓</i>{zh ? "看空" : "Bear"}</span>
        <span className="ml-auto">{zh ? "气泡大小 = Score 影响" : "Bubble size = Score impact"}</span>
      </div>

      {prices.length ? (
        <ReactECharts
          option={option}
          style={{ height, width: "100%" }}
          opts={{ renderer: "canvas" }}
          onEvents={{
            click: (params: any) => {
              const call = params?.data?.call as SmartVoiceRepresentativeCall | undefined;
              if (call) setSelectedKey(callKey(call));
            },
          }}
          notMerge
        />
      ) : (
        <div className="grid h-[180px] place-items-center text-[11px] text-neutral-600">
          {zh ? "该标的暂无可用日线价格" : "No daily close data for this ticker"}
        </div>
      )}

      <div className="border-t border-line/70 pt-2.5">
        <div className="flex items-center gap-1.5">
          <span
            className="rounded px-1.5 py-0.5 text-[9px] font-semibold ring-1 ring-inset"
            style={{
              color: directionColor(selected.direction),
              backgroundColor: `${directionColor(selected.direction)}16`,
              boxShadow: `inset 0 0 0 1px ${directionColor(selected.direction)}35`,
            }}
          >
            {directionLabel(selected.direction, zh)}
          </span>
          <span className="font-mono text-[9.5px] text-neutral-600">{selected.day} · {selected.horizon}</span>
          <span className={`ml-auto font-mono text-[10.5px] font-bold ${selected.contribution >= 0 ? "text-bull" : "text-bear"}`}>
            Score {signed(selected.contribution)}
          </span>
        </div>
        <p className="mt-1.5 line-clamp-3 text-[10.5px] leading-[1.5] text-neutral-400">{summary}</p>
        <div className="mt-2 flex items-center gap-2 font-mono text-[9px] text-neutral-600">
          <span>{selected.entryDay || selected.day}{selected.exitDay ? ` → ${selected.exitDay}` : ""}</span>
          {performance ? (
            <span className={performance.startsWith("+") ? "text-bull/80" : "text-bear/80"}>
              {zh ? "方向超额" : "Directional excess"} {performance}
            </span>
          ) : null}
          {selected.url ? (
            <a href={selected.url} target="_blank" rel="noopener noreferrer" className="ml-auto text-reddit hover:text-cream">
              {zh ? "原观点 ↗" : "Source ↗"}
            </a>
          ) : null}
        </div>
      </div>
    </section>
  );
}
