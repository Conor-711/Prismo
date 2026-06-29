"use client";

// 「整体数据」叠加面板：把 每日净情绪 / 讨论度 / 新增 / 聪明钱 / 散户 叠到**同一条日期轴**上，
// 每个指标一个开关（React 控显隐，按需叠加），各指标各自缩放（4 条隐藏 y 轴、互不压扁），
// 数值由**统一 hover tooltip**读出（含讨论度/新增的平台拆分 + 金色 ⚑ 标记日的 AI 异动归因）。
// x 轴 = 逐日历日（含周末）；折线类指标对非交易日 connectNulls 平滑跨越。
import { useMemo, useState } from "react";
import ReactECharts from "echarts-for-react";
import { fmtCompact } from "@/lib/format";
import type { VolStackItem } from "./kolShared";
import type { VolRow } from "./VolumePanel";
import type { ChartMarker } from "./SentimentPanel";
import type { DailyNet } from "@/lib/kolQueries";
import type { Divergence, SentStance } from "@/lib/overallData";

const GREEN = "#57D7BA", RED = "#FF5C6C", GOLD = "#F2B544", VOL = "#8A8D91", NEW = "#5BA3C4", SMART = "#F2B544", RETAIL = "#8A8D91";
const mmdd = (d: string) => { const [, m, dd] = (d || "").split("-"); return m ? `${+m}/${+dd}` : ""; };
const STANCE: Record<SentStance, { zh: string; en: string; color: string }> = {
  bull: { zh: "看多", en: "Bull", color: GREEN },
  bear: { zh: "看空", en: "Bear", color: RED },
  neutral: { zh: "中性", en: "Neutral", color: "#9a9a9a" },
};

type MetricKey = "sentiment" | "volume" | "newcomers" | "smart" | "retail";

