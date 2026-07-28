"use client";

import { useMemo, useState } from "react";
import type { SvSignalCohort, SvSignalHorizon, SvTickerSignalData, SvTickerSignalStat } from "@/server/queries/smartVoiceTickerSignals";
import { buildOpinionChangeRadar, buildWeightedTargetDistribution } from "../smartVoiceDecisionLogic";
import {
  buildSvOverviewMetrics,
  type SvBreadthMetric,
  type SvPriceDivergenceMetric,
  type SvShiftMetric,
  type SvTargetRevisionMetric,
} from "../smartVoiceOverviewLogic";
import { SmartVoiceShiftChart } from "./SmartVoiceShiftChart";
import { SmartVoiceWeightedTargets } from "./SmartVoiceWeightedTargets";

const HORIZONS: SvSignalHorizon[] = ["1D", "5D", "20D", "60D", "90D", "180D"];

function signed(value: number | null, digits = 0, suffix = "") {
  if (value == null || !Number.isFinite(value)) return "—";
  return `${value >= 0 ? "+" : ""}${value.toFixed(digits)}${suffix}`;
}

function money(value: number | null) {
  if (value == null || !Number.isFinite(value)) return "—";
  return `$${value.toLocaleString(undefined, { maximumFractionDigits: value >= 100 ? 0 : 2 })}`;
}

function percent(value: number | null, digits = 1) {
  return value == null ? "—" : signed(value * 100, digits, "%");
}

function shiftCopy(metric: SvShiftMetric, zh: boolean) {
  const copy = {
    cross_bull: [zh ? "由谨慎转为乐观" : "Turned from cautious to positive", "text-bull"],
    strong_bull: [zh ? "强烈转多" : "Strong bullish turn", "text-bull"],
    bull: [zh ? "明显转多" : "Bullish turn", "text-bull"],
    stable: [zh ? "观点基本稳定" : "Views broadly stable", "text-neutral-300"],
    bear: [zh ? "明显转空" : "Bearish turn", "text-bear"],
    strong_bear: [zh ? "强烈转空" : "Strong bearish turn", "text-bear"],
    cross_bear: [zh ? "由乐观转为谨慎" : "Turned from positive to cautious", "text-bear"],
    insufficient: [zh ? "历史样本不足" : "Insufficient history", "text-neutral-500"],
  } as const;
  return copy[metric.state];
}

function breadthCopy(metric: SvBreadthMetric, zh: boolean) {
  const direction = metric.direction === "bull"
    ? (zh ? "转多" : "bullish")
    : metric.direction === "bear"
      ? (zh ? "转空" : "bearish")
      : (zh ? "变化" : "change");
  const copy = {
    broad: [zh ? `广泛同步${direction}` : `Broad ${direction} participation`, metric.direction === "bear" ? "text-bear" : "text-bull"],
    majority: [zh ? `多数作者同步${direction}` : `Most authors moved ${direction}`, metric.direction === "bear" ? "text-bear" : "text-bull"],
    partial: [zh ? `部分作者开始${direction}` : `Some authors moved ${direction}`, "text-gold"],
    narrow: [zh ? "变化尚未扩散" : "Change has not broadened", "text-gold"],
    mixed: [zh ? "作者变化方向不一" : "Author changes are mixed", "text-neutral-300"],
    insufficient: [zh ? "可比较作者不足" : "Too few comparable authors", "text-neutral-500"],
  } as const;
  return copy[metric.state];
}

function targetCopy(metric: SvTargetRevisionMetric, zh: boolean) {
  const copy = {
    strong_up: [zh ? "目标预期显著上调" : "Targets revised sharply higher", "text-bull"],
    up: [zh ? "目标预期上调" : "Targets revised higher", "text-bull"],
    stable: [zh ? "目标预期基本不变" : "Targets broadly unchanged", "text-neutral-300"],
    down: [zh ? "目标预期下调" : "Targets revised lower", "text-bear"],
    strong_down: [zh ? "目标预期显著下调" : "Targets revised sharply lower", "text-bear"],
    new: [zh ? "本期出现新目标" : "New targets this period", "text-reddit"],
    insufficient: [zh ? "明确目标不足" : "Too few explicit targets", "text-neutral-500"],
  } as const;
  return copy[metric.state];
}

