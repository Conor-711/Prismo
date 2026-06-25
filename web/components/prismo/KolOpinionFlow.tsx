"use client";

// 「股价与观点结合的折线图」：横轴=日期（近 2 周），纵轴=股价折线；每个气泡=当天一条 KOL 观点，
// **以投资者头像呈现**——圆形头像 + 平台品牌圈色（X 黑 / YouTube 红 / Reddit 橙 / 雪球 蓝），
// 直径 ∝ 互动数；同一天的头像在价格点上做整齐竖向堆叠，超出上限折叠成 “+N”。**此图常驻**。
// 底部区间滑块(dataZoom)拖两个手柄选时间段，下方分类区只展示该区间观点。受控：range / vis 由父级持有。
import { useMemo } from "react";
import ReactECharts from "echarts-for-react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { fmtCompact } from "@/lib/format";
import type { KolCandle, KolOpinion, KolSource } from "@/lib/mockDetail";
import { SOURCE, SOURCE_ORDER, SOURCE_RING, STANCE, initialOf, mmdd, opinionText } from "./kolShared";

const N_PER_DAY = 5; // 单日最多展示几个头像，其余折叠成 “+N”
const MAX_COL = 232; // 单日头像列最大像素高度（超过则整体缩放，防溢出网格）
const GAP = 4; // 头像间距
const diameterOf = (n: number) => Math.max(20, Math.min(40, 18 + Math.sqrt(Math.max(0, n)) / 6));

interface Bubble {
  dayIdx: number;
  price: number;
  dy: number; // 相对价格点的竖向像素偏移（堆叠位置，与缩放无关）
  size: number;
  ring: string;
  avatar?: string;
  initial: string;
  op?: KolOpinion; // 真实头像气泡 → tooltip
  overflow?: number; // “+N” 折叠标记
}

