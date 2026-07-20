"use client";

import { useMemo, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { smartVoiceInvestorHref, type SvTickerBoard } from "@/features/smart-voice";
import type { SvSignalCohort, SvSignalHorizon, SvTickerSignalData, SvTickerSignalSnapshot, SvTickerSignalStat } from "@/server/queries/smartVoiceTickerSignals";
import { SmartVoiceSignalChart } from "./SmartVoiceSignalChart";
import { SmartVoiceSignalDiagnostics } from "./SmartVoiceSignalDiagnostics";
import { SmartVoiceDecisionSuite } from "./SmartVoiceDecisionSuite";

const HORIZONS: SvSignalHorizon[] = ["1D", "5D", "20D", "60D", "90D", "180D"];

function pct(value: number | null, digits = 1) {
  if (value == null || !Number.isFinite(value)) return "—";
  return `${value >= 0 ? "+" : ""}${(value * 100).toFixed(digits)}%`;
}

function wilsonInterval(rate: number, sampleSize: number): [number, number] {
  if (sampleSize <= 0) return [0, 1];
  const z = 1.96;
  const z2 = z * z;
  const successes = Math.round(rate * sampleSize);
  const observed = successes / sampleSize;
  const denominator = 1 + z2 / sampleSize;
  const center = (observed + z2 / (2 * sampleSize)) / denominator;
  const margin = z * Math.sqrt((observed * (1 - observed) + z2 / (4 * sampleSize)) / sampleSize) / denominator;
  return [Math.max(0, center - margin), Math.min(1, center + margin)];
}

function directionLabel(direction: "bull" | "bear", zh: boolean) {
  return direction === "bull" ? (zh ? "看多" : "Bullish") : (zh ? "看空" : "Bearish");
}

function SnapshotGroup({
  title,
  snapshot,
  zh,
}: {
  title: string;
  snapshot?: SvTickerSignalSnapshot;
  zh: boolean;
}) {
  if (!snapshot) {
    return (
      <div className="min-w-0 px-4 py-3">
        <div className="text-[11px] font-semibold text-neutral-400">{title}</div>
        <div className="mt-4 text-[11px] text-neutral-600">{zh ? "近期没有可分层观点" : "No recent scoreable views"}</div>
      </div>
    );
  }
  const directionTone = snapshot.dominantDirection === "bull" ? "text-bull" : "text-bear";
  const topCallType = Object.entries(snapshot.callTypes).sort((a, b) => b[1] - a[1])[0]?.[0];
  return (
    <div className="min-w-0 px-4 py-3">
      <div className="flex items-center justify-between gap-2">
        <div>
          <div className="text-[11px] font-semibold text-neutral-300">{title}</div>
          <div className="mt-0.5 text-[9px] text-neutral-600">{zh ? `截至 ${snapshot.day}` : `As of ${snapshot.day}`}</div>
        </div>
        <div className="text-right">
          <div className={`font-display text-[17px] font-extrabold leading-none ${directionTone}`}>
            {directionLabel(snapshot.dominantDirection, zh)}
          </div>
          <div className="mt-1 text-[9px] text-neutral-600">
            {snapshot.cluster ? (zh ? "形成聚集" : "Cluster active") : (zh ? "未形成聚集" : "No cluster")}
          </div>
        </div>
      </div>
      <div className="mt-3 flex h-2 overflow-hidden rounded-full bg-white/[.05]">
        <span className="bg-bull" style={{ width: `${snapshot.bullShare * 100}%` }} />
        <span className="bg-bear" style={{ width: `${snapshot.bearShare * 100}%` }} />
      </div>
      <div className="mt-1.5 flex items-center justify-between text-[10px]">
        <span className="text-bull">{zh ? "多" : "Bull"} {snapshot.nBull}</span>
        <span className="font-mono text-neutral-500">{snapshot.nAuthors} {zh ? "位作者" : "voices"}</span>
        <span className="text-bear">{zh ? "空" : "Bear"} {snapshot.nBear}</span>
      </div>
      <div className="mt-3 grid grid-cols-3 gap-3 border-t border-line/70 pt-2 text-[9px]">
        <div>
          <div className="text-neutral-600">{zh ? "有效广度" : "Breadth"}</div>
          <div className="mt-0.5 font-mono text-[11px] text-cream">{snapshot.effectiveVoices.toFixed(1)}</div>
        </div>
        <div>
          <div className="text-neutral-600">{zh ? "平台确认" : "Platforms"}</div>
          <div className="mt-0.5 font-mono text-[11px] text-cream">{snapshot.sourceCount}</div>
        </div>
        <div>
          <div className="text-neutral-600">{zh ? "平均 SV" : "Avg SV"}</div>
          <div className="mt-0.5 font-mono text-[11px] text-cream">{snapshot.avgSv.toFixed(0)}</div>
        </div>
      </div>
      <div className="mt-2 flex min-w-0 flex-wrap gap-1 text-[9px] text-neutral-500">
        {snapshot.targetMedian != null && <span className="rounded bg-white/[.04] px-1.5 py-0.5">{zh ? "目标中位" : "Target median"} ${snapshot.targetMedian.toFixed(0)}</span>}
        <span className="rounded bg-white/[.04] px-1.5 py-0.5">{zh ? "明确周期" : "Explicit horizon"} {snapshot.explicitHorizonCount}/{snapshot.nAuthors}</span>
        {topCallType && <span className="max-w-[150px] truncate rounded bg-white/[.04] px-1.5 py-0.5">{topCallType.replaceAll("_", " ")}</span>}
      </div>
    </div>
  );
}

function BacktestStats({ title, stat, zh }: { title: string; stat?: SvTickerSignalStat; zh: boolean }) {
  const enough = (stat?.nEvents ?? 0) >= 10;
  const interval = stat?.hitRate != null && stat.nEvents > 0 ? wilsonInterval(stat.hitRate, stat.nEvents) : null;
  return (
    <div className="min-w-0 px-4 py-3">
      <div className="flex items-center justify-between gap-2">
        <span className="text-[11px] font-semibold text-neutral-300">{title}</span>
        <span className={`text-[9px] ${enough ? "text-neutral-500" : "text-gold"}`}>
          {stat ? `${stat.nEvents} ${zh ? "次事件" : "events"}` : (zh ? "暂无样本" : "No sample")}
        </span>
      </div>
      <div className="mt-2 grid grid-cols-4 divide-x divide-line/70">
        {[
          [zh ? "命中率" : "Hit rate", stat?.hitRate == null ? "—" : `${(stat.hitRate * 100).toFixed(0)}%`],
          [zh ? "超额中位" : "Median excess", pct(stat?.medianDirectionalExcessPct ?? null)],
          [zh ? "最大有利" : "Avg MFE", pct(stat?.avgMaxFavorableExcess ?? null)],
          [zh ? "最大不利" : "Avg MAE", pct(stat?.avgMaxAdverseExcess ?? null)],
        ].map(([label, value]) => (
          <div key={label} className="min-w-0 px-2 first:pl-0 last:pr-0">
            <div className="truncate text-[8.5px] text-neutral-600">{label}</div>
            <div className="mt-1 truncate font-mono text-[11px] font-semibold text-cream">{value}</div>
          </div>
        ))}
      </div>
      {interval && (
        <div className={`mt-2 text-[8.5px] ${enough ? "text-neutral-600" : "text-gold"}`}>
          {zh
            ? `95% 命中区间 ${(interval[0] * 100).toFixed(0)}%–${(interval[1] * 100).toFixed(0)}%${enough ? "" : "；样本不足，不可据此比较分组优劣。"}`
            : `95% hit interval ${(interval[0] * 100).toFixed(0)}%–${(interval[1] * 100).toFixed(0)}%${enough ? "" : "; too few events for cohort comparison."}`}
        </div>
      )}
    </div>
  );
}

export function SmartVoiceTickerSignals({
  data,
  board,
  zh,
}: {
  data: SvTickerSignalData;
  board?: SvTickerBoard | null;
  zh: boolean;
}) {
  const [horizon, setHorizon] = useState<SvSignalHorizon>("20D");
  const [cut, setCut] = useState<10 | 25>(25);
  const topCohort = `top${cut}` as SvSignalCohort;
  const bottomCohort = `bottom${cut}` as SvSignalCohort;
  const currentTop = data.current.find((item) => item.horizon === horizon && item.cohort === topCohort);
  const currentBottom = data.current.find((item) => item.horizon === horizon && item.cohort === bottomCohort);
  const selectedEvents = useMemo(
    () => data.events.filter((event) => event.horizon === horizon && (event.cohort === topCohort || event.cohort === bottomCohort)),
    [bottomCohort, data.events, horizon, topCohort],
  );
  const statFor = (cohort: SvSignalCohort) => data.stats.find(
    (item) => item.cohort === cohort && item.signalHorizon === horizon && item.outcomeHorizon === horizon && item.direction === "all",
  );
  const topStat = statFor(topCohort);
  const bottomStat = statFor(bottomCohort);
  const comparableBacktest = (topStat?.nEvents ?? 0) >= 10 && (bottomStat?.nEvents ?? 0) >= 10;
  return (
    <section className="overflow-hidden rounded-lg bg-ink/25 ring-1 ring-inset ring-line">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line px-4 py-3">
        <div>
          <div className="text-[9px] font-bold uppercase tracking-[0.16em] text-reddit">Smart Voice · Ticker Signal</div>
          <h3 className="mt-1 font-display text-[14px] font-bold text-cream">{zh ? `${data.ticker} 的 SV 聚集与历史战绩` : `${data.ticker} SV clusters and track record`}</h3>
          <p className="mt-1 text-[10px] text-neutral-600">{zh ? "历史分层只使用当时已经结算的观点，下一交易日开盘后开始计算表现。" : "Point-in-time cohorts only; performance starts after the next market open."}</p>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex rounded-md p-0.5 ring-1 ring-inset ring-line">
            {([25, 10] as const).map((value) => (
              <button key={value} type="button" onClick={() => setCut(value)} className={`rounded px-2 py-1 text-[10px] font-semibold ${cut === value ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-500"}`}>
                {value}%
              </button>
            ))}
          </div>
          <div className="flex rounded-md p-0.5 ring-1 ring-inset ring-line">
            {HORIZONS.map((value) => (
              <button key={value} type="button" onClick={() => setHorizon(value)} className={`rounded px-2 py-1 text-[10px] font-semibold ${horizon === value ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-500 hover:text-cream"}`}>
                {value}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="grid divide-y divide-line border-b border-line lg:grid-cols-2 lg:divide-x lg:divide-y-0">
        <SnapshotGroup title={`Top ${cut}% SV`} snapshot={currentTop} zh={zh} />
        <SnapshotGroup title={`Bottom ${cut}% SV`} snapshot={currentBottom} zh={zh} />
      </div>

      <SmartVoiceSignalDiagnostics
        data={data}
        top={currentTop}
        bottom={currentBottom}
        topCohort={topCohort}
        bottomCohort={bottomCohort}
        horizon={horizon}
        cut={cut}
        zh={zh}
      />

      <SmartVoiceDecisionSuite
        data={data}
        horizon={horizon}
        top={currentTop}
        bottom={currentBottom}
        topCohort={topCohort}
        bottomCohort={bottomCohort}
        zh={zh}
      />

      <div className="border-b border-line px-3 pt-2">
        <div className="flex items-center justify-between gap-3 px-1 text-[9px] text-neutral-600">
          <span>{zh ? "价格与历史 SV 聚集" : "Price and historical SV clusters"}</span>
          <span className="flex items-center gap-3">
            <span><b className="text-bull">◆</b> {zh ? "看多" : "Bull"}</span>
            <span><b className="text-bear">◆</b> {zh ? "看空" : "Bear"}</span>
            <span>◆ Top · ○ Bottom</span>
          </span>
        </div>
        <SmartVoiceSignalChart prices={data.prices} events={selectedEvents} outcomeHorizon={horizon} zh={zh} />
      </div>

      <div className="grid divide-y divide-line border-b border-line lg:grid-cols-2 lg:divide-x lg:divide-y-0">
        <BacktestStats title={`Top ${cut}% SV · ${horizon}`} stat={topStat} zh={zh} />
        <BacktestStats title={`Bottom ${cut}% SV · ${horizon}`} stat={bottomStat} zh={zh} />
      </div>
      {!comparableBacktest && (
        <div className="border-b border-line bg-gold/[.04] px-4 py-2 text-[9px] leading-relaxed text-gold/90">
          {zh
            ? "当前仅展示未经平滑的真实事件结果。任一分组少于 10 次时，不判断 Top / Bottom 谁更强；重叠持有期也不等同于独立样本。"
            : "Raw event outcomes only. Do not rank Top vs Bottom while either cohort has fewer than 10 events; overlapping holding periods are not independent samples."}
        </div>
      )}

      <div className="grid gap-0 lg:grid-cols-[minmax(0,1fr)_290px]">
        <div className="min-w-0 border-b border-line lg:border-b-0 lg:border-r">
          <div className="border-b border-line/70 px-4 py-2 text-[9px] font-semibold uppercase text-neutral-600">{zh ? "最近聚集事件" : "Recent cluster events"}</div>
          {selectedEvents.slice(0, 5).map((event) => {
            const outcome = event.outcomes.find((item) => item.horizon === horizon);
            return (
              <div key={event.id} className="grid grid-cols-[72px_74px_minmax(0,1fr)_56px] items-center gap-2 border-b border-line/60 px-4 py-2 text-[9.5px] last:border-b-0">
                <span className="font-mono text-neutral-500">{event.signalDay}</span>
                <span className={event.direction === "bull" ? "text-bull" : "text-bear"}>{event.cohort.startsWith("top") ? "Top" : "Bottom"} · {directionLabel(event.direction, zh)}</span>
                <span className="truncate text-neutral-500">{event.nAuthors} {zh ? "位作者" : "voices"} · {(event.consensusStrength * 100).toFixed(0)}% {zh ? "同向" : "aligned"}</span>
                <span className={`text-right font-mono ${outcome?.directionalExcessPct != null && outcome.directionalExcessPct >= 0 ? "text-bull" : "text-bear"}`}>{pct(outcome?.directionalExcessPct ?? null)}</span>
              </div>
            );
          })}
          {!selectedEvents.length && <div className="px-4 py-6 text-center text-[10px] text-neutral-600">{zh ? "该周期尚无聚集事件" : "No cluster events for this horizon"}</div>}
        </div>
        <div className="min-w-0 px-4 py-3">
          <div className="text-[9px] font-semibold uppercase text-neutral-600">{zh ? "相关高 SV 投资者" : "Relevant high-SV voices"}</div>
          <div className="mt-2 space-y-1.5">
            {board?.investors.slice(0, 4).map((investor) => (
              <LocaleLink key={investor.id} href={smartVoiceInvestorHref(investor.id)} className="flex min-w-0 items-center justify-between gap-2 rounded px-2 py-1.5 hover:bg-white/[.04]">
                <span className="truncate text-[10px] text-neutral-300">{investor.name}</span>
                <span className="font-mono text-[10px] font-semibold text-reddit">{investor.contextualSv}</span>
              </LocaleLink>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
