"use client";

import ReactECharts from "echarts-for-react";
import { useIsLight } from "@/lib/useTheme";
import { useLocale } from "@/components/i18n/LocaleProvider";

const md = (d: string) => d.slice(5).replace("-", "/");
const TIP = { backgroundColor: "#16242F", borderColor: "#243845", textStyle: { color: "#e5e5e5", fontSize: 11 } };

export interface ComboPoint { day: string; vol: number; senti: number | null; price: number | null; }

// 价格 × 情绪 × 声量 叠加指数图（同一标的）：左轴=股价，右轴=情绪(-1..1)，底部柱=声量。
export function AsiaComboChart({ data, height = 230 }: { data: ComboPoint[]; height?: number }) {
  const light = useIsLight();
  const { dict } = useLocale();
  const t: any = (dict as any).asia;
  const axis = light ? "#5a6b77" : "#7a8a96";
  const x = data.map((d) => md(d.day));

  const option = {
    backgroundColor: "transparent",
    grid: { left: 6, right: 6, top: 36, bottom: 22, containLabel: true },
    legend: {
      top: 0, textStyle: { color: axis, fontSize: 11 }, itemWidth: 14, itemHeight: 8,
      data: [t.priceAxis, t.sentiAxis, t.volAxis],
    },
    tooltip: {
      trigger: "axis", ...TIP,
      formatter: (ps: any[]) => {
        const day = ps[0]?.axisValue ?? "";
        const get = (n: string) => ps.find((p) => p.seriesName === n);
        const pr = get(t.priceAxis)?.value, se = get(t.sentiAxis)?.value, vo = get(t.volAxis)?.value;
        return `${day}<br/>${pr != null ? `${t.priceAxis} <b>${pr}</b><br/>` : ""}` +
          `${se != null ? `${t.sentiAxis} <b>${se > 0 ? "+" : ""}${se}</b><br/>` : ""}` +
          `${vo != null ? `${t.volAxis} <b>${vo}</b>` : ""}`;
      },
    },
    xAxis: {
      type: "category", data: x, boundaryGap: true,
      axisLine: { lineStyle: { color: axis } }, axisLabel: { color: axis, fontSize: 10 },
      axisTick: { show: false },
    },
    yAxis: [
      { type: "value", scale: true, position: "left", name: t.priceAxis, nameTextStyle: { color: axis, fontSize: 10 },
        axisLabel: { color: axis, fontSize: 10 }, splitLine: { lineStyle: { color: "rgba(127,127,127,0.12)" } } },
      { type: "value", min: -1, max: 1, position: "right", name: t.sentiAxis, nameTextStyle: { color: axis, fontSize: 10 },
        axisLabel: { color: axis, fontSize: 10, formatter: (v: number) => (v > 0 ? "+" : "") + v }, splitLine: { show: false } },
      { type: "value", min: 0, max: Math.max(1, ...data.map((d) => d.vol)) * 3.2, show: false }, // 声量缩到底部
    ],
    series: [
      { name: t.volAxis, type: "bar", yAxisIndex: 2, data: data.map((d) => d.vol),
        itemStyle: { color: "rgba(122,138,150,0.32)" }, barWidth: "55%" },
      { name: t.priceAxis, type: "line", yAxisIndex: 0, data: data.map((d) => d.price), connectNulls: true,
        smooth: true, symbol: "circle", symbolSize: 5, lineStyle: { color: "#E8EAED", width: 2.4 }, itemStyle: { color: "#E8EAED" }, z: 5 },
      { name: t.sentiAxis, type: "line", yAxisIndex: 1, data: data.map((d) => d.senti), connectNulls: true,
        smooth: true, symbol: "none", lineStyle: { color: "#E6B450", width: 2, type: "dashed" },
        areaStyle: { color: "rgba(230,180,80,0.08)" },
        markLine: { silent: true, symbol: "none", lineStyle: { color: "rgba(127,127,127,0.3)", width: 1 }, data: [{ yAxis: 0 }] } },
    ],
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}

export interface LineSeries { name: string; color: string; data: (number | null)[]; }

// 多标的趋势线（每日声量 或 每日情绪）。sentiment=true 时 y 轴锁 -1..1 + 0 基线。
export function AsiaMultiLine({
  x, series, height = 220, sentiment = false,
}: { x: string[]; series: LineSeries[]; height?: number; sentiment?: boolean }) {
  const light = useIsLight();
  const axis = light ? "#5a6b77" : "#7a8a96";
  const option = {
    backgroundColor: "transparent",
    grid: { left: 6, right: 10, top: 30, bottom: 20, containLabel: true },
    legend: { top: 0, textStyle: { color: axis, fontSize: 11 }, itemWidth: 14, itemHeight: 8 },
    tooltip: {
      trigger: "axis", ...TIP,
      valueFormatter: (v: any) => (v == null ? "-" : sentiment ? (v > 0 ? "+" : "") + v : String(v)),
    },
    xAxis: {
      type: "category", data: x.map(md), boundaryGap: false,
      axisLine: { lineStyle: { color: axis } }, axisLabel: { color: axis, fontSize: 10 }, axisTick: { show: false },
    },
    yAxis: {
      type: "value", ...(sentiment ? { min: -1, max: 1 } : { min: 0 }),
      axisLabel: { color: axis, fontSize: 10, formatter: (v: number) => (sentiment && v > 0 ? "+" : "") + v },
      splitLine: { lineStyle: { color: "rgba(127,127,127,0.12)" } },
    },
    series: series.map((s) => ({
      name: s.name, type: "line", smooth: true, symbol: "none", connectNulls: true,
      data: s.data, lineStyle: { color: s.color, width: 2 }, itemStyle: { color: s.color },
      ...(sentiment ? {} : { areaStyle: { color: s.color + "1f" } }),
      ...(sentiment ? { markLine: { silent: true, symbol: "none", lineStyle: { color: "rgba(127,127,127,0.3)", width: 1 }, data: [{ yAxis: 0 }] } } : {}),
    })),
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}

const BULL = "#24B47E", BEAR = "#F0556E", NEU = "#7a8a96";

// 净情绪 / 声量异动 等「围绕 0 发散」的横向条形图。正=绿 负=红。
export interface DivItem { label: string; value: number; }
// 注意：本组件是 Client Component，父级（Server Component）只能传可序列化 props，
// 故用字符串 `unit` 后缀而非函数 formatter（RSC 禁止把函数当 prop 传给 client 组件）。
export function AsiaDivergingBars({
  items, height = 240, unit = "",
}: { items: DivItem[]; height?: number; unit?: string }) {
  const light = useIsLight();
  const axis = light ? "#5a6b77" : "#7a8a96";
  const f = (v: number) => (v > 0 ? "+" : "") + v + unit;
  const sorted = [...items].sort((a, b) => a.value - b.value); // 升序：最大正值排最上
  const maxAbs = Math.max(1, ...sorted.map((d) => Math.abs(d.value)));
  const option = {
    backgroundColor: "transparent",
    grid: { left: 6, right: 22, top: 6, bottom: 18, containLabel: true },
    tooltip: { trigger: "axis", axisPointer: { type: "shadow" }, ...TIP, valueFormatter: (v: any) => f(v) },
    xAxis: {
      type: "value", min: -maxAbs, max: maxAbs, axisLine: { show: false }, axisTick: { show: false },
      axisLabel: { color: axis, fontSize: 10, formatter: f }, splitLine: { lineStyle: { color: "rgba(127,127,127,0.1)" } },
    },
    yAxis: {
      type: "category", data: sorted.map((d) => d.label), axisTick: { show: false },
      axisLine: { lineStyle: { color: axis } }, axisLabel: { color: axis, fontSize: 11 },
    },
    series: [{
      type: "bar", barWidth: "62%",
      data: sorted.map((d) => ({
        value: d.value,
        itemStyle: { color: d.value >= 0 ? BULL : BEAR, borderRadius: 3 },
        // 每条单独设标签位置：正值标右、负值标左，避免压到 0 轴
        label: { show: true, position: d.value >= 0 ? "right" : "left", color: axis, fontSize: 10, formatter: (p: any) => f(p.value) },
      })),
    }],
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}

// 情绪日历热力：x=日期(或任意类目，rawX=true 时不按日期裁剪) y=标的，红→绿映射 -1..1。
export function AsiaHeatmap({
  x, y, cells, height = 220, rawX = false,
}: { x: string[]; y: string[]; cells: [number, number, number][]; height?: number; rawX?: boolean }) {
  const light = useIsLight();
  const axis = light ? "#5a6b77" : "#7a8a96";
  const mid = light ? "#e7e3ea" : "#2c2b33";
  const xLabels = rawX ? x : x.map(md);
  const option = {
    backgroundColor: "transparent",
    grid: { left: 6, right: 8, top: 8, bottom: 46, containLabel: true },
    tooltip: {
      ...TIP, position: "top",
      formatter: (p: any) => `${y[p.value[1]]} · ${x[p.value[0]]}<br/>${p.value[2] > 0 ? "+" : ""}${p.value[2]}`,
    },
    xAxis: {
      type: "category", data: xLabels, splitArea: { show: true }, axisTick: { show: false },
      axisLine: { lineStyle: { color: axis } }, axisLabel: { color: axis, fontSize: 10 },
    },
    yAxis: {
      type: "category", data: y, splitArea: { show: true }, axisTick: { show: false },
      axisLine: { lineStyle: { color: axis } }, axisLabel: { color: axis, fontSize: 11 },
    },
    visualMap: {
      min: -0.6, max: 0.6, calculable: true, orient: "horizontal", left: "center", bottom: 2,
      itemWidth: 11, itemHeight: 110, precision: 1, textStyle: { color: axis, fontSize: 9 },
      inRange: { color: [BEAR, mid, BULL] },
    },
    series: [{
      type: "heatmap", data: cells, progressive: 0,
      label: { show: false },
      itemStyle: { borderColor: light ? "#fff" : "#0d1117", borderWidth: 2, borderRadius: 3 },
      emphasis: { itemStyle: { borderColor: axis, borderWidth: 1 } },
    }],
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}

// 舆情定位气泡图：x=净情绪 y=声量 气泡大小=互动量，按市场分色/分图例。
export interface BubblePoint { name: string; x: number; y: number; size: number; color: string; market: string; }
export function AsiaBubble({
  points, xName, yName, height = 320,
}: { points: BubblePoint[]; xName: string; yName: string; height?: number }) {
  const light = useIsLight();
  const axis = light ? "#5a6b77" : "#7a8a96";
  const maxSize = Math.max(1, ...points.map((p) => p.size));
  const r = (s: number) => 11 + Math.sqrt(s / maxSize) * 34;
  const markets = [...new Set(points.map((p) => p.market))];
  const series = markets.map((mk, i) => ({
    name: mk, type: "scatter",
    data: points.filter((p) => p.market === mk).map((p) => ({ value: [p.x, p.y, p.size, p.name], itemStyle: { color: p.color, opacity: 0.85, borderColor: light ? "#fff" : "#0d1117", borderWidth: 1 } })),
    symbolSize: (val: any) => r(val[2]),
    label: { show: true, formatter: (pp: any) => pp.value[3], position: "inside", color: "#fff", fontSize: 9, fontWeight: 700 },
    ...(i === 0 ? { markLine: { silent: true, symbol: "none", lineStyle: { color: "rgba(127,127,127,0.35)", width: 1, type: "dashed" }, data: [{ xAxis: 0 }] } } : {}),
  }));
  const option = {
    backgroundColor: "transparent",
    grid: { left: 8, right: 18, top: 28, bottom: 32, containLabel: true },
    legend: { top: 0, textStyle: { color: axis, fontSize: 11 }, itemWidth: 12, itemHeight: 8 },
    tooltip: { ...TIP, formatter: (p: any) => `${p.value[3]} · ${p.seriesName}<br/>${xName} <b>${p.value[0] > 0 ? "+" : ""}${p.value[0]}</b><br/>${yName} <b>${p.value[1]}</b>` },
    xAxis: {
      type: "value", name: xName, nameLocation: "middle", nameGap: 22, nameTextStyle: { color: axis, fontSize: 10 },
      axisLabel: { color: axis, fontSize: 10, formatter: (v: number) => (v > 0 ? "+" : "") + v },
      axisLine: { lineStyle: { color: axis } }, splitLine: { lineStyle: { color: "rgba(127,127,127,0.1)" } },
    },
    yAxis: {
      type: "value", name: yName, nameTextStyle: { color: axis, fontSize: 10 }, scale: true,
      axisLabel: { color: axis, fontSize: 10 }, splitLine: { lineStyle: { color: "rgba(127,127,127,0.1)" } },
    },
    series,
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}

// 市场画像雷达：日/韩/台 多维归一化（0..1）对比。
export interface RadarSeries { name: string; color: string; value: number[]; }
export function AsiaRadar({
  indicators, series, height = 320,
}: { indicators: { name: string; max: number }[]; series: RadarSeries[]; height?: number }) {
  const light = useIsLight();
  const axis = light ? "#5a6b77" : "#7a8a96";
  const option = {
    backgroundColor: "transparent",
    legend: { top: 0, textStyle: { color: axis, fontSize: 11 }, itemWidth: 12, itemHeight: 8 },
    tooltip: { ...TIP },
    radar: {
      indicator: indicators, center: ["50%", "56%"], radius: "64%",
      axisName: { color: axis, fontSize: 10 },
      splitLine: { lineStyle: { color: "rgba(127,127,127,0.15)" } },
      splitArea: { areaStyle: { color: ["rgba(127,127,127,0.03)", "rgba(127,127,127,0.07)"] } },
      axisLine: { lineStyle: { color: "rgba(127,127,127,0.15)" } },
    },
    series: [{
      type: "radar", symbolSize: 4,
      data: series.map((s) => ({ value: s.value, name: s.name, itemStyle: { color: s.color }, lineStyle: { color: s.color, width: 2 }, areaStyle: { color: s.color + "22" } })),
    }],
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}

// 成对分组柱（认证用户 vs 大众 的平均情绪）。sentiment=true 时带 0 基线、不锁 min。
export function AsiaPairedBars({
  categories, series, height = 230, sentiment = false,
}: { categories: string[]; series: { name: string; color: string; data: (number | null)[] }[]; height?: number; sentiment?: boolean }) {
  const light = useIsLight();
  const axis = light ? "#5a6b77" : "#7a8a96";
  const option = {
    backgroundColor: "transparent",
    grid: { left: 6, right: 10, top: 28, bottom: 20, containLabel: true },
    legend: { top: 0, textStyle: { color: axis, fontSize: 11 }, itemWidth: 12, itemHeight: 8 },
    tooltip: {
      trigger: "axis", axisPointer: { type: "shadow" }, ...TIP,
      valueFormatter: (v: any) => (v == null ? "-" : sentiment ? (v > 0 ? "+" : "") + v : String(v)),
    },
    xAxis: {
      type: "category", data: categories, axisTick: { show: false },
      axisLine: { lineStyle: { color: axis } }, axisLabel: { color: axis, fontSize: 11 },
    },
    yAxis: {
      type: "value", ...(sentiment ? {} : { min: 0 }),
      axisLabel: { color: axis, fontSize: 10, formatter: (v: number) => (sentiment && v > 0 ? "+" : "") + v },
      splitLine: { lineStyle: { color: "rgba(127,127,127,0.12)" } },
    },
    series: series.map((s, i) => ({
      name: s.name, type: "bar", data: s.data, barWidth: 20, barGap: "10%",
      itemStyle: { color: s.color, borderRadius: 3 },
      ...(sentiment && i === 0 ? { markLine: { silent: true, symbol: "none", lineStyle: { color: "rgba(127,127,127,0.3)", width: 1 }, data: [{ yAxis: 0 }] } } : {}),
    })),
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}
