"use client";

// 「整体数据」模块容器：
//   ┌ 人群切换：KOL ↔ 整体散户（只切换叠加图里 净情绪/讨论度/新增 三条的数据源）
//   └ 叠加面板(OverlayPanel)：净情绪 / 讨论度 / 新增 / 聪明钱 / 散户 叠到同一条日期轴，按开关显隐。
import { useState } from "react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { OverlayPanel } from "./OverlayPanel";
import { KOL_VOL_STACK, RETAIL_VOL_STACK, RETAIL_NEW_STACK, type VolStackItem } from "./kolShared";
import type { VolRow } from "./VolumePanel";
import type { ChartMarker } from "./SentimentPanel";
import { TargetPricePanel } from "./TargetPricePanel";
import type { KolFlow, KolTargetData } from "@/lib/mockDetail";
import type { DailyNet, DailyVol, RetailVol, RetailNew } from "@/lib/kolQueries";
import type { OverallData, AnomalyMetric } from "@/lib/overallData";

type Cohort = "kol" | "retail";

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
  const { days } = flow;
  const [cohort, setCohort] = useState<Cohort>("kol");

  // 整体散户视图有数据才给切换入口（避免 mock/缺数据标的下出现空的散户图）
  const hasRetail =
    (retailSentiment?.some((d) => Math.abs(d.net) > 1e-6) ?? false) ||
    (retailVolume?.some((d) => d.total > 0) ?? false);
  const isRetail = cohort === "retail" && hasRetail;

  // 净情绪 / 讨论度 / 新增 随人群口径切换数据源 + 平台层
  const curSentiment: DailyNet[] = isRetail ? retailSentiment ?? [] : sentiment ?? [];
  const curVolume: VolRow[] = isRetail ? (retailVolume ?? []) : (volume ?? []);
  const curVolStack: VolStackItem[] = isRetail ? RETAIL_VOL_STACK : KOL_VOL_STACK;
  // 「新增 KOL」已删；新增只剩散户口径（仅整体散户视图出现，KOL 口径无 新增 系列）。
  const curNewcomers: VolRow[] = isRetail ? (retailNewcomers ?? []) : [];
  const curNewStack: VolStackItem[] = RETAIL_NEW_STACK;
  const curNewLabel = { zh: "新增散户", en: "New retail" };

  // 异动标记（金 ⚑ + AI 归因）仅 KOL 口径——归因基于 KOL 序列；切到整体散户时隐藏。
  const anomalies = overall?.anomalies ?? [];
  const toMarkers = (metric: AnomalyMetric): ChartMarker[] =>
    anomalies.filter((a) => a.metric === metric).map((a) => ({ day: a.day, direction: a.direction, reason: a.reason }));
  const sentMarkers = isRetail ? undefined : toMarkers("sentiment");
  const volMarkers = isRetail ? undefined : toMarkers("volume");
  // 聪明钱 vs 散户 分歧：技能加权 KOL ↔ 散户人群的固定比较，独立于人群切换，始终可叠加。
  const divergence = overall?.divergence ?? null;

  const COHORTS: { key: Cohort; zh: string; en: string }[] = [
    { key: "kol", zh: "KOL", en: "KOL" },
    { key: "retail", zh: "整体散户", en: "All retail" },
  ];
  const platforms = (isRetail ? RETAIL_VOL_STACK : KOL_VOL_STACK).map((s) => (zh ? s.zh : s.en)).join(" · ");

  return (
    <div>
      {/* 人群切换 + 平台提示（切换叠加图里 净情绪/讨论度/新增 三条的数据源） */}
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

      {/* 叠加图：净情绪 / 讨论度 / 新增 / 聪明钱 / 散户 同轴叠加，按开关显隐，统一 hover */}
      <OverlayPanel
        days={days}
        zh={zh}
        sentiment={curSentiment}
        volume={curVolume}
        volStack={curVolStack}
        newcomers={curNewcomers}
        newStack={curNewStack}
        newLabel={curNewLabel}
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
