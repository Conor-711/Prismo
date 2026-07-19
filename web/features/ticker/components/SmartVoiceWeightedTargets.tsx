"use client";

import ReactECharts from "echarts-for-react";
import type { SvWeightedTargetDistribution } from "../smartVoiceDecisionLogic";

const money = (value: number | null) => value == null
  ? "—"
  : `$${value.toLocaleString(undefined, { maximumFractionDigits: value >= 100 ? 0 : 2 })}`;

export function SmartVoiceWeightedTargets({
  distribution,
  currentPrice,
  zh,
}: {
  distribution: SvWeightedTargetDistribution;
  currentPrice: number | null;
  zh: boolean;
}) {
  const maxWeight = Math.max(...distribution.points.map((item) => item.weight), 1);
  const pointData = (direction: "bull" | "bear") => distribution.points
    .filter((item) => item.direction === direction)
    .map((item) => ({
      value: [item.target, direction === "bull" ? 1 : 0, item.weight],
      symbolSize: 6 + 13 * Math.sqrt(item.weight / maxWeight),
      item,
    }));
  const option = {
    animation: false,
    backgroundColor: "transparent",
    grid: { left: 42, right: 18, top: 18, bottom: 34, containLabel: true },
    tooltip: {
      trigger: "item",
      backgroundColor: "#202328",
      borderColor: "#343A42",
      textStyle: { color: "#F2F4F5", fontSize: 11 },
      formatter: (params: any) => {
        const item = params.data?.item;
        if (!item) return "";
        return [
          `${item.author} · ${item.source}`,
          `${item.direction === "bull" ? (zh ? "看多" : "Bull") : (zh ? "看空" : "Bear")} · ${money(item.target)}`,
          `SV ${Math.round(item.sv)} · Top ${Math.max(1, Math.ceil(item.percentile))}%`,
          item.createdAt.slice(0, 10),
        ].join("<br/>");
      },
    },
    xAxis: {
      type: "value",
      scale: true,
      axisLabel: { color: "#707780", fontSize: 9, formatter: (value: number) => money(value) },
      axisLine: { lineStyle: { color: "#343A42" } },
      splitLine: { lineStyle: { color: "rgba(112,119,128,.12)" } },
    },
    yAxis: {
      type: "category",
      data: [zh ? "看空" : "Bear", zh ? "看多" : "Bull"],
      axisTick: { show: false },
      axisLine: { show: false },
      axisLabel: { color: "#707780", fontSize: 9 },
    },
    series: [
      {
        type: "scatter",
        name: zh ? "看多目标" : "Bull targets",
        data: pointData("bull"),
        itemStyle: { color: "#57D7BA", opacity: 0.78, borderColor: "#17191C", borderWidth: 1 },
        markLine: {
          silent: true,
          symbol: "none",
          label: { color: "#A7A9AC", fontSize: 9, formatter: zh ? "现价" : "Spot" },
          lineStyle: { color: "#A7A9AC", type: "dashed", width: 1 },
          data: currentPrice == null ? [] : [{ xAxis: currentPrice }],
        },
      },
      {
        type: "scatter",
        name: zh ? "看空目标" : "Bear targets",
        data: pointData("bear"),
        itemStyle: { color: "#FF5C6C", opacity: 0.78, borderColor: "#17191C", borderWidth: 1 },
        markLine: {
          silent: true,
          symbol: "none",
          label: { color: "#57D7BA", fontSize: 9, formatter: zh ? "加权中位" : "Weighted median" },
          lineStyle: { color: "#57D7BA", type: "dotted", width: 1 },
          data: distribution.median == null ? [] : [{ xAxis: distribution.median }],
        },
      },
    ],
  };

  return (
    <section className="min-w-0 border-b border-line lg:border-b-0 lg:border-r">
      <div className="flex items-center justify-between gap-3 border-b border-line/70 px-4 py-2.5">
        <div>
          <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "SV 加权目标价分布" : "SV-weighted target distribution"}</h4>
          <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "权重包含历史时点 SV、证据质量、Call 强度与时间衰减" : "Weighted by point-in-time SV, evidence quality, call strength and recency"}</p>
        </div>
        <div className="text-right">
          <div className="font-mono text-[15px] font-bold text-cream">{money(distribution.median)}</div>
          <div className={`text-[9px] ${(distribution.impliedMove ?? 0) >= 0 ? "text-bull" : "text-bear"}`}>
            {distribution.impliedMove == null ? "—" : `${distribution.impliedMove >= 0 ? "+" : ""}${(distribution.impliedMove * 100).toFixed(1)}%`}
          </div>
        </div>
      </div>
      <div className="grid grid-cols-4 divide-x divide-line/60 border-b border-line/60 px-4 py-2 text-[8.5px]">
        <div><span className="text-neutral-600">IQR</span><b className="ml-1 font-mono text-neutral-300">{money(distribution.low)}–{money(distribution.high)}</b></div>
        <div className="pl-3"><span className="text-neutral-600">n</span><b className="ml-1 font-mono text-neutral-300">{distribution.count}</b></div>
        <div className="pl-3"><span className="text-neutral-600">n_eff</span><b className="ml-1 font-mono text-neutral-300">{distribution.effectiveCount.toFixed(1)}</b></div>
        <div className="pl-3"><span className="text-neutral-600">{zh ? "多头权重" : "Bull wt."}</span><b className="ml-1 font-mono text-neutral-300">{(distribution.bullWeightShare * 100).toFixed(0)}%</b></div>
      </div>
      {distribution.points.length ? (
        <ReactECharts option={option} style={{ height: 190 }} opts={{ renderer: "canvas" }} notMerge />
      ) : (
        <div className="grid h-[190px] place-items-center text-[10px] text-neutral-600">{zh ? "该周期暂无明确目标价" : "No explicit targets for this horizon"}</div>
      )}
    </section>
  );
}
