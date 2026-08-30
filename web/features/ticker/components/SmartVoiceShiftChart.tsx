"use client";

import ReactECharts from "echarts-for-react";
import type { SvShiftPoint } from "../smartVoiceOverviewLogic";

const BULL = "#57D7BA";
const BEAR = "#FF5C6C";
const PRICE = "#A7A9AC";
const AXIS = "#707780";

function signed(value: number) {
  return `${value >= 0 ? "+" : ""}${value.toFixed(0)}`;
}

export function SmartVoiceShiftChart({
  points,
  prices,
  zh,
}: {
  points: SvShiftPoint[];
  prices: { day: string; close: number }[];
  zh: boolean;
}) {
  const priceByDay = new Map(prices.map((item) => [item.day, item.close]));
  const days = points.map((item) => item.day);
  const option = {
    animation: false,
    backgroundColor: "transparent",
    grid: { left: 16, right: 54, top: 26, bottom: 28, containLabel: true },
    tooltip: {
      trigger: "axis",
      backgroundColor: "#202328",
      borderColor: "#343A42",
      textStyle: { color: "#F2F4F5", fontSize: 11 },
      formatter: (params: any[]) => {
        const day = params[0]?.axisValue ?? "";
        const shift = points.find((item) => item.day === day)?.shift;
        const price = priceByDay.get(day);
        return [
          day,
          `${zh ? "Score 7日转向" : "Score 7D shift"} <b style="color:${(shift ?? 0) >= 0 ? BULL : BEAR}">${shift == null ? "—" : signed(shift)}</b>`,
          `${zh ? "股价" : "Price"} <b>${price == null ? "—" : `$${price.toFixed(2)}`}</b>`,
        ].join("<br/>");
      },
    },
    legend: {
      right: 8,
      top: 0,
      itemWidth: 12,
      itemHeight: 2,
      textStyle: { color: AXIS, fontSize: 9 },
      data: [zh ? "Score 7日转向" : "Score 7D shift", zh ? "股价" : "Price"],
    },
    xAxis: {
      type: "category",
      data: days,
      boundaryGap: true,
      axisTick: { show: false },
      axisLine: { lineStyle: { color: "#343A42" } },
      axisLabel: {
        color: AXIS,
        fontSize: 9,
        formatter: (value: string) => value.slice(5).replace("-", "/"),
      },
    },
    yAxis: [
      {
        type: "value",
        min: -100,
        max: 100,
        interval: 50,
        axisLabel: {
          color: AXIS,
          fontSize: 9,
          formatter: (value: number) => signed(value),
        },
        splitLine: { lineStyle: { color: "rgba(112,119,128,.12)" } },
      },
      {
        type: "value",
        scale: true,
        position: "right",
        axisLabel: { color: AXIS, fontSize: 9, formatter: (value: number) => `$${Math.round(value)}` },
        splitLine: { show: false },
      },
    ],
    series: [
      {
        name: zh ? "Score 7日转向" : "Score 7D shift",
        type: "bar",
        yAxisIndex: 0,
        data: points.map((item) => ({
          value: item.shift,
          itemStyle: { color: (item.shift ?? 0) >= 0 ? BULL : BEAR, opacity: 0.62 },
        })),
        barMaxWidth: 7,
        markLine: {
          silent: true,
          symbol: "none",
          label: { show: false },
          lineStyle: { color: "rgba(167,169,172,.38)", width: 1 },
          data: [{ yAxis: 0 }],
        },
        z: 2,
      },
      {
        name: zh ? "股价" : "Price",
        type: "line",
        yAxisIndex: 1,
        data: days.map((day) => priceByDay.get(day) ?? null),
        symbol: "none",
        connectNulls: true,
        smooth: 0.14,
        lineStyle: { color: PRICE, width: 1.5 },
        z: 4,
      },
    ],
  };

  return <ReactECharts option={option} style={{ height: 290 }} opts={{ renderer: "canvas" }} notMerge />;
}
