"use client";

// 「整体数据」底部子面板：KOL 买入/卖出(目标)价位 时间线。
//   x = 下达日期、y = 价格，叠**真实股价折线**；买入=青、卖出·目标=珊瑚；**区间**=竖条、确切价=圆点。
//   同一天多条：y 按价位纵向分开 + 小幅左右抖动 + 半透明叠加(重叠=共识)。现价虚线基准。
//   悬浮 tooltip 出详情：作者 / 平台·日期 / 价位(±现价%) / 操作周期(短中长+原话) / 简单依据。
import { useMemo, useState } from "react";
import ReactECharts from "echarts-for-react";
import type { KolTargetData, TargetMark } from "@/lib/mockDetail";
import { SOURCE } from "./kolShared";

const BUY = "#57D7BA";
const SELL = "#FF5C6C";
const fmtPrice = (n: number) => (n >= 10 ? Math.round(n).toLocaleString() : String(+n.toFixed(2)));
const fmtRange = (lo: number, hi: number) => (hi > lo ? `$${fmtPrice(lo)}–$${fmtPrice(hi)}` : `$${fmtPrice(lo)}`);
const BUCKET_ZH: Record<string, string> = { short: "短线", mid: "中线", long: "长线" };
const BUCKET_EN: Record<string, string> = { short: "short", mid: "mid", long: "long" };
const mmdd = (ds: string) => { const [, m, d] = (ds || "").split("-"); return m ? `${+m}/${+d}` : ds; };
const PRICE_ZOOMS = [1, 2, 4, 8] as const;

// 同一天多条 → 稳定左右抖动（±0.15 天），按作者+侧+价位散开，避免重叠成一团。
function jitterMs(m: TargetMark): number {
  const k = `${m.author}${m.kind}${m.lo}`;
  let h = 0;
  for (let i = 0; i < k.length; i++) h = (h * 31 + k.charCodeAt(i)) >>> 0;
  return ((h % 1000) / 1000 - 0.5) * 0.3 * 864e5;
}