function divergenceCopy(metric: SvPriceDivergenceMetric, zh: boolean) {
  const copy = {
    opinion_leads_recovery: [zh ? "观点领先价格回暖" : "Views improve ahead of price", "text-bull"],
    opinion_cools_into_rally: [zh ? "上涨中观点降温" : "Views cool into the rally", "text-bear"],
    views_resilient_vs_price: [zh ? "观点相对价格更稳" : "Views are firmer than price", "text-bull"],
    views_lag_rally: [zh ? "观点弱于价格表现" : "Views lag the price rally", "text-bear"],
    aligned_up: [zh ? "价格与观点同步改善" : "Price and views improve together", "text-bull"],
    aligned_down: [zh ? "价格与观点同步走弱" : "Price and views weaken together", "text-bear"],
    neutral: [zh ? "暂无明显背离" : "No material divergence", "text-neutral-300"],
    insufficient: [zh ? "历史样本不足" : "Insufficient history", "text-neutral-500"],
  } as const;
  return copy[metric.state];
}

function MetricCell({
  title,
  value,
  status,
  tone,
  detail,
  foot,
}: {
  title: string;
  value: string;
  status: string;
  tone: string;
  detail: string;
  foot: string;
}) {
  return (
    <div className="min-w-0 px-4 py-3.5">
      <div className="flex items-center justify-between gap-3">
        <span className="text-[9px] font-semibold uppercase tracking-[0.08em] text-neutral-600">{title}</span>
        <span className={`truncate text-[9px] font-semibold ${tone}`}>{status}</span>
      </div>
      <div className={`mt-2 font-mono text-[22px] font-bold leading-none ${tone}`}>{value}</div>
      <div className="mt-2 truncate text-[9.5px] text-neutral-400" title={detail}>{detail}</div>
      <div className="mt-1 truncate text-[8.5px] text-neutral-600" title={foot}>{foot}</div>
    </div>
  );
}

function Summary({
  shift,
  breadth,
  target,
  divergence,
  zh,
}: {
  shift: SvShiftMetric;
  breadth: SvBreadthMetric;
  target: SvTargetRevisionMetric;
  divergence: SvPriceDivergenceMetric;
  zh: boolean;
}) {
  const [shiftLabel, shiftTone] = shiftCopy(shift, zh);
  const [breadthLabel] = breadthCopy(breadth, zh);
  const targetLabel = targetCopy(target, zh)[0];
  const divergenceLabel = divergenceCopy(divergence, zh)[0];
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line bg-reddit/[.035] px-4 py-3">
      <div className="min-w-0">
        <div className={`font-display text-[14px] font-bold ${shiftTone}`}>
          {zh ? `优质投资者：${shiftLabel}` : `High-SV investors: ${shiftLabel}`}
        </div>
        <p className="mt-1 text-[9.5px] text-neutral-500">
          {breadthLabel} · {targetLabel} · {divergenceLabel}
        </p>
      </div>
      <span className="shrink-0 rounded bg-white/[.04] px-2 py-1 font-mono text-[8.5px] text-neutral-500">
        {zh ? "相对前 7 日" : "vs prior 7 days"}
      </span>
    </div>
  );
}