export function KolOpinionFlow({
  days, opinions, range, onRangeChange, vis, onToggle,
}: {
  days: KolCandle[];
  opinions: KolOpinion[];
  range: [string, string]; // [起, 止]（含端点）
  onRangeChange: (r: [string, string]) => void;
  vis: Record<KolSource, boolean>;
  onToggle: (s: KolSource) => void;
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const closeByDay = useMemo(() => new Map(days.map((c) => [c.day, c.close])), [days]);
  const dayIndex = useMemo(() => new Map(days.map((c, i) => [c.day, i])), [days]);
  const n = days.length;
  const idxOf = (day: string, fb: number) => {
    const i = days.findIndex((d) => d.day === day);
    return i < 0 ? fb : i;
  };
  const i0 = idxOf(range[0], 0);
  const i1 = idxOf(range[1], n - 1);
  const startPct = n > 1 ? (Math.min(i0, i1) / (n - 1)) * 100 : 0;
  const endPct = n > 1 ? (Math.max(i0, i1) / (n - 1)) * 100 : 100;

  // 按天分组 → 每天按互动数降序、取前 N、整齐竖向堆叠（居中于价格点），其余折叠为 “+N”。
  const bubbles = useMemo(() => {
    const byDay = new Map<string, KolOpinion[]>();
    for (const o of opinions) {
      if (!vis[o.source] || !closeByDay.has(o.day)) continue;
      const arr = byDay.get(o.day);
      if (arr) arr.push(o);
      else byDay.set(o.day, [o]);
    }
    const out: Bubble[] = [];
    for (const [day, ops] of byDay) {
      const dayIdx = dayIndex.get(day)!;
      const price = closeByDay.get(day)!;
      ops.sort((a, b) => b.interactions - a.interactions);
      const shown = ops.slice(0, N_PER_DAY);
      const overflow = ops.length - shown.length;
      const pillH = overflow > 0 ? 16 : 0;
      let sizes = shown.map((o) => diameterOf(o.interactions));
      const raw = sizes.reduce((a, s) => a + s, 0) + GAP * (shown.length - 1) + (pillH ? pillH + GAP : 0);
      const scale = raw > MAX_COL ? MAX_COL / raw : 1;
      sizes = sizes.map((s) => s * scale);
      const gap = GAP * scale;
      const ph = pillH * scale;
      const total = sizes.reduce((a, s) => a + s, 0) + gap * (shown.length - 1) + (ph ? ph + gap : 0);
      let cursor = -total / 2;
      shown.forEach((o, i) => {
        const size = sizes[i];
        out.push({
          dayIdx, price, dy: cursor + size / 2, size,
          ring: SOURCE_RING[o.source], avatar: o.avatar, initial: initialOf(o.author), op: o,
        });
        cursor += size + gap;
      });
      if (overflow > 0) out.push({ dayIdx, price, dy: cursor + ph / 2, size: ph, ring: "", initial: "", overflow });
    }
    return out;
  }, [opinions, vis, closeByDay, dayIndex]);

  const option = useMemo(() => {
    // 头像气泡（custom 系列）：value=[日期索引, 价格, 自身在 bubbles 的下标]；
    // renderItem 经第 3 维取回元数据（避免 dataZoom 过滤后 dataIndex 错位）。
    const renderItem = (_params: any, api: any) => {
      const b = bubbles[api.value(2) as number];
      if (!b) return;
      const [x, y] = api.coord([api.value(0), api.value(1)]);
      const cy = y + b.dy;
      if (b.overflow) {
        return {
          type: "group", x, y: cy,
          children: [
            { type: "rect", shape: { x: -15, y: -8, width: 30, height: 16, r: 8 }, style: { fill: "#1C1D1F", stroke: "#2A2D2F", lineWidth: 1 } },
            { type: "text", style: { text: `+${b.overflow}`, x: 0, y: 0, fill: "#9AA0A6", font: "600 10px sans-serif", align: "center", verticalAlign: "middle" } },
          ],
        };
      }
      const r = b.size / 2;
      const children: any[] = [
        { type: "circle", shape: { cx: 0, cy: 0, r }, style: { fill: "#1C1D1F", shadowBlur: 6, shadowColor: "rgba(0,0,0,0.55)" }, z2: 1 },
        { type: "text", style: { text: b.initial, x: 0, y: 0, fill: "#E8EAED", font: `600 ${Math.round(r * 0.82)}px sans-serif`, align: "center", verticalAlign: "middle" }, z2: 2 },
      ];
      if (b.avatar) {
        children.push({
          type: "image",
          style: { image: b.avatar, x: -r, y: -r, width: b.size, height: b.size },
          clipPath: { type: "circle", shape: { cx: 0, cy: 0, r } },
          z2: 3,
        });
      }
      // 淡色外环（提升黑色 X 圈在深底上的可见度）+ 品牌圈色
      children.push({ type: "circle", shape: { cx: 0, cy: 0, r: r + 0.75 }, style: { fill: "none", stroke: "rgba(255,255,255,0.18)", lineWidth: 1 }, z2: 4 });
      children.push({ type: "circle", shape: { cx: 0, cy: 0, r }, style: { fill: "none", stroke: b.ring, lineWidth: 2 }, z2: 5 });
      return { type: "group", x, y: cy, children };
    };

    return {
      backgroundColor: "transparent",
      grid: { left: 4, right: 16, top: 22, bottom: 58, containLabel: true },
      tooltip: {
        trigger: "item",
        backgroundColor: "rgba(20,20,20,0.96)",
        borderColor: "#2a2d2f",
        borderWidth: 1,
        padding: [8, 11],
        textStyle: { color: "#e5e5e5", fontSize: 11 },
        extraCssText: "border-radius:10px;box-shadow:0 8px 28px rgba(0,0,0,0.5)",
        confine: true,
        formatter: (p: any) => {
          if (p.seriesType === "line") return `<b>${mmdd(p.name)}</b> · $${p.value}`;
          const o: KolOpinion | undefined = p.data?.op;
          if (!o) return "";
          const s = STANCE[o.stance];
          return `<div style="max-width:248px;white-space:normal"><b style="color:${SOURCE[o.source].color}">${SOURCE[o.source].label}</b> · ${o.author}<br/><span style="color:${s.color}">${zh ? s.zh : s.en}</span> · ${fmtCompact(o.interactions)} ${zh ? "互动" : "interactions"}<br/><span style="color:#cfd3d6">${opinionText(o, zh)}</span></div>`;
        },
      },
      xAxis: {
        type: "category",
        data: days.map((c) => c.day),
        boundaryGap: true,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: "#73757a", fontSize: 10.5, margin: 12, formatter: (v: string) => mmdd(v) },
      },
      yAxis: {
        type: "value",
        scale: true,
        position: "right",
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: "#73757a", fontSize: 10.5, formatter: (v: number) => "$" + v },
        splitLine: { lineStyle: { color: "rgba(127,127,127,0.06)" } },
      },
      dataZoom: [
        {
          type: "slider",
          xAxisIndex: 0,
          start: startPct,
          end: endPct,
          height: 16,
          bottom: 8,
          brushSelect: false,
          backgroundColor: "transparent",
          borderColor: "#2a2d2f",
          fillerColor: "rgba(87,215,186,0.10)",
          dataBackground: { lineStyle: { color: "#3a3d3f", width: 1 }, areaStyle: { color: "rgba(205,210,215,0.04)" } },
          selectedDataBackground: { lineStyle: { color: "#57D7BA", width: 1 }, areaStyle: { color: "rgba(87,215,186,0.10)" } },
          handleStyle: { color: "#161616", borderColor: "#57D7BA", borderWidth: 1.5 },
          moveHandleStyle: { color: "#57D7BA", opacity: 0.5 },
          handleSize: "120%",
          textStyle: { color: "#73757a", fontSize: 10 },
          labelFormatter: (idx: number) => mmdd(days[Math.round(idx)]?.day ?? days[0]?.day ?? ""),
        },
      ],
      series: [
        {
          name: "price",
          type: "line",
          data: days.map((c) => c.close),
          smooth: 0.4,
          symbol: "none",
          lineStyle: { color: "#D2D6DB", width: 2, shadowBlur: 8, shadowColor: "rgba(0,0,0,0.4)", shadowOffsetY: 2 },
          areaStyle: {
            color: {
              type: "linear", x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: "rgba(210,214,219,0.12)" },
                { offset: 1, color: "rgba(210,214,219,0)" },
              ],
            },
          },
          z: 3,
          markPoint: {
            symbol: "circle",
            symbolSize: 8,
            itemStyle: { color: "#57D7BA", borderColor: "#121212", borderWidth: 2 },
            label: { show: false },
            data: days.length ? [{ coord: [days[days.length - 1].day, days[days.length - 1].close] }] : [],
          },
        },
        {
          name: "opinions",
          type: "custom",
          coordinateSystem: "cartesian2d",
          xAxisIndex: 0,
          yAxisIndex: 0,
          clip: true,
          z: 10,
          encode: { x: 0, y: 1 },
          renderItem,
          data: bubbles.map((b, i) => ({ value: [b.dayIdx, b.price, i], op: b.op })),
        },
      ],
    };
  }, [days, bubbles, zh, startPct, endPct]);

  // 拖动区间滑块 → 读出当前窗口的起止索引 → 映射成日期区间，回报父级
  const onDataZoom = (_params: any, chart: any) => {
    try {
      const dz = chart.getOption().dataZoom?.[0];
      if (!dz || n === 0) return;
      const a = Math.max(0, Math.round(((dz.start ?? 0) / 100) * (n - 1)));
      const b = Math.min(n - 1, Math.round(((dz.end ?? 100) / 100) * (n - 1)));
      const lo = Math.min(a, b), hi = Math.max(a, b);
      const next: [string, string] = [days[lo].day, days[hi].day];
      if (next[0] !== range[0] || next[1] !== range[1]) onRangeChange(next);
    } catch {
      /* ignore */
    }
  };

  return (
    <div>
      {/* 来源筛选（品牌圈色 chips；点切显隐，同时作用于图与下方分类区） */}
      <div className="mb-2.5 flex flex-wrap items-center gap-2">
        {SOURCE_ORDER.map((s) => {
          const on = vis[s];
          return (
            <button
              key={s}
              onClick={() => onToggle(s)}
              className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-medium ring-1 ring-inset transition ${
                on ? "ring-line text-cream hover:bg-elevated" : "text-neutral-600 ring-line/50"
              }`}
            >
              <span
                className="h-2.5 w-2.5 rounded-full border transition"
                style={{ background: SOURCE_RING[s], borderColor: "rgba(255,255,255,0.28)", opacity: on ? 1 : 0.3 }}
              />
              {SOURCE[s].label}
            </button>
          );
        })}
        <span className="ml-auto text-[11px] text-neutral-600">
          {zh ? "头像=投资者 · 圈色分平台 · 大小∝互动 · 拖下方滑块选区间" : "avatar = investor · ring = platform · size ∝ interactions · drag slider for range"}
        </span>
      </div>

      <ReactECharts option={option} style={{ height: 360 }} opts={{ renderer: "canvas" }} onEvents={{ datazoom: onDataZoom }} lazyUpdate />
    </div>
  );
}
