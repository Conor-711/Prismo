"use client";

// 标的「值得参考的投资者」图表：按跨标的验证过的选股技能 z 排名。
// 主视觉用横向条形图承载技能分，颜色表示该投资者近 30 天对本标的的立场。
import { useMemo } from "react";
import ReactECharts from "echarts-for-react";
import type { TopInvestorBoard, TopInvestor, InvestorStance } from "@/lib/topInvestors";

const STANCE: Record<InvestorStance, { zh: string; en: string; color: string; soft: string }> = {
  bull: { zh: "看多", en: "Bull", color: "#57D7BA", soft: "bg-bull/10 text-bull ring-bull/25" },
  bear: { zh: "看空", en: "Bear", color: "#FF5C6C", soft: "bg-bear/10 text-bear ring-bear/25" },
  neutral: { zh: "中性", en: "Neutral", color: "#8A949E", soft: "bg-white/[.05] text-neutral-400 ring-line" },
};

const AXIS = "#73757a";
const LINE = "#343A42";
const CREAM = "#F1F3F4";

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function callCount(inv: TopInvestor) {
  return inv.tickerCalls ?? inv.pltrCalls;
}

function hitRate(inv: TopInvestor) {
  return inv.tickerHit ?? inv.pltrHit;
}

export function TopInvestors({ board, zh }: { board: TopInvestorBoard; zh: boolean }) {
  const investors = board.investors.slice(0, 8);
  const chartHeight = Math.max(206, investors.length * 34 + 58);
  const totalCalls = investors.reduce((sum, inv) => sum + (callCount(inv) ?? 0), 0);

  const option = useMemo(() => {
    const maxZ = Math.max(1, ...investors.map((inv) => inv.skillZ));
    const maxAxis = Math.ceil((maxZ + 0.4) * 10) / 10;

    return {
      backgroundColor: "transparent",
      grid: { left: 118, right: 54, top: 8, bottom: 24, containLabel: false },
      tooltip: {
        trigger: "item",
        backgroundColor: "#20242A",
        borderColor: LINE,
        borderWidth: 1,
        padding: [8, 10],
        textStyle: { color: "#e5e5e5", fontSize: 11 },
        extraCssText: "border-radius:8px;max-width:320px;white-space:normal",
        formatter: (p: any) => {
          const inv: TopInvestor | undefined = investors[p.dataIndex];
          if (!inv) return "";
          const st = STANCE[inv.stance];
          const latest = inv.latest?.[0];
          const calls = callCount(inv);
          const hit = hitRate(inv);
          const hitText = hit == null ? "—" : `${Math.round(hit * 100)}%`;
          let html = `<div style="display:flex;align-items:center;gap:8px;margin-bottom:5px">`;
          html += `<b style="color:${CREAM}">@${escapeHtml(inv.handle)}</b>`;
          html += `<span style="color:${st.color};font-weight:600">${zh ? st.zh : st.en}</span>`;
          html += `</div>`;
          html += `<div style="color:#9a9da1">${zh ? "技能 z" : "Skill z"} <b style="color:${st.color}">${inv.skillZ.toFixed(1)}</b>`;
          html += ` · ${zh ? "命中率" : "hit"} <b style="color:${CREAM}">${hitText}</b>`;
          if (calls != null) html += ` · ${calls} ${zh ? "次" : "calls"}`;
          html += `</div>`;
          if (latest?.text) {
            html += `<div style="margin-top:6px;border-top:1px solid ${LINE};padding-top:6px;color:#b8babd;line-height:1.45">${escapeHtml(latest.text).slice(0, 180)}</div>`;
          }
          return html;
        },
      },
      xAxis: {
        type: "value",
        min: 0,
        max: maxAxis,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: AXIS, fontSize: 10, formatter: (v: number) => v.toFixed(1) },
        splitLine: { lineStyle: { color: "rgba(127,127,127,0.1)" } },
      },
      yAxis: {
        type: "category",
        inverse: true,
        data: investors.map((inv) => inv.handle),
        axisTick: { show: false },
        axisLine: { show: false },
        axisLabel: {
          color: CREAM,
          fontSize: 11,
          fontWeight: 700,
          width: 104,
          overflow: "truncate",
          formatter: (value: string, index: number) => `{rank|${index + 1}}  @${value}`,
          rich: {
            rank: { color: "#57D7BA", fontFamily: "Roboto", fontWeight: 800, width: 14, align: "center" },
          },
        },
      },
      series: [
        {
          type: "bar",
          name: zh ? "选股技能" : "Skill",
          barWidth: 14,
          data: investors.map((inv) => ({
            value: inv.skillZ,
            handle: inv.handle,
            itemStyle: { color: STANCE[inv.stance].color, borderRadius: [0, 6, 6, 0] },
          })),
          label: {
            show: true,
            position: "right",
            color: CREAM,
            fontSize: 11,
            fontFamily: "Roboto",
            fontWeight: 800,
            formatter: (p: any) => `z ${Number(p.value).toFixed(1)}`,
          },
          emphasis: { focus: "self" },
        },
      ],
    };
  }, [investors, zh]);

  return (
    <div>
      <ReactECharts
        option={option}
        style={{ height: chartHeight, width: "100%" }}
        opts={{ renderer: "canvas" }}
        notMerge
        onEvents={{
          click: (p: any) => {
            const handle = p?.data?.handle;
            if (handle) window.open(`https://x.com/${handle}`, "_blank", "noopener,noreferrer");
          },
        }}
      />
      <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-line/70 pt-2 text-[10.5px] text-neutral-600">
        <span>
          {zh ? "盲多基准" : "base"} <b className="font-mono text-neutral-400">{Math.round(board.base * 100)}%</b>
        </span>
        <span>
          {zh ? "样本" : "sample"} <b className="font-mono text-neutral-400">{totalCalls || "—"}</b>
        </span>
        {(["bull", "neutral", "bear"] as InvestorStance[]).map((key) => {
          const st = STANCE[key];
          return (
            <span key={key} className={`inline-flex items-center gap-1 rounded px-1.5 py-0.5 ring-1 ring-inset ${st.soft}`}>
              <span className="h-1.5 w-1.5 rounded-full" style={{ background: st.color }} />
              {zh ? st.zh : st.en}
            </span>
          );
        })}
        <span className="ml-auto">{zh ? "点击条形打开 X 主页" : "Click a bar to open X"}</span>
      </div>
      <p className="mt-2 text-[10.5px] text-neutral-600">
        {zh
          ? "按博主「跨标的选股技能 z」排名（样本外验证，非单票运气）。参考信号，非投资建议。"
          : "Ranked by cross-ticker stock-picking skill (z, out-of-sample validated). Reference signal, not advice."}
      </p>
    </div>
  );
}