export function OverlayPanel({
  days, zh, sentiment, volume, volStack, newcomers, newStack, newLabel, divergence, sentMarkers, volMarkers,
}: {
  days: { day: string }[];
  zh: boolean;
  sentiment: DailyNet[];
  volume: VolRow[];
  volStack: VolStackItem[];
  newcomers: VolRow[];
  newStack: VolStackItem[];
  newLabel: { zh: string; en: string };
  divergence?: Divergence | null;
  sentMarkers?: ChartMarker[];
  volMarkers?: ChartMarker[];
}) {
  // 逐日历日轴 [首日, 末日]（含周末，一日一格）
  const cats = useMemo(() => {
    const start = days[0]?.day, end = days[days.length - 1]?.day;
    if (!start || !end) return [] as string[];
    const out: string[] = [];
    const d = new Date(start + "T00:00:00Z"), e = new Date(end + "T00:00:00Z");
    while (d <= e) { out.push(d.toISOString().slice(0, 10)); d.setUTCDate(d.getUTCDate() + 1); }
    return out;
  }, [days]);

  const prep = useMemo(() => {
    const sentByDay = new Map(sentiment.map((d) => [d.day, +d.net.toFixed(2)]));
    const volByDay = new Map(volume.map((r) => [r.day, r]));
    const newByDay = new Map(newcomers.map((r) => [r.day, r]));
    const drvByDay = new Map((divergence?.series ?? []).map((p) => [p.day, p]));
    const sentArr = cats.map((d) => (sentByDay.has(d) ? (sentByDay.get(d) as number) : null));
    const green = sentArr.map((v) => (v == null ? null : Math.max(0, v)));
    const red = sentArr.map((v) => (v == null ? null : Math.min(0, v)));
    const volTotal = cats.map((d) => +(volByDay.get(d)?.total ?? 0) || 0);
    const newTotal = cats.map((d) => +(newByDay.get(d)?.total ?? 0) || 0);
    const smart = cats.map((d) => (drvByDay.has(d) ? drvByDay.get(d)!.smart : null));
    const retail = cats.map((d) => (drvByDay.has(d) ? drvByDay.get(d)!.retail : null));
    const inCats = new Set(cats);
    const sentMk = (sentMarkers ?? []).filter((m) => inCats.has(m.day)).map((m) => ({ value: [m.day, sentByDay.get(m.day) ?? 0] }));
    const volMk = (volMarkers ?? []).filter((m) => inCats.has(m.day)).map((m) => ({ value: [m.day, +(volByDay.get(m.day)?.total ?? 0) || 0] }));
    const anomByDay = new Map<string, { sent?: string; vol?: string }>();
    for (const m of sentMarkers ?? []) anomByDay.set(m.day, { ...anomByDay.get(m.day), sent: zh ? m.reason.zh : m.reason.en });
    for (const m of volMarkers ?? []) anomByDay.set(m.day, { ...anomByDay.get(m.day), vol: zh ? m.reason.zh : m.reason.en });
    return { sentByDay, volByDay, newByDay, drvByDay, green, red, volTotal, newTotal, smart, retail, sentMk, volMk, anomByDay };
  }, [cats, sentiment, volume, newcomers, divergence, sentMarkers, volMarkers, zh]);

  // 各指标是否有数据（无则不出 chip）
  const avail = useMemo(() => ({
    sentiment: sentiment.some((d) => Math.abs(d.net) > 1e-6),
    volume: volume.some((r) => (r.total || 0) > 0),
    newcomers: newcomers.some((r) => (r.total || 0) > 0),
    smart: !!divergence && divergence.series.some((p) => Math.abs(p.smart) > 1e-6),
    retail: !!divergence && divergence.series.some((p) => Math.abs(p.retail) > 1e-6),
  }), [sentiment, volume, newcomers, divergence]);

  // 默认只开 净情绪 + 讨论度（其余按需叠加）
  const [vis, setVis] = useState<Record<MetricKey, boolean>>({ sentiment: true, volume: true, newcomers: false, smart: false, retail: false });
  const on = (k: MetricKey) => avail[k] && vis[k];
  const toggle = (k: MetricKey) => setVis((v) => ({ ...v, [k]: !v[k] }));

  const CHIPS: { key: MetricKey; label: string; color: string; kind: "area" | "bar" | "line" | "dash" }[] = [
    { key: "sentiment", label: zh ? "净情绪" : "Net sentiment", color: GREEN, kind: "area" },
    { key: "volume", label: zh ? "讨论度" : "Volume", color: VOL, kind: "bar" },
    { key: "newcomers", label: zh ? newLabel.zh : newLabel.en, color: NEW, kind: "bar" },
    { key: "smart", label: zh ? "聪明钱" : "Smart $", color: SMART, kind: "line" },
    { key: "retail", label: zh ? "散户" : "Retail", color: RETAIL, kind: "dash" },
  ];

  const option = useMemo(() => {
    const series: any[] = [];
    const markPt = (data: any[], yIdx: number) => ({
      type: "scatter", data, yAxisIndex: yIdx, symbol: "diamond", symbolSize: 9,
      itemStyle: { color: GOLD, borderColor: "#141414", borderWidth: 1 },
      label: { show: true, position: "top", distance: 3, formatter: "⚑", color: GOLD, fontSize: 11 },
      emphasis: { scale: 1.4 }, tooltip: { show: false }, silent: true, z: 12,
    });
    if (on("volume")) series.push({
      name: "vol", type: "bar", yAxisIndex: 1, data: prep.volTotal,
      itemStyle: { color: VOL, opacity: 0.34, borderRadius: [2, 2, 0, 0] }, barMaxWidth: 16, barGap: "10%", z: 2,
    });
    if (on("newcomers")) series.push({
      name: "new", type: "bar", yAxisIndex: 2, data: prep.newTotal,
      itemStyle: { color: NEW, opacity: 0.5, borderRadius: [2, 2, 0, 0] }, barMaxWidth: 11, barGap: "10%", z: 3,
    });
    if (on("sentiment")) {
      series.push({
        name: "sentG", type: "line", yAxisIndex: 0, data: prep.green, smooth: 0.35, symbol: "none", connectNulls: true,
        lineStyle: { width: 2, color: GREEN }, areaStyle: { color: GREEN, opacity: 0.42, origin: "auto" }, z: 4,
        markLine: { silent: true, symbol: "none", lineStyle: { color: "rgba(127,127,127,0.35)", width: 1, type: "dashed" }, label: { show: false }, data: [{ yAxis: 0 }] },
      });
      series.push({
        name: "sentR", type: "line", yAxisIndex: 0, data: prep.red, smooth: 0.35, symbol: "none", connectNulls: true,
        lineStyle: { width: 2, color: RED }, areaStyle: { color: RED, opacity: 0.42, origin: "auto" }, z: 4,
      });
      if (prep.sentMk.length) series.push(markPt(prep.sentMk, 0));
    }
    if (on("volume") && prep.volMk.length) series.push(markPt(prep.volMk, 1));
    if (on("smart")) series.push({ name: "smart", type: "line", yAxisIndex: 3, data: prep.smart, smooth: 0.3, symbol: "none", connectNulls: true, lineStyle: { width: 2.2, color: SMART }, z: 6 });
    if (on("retail")) series.push({ name: "retail", type: "line", yAxisIndex: 3, data: prep.retail, smooth: 0.3, symbol: "none", connectNulls: true, lineStyle: { width: 1.8, color: RETAIL, type: "dashed" }, z: 5 });

    const hiddenY = (extra: any) => ({ type: "value", show: false, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false }, splitLine: { show: false }, ...extra });
    return {
      backgroundColor: "transparent",
      grid: { left: 6, right: 10, top: 16, bottom: 22, containLabel: true },
      tooltip: {
        trigger: "axis", axisPointer: { type: "line", lineStyle: { color: "rgba(127,127,127,0.3)", width: 1 } },
        backgroundColor: "rgba(20,20,20,0.96)", borderColor: "#2a2d2f", borderWidth: 1, padding: [9, 11],
        textStyle: { color: "#e5e5e5", fontSize: 11 }, extraCssText: "border-radius:10px;box-shadow:0 8px 28px rgba(0,0,0,0.5)",
        formatter: (ps: any) => {
          const day = ps?.[0]?.axisValue;
          if (!day) return "";
          const lines: string[] = [];
          if (on("sentiment") && prep.sentByDay.has(day)) {
            const v = prep.sentByDay.get(day) as number;
            lines.push(`<span style="color:${v >= 0 ? GREEN : RED}">●</span> ${zh ? "净情绪" : "Net sent."} <b>${v >= 0 ? "+" : ""}${v}</b>`);
          }
          if (on("volume")) {
            const r = prep.volByDay.get(day);
            const total = +(r?.total ?? 0) || 0;
            lines.push(`<span style="color:${VOL}">▮</span> ${zh ? "讨论度" : "Volume"} <b>${fmtCompact(total)}</b>`);
            if (r) {
              const bd = volStack.filter((s) => (+(r[s.key] ?? 0) || 0) > 0).map((s) => `<span style="color:${s.color}">${zh ? s.zh : s.en} ${fmtCompact(+(r[s.key] ?? 0) || 0)}</span>`).join(" · ");
              if (bd) lines.push(`<span style="color:#9aa0a6;font-size:10px;margin-left:14px">${bd}</span>`);
            }
          }
          if (on("newcomers")) {
            const r = prep.newByDay.get(day);
            const total = +(r?.total ?? 0) || 0;
            lines.push(`<span style="color:${NEW}">▮</span> ${zh ? newLabel.zh : newLabel.en} <b>${fmtCompact(total)}</b>`);
            if (r) {
              const bd = newStack.filter((s) => (+(r[s.key] ?? 0) || 0) > 0).map((s) => `<span style="color:${s.color}">${zh ? s.zh : s.en} ${fmtCompact(+(r[s.key] ?? 0) || 0)}</span>`).join(" · ");
              if (bd) lines.push(`<span style="color:#9aa0a6;font-size:10px;margin-left:14px">${bd}</span>`);
            }
          }
          if (on("smart") && prep.drvByDay.has(day)) lines.push(`<span style="color:${SMART}">◆</span> ${zh ? "聪明钱" : "Smart $"} <b>${prep.drvByDay.get(day)!.smart.toFixed(2)}</b>`);
          if (on("retail") && prep.drvByDay.has(day)) lines.push(`<span style="color:${RETAIL}">◇</span> ${zh ? "散户" : "Retail"} <b>${prep.drvByDay.get(day)!.retail.toFixed(2)}</b>`);
          let html = `<b>${mmdd(day)}</b><br/>${lines.join("<br/>")}`;
          const a = prep.anomByDay.get(day);
          const reasons = [on("sentiment") ? a?.sent : "", on("volume") ? a?.vol : ""].filter(Boolean);
          if (reasons.length) html += `<div style="margin-top:6px;max-width:240px;white-space:normal;border-top:1px solid #2a2d2f;padding-top:5px"><span style="color:${GOLD}">⚑ ${zh ? "AI 异动归因" : "AI anomaly"}</span><br/><span style="color:#cfcfcf">${reasons.join("；")}</span></div>`;
          return html;
        },
      },
      xAxis: {
        type: "category", data: cats, boundaryGap: true,
        axisLine: { show: false }, axisTick: { show: false },
        axisLabel: { color: "#73757a", fontSize: 10, margin: 10, formatter: (v: string) => mmdd(v) },
      },
      yAxis: [
        hiddenY({ scale: true }),                 // 0 净情绪
        hiddenY({ min: 0 }),                       // 1 讨论度
        hiddenY({ min: 0 }),                       // 2 新增
        hiddenY({ min: -1.15, max: 1.15 }),        // 3 聪明钱/散户（归一）
      ],
      series,
    };
  }, [cats, prep, vis, avail, zh, volStack, newStack, newLabel]);

  const chips = CHIPS.filter((c) => avail[c.key]);
  if (!chips.length) return <p className="px-1 py-4 text-[12px] text-neutral-600">{zh ? "暂无整体数据" : "No data yet"}</p>;

  const sm = divergence ? STANCE[divergence.read.smart] ?? STANCE.neutral : null;
  const rt = divergence ? STANCE[divergence.read.retail] ?? STANCE.neutral : null;

  return (
    <div className="mt-1">
      {/* 聪明钱 vs 散户 一句话判读（背离=机会信号）*/}
      {divergence && sm && rt && (
        <div className="mb-2 flex flex-wrap items-center gap-2 px-1 text-[11.5px]">
          <span className="font-semibold text-neutral-400">{zh ? "聪明钱 vs 散户" : "Smart $ vs retail"}</span>
          <span className="inline-flex items-center gap-1"><span className="h-2 w-2 rounded-full" style={{ background: SMART }} />{zh ? "聪明钱" : "Smart $"} <b style={{ color: sm.color }}>{zh ? sm.zh : sm.en}</b></span>
          <span className="text-neutral-700">·</span>
          <span className="inline-flex items-center gap-1"><span className="h-2 w-2 rounded-full" style={{ background: RETAIL }} />{zh ? "散户" : "Retail"} <b style={{ color: rt.color }}>{zh ? rt.zh : rt.en}</b></span>
          <span className={`rounded px-1.5 py-0.5 text-[10px] font-medium ring-1 ring-inset ${divergence.read.diverging ? "bg-[#F2B544]/12 text-[#F2B544] ring-[#F2B544]/30" : "bg-white/[.04] text-neutral-400 ring-line"}`}>
            {divergence.read.diverging ? (zh ? "⚠ 背离(机会)" : "⚠ Diverging") : (zh ? "一致" : "Aligned")}
          </span>
        </div>
      )}

      {/* 指标开关 chips */}
      <div className="mb-2 flex flex-wrap items-center gap-2 px-1">
        {chips.map((c) => {
          const active = vis[c.key];
          const swatch =
            c.kind === "bar"
              ? <span className="h-2.5 w-2.5 rounded-[2px]" style={{ background: c.color, opacity: active ? 1 : 0.5 }} />
              : <span className="inline-block w-3.5" style={{ borderTop: `2px ${c.kind === "dash" ? "dashed" : "solid"} ${c.color}`, opacity: active ? 1 : 0.5 }} />;
          return (
            <button
              key={c.key}
              onClick={() => toggle(c.key)}
              className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-medium ring-1 ring-inset transition"
              style={{
                borderColor: "transparent",
                background: active ? `${c.color}1f` : "transparent",
                boxShadow: `inset 0 0 0 1px ${active ? c.color : "#2a2d2f"}`,
                color: active ? "#F1F3F4" : "#73757a",
              }}
            >
              {swatch}{c.label}
            </button>
          );
        })}
        <span className="ml-auto text-[10.5px] text-neutral-600">{zh ? "悬停某日读全部数值 · 各指标各自缩放" : "hover a day for all values · each metric self-scaled"}</span>
      </div>

      <ReactECharts
        option={option}
        style={{ height: 280, width: "100%" }}
        opts={{ renderer: "canvas" }}
        onChartReady={(c: any) => { requestAnimationFrame(() => { try { c.resize(); } catch {} }); }}
        notMerge
      />
    </div>
  );
}
