"use client";

import { useMemo } from "react";
import ReactECharts from "echarts-for-react";
import { fmtCompact } from "@/shared/formatting/format";
import type { DailyNet, WindowedArguments } from "@/server/queries/kolQueries";
import type { VolStackItem } from "../overallDataConstants";
import type { VolRow } from "../overallDataTypes";

const BULL = "#57D7BA";
const BEAR = "#FF5C6C";
const NEUTRAL = "#8A8D91";
const GOLD = "#F2B544";
const GRID = "rgba(127,127,127,0.11)";
const AXIS = "#73757a";
const LINE = "#343A42";
const TIP_BG = "#20242A";
const TIP = {
  backgroundColor: TIP_BG,
  borderColor: LINE,
  borderWidth: 1,
  padding: [8, 10],
  textStyle: { color: "#e5e5e5", fontSize: 11 },
  extraCssText: "border-radius:9px;box-shadow:0 8px 24px rgba(0,0,0,0.32)",
};

const md = (day: string) => {
  const [, m, d] = (day || "").split("-");
  return m ? `${+m}/${+d}` : day;
};
const monthTick = (day: string) => (day.endsWith("-01") ? `${+day.slice(5, 7)}月` : "");
const last = <T,>(rows: T[], n = 93) => rows.slice(Math.max(0, rows.length - n));

function Panel({
  title,
  hint,
  children,
}: {
  title: string;
  hint: string;
  children: React.ReactNode;
}) {
  return (
    <section className="min-h-0 rounded-lg bg-ink/35 p-3 ring-1 ring-inset ring-line">
      <div className="mb-2 flex min-h-[18px] items-center justify-between gap-3">
        <h3 className="truncate text-[11.5px] font-semibold text-neutral-300">{title}</h3>
        <span className="shrink-0 text-[10px] text-neutral-600">{hint}</span>
      </div>
      {children}
    </section>
  );
}

function Empty({ zh }: { zh: boolean }) {
  return <div className="grid h-[154px] place-items-center text-[12px] text-neutral-600">{zh ? "暂无数据" : "No data"}</div>;
}

export function BullBearStructureChart({ data, zh }: { data: DailyNet[]; zh: boolean }) {
  const rows = useMemo(() => last(data.filter((d) => d.nPosts > 0)), [data]);
  const option = useMemo(() => {
    const days = rows.map((r) => r.day);
    const raw = rows.map((r) => {
      const neutral = Math.max(0, r.nPosts - r.nBull - r.nBear);
      const total = Math.max(1, r.nBull + r.nBear + neutral);
      return {
        bull: r.nBull,
        bear: r.nBear,
        neutral,
        bullPct: +(r.nBull / total * 100).toFixed(1),
        bearPct: +(r.nBear / total * 100).toFixed(1),
        neutralPct: +(neutral / total * 100).toFixed(1),
      };
    });
    return {
      backgroundColor: "transparent",
      grid: { left: 2, right: 4, top: 8, bottom: 18, containLabel: true },
      tooltip: {
        trigger: "axis",
        axisPointer: { type: "shadow" },
        ...TIP,
        formatter: (ps: any[]) => {
          const idx = ps?.[0]?.dataIndex ?? 0;
          const r = raw[idx];
          return `<b>${md(days[idx])}</b><br/><span style="color:${BULL}">●</span> ${zh ? "看多" : "Bull"} <b>${r.bull}</b> · ${r.bullPct}%<br/><span style="color:${NEUTRAL}">●</span> ${zh ? "中性" : "Neutral"} <b>${r.neutral}</b> · ${r.neutralPct}%<br/><span style="color:${BEAR}">●</span> ${zh ? "看空" : "Bear"} <b>${r.bear}</b> · ${r.bearPct}%`;
        },
      },
      xAxis: {
        type: "category",
        data: days,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: AXIS, fontSize: 9, interval: 0, formatter: monthTick },
      },
      yAxis: {
        type: "value",
        min: 0,
        max: 100,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { show: false },
        splitLine: { lineStyle: { color: GRID } },
      },
      series: [
        { name: zh ? "看多" : "Bull", type: "bar", stack: "stance", data: raw.map((r) => r.bullPct), itemStyle: { color: BULL, opacity: 0.92 }, barMaxWidth: 10 },
        { name: zh ? "中性" : "Neutral", type: "bar", stack: "stance", data: raw.map((r) => r.neutralPct), itemStyle: { color: NEUTRAL, opacity: 0.38 }, barMaxWidth: 10 },
        { name: zh ? "看空" : "Bear", type: "bar", stack: "stance", data: raw.map((r) => r.bearPct), itemStyle: { color: BEAR, opacity: 0.9 }, barMaxWidth: 10 },
      ],
    };
  }, [rows, zh]);

  return (
    <Panel title={zh ? "多空结构" : "Bull / bear structure"} hint={zh ? "近 3 月 · 占比" : "3M · share"}>
      {rows.length ? <ReactECharts option={option} style={{ height: 154, width: "100%" }} opts={{ renderer: "canvas" }} notMerge /> : <Empty zh={zh} />}
    </Panel>
  );
}

