"use client";

import ReactECharts from "echarts-for-react";

// 详情页模块用的小图表（ECharts），风格对齐 components/asia/AsiaCharts。
// 全部 client 组件：父级 server 页面只传可序列化 props（数字/字符串/数组），不传函数。

const AXIS = "#7a8a96";
const TIP = { backgroundColor: "#161616", borderColor: "#2a2d2f", textStyle: { color: "#e5e5e5", fontSize: 11 } };
const BULL = "#57D7BA";
const BEAR = "#fe5555";

// 风险/温度环形仪表（0..100）。tone: risk(低绿→高红) / good(低红→高绿) / brand(青绿)。
export function Gauge({ value, suffix = "", tone = "brand", height = 150 }: { value: number; suffix?: string; tone?: "risk" | "good" | "brand"; height?: number }) {
  const color =
    tone === "risk" ? (value > 66 ? BEAR : value > 40 ? "#E6B450" : BULL)
    : tone === "good" ? (value > 60 ? BULL : value > 35 ? "#E6B450" : BEAR)
    : BULL;
  const option = {
    backgroundColor: "transparent",
    series: [{
      type: "gauge", startAngle: 210, endAngle: -30, min: 0, max: 100, radius: "100%", center: ["50%", "60%"],
      progress: { show: true, width: 9, roundCap: true, itemStyle: { color } },
      axisLine: { lineStyle: { width: 9, color: [[1, "rgba(127,127,127,0.16)"]] } },
      pointer: { show: false }, anchor: { show: false }, axisTick: { show: false }, splitLine: { show: false }, axisLabel: { show: false },
      title: { show: false },
      detail: { valueAnimation: false, fontSize: 24, fontWeight: 800, offsetCenter: [0, "2%"], color: "#F1F3F4", formatter: `{v|{value}}${suffix}`, rich: { v: { fontSize: 24, fontWeight: 800, color: "#F1F3F4", fontFamily: "Roboto" } } },
      data: [{ value }],
    }],
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}

// 环形占比（多空 / call-put / 地区贡献…）。data: {name,value,color}[]。
export function Donut({ data, height = 150, centerTop = "", centerBottom = "" }: { data: { name: string; value: number; color: string }[]; height?: number; centerTop?: string; centerBottom?: string }) {
  const option = {
    backgroundColor: "transparent",
    tooltip: { trigger: "item", ...TIP, formatter: (p: any) => `${p.name} <b>${p.value}</b> (${p.percent}%)` },
    title: centerTop
      ? { text: centerTop, subtext: centerBottom, left: "center", top: "38%",
          textStyle: { color: "#F1F3F4", fontSize: 18, fontWeight: 800, fontFamily: "Roboto" },
          subtextStyle: { color: AXIS, fontSize: 10 }, textAlign: "center" }
      : undefined,
    series: [{
      type: "pie", radius: ["62%", "86%"], center: ["50%", "50%"], avoidLabelOverlap: false,
      label: { show: false }, labelLine: { show: false },
      data: data.map((d) => ({ name: d.name, value: d.value, itemStyle: { color: d.color, borderColor: "#161616", borderWidth: 2 } })),
    }],
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}

// 迷你趋势（无轴 sparkline）。up 决定主色，可被 color 覆盖。
export function MiniTrend({ data, up, color, height = 44 }: { data: number[]; up?: boolean; color?: string; height?: number }) {
  const c = color ?? (up ? BULL : BEAR);
  const option = {
    backgroundColor: "transparent",
    grid: { left: 1, right: 1, top: 4, bottom: 2 },
    xAxis: { type: "category", show: false, data: data.map((_, i) => i), boundaryGap: false },
    yAxis: { type: "value", show: false, scale: true },
    tooltip: { trigger: "axis", ...TIP, formatter: (p: any[]) => `${p[0].value}` },
    series: [{
      type: "line", data, smooth: true, symbol: "none",
      lineStyle: { color: c, width: 2 },
      areaStyle: { color: c + "26" },
    }],
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}

// 横向「升温/降温」条（注意力轮动）：正绿负红，围绕 0。
export function ChangeBars({ items, height = 200 }: { items: { label: string; value: number }[]; height?: number }) {
  const sorted = [...items].sort((a, b) => a.value - b.value);
  const maxAbs = Math.max(1, ...sorted.map((d) => Math.abs(d.value)));
  const option = {
    backgroundColor: "transparent",
    grid: { left: 6, right: 26, top: 6, bottom: 16, containLabel: true },
    tooltip: { trigger: "axis", axisPointer: { type: "shadow" }, ...TIP, valueFormatter: (v: any) => (v > 0 ? "+" : "") + v + "%" },
    xAxis: { type: "value", min: -maxAbs, max: maxAbs, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: AXIS, fontSize: 10, formatter: (v: number) => (v > 0 ? "+" : "") + v + "%" }, splitLine: { lineStyle: { color: "rgba(127,127,127,0.1)" } } },
    yAxis: { type: "category", data: sorted.map((d) => d.label), axisTick: { show: false }, axisLine: { lineStyle: { color: AXIS } }, axisLabel: { color: AXIS, fontSize: 11 } },
    series: [{ type: "bar", barWidth: "58%", data: sorted.map((d) => ({ value: d.value, itemStyle: { color: d.value >= 0 ? BULL : BEAR, borderRadius: 3 }, label: { show: true, position: d.value >= 0 ? "right" : "left", color: AXIS, fontSize: 10, formatter: (p: any) => (p.value > 0 ? "+" : "") + p.value + "%" } })) }],
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} notMerge />;
}
