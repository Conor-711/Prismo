"use client";

import ReactECharts from "echarts-for-react";
import type { SvSignalHorizon, SvTickerSignalEvent } from "@/server/queries/smartVoiceTickerSignals";

const BULL = "#57D7BA";
const BEAR = "#FF5C6C";
const AXIS = "#707780";

function percent(value: number | null) {
  if (value == null) return "—";
  return `${value >= 0 ? "+" : ""}${(value * 100).toFixed(1)}%`;
}

export function SmartVoiceSignalChart({
  prices,
  events,
  outcomeHorizon,
  zh,
}: {
  prices: { day: string; close: number }[];
  events: SvTickerSignalEvent[];
  outcomeHorizon: SvSignalHorizon;
  zh: boolean;
}) {
  const eventPoint = (event: SvTickerSignalEvent) => {
    const outcome = event.outcomes.find((item) => item.horizon === outcomeHorizon);
    return {
      value: [event.entryDay || event.signalDay, event.entryPrice],
      event,
      outcome,
    };
  };
  const seriesFor = (cohort: "top" | "bottom", direction: "bull" | "bear") =>
    events
      .filter((event) => event.cohort.startsWith(cohort) && event.direction === direction && event.entryPrice != null)
      .map(eventPoint);

  const option = {
    animation: false,
    backgroundColor: "transparent",
    grid: { left: 10, right: 52, top: 22, bottom: 28, containLabel: true },
    tooltip: {
      trigger: "item",
      backgroundColor: "#202328",
      borderColor: "#343A42",
      textStyle: { color: "#F2F4F5", fontSize: 11 },
      formatter: (params: any) => {
        if (params.seriesType === "line") return `${params.name}<br/>$${Number(params.value).toFixed(2)}`;
        const event = params.data?.event as SvTickerSignalEvent | undefined;
        const outcome = params.data?.outcome;
        if (!event) return "";
        const group = event.cohort.startsWith("top") ? "Top Score" : "Bottom Score";
        const direction = event.direction === "bull" ? (zh ? "看多" : "Bullish") : (zh ? "看空" : "Bearish");
        return [
          `${event.signalDay} · ${group} ${direction}`,
          `${zh ? "作者" : "Voices"}: ${event.nAuthors} · ${zh ? "共识" : "Consensus"}: ${(event.consensusStrength * 100).toFixed(0)}%`,
          `${outcomeHorizon} ${zh ? "方向超额" : "directional excess"}: ${percent(outcome?.directionalExcessPct ?? null)}`,
        ].join("<br/>");
      },
    },
    xAxis: {
      type: "category",
      data: prices.map((item) => item.day),
      boundaryGap: false,
      axisTick: { show: false },
      axisLine: { lineStyle: { color: "#343A42" } },
      axisLabel: { color: AXIS, fontSize: 9, formatter: (value: string) => value.slice(5).replace("-", "/") },
    },
    yAxis: {
      type: "value",
      scale: true,
      position: "right",
      axisLabel: { color: AXIS, fontSize: 9, formatter: (value: number) => `$${Math.round(value)}` },
      splitLine: { lineStyle: { color: "rgba(112,119,128,.12)" } },
    },
    series: [
      {
        name: zh ? "股价" : "Price",
        type: "line",
        data: prices.map((item) => item.close),
        symbol: "none",
        smooth: 0.16,
        lineStyle: { color: "#A7A9AC", width: 1.6 },
        z: 2,
      },
      {
        name: "Top Score Bull",
        type: "scatter",
        data: seriesFor("top", "bull"),
        symbol: "diamond",
        symbolSize: 9,
        itemStyle: { color: BULL, borderColor: "#17191C", borderWidth: 1 },
        z: 5,
      },
      {
        name: "Top Score Bear",
        type: "scatter",
        data: seriesFor("top", "bear"),
        symbol: "diamond",
        symbolSize: 9,
        itemStyle: { color: BEAR, borderColor: "#17191C", borderWidth: 1 },
        z: 5,
      },
      {
        name: "Bottom Score Bull",
        type: "scatter",
        data: seriesFor("bottom", "bull"),
        symbol: "circle",
        symbolSize: 7,
        itemStyle: { color: "transparent", borderColor: BULL, borderWidth: 1.5 },
        z: 4,
      },
      {
        name: "Bottom Score Bear",
        type: "scatter",
        data: seriesFor("bottom", "bear"),
        symbol: "circle",
        symbolSize: 7,
        itemStyle: { color: "transparent", borderColor: BEAR, borderWidth: 1.5 },
        z: 4,
      },
    ],
  };

  return <ReactECharts option={option} style={{ height: 250 }} opts={{ renderer: "canvas" }} notMerge />;
}
