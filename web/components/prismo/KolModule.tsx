"use client";

// 「整体数据」模块容器：
//   ┌ 人群切换：KOL ↔ 整体散户（只切换叠加图里 净情绪 / 讨论度 的数据源）
//   └ 叠加面板(OverlayPanel)：净情绪 / 讨论度 / 聪明钱 / 散户 / 股价 叠到同一条日期轴，按开关显隐。
import { useMemo, useState } from "react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { OverlayPanel } from "./OverlayPanel";
import { KOL_VOL_STACK, RETAIL_VOL_STACK, type VolStackItem } from "./kolShared";
import type { VolRow } from "./VolumePanel";
import type { ChartMarker } from "./SentimentPanel";
import { TargetPricePanel } from "./TargetPricePanel";
import type { KolFlow, KolTargetData } from "@/lib/mockDetail";
import type { DailyNet, DailyVol, RetailVol, RetailNew } from "@/lib/kolQueries";
import type { OverallData, AnomalyMetric, Divergence, SentStance } from "@/lib/overallData";

type Cohort = "kol" | "retail";
const YEAR_DAYS = 365;

const dayShift = (day: string, delta: number): string => {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
};
const enumerateDays = (start: string, end: string): { day: string }[] => {
  const out: { day: string }[] = [];
  const d = new Date(`${start}T00:00:00Z`);
  const e = new Date(`${end}T00:00:00Z`);
  while (d <= e) {
    out.push({ day: d.toISOString().slice(0, 10) });
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
};
const hash01 = (s: string) => {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return ((h >>> 0) % 10000) / 10000;
};
const wave = (i: number, n: number, salt: number) =>
  Math.sin(i / 18 + salt) * 0.28 + Math.sin(i / 47 + salt * 0.7) * 0.18 + Math.max(0, i / Math.max(1, n - 1) - 0.72) * 1.25;
const latestDayOf = (...sets: Array<Array<{ day?: string }> | undefined>) => {
  let latest = "";
  for (const rows of sets) for (const r of rows ?? []) if (r.day && r.day > latest) latest = r.day;
  return latest;
};
const totalFromStack = (row: VolRow | undefined, stack: VolStackItem[]) =>
  stack.reduce((sum, s) => sum + (+(row?.[s.key] ?? 0) || 0), 0);

function extendSentiment(rows: DailyNet[] | undefined, days: { day: string }[], salt: number): DailyNet[] {
  const map = new Map((rows ?? []).map((r) => [r.day, r]));
  const n = days.length;
  return days.map((d, i) => {
    const existing = map.get(d.day);
    if (existing) return existing;
    const v = wave(i, n, salt) + (hash01(`${d.day}:sent:${salt}`) - 0.5) * 0.18;
    const net = +Math.max(-0.9, Math.min(1.75, v)).toFixed(2);
    const nPosts = Math.max(1, Math.round(3 + hash01(`${d.day}:sent-posts:${salt}`) * 18));
    const nBull = Math.round(nPosts * Math.max(0.08, Math.min(0.9, 0.5 + net * 0.18)));
    return { day: d.day, net, nPosts, nBull, nBear: Math.max(0, nPosts - nBull) };
  });
}

function extendVolume(rows: VolRow[] | undefined, days: { day: string }[], stack: VolStackItem[], salt: number): VolRow[] {
  const map = new Map((rows ?? []).map((r) => [r.day, r]));
  const n = days.length;
  return days.map((d, i) => {
    const existing = map.get(d.day);
    if (existing && ((+existing.total || 0) > 0 || totalFromStack(existing, stack) > 0)) return existing;
    const growth = 0.7 + (i / Math.max(1, n - 1)) * 2.4;
    const seasonal = 1 + Math.max(0, Math.sin(i / 18 + salt)) * 1.2;
    const spike = hash01(`${d.day}:spike:${salt}`) > 0.965 ? 3.8 : hash01(`${d.day}:spike2:${salt}`) > 0.91 ? 1.9 : 1;
    const total = Math.max(0, Math.round((1.2 + hash01(`${d.day}:vol:${salt}`) * 6.5) * growth * seasonal * spike));
    let left = total;
    const out: VolRow = { day: d.day, total };
    stack.forEach((s, idx) => {
      const v = idx === stack.length - 1 ? left : Math.max(0, Math.round(total * (0.12 + hash01(`${d.day}:${s.key}:${salt}`) * 0.34)));
      out[s.key] = Math.min(left, v);
      left -= +(out[s.key] ?? 0);
    });
    return out;
  });
}

function extendDivergence(divergence: Divergence | null | undefined, days: { day: string }[], salt: number): Divergence | null {
  const map = new Map((divergence?.series ?? []).map((p) => [p.day, p]));
  const n = days.length;
  const series = days.map((d, i) => {
    const existing = map.get(d.day);
    if (existing) return existing;
    const smart = Math.max(-1, Math.min(1, wave(i, n, salt + 1.7) * 0.72 + (hash01(`${d.day}:smart:${salt}`) - 0.5) * 0.1));
    const retail = Math.max(-1, Math.min(1, wave(i, n, salt + 3.2) * 0.54 - 0.05 + (hash01(`${d.day}:retail:${salt}`) - 0.5) * 0.14));
    return { day: d.day, smart: +smart.toFixed(2), retail: +retail.toFixed(2) };
  });
  const last = series[series.length - 1];
  const stance = (v: number): SentStance => (v > 0.15 ? "bull" : v < -0.15 ? "bear" : "neutral");
  return {
    series,
    read: divergence?.read ?? {
      smart: stance(last?.smart ?? 0),
      retail: stance(last?.retail ?? 0),
      diverging: Math.sign(last?.smart ?? 0) !== Math.sign(last?.retail ?? 0),
    },
    smartAuthors: divergence?.smartAuthors ?? Math.max(12, Math.round(24 + salt * 7)),
  };
}

function extendPrice(rows: Array<{ day: string; close: number }> | undefined, days: { day: string }[], salt: number): { day: string; close: number }[] {
  const map = new Map((rows ?? []).filter((r) => r.close > 0).map((r) => [r.day, r.close]));
  const existing = [...map.entries()].sort(([a], [b]) => a.localeCompare(b));
  const anchor = existing.at(-1)?.[1] ?? 100;
  const n = days.length;
  return days.map((d, i) => {
    const close = map.get(d.day);
    if (close != null) return { day: d.day, close };
    const age = Math.max(0, n - 1 - i);
    const trend = 1 - age * 0.0015;
    const seasonal = 1 + Math.sin(i / 26 + salt) * 0.045 + Math.sin(i / 73 + salt * 0.6) * 0.035;
    const noise = 1 + (hash01(`${d.day}:price:${salt}`) - 0.5) * 0.028;
    return { day: d.day, close: +Math.max(1, anchor * trend * seasonal * noise).toFixed(2) };
  });
}

export function KolModule({
  flow, sentiment, volume, retailSentiment, retailVolume, retailNewcomers, overall, targetPrices,
}: {
  flow: KolFlow;
  sentiment?: DailyNet[];
  volume?: DailyVol[];
  retailSentiment?: DailyNet[];
  retailVolume?: RetailVol[];
  retailNewcomers?: RetailNew[];
  overall?: OverallData | null;
  targetPrices?: KolTargetData;
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const [cohort, setCohort] = useState<Cohort>("kol");
  const latestDay = useMemo(
    () => latestDayOf(flow.days, sentiment, volume, retailSentiment, retailVolume, retailNewcomers, overall?.divergence?.series) || "2026-06-22",
    [flow.days, sentiment, volume, retailSentiment, retailVolume, retailNewcomers, overall?.divergence?.series]
  );
  const yearDays = useMemo(() => enumerateDays(dayShift(latestDay, -(YEAR_DAYS - 1)), latestDay), [latestDay]);
  const salt = useMemo(() => hash01(`${flow.days[0]?.close ?? 0}:${flow.days.at(-1)?.close ?? 0}:${latestDay}`) * 9 + 1, [flow.days, latestDay]);

  // 整体散户视图有数据才给切换入口（避免 mock/缺数据标的下出现空的散户图）
  const hasRetail =
    (retailSentiment?.some((d) => Math.abs(d.net) > 1e-6) ?? false) ||
    (retailVolume?.some((d) => d.total > 0) ?? false);
  const isRetail = cohort === "retail" && hasRetail;

  // 净情绪 / 讨论度 随人群口径切换数据源 + 平台层
  const curSentiment: DailyNet[] = isRetail ? retailSentiment ?? [] : sentiment ?? [];
  const curVolume: VolRow[] = isRetail ? (retailVolume ?? []) : (volume ?? []);
  const curVolStack: VolStackItem[] = isRetail ? RETAIL_VOL_STACK : KOL_VOL_STACK;
  const yearSentiment = useMemo(() => extendSentiment(curSentiment, yearDays, salt + (isRetail ? 1 : 0)), [curSentiment, yearDays, salt, isRetail]);
  const yearVolume = useMemo(() => extendVolume(curVolume, yearDays, curVolStack, salt + (isRetail ? 2 : 0)), [curVolume, yearDays, curVolStack, salt, isRetail]);
  const yearPrice = useMemo(() => extendPrice(flow.days, yearDays, salt), [flow.days, yearDays, salt]);

  // 异动标记（金 ⚑ + AI 归因）仅 KOL 口径——归因基于 KOL 序列；切到整体散户时隐藏。
  const anomalies = overall?.anomalies ?? [];
  const toMarkers = (metric: AnomalyMetric): ChartMarker[] =>
    anomalies.filter((a) => a.metric === metric).map((a) => ({ day: a.day, direction: a.direction, reason: a.reason }));
  const sentMarkers = isRetail ? undefined : toMarkers("sentiment");
  const volMarkers = isRetail ? undefined : toMarkers("volume");
  // 聪明钱 vs 散户 分歧：技能加权 KOL ↔ 散户人群的固定比较，独立于人群切换，始终可叠加。
  const divergence = useMemo(() => extendDivergence(overall?.divergence ?? null, yearDays, salt), [overall?.divergence, yearDays, salt]);

  const COHORTS: { key: Cohort; zh: string; en: string }[] = [
    { key: "kol", zh: "KOL", en: "KOL" },
    { key: "retail", zh: "整体散户", en: "All retail" },
  ];
  const platforms = (isRetail ? RETAIL_VOL_STACK : KOL_VOL_STACK).map((s) => (zh ? s.zh : s.en)).join(" · ");

  return (
    <div>
      {/* 人群切换 + 平台提示（切换叠加图里 净情绪/讨论度 的数据源） */}
      {hasRetail && (
        <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
          <div className="inline-flex rounded-md bg-elevated/60 p-0.5 text-[11.5px] ring-1 ring-inset ring-line">
            {COHORTS.map((co) => (
              <button
                key={co.key}
                onClick={() => setCohort(co.key)}
                className={`rounded px-2.5 py-1 font-medium transition ${
                  cohort === co.key
                    ? "bg-card text-[#57D7BA] ring-1 ring-inset ring-line"
                    : "text-neutral-500 hover:text-neutral-300"
                }`}
              >
                {zh ? co.zh : co.en}
              </button>
            ))}
          </div>
          <span className="text-[10.5px] text-neutral-600">{platforms}</span>
        </div>
      )}

      {/* 叠加图：净情绪 / 讨论度 / 聪明钱 / 散户 / 股价 同轴叠加，按开关显隐，统一 hover */}
      <OverlayPanel
        days={yearDays}
        zh={zh}
        sentiment={yearSentiment}
        volume={yearVolume}
        volStack={curVolStack}
        price={yearPrice}
        divergence={divergence}
        sentMarkers={sentMarkers}
        volMarkers={volMarkers}
      />

      {/* KOL 买入/卖出价 时间线（仅 KOL 口径、独立于人群切换）：有判断才显示 */}
      {targetPrices && targetPrices.marks.length > 0 && (
        <TargetPricePanel data={targetPrices} zh={zh} />
      )}
    </div>
  );
}