function HistoryValidation({
  stat,
  zh,
}: {
  stat?: SvTickerSignalStat;
  zh: boolean;
}) {
  const enough = (stat?.nEvents ?? 0) >= 10;
  const rows = [
    [zh ? "历史事件" : "Events", stat ? String(stat.nEvents) : "—"],
    [zh ? "超额命中" : "Excess hit", stat?.hitRate == null ? "—" : `${(stat.hitRate * 100).toFixed(0)}%`],
    [zh ? "超额中位" : "Median excess", percent(stat?.medianDirectionalExcessPct ?? null)],
    [zh ? "平均有利波动" : "Average MFE", percent(stat?.avgMaxFavorableExcess ?? null)],
    [zh ? "平均不利波动" : "Average MAE", percent(stat?.avgMaxAdverseExcess ?? null)],
  ];
  return (
    <section className="min-w-0">
      <div className="flex items-center justify-between gap-3 border-b border-line/70 px-4 py-2.5">
        <div>
          <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "类似 SV 信号的历史表现" : "Historical performance of similar SV signals"}</h4>
          <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "下一交易日入场，相对 SPY 计算方向性超额" : "Next-session entry; directional excess versus SPY"}</p>
        </div>
        <span className={`text-[8.5px] ${enough ? "text-neutral-500" : "text-gold"}`}>
          {enough ? (zh ? "可观察" : "Observable") : (zh ? "样本有限" : "Limited sample")}
        </span>
      </div>
      <div className="grid grid-cols-5 divide-x divide-line/60">
        {rows.map(([label, value]) => (
          <div key={label} className="min-w-0 px-3 py-3">
            <div className="truncate text-[8px] text-neutral-600">{label}</div>
            <div className="mt-1 truncate font-mono text-[12px] font-semibold text-neutral-300">{value}</div>
          </div>
        ))}
      </div>
      <p className="border-t border-line/60 px-4 py-2 text-[8px] leading-relaxed text-neutral-700">
        {zh
          ? "历史表现用于描述同口径事件，不代表未来收益；少于 10 次事件时不作强弱结论。"
          : "Historical outcomes describe same-definition events, not future returns; fewer than 10 events are not used for comparative conclusions."}
      </p>
    </section>
  );
}

const CHANGE_LABEL = {
  new: ["新开", "New"],
  reinforce: ["加强", "Reinforce"],
  reverse: ["反转", "Reverse"],
  invalidate: ["失效", "Invalidate"],
  close: ["关闭", "Close"],
} as const;

