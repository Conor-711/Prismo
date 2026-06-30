"use client";

import { useMemo } from "react";
import ReactECharts from "echarts-for-react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { fmtCompact } from "@/lib/format";
import type { NarrativeDay, NarrativeLeader } from "@/lib/narrativeRotation";

const AXIS = "#73757a";
const GRID = { left: 6, right: 16, top: 28, bottom: 24, containLabel: true };
const TIP = {
  trigger: "axis",
  backgroundColor: "rgba(20,20,20,0.96)",
  borderColor: "#2a2d2f",
  borderWidth: 1,
  textStyle: { color: "#e5e5e5", fontSize: 11 },
  extraCssText: "border-radius:8px",
};
const md = (d: string) => d.slice(5).replace("-", "/");

function topLeaders(leaders: NarrativeLeader[]) {
  return leaders.filter((l) => l.volume > 0).slice(0, 6);
}

export function NarrativeRankChart({
  leaders, series, height = 260,
}: {
  leaders: NarrativeLeader[];
  series: Record<string, NarrativeDay[]>;
  height?: number;
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const active = topLeaders(leaders);
  const days = series[active[0]?.id || ""]?.map((d) => d.day) ?? [];
  const option = useMemo(() => ({
    backgroundColor: "transparent",
    grid: GRID,
    tooltip: {
      ...TIP,
      valueFormatter: (v: any) => (v == null ? "-" : `#${v}`),
    },
    legend: { top: 0, textStyle: { color: AXIS, fontSize: 11 }, itemWidth: 14, itemHeight: 8 },
    xAxis: {
      type: "category",
      data: days.map(md),
      boundaryGap: false,
      axisLine: { lineStyle: { color: AXIS } },
      axisTick: { show: false },
      axisLabel: { color: AXIS, fontSize: 10 },
    },
    yAxis: {
      type: "value",
      inverse: true,
      min: 1,
      max: Math.max(6, active.length),
      minInterval: 1,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: AXIS, fontSize: 10, formatter: (v: number) => `#${Math.round(v)}` },
      splitLine: { lineStyle: { color: "rgba(127,127,127,0.12)" } },
    },
    series: active.map((l) => ({
      name: zh ? l.title.zh : l.title.en,
      type: "line",
      smooth: 0.25,
      symbol: "circle",
      symbolSize: 4,
      connectNulls: false,
      data: (series[l.id] ?? []).map((d) => d.rank),
      lineStyle: { color: l.color, width: 2 },
      itemStyle: { color: l.color },
    })),
  }), [active, days, series, zh]);
  return <ReactECharts option={option} style={{ height, width: "100%" }} opts={{ renderer: "canvas" }} notMerge />;
}

export function NarrativeShareChart({
  leaders, series, height = 260,
}: {
  leaders: NarrativeLeader[];
  series: Record<string, NarrativeDay[]>;
  height?: number;
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const active = topLeaders(leaders);
  const days = series[active[0]?.id || ""]?.map((d) => d.day) ?? [];
  const option = useMemo(() => ({
    backgroundColor: "transparent",
    grid: GRID,
    tooltip: {
      ...TIP,
      valueFormatter: (v: any) => (v == null ? "-" : `${(+v).toFixed(1)}%`),
    },
    legend: { top: 0, textStyle: { color: AXIS, fontSize: 11 }, itemWidth: 14, itemHeight: 8 },
    xAxis: {
      type: "category",
      data: days.map(md),
      boundaryGap: false,
      axisLine: { lineStyle: { color: AXIS } },
      axisTick: { show: false },
      axisLabel: { color: AXIS, fontSize: 10 },
    },
    yAxis: {
      type: "value",
      min: 0,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: AXIS, fontSize: 10, formatter: (v: number) => `${v}%` },
      splitLine: { lineStyle: { color: "rgba(127,127,127,0.12)" } },
    },
    series: active.map((l) => ({
      name: zh ? l.title.zh : l.title.en,
      type: "line",
      smooth: 0.35,
      symbol: "none",
      data: (series[l.id] ?? []).map((d) => +(d.share * 100).toFixed(2)),
      lineStyle: { color: l.color, width: 2 },
      areaStyle: { color: l.color, opacity: 0.08 },
      itemStyle: { color: l.color },
    })),
  }), [active, days, series, zh]);
  return <ReactECharts option={option} style={{ height, width: "100%" }} opts={{ renderer: "canvas" }} notMerge />;
}

