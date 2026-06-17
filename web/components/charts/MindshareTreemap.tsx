"use client";

import ReactECharts from "echarts-for-react";
import { useRouter } from "next/navigation";
import { useIsLight } from "@/lib/useTheme";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";

type Item = { ticker: string; name: string; value: number; sentiment: number; sector: string; mentions: number };

// 按情绪「强度」上色：强烈→饱和绿/红，微弱→退回石板灰。比纯三色更有层次。
const NEUTRAL = [92, 107, 117];
function tile(s: number): string {
  const mag = Math.min(1, Math.abs(s));
  if (mag < 0.08) return `rgb(${NEUTRAL.join(",")})`;
  const target = s > 0 ? [36, 180, 126] : [240, 85, 110];
  const t = 0.35 + 0.65 * mag;
  const c = NEUTRAL.map((nv, i) => Math.round(nv + (target[i] - nv) * t));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

export function MindshareTreemap({ data, height = 400 }: { data: Item[]; height?: number }) {
  const router = useRouter();
  const isLight = useIsLight();
  const { lang, dict } = useLocale();
  const items = data.map((d) => ({
    name: d.ticker,
    value: d.value,
    sentiment: d.sentiment,
    company: d.name,
    mentions: d.mentions,
    itemStyle: { color: tile(d.sentiment) },
  }));

  const option = {
    backgroundColor: "transparent",
    tooltip: {
      trigger: "item",
      backgroundColor: "#16242F",
      borderColor: "#243845",
      textStyle: { color: "#e5e5e5", fontSize: 12 },
      formatter: (p: any) =>
        `<b>${p.name}</b> ${p.data.company ? `· ${p.data.company}` : ""}<br/>` +
        `Mindshare <b>${Number(p.value).toFixed(1)}%</b><br/>` +
        `${dict.charts.sentiment} ${p.data.sentiment > 0 ? "+" : ""}${p.data.sentiment.toFixed(2)} · ${p.data.mentions}${dict.charts.mentionsSuffix}`,
    },
    series: [
      {
        type: "treemap",
        roam: false,
        nodeClick: false,
        breadcrumb: { show: false },
        width: "100%",
        height: "100%",
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        itemStyle: { borderColor: isLight ? "#ffffff" : "#16161a", borderWidth: 2, gapWidth: 2, borderRadius: 3 },
        label: {
          show: true,
          formatter: (p: any) => `{t|${p.name}}\n{v|${Number(p.value).toFixed(1)}%}`,
          rich: {
            t: { fontSize: 13, fontWeight: 700, color: "#fff", fontFamily: "monospace", lineHeight: 16 },
            v: { fontSize: 11, color: "rgba(255,255,255,.85)", fontFamily: "monospace" },
          },
        },
        data: items,
      },
    ],
  };

  return (
    <ReactECharts
      option={option}
      style={{ height }}
      opts={{ renderer: "canvas" }}
      onEvents={{ click: (p: any) => p?.name && router.push(withLang(lang, `/ticker/${p.name}`)) }}
    />
  );
}