export function CrowdingChart({
  newcomers,
  volume,
  stack,
  zh,
}: {
  newcomers: VolRow[];
  volume: VolRow[];
  stack: VolStackItem[];
  zh: boolean;
}) {
  const rows = useMemo(() => last(newcomers.filter((r) => r.total > 0)), [newcomers]);
  const volMap = useMemo(() => new Map(volume.map((r) => [r.day, r])), [volume]);
  const activeStack = useMemo(
    () => stack.filter((s) => rows.some((r) => +(r[s.key] ?? 0) > 0)),
    [rows, stack]
  );
  const option = useMemo(() => {
    const days = rows.map((r) => r.day);
    const ratio = rows.map((r) => {
      const v = +(volMap.get(r.day)?.total ?? 0) || 0;
      return v > 0 ? +(Math.min(2, r.total / v) * 100).toFixed(1) : 0;
    });
    return {
      backgroundColor: "transparent",
      grid: { left: 2, right: 26, top: 8, bottom: 18, containLabel: true },
      tooltip: {
        trigger: "axis",
        axisPointer: { type: "shadow" },
        ...TIP,
        formatter: (ps: any[]) => {
          const idx = ps?.[0]?.dataIndex ?? 0;
          const r = rows[idx];
          const parts = activeStack
            .filter((s) => +(r[s.key] ?? 0) > 0)
            .map((s) => `<span style="color:${s.color}">${zh ? s.zh : s.en} ${fmtCompact(+(r[s.key] ?? 0))}</span>`)
            .join(" · ");
          return `<b>${md(days[idx])}</b><br/>${zh ? "新增参与者" : "New participants"} <b>${fmtCompact(r.total)}</b><br/>${zh ? "拥挤度" : "Crowding"} <b>${ratio[idx]}%</b>${parts ? `<br/><span style="font-size:10px;color:#9aa0a6">${parts}</span>` : ""}`;
        },
      },
      xAxis: {
        type: "category",
        data: days,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: AXIS, fontSize: 9, interval: 0, formatter: monthTick },
      },
      yAxis: [
        {
          type: "value",
          min: 0,
          axisLine: { show: false },
          axisTick: { show: false },
          axisLabel: { show: false },
          splitLine: { lineStyle: { color: GRID } },
        },
        {
          type: "value",
          min: 0,
          axisLine: { show: false },
          axisTick: { show: false },
          axisLabel: { color: AXIS, fontSize: 9, formatter: "{value}%" },
          splitLine: { show: false },
        },
      ],
      series: [
        ...activeStack.map((s) => ({
          name: zh ? s.zh : s.en,
          type: "bar",
          stack: "new",
          data: rows.map((r) => +(r[s.key] ?? 0) || 0),
          itemStyle: { color: s.color, opacity: 0.75, borderRadius: [2, 2, 0, 0] },
          barMaxWidth: 10,
        })),
        {
          name: zh ? "拥挤度" : "Crowding",
          type: "line",
          yAxisIndex: 1,
          data: ratio,
          smooth: 0.25,
          symbol: "none",
          lineStyle: { color: GOLD, width: 1.8 },
        },
      ],
    };
  }, [activeStack, rows, volMap, zh]);

  return (
    <Panel title={zh ? "新增参与者 / 拥挤度" : "New participants / crowding"} hint={zh ? "近 3 月" : "3M"}>
      {rows.length ? <ReactECharts option={option} style={{ height: 154, width: "100%" }} opts={{ renderer: "canvas" }} notMerge /> : <Empty zh={zh} />}
    </Panel>
  );
}

