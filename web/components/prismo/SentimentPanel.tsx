"use client";

// KOL 模块里的「每日净情绪」折线子面板（Kaito 风）：绿(>0 偏多) 在上 / 红(<0 偏空) 在下，各自从 y=0 起填充。
// 数据 = kol_sentiment_daily 的 net（跨平台 情绪×ln(1+互动)×相关性 加权净值）。展示完整近 2 周（价格图已上移页头、无区间滑块）。
import { useMemo } from "react";
import ReactECharts from "echarts-for-react";
import { useLocale } from "@/components/i18n/LocaleProvider";

const mmdd = (d: string) => {
  const [, m, dd] = (d || "").split("-");
  return m ? `${+m}/${+dd}` : "";
};

// 异动标记：当天净情绪偏离基线（pipeline overall_signals 产出），金色 ⚑ 标在折线上、hover 出 AI 归因。
export interface ChartMarker { day: string; direction?: "up" | "down"; reason: { zh: string; en: string } }
const GOLD = "#F2B544";

export function SentimentPanel({
  days, data, markers,
}: {
  days: { day: string }[];
  data: { day: string; net: number }[];
  markers?: ChartMarker[];
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";

  const { series, hasData } = useMemo(() => {
    const m = new Map(data.map((d) => [d.day, d.net]));
    const s = days.map((c) => +(m.get(c.day) ?? 0).toFixed(2));
    return { series: s, hasData: data.some((d) => Math.abs(d.net) > 1e-6) };
  }, [days, data]);

  // 异动日 → 归因（按 x 轴的交易日匹配；不在轴上的日子丢弃）+ 标记散点 [day, 当天净值]
  const { markerMap, markerData } = useMemo(() => {
    const idx = new Map(days.map((c, i) => [c.day, i]));
    const mm = new Map<string, ChartMarker>();
    const md: { value: [string, number] }[] = [];
    for (const mk of markers ?? []) {
      const i = idx.get(mk.day);
      if (i == null) continue;
      mm.set(mk.day, mk);
      md.push({ value: [mk.day, series[i] ?? 0] });
    }
    return { markerMap: mm, markerData: md };
  }, [days, series, markers]);

  const option = useMemo(() => {
    // y 轴**贴合数据**（始终含 0 当绿/红基线）：避免对称轴把单边曲线压扁、半屏空白
    const lo = Math.min(0, ...series);
    const hi = Math.max(0, ...series);
    const span = hi - lo || 1;
    const yMin = lo - span * 0.08;
    const yMax = hi + span * 0.08;
    return {
      backgroundColor: "transparent",
      grid: { left: 4, right: 16, top: 8, bottom: 6, containLabel: true },
      tooltip: {
        trigger: "axis",
        backgroundColor: "rgba(20,20,20,0.96)",
        borderColor: "#2a2d2f",
        borderWidth: 1,
        textStyle: { color: "#e5e5e5", fontSize: 11 },
        extraCssText: "border-radius:8px",
        formatter: (ps: any) => {
          // 两条线在同一点各有一个值（其一被夹成 0）→ 取非零的那个作为真实净情绪（排除散点的数组值）
          const arr = ps || [];
          const nums = arr.filter((x: any) => typeof x.value === "number");
          const p = nums.find((x: any) => Math.abs(x.value) > 1e-9) ?? nums[0];
          const axisVal = arr[0]?.axisValue;
          if (!axisVal) return "";
          const v = (p?.value ?? 0) as number;
          const c = v >= 0 ? "#57D7BA" : "#FF5C6C";
          let html = `<b>${mmdd(axisVal)}</b><br/><span style="color:${c}">${zh ? "净情绪" : "Net sentiment"} ${v >= 0 ? "+" : ""}${v}</span>`;
          const mk = markerMap.get(axisVal);
          const r = mk && (zh ? mk.reason.zh : mk.reason.en);
          if (r) html += `<div style="margin-top:6px;max-width:240px;white-space:normal;border-top:1px solid #2a2d2f;padding-top:5px"><span style="color:${GOLD}">⚑ ${zh ? "异动归因" : "Why"}</span><br/><span style="color:#cfcfcf">${r}</span></div>`;
          return html;
        },
      },
      xAxis: {
        type: "category",
        data: days.map((c) => c.day),
        boundaryGap: false,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { show: false }, // 日期标签由上方/页头呈现，这里只显形状
      },
      yAxis: {
        type: "value",
        min: yMin,
        max: yMax,
        position: "right",
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: "#73757a", fontSize: 9.5, showMinLabel: false, showMaxLabel: true, formatter: (v: number) => (v > 0 ? "+" : "") + Math.round(v) },
        splitLine: { show: false },
      },
      // 两条 line：绿（取 ≥0 部分）+ 红（取 ≤0 部分），各自从 y=0 起填充 → Kaito 风绿上红下。
      series: [
        {
          type: "line",
          data: series.map((v) => (v >= 0 ? v : 0)),
          smooth: 0.35,
          symbol: "none",
          lineStyle: { width: 2, color: "#57D7BA" },
          areaStyle: { color: "#57D7BA", opacity: 0.5, origin: "auto" },
          z: 2,
        },
        {
          type: "line",
          data: series.map((v) => (v <= 0 ? v : 0)),
          smooth: 0.35,
          symbol: "none",
          lineStyle: { width: 2, color: "#FF5C6C" },
          areaStyle: { color: "#FF5C6C", opacity: 0.5, origin: "auto" },
          markLine: {
            silent: true,
            symbol: "none",
            lineStyle: { color: "rgba(127,127,127,0.4)", width: 1, type: "dashed" },
            label: { show: false },
            data: [{ yAxis: 0 }],
          },
          z: 2,
        },
        // 异动标记（金色 ⚑ 钻石）：落在异常日的净值上，hover 当天列即出 AI 归因
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
    };
  }, [days, series, zh, markerMap, markerData]);

  return (
    <div className="mt-1">
      <div className="mb-1 flex items-center gap-2 px-1">
        <span className="text-[11.5px] font-semibold text-neutral-400">{zh ? "每日净情绪" : "Daily net sentiment"}</span>
        <span className="text-[10.5px] text-neutral-600">{zh ? "各平台 情绪×热度×相关性 加权（绿=偏多 / 红=偏空）" : "weighted across platforms (green=bullish / red=bearish)"}</span>
      </div>
      {hasData ? (
        <ReactECharts
          option={option}
          style={{ height: 120, width: "100%" }}
          opts={{ renderer: "canvas" }}
          // 关键：水合时容器可能尚无宽度→canvas 渲染成 0 宽（空白）。挂载后强制 resize 修正。
          onChartReady={(c: any) => { requestAnimationFrame(() => { try { c.resize(); } catch {} }); }}
          notMerge
        />
      ) : (
        <p className="px-1 py-3 text-[12px] text-neutral-600">{zh ? "暂无情绪数据（待跑 kol-sentiment）" : "No sentiment data yet"}</p>
      )}
    </div>
  );
}
