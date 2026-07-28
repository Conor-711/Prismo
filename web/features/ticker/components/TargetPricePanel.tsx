"use client";

// 「整体数据」底部子面板：KOL 买入/卖出(目标)价位 时间线。
//   x = 下达日期、y = 价格，叠**真实股价折线**；买入=青、卖出·目标=珊瑚；区间=竖条，单一价位=圆点。
//   同一天多条：y 按价位纵向分开 + 小幅左右抖动 + 半透明叠加(重叠=共识)。现价虚线基准。
//   悬浮 tooltip 出详情：作者 / 平台·日期 / 价位(±现价%) / 操作周期(短中长+原话) / 简单依据。
import { useMemo, useState } from "react";
import ReactECharts from "echarts-for-react";
import type { KolSource, KolTargetData, TargetMark } from "@/shared/market/mockDetail";
import { SOURCE } from "@/shared/market/kolPresentation";

const BUY = "#57D7BA";
const SELL = "#FF5C6C";
const LINE = "#343A42";
const TIP_BG = "#20242A";
const CHART_BG = "#17191C";
const fmtPrice = (n: number) => (n >= 10 ? Math.round(n).toLocaleString() : String(+n.toFixed(2)));
const fmtRange = (lo: number, hi: number) => (hi > lo ? `$${fmtPrice(lo)}–$${fmtPrice(hi)}` : `$${fmtPrice(lo)}`);
const BUCKET_ZH: Record<string, string> = { short: "短线", mid: "中线", long: "长线" };
const BUCKET_EN: Record<string, string> = { short: "short", mid: "mid", long: "long" };
const mmdd = (ds: string) => { const [, m, d] = (ds || "").split("-"); return m ? `${+m}/${+d}` : ds; };
const DEFAULT_PRICE_ZOOM = 2;
const BUCKETS = ["short", "mid", "long"] as const;
const PLATFORM_ORDER: KolSource[] = ["x", "youtube", "reddit", "xueqiu", "toss", "yahoojp"];
const RECENCY_OPTIONS = [1, 3, 7, 14, 30, 60, 90] as const;
type BucketFilter = "all" | (typeof BUCKETS)[number];
type SourceFilter = "all" | KolSource;
type RecencyFilter = (typeof RECENCY_OPTIONS)[number];
type SvFilter = "top5" | "top10" | "top25" | "top50" | "scored" | "all";

const shiftDay = (day: string, delta: number) => {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return date.toISOString().slice(0, 10);
};

// 同一天多条 → 稳定左右抖动（±0.15 天），按作者+侧+价位散开，避免重叠成一团。
function jitterMs(m: TargetMark): number {
  const k = `${m.author}${m.kind}${m.lo}`;
  let h = 0;
  for (let i = 0; i < k.length; i++) h = (h * 31 + k.charCodeAt(i)) >>> 0;
  return ((h % 1000) / 1000 - 0.5) * 0.3 * 864e5;
}