const LENSES = [
  { key: "valuation", zh: "估值", en: "Valuation" },
  { key: "growth", zh: "成长", en: "Growth" },
  { key: "competition", zh: "竞争", en: "Competition" },
  { key: "management", zh: "管理层", en: "Management" },
  { key: "macro", zh: "宏观", en: "Macro" },
  { key: "catalyst", zh: "催化", en: "Catalyst" },
  { key: "flows", zh: "资金", en: "Flows" },
] as const;

export function ViewpointStanceChart({ data, zh }: { data?: WindowedArguments; zh: boolean }) {
  const rows = useMemo(() => {
    const win = data?.["14d"] ?? data?.["1mo"] ?? data?.["7d"] ?? data?.[Object.keys(data ?? {})[0] ?? ""];
    return LENSES.map((lens) => {
      const g = win?.[lens.key];
      const sum = (stance: "bull" | "neutral" | "bear") =>
        (g?.[stance].args ?? []).reduce((s, a) => s + (a.supportCount || a.supporters.length || 1), 0);
      return {
        label: zh ? lens.zh : lens.en,
        bull: sum("bull"),
        neutral: sum("neutral"),
        bear: sum("bear"),
      };
    }).filter((r) => r.bull + r.neutral + r.bear > 0);
  }, [data, zh]);

  const option = useMemo(() => {
    const shown = [...rows].reverse();
    return {
      backgroundColor: "transparent",
      grid: { left: 2, right: 8, top: 4, bottom: 6, containLabel: true },
      tooltip: {
        trigger: "axis",
        axisPointer: { type: "shadow" },
        ...TIP,
        formatter: (ps: any[]) => {
          const idx = ps?.[0]?.dataIndex ?? 0;
          const r = shown[idx];
          return `<b>${r.label}</b><br/><span style="color:${BULL}">●</span> ${zh ? "看多" : "Bull"} <b>${r.bull}</b><br/><span style="color:${NEUTRAL}">●</span> ${zh ? "中性" : "Neutral"} <b>${r.neutral}</b><br/><span style="color:${BEAR}">●</span> ${zh ? "看空" : "Bear"} <b>${r.bear}</b>`;
        },
      },
      xAxis: {
        type: "value",
        min: 0,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { show: false },
        splitLine: { lineStyle: { color: GRID } },
      },
      yAxis: {
        type: "category",
        data: shown.map((r) => r.label),
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: AXIS, fontSize: 10 },
      },
      series: [
        { name: zh ? "看多" : "Bull", type: "bar", stack: "view", data: shown.map((r) => r.bull), itemStyle: { color: BULL, opacity: 0.9 }, barMaxWidth: 12 },
        { name: zh ? "中性" : "Neutral", type: "bar", stack: "view", data: shown.map((r) => r.neutral), itemStyle: { color: NEUTRAL, opacity: 0.38 }, barMaxWidth: 12 },
        { name: zh ? "看空" : "Bear", type: "bar", stack: "view", data: shown.map((r) => r.bear), itemStyle: { color: BEAR, opacity: 0.9 }, barMaxWidth: 12 },
      ],
    };
  }, [rows, zh]);

  return (
    <Panel title={zh ? "观点视角 × 多空" : "Viewpoint × stance"} hint={zh ? "14 天" : "14D"}>
      {rows.length ? <ReactECharts option={option} style={{ height: 154, width: "100%" }} opts={{ renderer: "canvas" }} notMerge /> : <Empty zh={zh} />}
    </Panel>
  );
}