export function TargetPricePanel({ data, zh }: { data: KolTargetData; zh: boolean }) {
  const { current, priceLine, marks } = data;
  const [priceZoom, setPriceZoom] = useState<(typeof PRICE_ZOOMS)[number]>(2);

  const option = useMemo(() => {
    const lineData = priceLine.map((p) => [+new Date(p.day), p.close] as [number, number]);
    const markData = marks.map((m) => ({ value: [+new Date(m.date) + jitterMs(m), m.lo, m.hi] }));

    const tsAll = [...lineData.map((d) => d[0]), ...marks.map((m) => +new Date(m.date))].filter((n) => n > 0);
    const prices = [
      ...lineData.map((d) => d[1]),
      ...marks.flatMap((m) => [m.lo, m.hi]),
      ...(current ? [current] : []),
    ].filter((n) => n > 0);
    if (!prices.length) return { backgroundColor: "transparent" };
    const yLo = Math.min(...prices), yHi = Math.max(...prices);
    const span = yHi - yLo || yHi * 0.2 || 1;
    const yMin = Math.max(0, yLo - span * 0.15);
    const yMax = yHi + span * 0.15;
    const fullSpan = Math.max(1, yMax - yMin);
    const sortedPrices = [...prices].sort((a, b) => a - b);
    const median = sortedPrices[Math.floor(sortedPrices.length / 2)] ?? yLo;
    const center = current && current > 0 ? current : median;
    const visibleSpan = fullSpan / priceZoom;
    let zoomStart = Math.max(yMin, center - visibleSpan / 2);
    let zoomEnd = Math.min(yMax, center + visibleSpan / 2);
    if (zoomEnd - zoomStart < visibleSpan) {
      if (zoomStart <= yMin) zoomEnd = Math.min(yMax, yMin + visibleSpan);
      if (zoomEnd >= yMax) zoomStart = Math.max(yMin, yMax - visibleSpan);
    }

    return {
      backgroundColor: "transparent",
      grid: { left: 6, right: 74, top: 12, bottom: 22, containLabel: true },
      tooltip: {
        trigger: "item",
        backgroundColor: "rgba(20,20,20,0.96)",
        borderColor: "#2a2d2f",
        borderWidth: 1,
        textStyle: { color: "#e5e5e5", fontSize: 11 },
        extraCssText: "border-radius:8px;max-width:260px;white-space:normal",
        formatter: (p: any) => {
          const m: TargetMark | undefined = marks[p.dataIndex];
          if (!m) return "";
          const color = m.kind === "buy" ? BUY : SELL;
          const kind = m.kind === "buy" ? (zh ? "买入" : "Buy") : (zh ? "卖出/目标" : "Sell/target");
          const plat = SOURCE[m.source]?.label || m.source;
          const mid = (m.lo + m.hi) / 2;
          const dl = current ? ` (${mid >= current ? "+" : ""}${Math.round(((mid - current) / current) * 100)}%)` : "";
          const horizon = m.horizon ? (zh ? m.horizon.zh : m.horizon.en) : "";
          const bk = m.bucket ? (zh ? BUCKET_ZH[m.bucket] : BUCKET_EN[m.bucket]) : "";
          const reason = m.reason ? (zh ? m.reason.zh : m.reason.en) : "";
          let html = `<div style="font-weight:600;color:${color}">${m.author}</div>`;
          html += `<div style="color:#9a9da1;margin:2px 0 4px">${plat} · ${m.date}</div>`;
          html += `<div><span style="color:#73757a">${kind} </span><b style="color:${color}">${fmtRange(m.lo, m.hi)}</b><span style="color:#73757a">${dl}</span></div>`;
          if (horizon || bk) html += `<div style="color:#cfcfcf;margin-top:2px">${zh ? "周期" : "Horizon"}: ${horizon}${bk ? `（${bk}）` : ""}</div>`;
          if (reason) html += `<div style="color:#9a9da1;margin-top:3px;border-top:1px solid #2a2d2f;padding-top:4px">${reason.slice(0, 90)}</div>`;
          else if (m.priceRaw) html += `<div style="color:#6b6e72;margin-top:3px;font-size:10px">“${m.priceRaw}”</div>`;
          return html;
        },
      },
      xAxis: {
        type: "time",
        min: tsAll.length ? Math.min(...tsAll) : undefined,
        max: tsAll.length ? Math.max(...tsAll) : undefined,
        axisLine: { lineStyle: { color: "#2a2d2f" } },
        axisTick: { show: false },
        axisLabel: { color: "#73757a", fontSize: 10, formatter: (v: number) => mmdd(new Date(v).toISOString().slice(0, 10)) },
        splitLine: { show: false },
      },
      yAxis: {
        type: "value",
        min: yMin,
        max: yMax,
        position: "right",
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: "#73757a", fontSize: 9.5, formatter: (v: number) => "$" + fmtPrice(v) },
        splitLine: { show: true, lineStyle: { color: "#1d1f21" } },
      },
      dataZoom: [
        {
          type: "inside",
          yAxisIndex: 0,
          filterMode: "none",
          startValue: priceZoom === 1 ? yMin : zoomStart,
          endValue: priceZoom === 1 ? yMax : zoomEnd,
          zoomOnMouseWheel: true,
          moveOnMouseMove: true,
          moveOnMouseWheel: true,
          preventDefaultMouseMove: true,
        },
        {
          type: "slider",
          yAxisIndex: 0,
          filterMode: "none",
          right: 4,
          top: 28,
          bottom: 22,
          width: 11,
          startValue: priceZoom === 1 ? yMin : zoomStart,
          endValue: priceZoom === 1 ? yMax : zoomEnd,
          showDataShadow: false,
          showDetail: false,
          brushSelect: false,
          borderColor: "#2a2d2f",
          fillerColor: "rgba(87,215,186,0.14)",
          backgroundColor: "rgba(255,255,255,0.03)",
          handleSize: 14,
          handleStyle: { color: "#57D7BA", borderColor: "#57D7BA" },
          moveHandleStyle: { color: "#57D7BA" },
          textStyle: { color: "#73757a" },
        },
      ],
      series: [
        {
          type: "line",
          name: "price",
          data: lineData,
          smooth: 0.2,
          symbol: "none",
          lineStyle: { color: "#6b6e72", width: 1.6 },
          tooltip: { show: false },
          markLine: current
            ? {
                silent: true,
                symbol: "none",
                lineStyle: { color: "#9a9da1", width: 1, type: "dashed" },
                label: { show: true, position: "insideEndTop", formatter: `${zh ? "现价" : "Now"} $${fmtPrice(current)}`, color: "#c2c4c7", fontSize: 10 },
                data: [{ yAxis: current }],
              }
            : undefined,
          z: 2,
        },
        {
          type: "custom",
          name: "marks",
          data: markData,
          encode: { x: 0, y: [1, 2] },
          clip: true,
          z: 5,
          renderItem: (params: any, api: any) => {
            const m: TargetMark | undefined = marks[params.dataIndex];
            if (!m) return null;
            const color = m.kind === "buy" ? BUY : SELL;
            const ts = api.value(0);
            const pLo = api.coord([ts, api.value(1)]);
            const pHi = api.coord([ts, api.value(2)]);
            const h = Math.abs(pLo[1] - pHi[1]);
            if (h < 5) {
              return { type: "circle", shape: { cx: pLo[0], cy: pLo[1], r: 4.5 }, style: { fill: color, stroke: "#141414", lineWidth: 1 } };
            }
            const w = 7;
            return {
              type: "group",
              children: [
                { type: "rect", shape: { x: pLo[0] - w / 2, y: pHi[1], width: w, height: h, r: 2 }, style: { fill: color, opacity: 0.3, stroke: color, lineWidth: 1 } },
                { type: "line", shape: { x1: pLo[0] - w / 2, y1: pHi[1], x2: pLo[0] + w / 2, y2: pHi[1] }, style: { stroke: color, lineWidth: 1.4 } },
                { type: "line", shape: { x1: pLo[0] - w / 2, y1: pLo[1], x2: pLo[0] + w / 2, y2: pLo[1] }, style: { stroke: color, lineWidth: 1.4 } },
              ],
            };
          },
        },
      ],
    };
  }, [priceLine, marks, current, zh, priceZoom]);

  if (!marks.length && !priceLine.length) return null;

  return (
    <div className="mt-4 border-t border-line/60 pt-3">
      <div className="mb-1 flex flex-wrap items-center gap-x-2 gap-y-1 px-1">
        <span className="text-[11.5px] font-semibold text-neutral-400">{zh ? "买入 / 卖出价 时间线" : "Buy / sell price timeline"}</span>
        <span className="text-[10.5px] text-neutral-600">{zh ? "近 3 个月 · 悬浮看作者/依据/周期 · 现价剔噪" : "last 3mo · hover for author/why/horizon"}</span>
        <span className="ml-auto flex items-center gap-2.5 text-[10px] text-neutral-500">
          <span className="flex items-center gap-1"><span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: BUY }} />{zh ? "买入" : "Buy"}</span>
          <span className="flex items-center gap-1"><span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: SELL }} />{zh ? "卖出/目标" : "Sell/target"}</span>
          <span className="flex items-center gap-1"><span className="inline-block h-3 w-[5px] rounded-sm ring-1 ring-inset ring-neutral-500" />{zh ? "区间" : "range"}</span>
          <span className="flex items-center gap-1"><span className="inline-block h-2 w-2 rounded-full bg-neutral-500" />{zh ? "确切价" : "exact"}</span>
          <span className="flex items-center gap-1"><span className="inline-block h-px w-3 bg-neutral-500" />{zh ? "股价" : "price"}</span>
        </span>
        <span className="flex items-center gap-1 rounded-md bg-elevated/50 p-0.5 text-[10.5px] ring-1 ring-inset ring-line" title={zh ? "价格轴缩放" : "Price-axis zoom"}>
          <span className="px-1.5 text-neutral-600">{zh ? "价格" : "Price"}</span>
          {PRICE_ZOOMS.map((z) => (
            <button
              key={z}
              type="button"
              onClick={() => setPriceZoom(z)}
              className={`rounded px-1.5 py-0.5 font-mono font-semibold transition ${
                priceZoom === z ? "bg-[#57D7BA]/12 text-[#57D7BA] ring-1 ring-inset ring-[#57D7BA]/55" : "text-neutral-500 hover:text-neutral-300"
              }`}
            >
              {z}×
            </button>
          ))}
        </span>
      </div>
      {marks.length ? (
        <ReactECharts
          option={option}
          style={{ height: 250, width: "100%" }}
          opts={{ renderer: "canvas" }}
          onChartReady={(c: any) => { requestAnimationFrame(() => { try { c.resize(); } catch {} }); }}
          notMerge
        />
      ) : (
        <p className="px-1 py-6 text-center text-[12px] text-neutral-600">
          {zh ? "暂无明确买卖价位（KOL 多数只给方向、不给具体价位）" : "No explicit buy/sell prices yet"}
        </p>
      )}
    </div>
  );
}