function TargetDistributionChart({ marks, current, zh }: { marks: TargetMark[]; current: number | null; zh: boolean }) {
  const option = useMemo(() => {
    const points = marks.map((m) => ({ mark: m, mid: (m.lo + m.hi) / 2 })).filter((p) => p.mid > 0);
    const prices = [...points.map((p) => p.mid), ...(current ? [current] : [])];
    if (!points.length || !prices.length) return { backgroundColor: "transparent" };
    const rawMin = Math.min(...prices);
    const rawMax = Math.max(...prices);
    const span = rawMax - rawMin || rawMax * 0.2 || 1;
    const min = Math.max(0, rawMin - span * 0.12);
    const max = rawMax + span * 0.12;
    const binCount = Math.max(4, Math.min(9, Math.ceil(Math.sqrt(points.length) * 1.8)));
    const step = (max - min) / binCount || 1;
    const labels = Array.from({ length: binCount }, (_, i) => {
      const a = min + step * i;
      const b = i === binCount - 1 ? max : min + step * (i + 1);
      return `$${fmtPrice(a)}–${fmtPrice(b)}`;
    });
    const buy = Array(binCount).fill(0);
    const sell = Array(binCount).fill(0);
    for (const p of points) {
      const idx = Math.max(0, Math.min(binCount - 1, Math.floor((p.mid - min) / step)));
      if (p.mark.kind === "buy") buy[idx] += 1;
      else sell[idx] += 1;
    }
    const currentIdx = current ? Math.max(0, Math.min(binCount - 1, Math.floor((current - min) / step))) : null;
    return {
      backgroundColor: "transparent",
      grid: { left: 6, right: 12, top: 8, bottom: 28, containLabel: true },
      tooltip: {
        trigger: "axis",
        axisPointer: { type: "shadow" },
        backgroundColor: TIP_BG,
        borderColor: LINE,
        borderWidth: 1,
        textStyle: { color: "#e5e5e5", fontSize: 11 },
        extraCssText: "border-radius:8px;max-width:240px;white-space:normal",
        formatter: (ps: any[]) => {
          const idx = ps?.[0]?.dataIndex ?? 0;
          return `<b>${labels[idx]}</b><br/><span style="color:${BUY}">●</span> ${zh ? "买入" : "Buy"} <b>${buy[idx]}</b><br/><span style="color:${SELL}">●</span> ${zh ? "卖出/目标" : "Sell/target"} <b>${sell[idx]}</b>${currentIdx === idx ? `<br/><span style="color:#9a9da1">${zh ? "现价所在区间" : "Current price bin"}</span>` : ""}`;
        },
      },
      xAxis: {
        type: "category",
        data: labels,
        axisLine: { lineStyle: { color: LINE } },
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
          itemStyle: { color: BUY, opacity: 0.82, borderRadius: [2, 2, 0, 0] },
          barMaxWidth: 18,
          markLine: currentIdx != null ? {
            silent: true,
            symbol: "none",
            lineStyle: { color: "#9a9da1", type: "dashed", width: 1 },
            label: { color: "#c2c4c7", fontSize: 9, formatter: `${zh ? "现价" : "Now"} $${fmtPrice(current!)}` },
            data: [{ xAxis: labels[currentIdx] }],
          } : undefined,
        },
        {
          name: zh ? "卖出/目标" : "Sell/target",
          type: "bar",
          data: sell,
          itemStyle: { color: SELL, opacity: 0.82, borderRadius: [2, 2, 0, 0] },
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
        onChartReady={(c: any) => { requestAnimationFrame(() => { try { c.resize(); } catch {} }); }}
        notMerge
      />
    </div>
  );
}

export function TargetPricePanel({ data, zh }: { data: KolTargetData; zh: boolean }) {
  const { current, priceLine, marks } = data;
  const [bucket, setBucket] = useState<BucketFilter>("all");
  const [source, setSource] = useState<SourceFilter>("all");
  const [recency, setRecency] = useState<RecencyFilter>(30);
  const [svFilter, setSvFilter] = useState<SvFilter>("top25");

  const anchorDay = useMemo(
    () => [...priceLine.map((p) => p.day), ...marks.map((m) => m.date)].sort().at(-1) ?? new Date().toISOString().slice(0, 10),
    [priceLine, marks]
  );
  const cutoffDay = useMemo(() => shiftDay(anchorDay, -(recency - 1)), [anchorDay, recency]);

  const sourceOptions = useMemo(
    () => PLATFORM_ORDER.filter((s) => marks.some((m) => m.source === s)),
    [marks]
  );
  const filteredMarks = useMemo(
    () => marks.filter((m) => {
      if (m.date < cutoffDay || m.date > anchorDay) return false;
      if (bucket !== "all" && m.bucket !== bucket) return false;
      if (source !== "all" && m.source !== source) return false;
      if (svFilter === "all") return true;
      if (m.svPercentile == null) return false;
      if (svFilter === "scored") return true;
      const percentileCut = { top5: 5, top10: 10, top25: 25, top50: 50 }[svFilter];
      return m.svPercentile <= percentileCut;
    }),
    [marks, cutoffDay, anchorDay, bucket, source, svFilter]
  );
  const filteredPriceLine = useMemo(
    () => priceLine.filter((point) => point.day >= cutoffDay && point.day <= anchorDay),
    [priceLine, cutoffDay, anchorDay]
  );

  const option = useMemo(() => {
    const lineData = filteredPriceLine.map((p) => [+new Date(p.day), p.close] as [number, number]);
    const markData = filteredMarks.map((m) => ({
      value: [+new Date(m.date) + jitterMs(m), m.lo, m.hi],
      opinionId: m.opinionId,
      date: m.date,
    }));

    const tsAll = [...lineData.map((d) => d[0]), ...filteredMarks.map((m) => +new Date(m.date))].filter((n) => n > 0);
    const prices = [
      ...lineData.map((d) => d[1]),
      ...filteredMarks.flatMap((m) => [m.lo, m.hi]),
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
    const visibleSpan = fullSpan / DEFAULT_PRICE_ZOOM;
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
        backgroundColor: TIP_BG,
        borderColor: LINE,
        borderWidth: 1,
        textStyle: { color: "#e5e5e5", fontSize: 11 },
        extraCssText: "border-radius:8px;max-width:260px;white-space:normal",
        formatter: (p: any) => {
          const m: TargetMark | undefined = filteredMarks[p.dataIndex];
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
          if (m.svScore != null && m.svPercentile != null) {
            const top = Math.max(1, Math.ceil(m.svPercentile));
            html += `<div style="color:#57D7BA;margin-bottom:3px">SV <b>${Math.round(m.svScore)}</b> · ${zh ? `平台 Top ${top}%` : `Platform top ${top}%`}</div>`;
          }
          html += `<div><span style="color:#73757a">${kind} </span><b style="color:${color}">${fmtRange(m.lo, m.hi)}</b><span style="color:#73757a">${dl}</span></div>`;
          if (horizon || bk) html += `<div style="color:#cfcfcf;margin-top:2px">${zh ? "周期" : "Horizon"}: ${horizon}${bk ? `（${bk}）` : ""}</div>`;
          if (reason) html += `<div style="color:#aeb4bb;margin-top:3px;border-top:1px solid ${LINE};padding-top:4px">${reason.slice(0, 90)}</div>`;
          else if (m.priceRaw) html += `<div style="color:#6b6e72;margin-top:3px;font-size:10px">“${m.priceRaw}”</div>`;
          if (m.opinionId) html += `<div style="color:#57D7BA;margin-top:5px;font-size:10px">${zh ? "点击在右侧打开正文" : "Click to open the post here"}</div>`;
          return html;
        },
      },
      xAxis: {
        type: "time",
        min: tsAll.length ? Math.min(...tsAll) : undefined,
        max: tsAll.length ? Math.max(...tsAll) : undefined,
        axisLine: { lineStyle: { color: LINE } },
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
          type: "slider",
          yAxisIndex: 0,
          filterMode: "none",
          right: 4,
          top: 28,
          bottom: 22,
          width: 11,
          startValue: zoomStart,
          endValue: zoomEnd,
          zoomLock: false,
          showDataShadow: false,
          showDetail: false,
          brushSelect: false,
          borderColor: LINE,
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
            const m: TargetMark | undefined = filteredMarks[params.dataIndex];
            if (!m) return null;
            const color = m.kind === "buy" ? BUY : SELL;
            const ts = api.value(0);
            const pLo = api.coord([ts, api.value(1)]);
            const pHi = api.coord([ts, api.value(2)]);
            const h = Math.abs(pLo[1] - pHi[1]);
            if (h < 5) {
              return { type: "circle", cursor: "pointer", shape: { cx: pLo[0], cy: pLo[1], r: 4.5 }, style: { fill: color, stroke: CHART_BG, lineWidth: 1 } };
            }
            const w = 7;
            return {
              type: "group",
              cursor: "pointer",
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
  }, [filteredPriceLine, filteredMarks, current, zh]);

  if (!marks.length && !priceLine.length) return null;

  return (
    <div className="mt-4 border-t border-line/60 pt-3">
      <div className="mb-1 flex flex-wrap items-center gap-x-2 gap-y-1 px-1">
        <span className="text-[11.5px] font-semibold text-neutral-400">{zh ? "买入 / 卖出价 时间线" : "Buy / sell price timeline"}</span>
        <span className="text-[10.5px] text-neutral-600">
          {zh ? "默认近 1 月 SV Top 25% · 悬浮看作者/依据 · 右侧缩放价格轴" : "defaults to 1M SV top 25% · hover for evidence · right bar zooms price"}
        </span>
        <span className="ml-auto flex items-center gap-2.5 text-[10px] text-neutral-500">
          <span className="flex items-center gap-1"><span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: BUY }} />{zh ? "买入" : "Buy"}</span>
          <span className="flex items-center gap-1"><span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: SELL }} />{zh ? "卖出/目标" : "Sell/target"}</span>
          <span className="flex items-center gap-1"><span className="inline-block h-3 w-[5px] rounded-sm ring-1 ring-inset ring-neutral-500" />{zh ? "区间" : "range"}</span>
          <span className="flex items-center gap-1"><span className="inline-block h-px w-3 bg-neutral-500" />{zh ? "股价" : "price"}</span>
        </span>
      </div>
      <div className="mb-2 flex flex-wrap items-center gap-2 px-1">
        <div className="inline-flex rounded-md bg-elevated/50 p-0.5 text-[10.5px] ring-1 ring-inset ring-line">
          {RECENCY_OPTIONS.map((days) => (
            <button
              key={days}
              type="button"
              onClick={() => setRecency(days)}
              className={`min-w-10 rounded px-2 py-0.5 font-semibold transition ${recency === days ? "bg-card text-reddit ring-1 ring-inset ring-reddit/45" : "text-neutral-500 hover:text-neutral-300"}`}
            >
              {days === 14
                ? (zh ? "2周" : "2W")
                : days >= 30
                  ? `${days / 30}${zh ? "月" : "M"}`
                  : `${days}${zh ? "天" : "D"}`}
            </button>
          ))}
        </div>
        <div className="inline-flex rounded-md bg-elevated/50 p-0.5 text-[10.5px] ring-1 ring-inset ring-line">
          {([
            ["top5", "SV Top 5%", "SV Top 5%"],
            ["top10", "SV Top 10%", "SV Top 10%"],
            ["top25", "SV Top 25%", "SV Top 25%"],
            ["top50", "SV Top 50%", "SV Top 50%"],
            ["scored", "有 SV", "Scored"],
            ["all", "全部作者", "All authors"],
          ] as const).map(([value, labelZh, labelEn]) => (
            <button
              key={value}
              type="button"
              onClick={() => setSvFilter(value)}
              className={`rounded px-2 py-0.5 font-semibold transition ${svFilter === value ? "bg-card text-reddit ring-1 ring-inset ring-reddit/45" : "text-neutral-500 hover:text-neutral-300"}`}
            >
              {zh ? labelZh : labelEn}
            </button>
          ))}
        </div>
        <div className="inline-flex rounded-md bg-elevated/50 p-0.5 text-[10.5px] ring-1 ring-inset ring-line">
          <button
            type="button"
            onClick={() => setBucket("all")}
            className={`rounded px-2 py-0.5 font-semibold transition ${bucket === "all" ? "bg-card text-reddit ring-1 ring-inset ring-line" : "text-neutral-500 hover:text-neutral-300"}`}
          >
            {zh ? "全部周期" : "All horizons"}
          </button>
          {BUCKETS.map((b) => (
            <button
              key={b}
              type="button"
              onClick={() => setBucket(b)}
              className={`rounded px-2 py-0.5 font-semibold transition ${bucket === b ? "bg-card text-reddit ring-1 ring-inset ring-line" : "text-neutral-500 hover:text-neutral-300"}`}
            >
              {zh ? BUCKET_ZH[b] : BUCKET_EN[b]}
            </button>
          ))}
        </div>
        <div className="inline-flex rounded-md bg-elevated/50 p-0.5 text-[10.5px] ring-1 ring-inset ring-line">
          <button
            type="button"
            onClick={() => setSource("all")}
            className={`rounded px-2 py-0.5 font-semibold transition ${source === "all" ? "bg-card text-reddit ring-1 ring-inset ring-line" : "text-neutral-500 hover:text-neutral-300"}`}
          >
            {zh ? "全部平台" : "All sources"}
          </button>
          {sourceOptions.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => setSource(s)}
              className={`rounded px-2 py-0.5 font-semibold transition ${source === s ? "bg-card text-reddit ring-1 ring-inset ring-line" : "text-neutral-500 hover:text-neutral-300"}`}
            >
              {SOURCE[s].label}
            </button>
          ))}
        </div>
        <span className="ml-auto text-[10px] tabular-nums text-neutral-600">
          {zh ? `${filteredMarks.length} / ${marks.length} 条` : `${filteredMarks.length} / ${marks.length}`}
        </span>
      </div>
      {filteredMarks.length ? (
        <>
          <ReactECharts
            option={option}
            style={{ height: 250, width: "100%" }}
            opts={{ renderer: "canvas" }}
            onChartReady={(c: any) => { requestAnimationFrame(() => { try { c.resize(); } catch {} }); }}
            onEvents={{
              click: (p: any) => {
                if (p?.seriesName !== "marks" || !p?.data?.opinionId) return;
                window.dispatchEvent(new CustomEvent("prismo:open-opinion", {
                  detail: { opinionId: p.data.opinionId, day: p.data.date },
                }));
              },
            }}
            notMerge
          />
          <TargetDistributionChart marks={filteredMarks} current={current} zh={zh} />
        </>
      ) : (
        <div className="flex items-center justify-center gap-3 px-1 py-6 text-[12px] text-neutral-600">
          <span>
            {marks.length
              ? (zh ? "没有符合筛选的目标价" : "No target prices match the filters")
              : (zh ? "暂无明确买卖价位（KOL 多数只给方向、不给具体价位）" : "No explicit buy/sell prices yet")}
          </span>
          {marks.length > 0 && (
            <button
              type="button"
              onClick={() => {
                setRecency(90);
                setSvFilter("all");
                setBucket("all");
                setSource("all");
              }}
              className="rounded px-2 py-1 font-semibold text-reddit ring-1 ring-inset ring-reddit/45 transition hover:bg-reddit/10"
            >
              {zh ? "查看全部" : "Show all"}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
