"use client";

// 「每日讨论度」堆叠条状子面板：当天**讨论该标的的帖子 / 视频总量**，按平台堆叠。
// 平台层由 `stack`（VolStackItem[]）配置 → 同一面板既能渲染 KOL 口径(X/YouTube/Reddit/雪球)，
// 也能渲染整体散户口径(X/Reddit/雪球/Naver/YahooJP/PTT/Toss)。x 轴 = **逐日历日**（含周末，一日一柱，
// 不折叠 → 不系统性放大周五）；范围 = 与上方「每日净情绪」相同的 [首交易日, 末交易日]。
import { useMemo } from "react";
import ReactECharts from "echarts-for-react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import type { VolStackItem } from "./kolShared";
import type { ChartMarker } from "./SentimentPanel";
import { fmtCompact } from "@/lib/format";

const mmdd = (d: string) => {
  const [, m, dd] = (d || "").split("-");
  return m ? `${+m}/${+dd}` : "";
};
const GOLD = "#F2B544"; // 异动标记色（与情绪面板一致；区别于绿/红情绪）

// 通用「每日各平台计数」行：day + total + 任意平台键。DailyVol / RetailVol 均可直接传入。
export interface VolRow { day: string; total: number; [key: string]: number | string }

export function VolumePanel({
  days, data, stack, title, subtitle, unit, markers,
}: {
  days: { day: string }[];
  data: VolRow[];
  stack: VolStackItem[];
  title?: { zh: string; en: string }; // 子面板小标题（默认「每日讨论度」）
  subtitle?: { zh: string; en: string }; // 小标题旁灰字说明
  unit?: { zh: string; en: string }; // tooltip 合计后缀（如「位」；默认无）
  markers?: ChartMarker[]; // 讨论度异动标记（金色 ⚑ + AI 归因，hover 出）
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const ttl = title ? (zh ? title.zh : title.en) : zh ? "每日讨论度" : "Daily volume";
  const sub = subtitle
    ? (zh ? subtitle.zh : subtitle.en)
    : zh ? "各平台讨论该标的的帖子 / 视频数（堆叠）" : "posts / videos discussing this ticker (stacked)";
  const unitStr = unit ? ` ${zh ? unit.zh : unit.en}` : "";

  const { cats, stacks, hasData } = useMemo(() => {
    const start = days[0]?.day, end = days[days.length - 1]?.day;
    const empty: Record<string, number[]> = Object.fromEntries(stack.map((s) => [s.key, []]));
    if (!start || !end) return { cats: [] as string[], stacks: empty, hasData: false };
    // 枚举 [start, end] 内每一个日历日 → 均匀时间轴、一日一柱（含无数据日为 0）
    const cats: string[] = [];
    const d = new Date(start + "T00:00:00Z"), endD = new Date(end + "T00:00:00Z");
    while (d <= endD) { cats.push(d.toISOString().slice(0, 10)); d.setUTCDate(d.getUTCDate() + 1); }
    const idx = new Map(cats.map((c, i) => [c, i]));
    const n = cats.length;
    const st: Record<string, number[]> = Object.fromEntries(stack.map((s) => [s.key, Array(n).fill(0)]));
    let any = false;
    for (const r of data) {
      if (r.day < start || r.day > end) continue;
      const i = idx.get(r.day);
      if (i == null) continue;
      for (const s of stack) {
        const v = +(r[s.key] ?? 0) || 0;
        st[s.key][i] += v;
        if (v > 0) any = true;
      }
    }
    return { cats, stacks: st, hasData: any };
  }, [days, data, stack]);

  // 异动日 → 归因 + 标记散点 [day, 当天堆叠总高]（按日历日轴匹配；不在范围内的丢弃）
  const { markerMap, markerData } = useMemo(() => {
    const idx = new Map(cats.map((c, i) => [c, i]));
    const mm = new Map<string, ChartMarker>();
    const md: { value: [string, number] }[] = [];
    for (const mk of markers ?? []) {
      const i = idx.get(mk.day);
      if (i == null) continue;
      const total = stack.reduce((s, it) => s + (stacks[it.key]?.[i] ?? 0), 0);
      mm.set(mk.day, mk);
      md.push({ value: [mk.day, total] });
    }
    return { markerMap: mm, markerData: md };
  }, [cats, stacks, stack, markers]);

  const option = useMemo(() => ({
    backgroundColor: "transparent",
    grid: { left: 4, right: 16, top: 8, bottom: 6, containLabel: true }, // 左右与情绪面板一致 → 竖向对齐
    tooltip: {
      trigger: "axis",
      axisPointer: { type: "shadow" },
      backgroundColor: "rgba(20,20,20,0.96)",
      borderColor: "#2a2d2f",
      borderWidth: 1,
      textStyle: { color: "#e5e5e5", fontSize: 11 },
      extraCssText: "border-radius:8px",
      formatter: (ps: any) => {
        if (!ps?.length) return "";
        const bars = ps.filter((p: any) => typeof p.value === "number"); // 排除散点（其值为数组）
        const total = bars.reduce((s: number, p: any) => s + (p.value || 0), 0);
        const lines = bars
          .filter((p: any) => p.value > 0)
          .map((p: any) => `<span style="color:${p.color}">●</span> ${p.seriesName} <b>${fmtCompact(p.value)}</b>`)
          .join("<br/>");
        const axisVal = ps[0].axisValue;
        let html = `<b>${mmdd(axisVal)}</b> · ${zh ? "共" : "total"} ${fmtCompact(total)}${unitStr}<br/>${lines}`;
        const mk = markerMap.get(axisVal);
        const r = mk && (zh ? mk.reason.zh : mk.reason.en);
        if (r) html += `<div style="margin-top:6px;max-width:240px;white-space:normal;border-top:1px solid #2a2d2f;padding-top:5px"><span style="color:${GOLD}">⚑ ${zh ? "异动归因" : "Why"}</span><br/><span style="color:#cfcfcf">${r}</span></div>`;
        return html;
      },
    },
    xAxis: {
      type: "category",
      data: cats,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { show: false }, // 日期标签由页头/情绪面板呈现，这里只显形状
    },
    yAxis: {
      type: "value",
      position: "right",
      minInterval: 1,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: "#73757a", fontSize: 9.5, showMinLabel: false, showMaxLabel: true, formatter: (v: number) => fmtCompact(v) },
      splitLine: { show: false },
    },
    series: [
      ...stack.map((s, si) => ({
        name: zh ? s.zh : s.en,
        type: "bar",
        stack: "vol",
        data: stacks[s.key],
        itemStyle: { color: s.color, borderRadius: si === stack.length - 1 ? [2, 2, 0, 0] : 0 },
        barMaxWidth: 18,
      })),
      // 异动标记（金色 ⚑ 钻石）：落在当天堆叠柱顶，hover 当天列即出 AI 归因
      ...(markerData.length
        ? [{
            type: "scatter",
            data: markerData,
            symbol: "diamond",
            symbolSize: 9,
            itemStyle: { color: GOLD, borderColor: "#141414", borderWidth: 1 },
            label: { show: true, position: "top", distance: 3, formatter: "⚑", color: GOLD, fontSize: 11 },
            emphasis: { scale: 1.5 },
            tooltip: { show: false },
            z: 10,
          }]
        : []),
    ],
  }), [cats, stacks, stack, zh, unitStr, markerMap, markerData]);

  return (
    <div className="mt-2">
      <div className="mb-1 flex items-center gap-2 px-1">
        <span className="text-[11.5px] font-semibold text-neutral-400">{ttl}</span>
        <span className="text-[10.5px] text-neutral-600">{sub}</span>
      </div>
      {hasData ? (
        <ReactECharts
          option={option}
          style={{ height: 110, width: "100%" }}
          opts={{ renderer: "canvas" }}
          // 水合时容器可能尚无宽度→canvas 渲染成 0 宽（空白）。挂载后强制 resize 修正。
          onChartReady={(c: any) => { requestAnimationFrame(() => { try { c.resize(); } catch {} }); }}
          notMerge
        />
      ) : (
        <p className="px-1 py-3 text-[12px] text-neutral-600">{zh ? "暂无数据" : "No data yet"}</p>
      )}
    </div>
  );
}
