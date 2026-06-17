"use client";

import ReactECharts from "echarts-for-react";
import { useLocale } from "@/components/i18n/LocaleProvider";

export function Sparkline({
  series,
  height = 70,
  color = "#FF4500",
  metric = "mentions",
}: {
  series: { ts: string; mentions: number; sentiment: number }[];
  height?: number;
  color?: string;
  metric?: "mentions" | "sentiment";
}) {
  const { dict } = useLocale();
  const x = series.map((s) => s.ts);
  const y = series.map((s) => (metric === "sentiment" ? Number((s.sentiment ?? 0).toFixed(3)) : s.mentions));
  const option = {
    backgroundColor: "transparent",
    grid: { left: 0, right: 0, top: 6, bottom: 0 },
    xAxis: { type: "category", show: false, data: x, boundaryGap: false },
    yAxis: { type: "value", show: false, ...(metric === "sentiment" ? { min: -1, max: 1 } : { min: 0 }) },
    tooltip: {
      trigger: "axis",
      backgroundColor: "#18171C",
      borderColor: "#2A2930",
      textStyle: { color: "#e5e5e5", fontSize: 11 },
      formatter: (p: any) =>
        metric === "sentiment"
          ? `${dict.charts.sentiment} ${p[0].value > 0 ? "+" : ""}${Number(p[0].value).toFixed(2)}`
          : `${p[0].value}${dict.charts.mentionsSuffix}`,
    },
    series: [
      {
        type: "line",
        smooth: true,
        symbol: "none",
        data: y,
        lineStyle: { color, width: 2 },
        areaStyle: { color: "rgba(255,69,0,0.14)" },
        ...(metric === "sentiment"
          ? { markLine: { silent: true, symbol: "none", lineStyle: { color: "rgba(127,127,127,0.35)", type: "dashed", width: 1 }, data: [{ yAxis: 0 }] } }
          : {}),
      },
    ],
  };
  return <ReactECharts option={option} style={{ height }} opts={{ renderer: "canvas" }} />;
}