export function NarrativeSentimentChart({
  leaders, series, height = 260,
}: {
  leaders: NarrativeLeader[];
  series: Record<string, NarrativeDay[]>;
  height?: number;
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const active = topLeaders(leaders);
  const days = series[active[0]?.id || ""]?.map((d) => d.day) ?? [];
  const option = useMemo(() => ({
    backgroundColor: "transparent",
    grid: GRID,
    tooltip: {
      ...TIP,
      valueFormatter: (v: any) => (v == null ? "-" : `${v > 0 ? "+" : ""}${(+v).toFixed(2)}`),
    },
    legend: { top: 0, textStyle: { color: AXIS, fontSize: 11 }, itemWidth: 14, itemHeight: 8 },
    xAxis: {
      type: "category",
      data: days.map(md),
      boundaryGap: false,
      axisLine: { lineStyle: { color: AXIS } },
      axisTick: { show: false },
      axisLabel: { color: AXIS, fontSize: 10 },
    },
    yAxis: {
      type: "value",
      min: -1,
      max: 1,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: AXIS, fontSize: 10, formatter: (v: number) => (v > 0 ? "+" : "") + v },
      splitLine: { lineStyle: { color: "rgba(127,127,127,0.12)" } },
    },
    series: active.map((l) => ({
      name: zh ? l.title.zh : l.title.en,
      type: "line",
      smooth: 0.25,
      symbol: "none",
      data: (series[l.id] ?? []).map((d) => d.volume > 0 ? d.sentiment : null),
      lineStyle: { color: l.color, width: 2 },
      itemStyle: { color: l.color },
      markLine: {
        silent: true,
        symbol: "none",
        lineStyle: { color: "rgba(127,127,127,0.35)", width: 1, type: "dashed" },
        data: [{ yAxis: 0 }],
      },
    })),
  }), [active, days, series, zh]);
  return <ReactECharts option={option} style={{ height, width: "100%" }} opts={{ renderer: "canvas" }} notMerge />;
}

export function NarrativeDetailTimeline({
  rows, color, height = 320,
}: {
  rows: NarrativeDay[];
  color: string;
  height?: number;
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const option = useMemo(() => ({
    backgroundColor: "transparent",
    grid: { left: 8, right: 12, top: 34, bottom: 28, containLabel: true },
    tooltip: {
      ...TIP,
      formatter: (ps: any[]) => {
        const day = ps[0]?.axisValue ?? "";
        const vol = ps.find((p) => p.seriesName === (zh ? "讨论度" : "Volume"))?.value ?? 0;
        const share = ps.find((p) => p.seriesName === (zh ? "占比" : "Share"))?.value ?? 0;
        const sent = ps.find((p) => p.seriesName === (zh ? "情绪" : "Sentiment"))?.value ?? 0;
        return `<b>${day}</b><br/>${zh ? "讨论度" : "Volume"} <b>${fmtCompact(vol)}</b><br/>${zh ? "占比" : "Share"} <b>${(+share).toFixed(1)}%</b><br/>${zh ? "情绪" : "Sentiment"} <b>${sent > 0 ? "+" : ""}${(+sent).toFixed(2)}</b>`;
      },
    },
    legend: { top: 0, textStyle: { color: AXIS, fontSize: 11 }, itemWidth: 14, itemHeight: 8 },
    xAxis: {
      type: "category",
      data: rows.map((r) => md(r.day)),
      axisLine: { lineStyle: { color: AXIS } },
      axisTick: { show: false },
      axisLabel: { color: AXIS, fontSize: 10 },
    },
    yAxis: [
      {
        type: "value",
        min: 0,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: AXIS, fontSize: 10, formatter: (v: number) => `${v}%` },
        splitLine: { lineStyle: { color: "rgba(127,127,127,0.12)" } },
      },
      {
        type: "value",
        min: -1,
        max: 1,
        position: "right",
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: AXIS, fontSize: 10, formatter: (v: number) => (v > 0 ? "+" : "") + v },
        splitLine: { show: false },
      },
      { type: "value", min: 0, max: Math.max(1, ...rows.map((r) => r.volume)) * 4, show: false },
    ],
    series: [
      {
        name: zh ? "讨论度" : "Volume",
        type: "bar",
        yAxisIndex: 2,
        data: rows.map((r) => r.volume),
        itemStyle: { color: "rgba(122,138,150,0.28)", borderRadius: [2, 2, 0, 0] },
        barMaxWidth: 18,
      },
      {
        name: zh ? "占比" : "Share",
        type: "line",
        yAxisIndex: 0,
        smooth: 0.3,
        symbol: "none",
        data: rows.map((r) => +(r.share * 100).toFixed(2)),
        lineStyle: { color, width: 2.4 },
        areaStyle: { color, opacity: 0.12 },
        itemStyle: { color },
      },
      {
        name: zh ? "情绪" : "Sentiment",
        type: "line",
        yAxisIndex: 1,
        smooth: 0.25,
        symbol: "none",
        data: rows.map((r) => r.volume > 0 ? r.sentiment : null),
        lineStyle: { color: "#E0A33E", width: 2, type: "dashed" },
        itemStyle: { color: "#E0A33E" },
        markLine: {
          silent: true,
          symbol: "none",
          lineStyle: { color: "rgba(127,127,127,0.35)", width: 1, type: "dashed" },
          data: [{ yAxis: 0 }],
        },
      },
    ],
  }), [rows, color, zh]);
  return <ReactECharts option={option} style={{ height, width: "100%" }} opts={{ renderer: "canvas" }} notMerge />;
}