export function SmartVoiceTickerSignals({
  data,
  zh,
}: {
  data: SvTickerSignalData;
  zh: boolean;
}) {
  const [horizon, setHorizon] = useState<SvSignalHorizon>("20D");
  const [cut, setCut] = useState<10 | 25>(25);
  const cohort = `top${cut}` as SvSignalCohort;
  const metrics = useMemo(() => buildSvOverviewMetrics(data, horizon, cohort), [cohort, data, horizon]);
  const targetDistribution = useMemo(
    () => buildWeightedTargetDistribution(
      data.evidence.filter((item) => item.percentile <= cut),
      horizon,
      data.prices.at(-1)?.close ?? null,
      metrics.asOfDay,
    ),
    [cut, data.evidence, data.prices, horizon, metrics.asOfDay],
  );
  const changes = useMemo(
    () => buildOpinionChangeRadar(
      data.evidence.filter((item) => item.percentile <= cut),
      horizon,
      metrics.asOfDay,
    ),
    [cut, data.evidence, horizon, metrics.asOfDay],
  );
  const stat = data.stats.find((item) => (
    item.cohort === cohort
    && item.signalHorizon === horizon
    && item.outcomeHorizon === horizon
    && item.direction === "all"
  ));
  const [shiftStatus, shiftTone] = shiftCopy(metrics.shift, zh);
  const [breadthStatus, breadthTone] = breadthCopy(metrics.breadth, zh);
  const [targetStatus, targetTone] = targetCopy(metrics.targetRevision, zh);
  const [divergenceStatus, divergenceTone] = divergenceCopy(metrics.priceDivergence, zh);
  const historyLabel = metrics.shift.historyDays >= 300
    ? (zh ? "过去一年" : "1Y")
    : (zh ? `过去 ${metrics.shift.historyDays} 天` : `${metrics.shift.historyDays}D`);

  return (
    <section className="overflow-hidden rounded-lg bg-ink/25 ring-1 ring-inset ring-line">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line px-4 py-3">
        <div>
          <div className="text-[9px] font-bold uppercase tracking-[0.16em] text-reddit">Smart Voice · Overview</div>
          <h3 className="mt-1 font-display text-[14px] font-bold text-cream">
            {zh ? `${data.ticker} 优质投资者观点变化` : `${data.ticker} high-SV investor changes`}
          </h3>
          <p className="mt-1 text-[9px] text-neutral-600">
            {zh ? "核心数字展示变化幅度，并同时给出起止值、作者样本和历史位置。" : "Core values show the size of change with start/end levels, author samples and historical context."}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex rounded-md p-0.5 ring-1 ring-inset ring-line">
            {([25, 10] as const).map((value) => (
              <button
                key={value}
                type="button"
                onClick={() => setCut(value)}
                className={`rounded px-2 py-1 text-[9px] font-semibold ${cut === value ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-600 hover:text-neutral-300"}`}
              >
                Top {value}%
              </button>
            ))}
          </div>
          <div className="flex rounded-md p-0.5 ring-1 ring-inset ring-line">
            {HORIZONS.map((value) => (
              <button
                key={value}
                type="button"
                onClick={() => setHorizon(value)}
                className={`rounded px-2 py-1 text-[9px] font-semibold ${horizon === value ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-600 hover:text-neutral-300"}`}
              >
                {value}
              </button>
            ))}
          </div>
        </div>
      </div>

      <Summary
        shift={metrics.shift}
        breadth={metrics.breadth}
        target={metrics.targetRevision}
        divergence={metrics.priceDivergence}
        zh={zh}
      />

      <div className="grid divide-y divide-line border-b border-line sm:grid-cols-2 sm:divide-x sm:divide-y-0 xl:grid-cols-4">
        <MetricCell
          title={zh ? "SV 转向" : "SV shift"}
          value={signed(metrics.shift.score)}
          status={shiftStatus}
          tone={shiftTone}
          detail={zh
            ? `7日：${signed(metrics.shift.previousLevel)} → ${signed(metrics.shift.currentLevel)}`
            : `7D: ${signed(metrics.shift.previousLevel)} → ${signed(metrics.shift.currentLevel)}`}
          foot={metrics.shift.historyPercentile == null
            ? (zh ? "历史样本不足" : "Insufficient history")
            : `${zh ? `强于${historyLabel} ${metrics.shift.historyPercentile}% 的同类变化` : `Stronger than ${metrics.shift.historyPercentile}% of ${historyLabel} changes`}${metrics.shift.improvingSessions ? ` · ${zh ? `连续 ${metrics.shift.improvingSessions} 日` : `${metrics.shift.improvingSessions} sessions`}` : ""}`}
        />
        <MetricCell
          title={zh ? "变化广度" : "Change breadth"}
          value={metrics.breadth.percent == null ? "—" : `${metrics.breadth.percent.toFixed(0)}%`}
          status={breadthStatus}
          tone={breadthTone}
          detail={zh
            ? `${metrics.breadth.up} 位转多 · ${metrics.breadth.down} 位转空 · ${metrics.breadth.stable} 位稳定`
            : `${metrics.breadth.up} bullish · ${metrics.breadth.down} bearish · ${metrics.breadth.stable} stable`}
          foot={zh
            ? `有效作者 ${metrics.breadth.total} 位 · 新加入 ${metrics.breadth.newAuthors} 位`
            : `${metrics.breadth.total} effective authors · ${metrics.breadth.newAuthors} new`}
        />
        <MetricCell
          title={zh ? "SV 目标修正" : "SV target revision"}
          value={percent(metrics.targetRevision.changePct)}
          status={targetStatus}
          tone={targetTone}
          detail={`${money(metrics.targetRevision.previousMedian)} → ${money(metrics.targetRevision.currentMedian)}`}
          foot={zh
            ? `${metrics.targetRevision.count} 个明确目标 · 多数区间 ${money(metrics.targetRevision.low)}–${money(metrics.targetRevision.high)}`
            : `${metrics.targetRevision.count} targets · middle range ${money(metrics.targetRevision.low)}–${money(metrics.targetRevision.high)}`}
        />
        <MetricCell
          title={zh ? "价格-SV 背离" : "Price-SV divergence"}
          value={metrics.priceDivergence.sigma == null ? "—" : signed(metrics.priceDivergence.sigma, 1, "σ")}
          status={divergenceStatus}
          tone={divergenceTone}
          detail={zh
            ? `20日股价 ${percent(metrics.priceDivergence.priceReturnPct)} · SV转向 ${signed(metrics.priceDivergence.shiftScore)}`
            : `20D price ${percent(metrics.priceDivergence.priceReturnPct)} · SV shift ${signed(metrics.priceDivergence.shiftScore)}`}
          foot={zh
            ? `${historyLabel}有 ${metrics.priceDivergence.similarHistoryCount} 个交易日达到同级别`
            : `${metrics.priceDivergence.similarHistoryCount} sessions reached this scale in ${historyLabel}`}
        />
      </div>

      <div className="grid border-b border-line xl:grid-cols-[minmax(0,1.55fr)_minmax(280px,0.65fr)]">
        <div className="min-w-0 border-b border-line xl:border-b-0 xl:border-r">
          <div className="flex items-center justify-between gap-3 border-b border-line/70 px-4 py-2.5">
            <div>
              <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "股价与 SV 转向" : "Price and SV shift"}</h4>
              <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "柱状图为滚动 7 日观点变化，折线为同期股价" : "Bars show rolling 7D view changes; line shows price"}</p>
            </div>
            <span className="font-mono text-[8.5px] text-neutral-600">{metrics.asOfDay}</span>
          </div>
          <SmartVoiceShiftChart points={metrics.shift.series} prices={data.prices} zh={zh} />
        </div>
        <section className="min-w-0">
          <div className="flex items-center justify-between gap-3 border-b border-line/70 px-4 py-2.5">
            <div>
              <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "关键观点变化" : "Key view changes"}</h4>
              <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "最近 7 日中权重最高的观点更新" : "Highest-weight updates from the last 7 days"}</p>
            </div>
            <span className="font-mono text-[8.5px] text-neutral-600">{changes.changes.length}</span>
          </div>
          <div className="divide-y divide-line/60">
            {changes.changes.slice(0, 5).map(({ kind, evidence }) => (
              <div key={evidence.candidateId} className="px-4 py-2.5">
                <div className="flex items-center justify-between gap-2 text-[8.5px]">
                  <span className="truncate font-semibold text-neutral-300">{evidence.authorHandle || evidence.source}</span>
                  <span className={evidence.direction === "bull" ? "shrink-0 text-bull" : "shrink-0 text-bear"}>
                    {zh ? CHANGE_LABEL[kind][0] : CHANGE_LABEL[kind][1]} · {evidence.direction === "bull" ? (zh ? "看多" : "Bull") : (zh ? "看空" : "Bear")}
                  </span>
                </div>
                <p className="mt-1 line-clamp-2 text-[8.5px] leading-relaxed text-neutral-500">
                  {evidence.evidenceSpan || (zh ? evidence.summaryZh : evidence.summaryEn) || evidence.callStructure}
                </p>
              </div>
            ))}
            {!changes.changes.length && (
              <div className="grid min-h-[210px] place-items-center px-4 text-[9px] text-neutral-600">
                {zh ? "最近 7 日没有可识别的观点变化" : "No identifiable changes in the last 7 days"}
              </div>
            )}
          </div>
        </section>
      </div>

      <div className="grid xl:grid-cols-2">
        <SmartVoiceWeightedTargets
          distribution={targetDistribution}
          currentPrice={data.prices.at(-1)?.close ?? null}
          revision={metrics.targetRevision}
          zh={zh}
        />
        <HistoryValidation stat={stat} zh={zh} />
      </div>
    </section>
  );
}
