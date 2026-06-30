"use client";

// 顶部基础信息卡里的「迷你价格走势」：近 ~2 周收盘价折线（简单展示，无坐标轴/滑块/tooltip）。
// 颜色按区间净涨跌：涨=青绿 / 跌=珊瑚红；末点小圆点标当前价位置。
import { useMemo } from "react";
import ReactECharts from "echarts-for-react";
import type { KolCandle } from "@/lib/mockDetail";

export function PriceSparkline({ days, height = 48 }: { days: KolCandle[]; height?: number }) {
  const option = useMemo(() => {
    const closes = days.map((d) => d.close);
    const up = closes.length >= 2 ? closes[closes.length - 1] >= closes[0] : true;
    const color = up ? "#57D7BA" : "#FF5C6C";
    const fill = up ? "rgba(87,215,186,0.16)" : "rgba(255,92,108,0.16)";
    return {
      backgroundColor: "transparent",
      grid: { left: 2, right: 6, top: 8, bottom: 6 },
      xAxis: { type: "category", data: days.map((d) => d.day), show: false, boundaryGap: false },
      yAxis: { type: "value", scale: true, show: false },
      tooltip: { show: false },
      series: [
        {
          type: "line",
          data: closes,
          smooth: 0.4,
          symbol: "none",
          lineStyle: { color, width: 1.8 },
          areaStyle: {
            color: { type: "linear", x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: fill }, { offset: 1, color: "rgba(0,0,0,0)" }] },
          },
          markPoint: {
            symbol: "circle",
            symbolSize: 6,
            silent: true,
            itemStyle: { color, borderColor: "#121212", borderWidth: 1.5 },
            label: { show: false },
            data: closes.length ? [{ coord: [days[days.length - 1].day, closes[closes.length - 1]] }] : [],
          },
          z: 2,
        },
      ],
    };
  }, [days]);

  if (!days.length) return null;
  return (
    <ReactECharts
      option={option}
      style={{ height, width: "100%" }}
      opts={{ renderer: "canvas" }}
      onChartReady={(c: any) => { requestAnimationFrame(() => { try { c.resize(); } catch {} }); }}
      notMerge
    />
  );
}
