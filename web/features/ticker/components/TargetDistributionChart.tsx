"use client";

import { useMemo } from "react";
import ReactECharts from "echarts-for-react";
import type { TargetMark } from "@/shared/market/mockDetail";
import {
  formatTargetPrice,
  TARGET_BUY_COLOR,
  TARGET_LINE_COLOR,
  TARGET_SELL_COLOR,
  TARGET_TOOLTIP_BACKGROUND,
} from "../targetPriceModel";

export function TargetDistributionChart({
  marks,
  current,
  zh,
}: {
  marks: TargetMark[];
  current: number | null;
  zh: boolean;
}) {
  const option = useMemo(() => {
    const points = marks.map((mark) => ({ mark, mid: (mark.lo + mark.hi) / 2 })).filter((point) => point.mid > 0);
    const prices = [...points.map((point) => point.mid), ...(current ? [current] : [])];
    if (!points.length || !prices.length) return { backgroundColor: "transparent" };
    const rawMin = Math.min(...prices);
    const rawMax = Math.max(...prices);
    const span = rawMax - rawMin || rawMax * 0.2 || 1;
    const min = Math.max(0, rawMin - span * 0.12);
    const max = rawMax + span * 0.12;
    const binCount = Math.max(4, Math.min(9, Math.ceil(Math.sqrt(points.length) * 1.8)));
    const step = (max - min) / binCount || 1;
    const labels = Array.from({ length: binCount }, (_, index) => {
      const start = min + step * index;
      const end = index === binCount - 1 ? max : min + step * (index + 1);
      return `$${formatTargetPrice(start)}–${formatTargetPrice(end)}`;
    });
    const buy = Array(binCount).fill(0);
    const sell = Array(binCount).fill(0);
    for (const point of points) {
      const index = Math.max(0, Math.min(binCount - 1, Math.floor((point.mid - min) / step)));
      if (point.mark.kind === "buy") buy[index] += 1;
      else sell[index] += 1;
    }
    const currentIndex = current
      ? Math.max(0, Math.min(binCount - 1, Math.floor((current - min) / step)))
      : null;
    return {
      backgroundColor: "transparent",
      grid: { left: 6, right: 12, top: 8, bottom: 28, containLabel: true },
      tooltip: {
        trigger: "axis",
        axisPointer: { type: "shadow" },
        backgroundColor: TARGET_TOOLTIP_BACKGROUND,
        borderColor: TARGET_LINE_COLOR,
        borderWidth: 1,
        textStyle: { color: "#e5e5e5", fontSize: 11 },
        extraCssText: "border-radius:8px;max-width:240px;white-space:normal",
        formatter: (params: any[]) => {
          const index = params?.[0]?.dataIndex ?? 0;
          return `<b>${labels[index]}</b><br/><span style="color:${TARGET_BUY_COLOR}">●</span> ${zh ? "买入" : "Buy"} <b>${buy[index]}</b><br/><span style="color:${TARGET_SELL_COLOR}">●</span> ${zh ? "卖出/目标" : "Sell/target"} <b>${sell[index]}</b>${currentIndex === index ? `<br/><span style="color:#9a9da1">${zh ? "现价所在区间" : "Current price bin"}</span>` : ""}`;
        },
      },
      xAxis: {
        type: "category",
        data: labels,
        axisLine: { lineStyle: { color: TARGET_LINE_COLOR } },
        axisTick: { show: false },
        axisLabel: { color: "#73757a", fontSize: 9, interval: 0, rotate: labels.length > 5 ? 18 : 0 },
      },
      yAxis: {
        type: "value",
        minInterval: 1,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: "#73757a", fontSize: 9 },
        splitLine: { lineStyle: { color: "#1d1f21" } },
      },
      series: [
        {
          name: zh ? "买入" : "Buy",
          type: "bar",
          data: buy,
          itemStyle: { color: TARGET_BUY_COLOR, opacity: 0.82, borderRadius: [2, 2, 0, 0] },
          barMaxWidth: 18,
          markLine: currentIndex != null ? {
            silent: true,
            symbol: "none",
            lineStyle: { color: "#9a9da1", type: "dashed", width: 1 },
            label: { color: "#c2c4c7", fontSize: 9, formatter: `${zh ? "现价" : "Now"} $${formatTargetPrice(current!)}` },
            data: [{ xAxis: labels[currentIndex] }],
          } : undefined,
        },
        {
          name: zh ? "卖出/目标" : "Sell/target",
          type: "bar",
          data: sell,
          itemStyle: { color: TARGET_SELL_COLOR, opacity: 0.82, borderRadius: [2, 2, 0, 0] },
          barMaxWidth: 18,
        },
      ],
    };
  }, [marks, current, zh]);

  if (!marks.length) return null;
  return (
    <div className="mt-3 border-t border-line/50 pt-2">
      <div className="mb-1 flex items-center justify-between gap-3 px-1">
        <span className="text-[11.5px] font-semibold text-neutral-400">{zh ? "目标价分布" : "Target price distribution"}</span>
        <span className="text-[10px] text-neutral-600">{zh ? "同筛选条件 · 区间计数" : "same filters · binned"}</span>
      </div>
      <ReactECharts
        option={option}
        style={{ height: 148, width: "100%" }}
        opts={{ renderer: "canvas" }}
        onChartReady={(chart: any) => { requestAnimationFrame(() => { try { chart.resize(); } catch {} }); }}
        notMerge
      />
    </div>
  );
}
