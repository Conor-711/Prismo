"use client";

import type { SvOpinionChangeRadar, SvChangeKind } from "../smartVoiceDecisionLogic";

const COPY: Record<SvChangeKind, { zh: string; en: string; tone: string }> = {
  new: { zh: "新开", en: "New", tone: "text-reddit" },
  reinforce: { zh: "加强", en: "Reinforce", tone: "text-bull" },
  reverse: { zh: "反转", en: "Reverse", tone: "text-gold" },
  invalidate: { zh: "失效", en: "Invalidate", tone: "text-bear" },
  close: { zh: "关闭", en: "Close", tone: "text-neutral-400" },
};

const signed = (value: number | null, pct = false) => value == null
  ? "—"
  : `${value >= 0 ? "+" : ""}${(value * (pct ? 100 : 1)).toFixed(pct ? 1 : 2)}${pct ? "%" : ""}`;

export function SmartVoiceChangeRadar({ radar, zh }: { radar: SvOpinionChangeRadar; zh: boolean }) {
  const deltaTone = (radar.netDelta ?? 0) > 0.08 ? "text-bull" : (radar.netDelta ?? 0) < -0.08 ? "text-bear" : "text-neutral-300";
  return (
    <section className="min-w-0">
      <div className="flex items-center justify-between gap-3 border-b border-line/70 px-4 py-2.5">
        <div>
          <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "Score 观点变化雷达" : "Score opinion change radar"}</h4>
          <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "最近 7 天相对前 7 天；基于同一作者的 Call 生命周期" : "Latest 7 days vs prior 7; based on author call lifecycle"}</p>
        </div>
        <div className="text-right">
          <div className={`font-mono text-[15px] font-bold ${deltaTone}`}>{signed(radar.netDelta)}</div>
          <div className="text-[8.5px] text-neutral-600">{zh ? "Score 净方向变化" : "Score net direction delta"}</div>
        </div>
      </div>
      <div className="grid grid-cols-4 divide-x divide-line/60 border-b border-line/60 px-4 py-2 text-[8.5px]">
        <div><span className="text-neutral-600">7D Call</span><b className="ml-1 font-mono text-neutral-300">{radar.currentCalls}</b></div>
        <div className="pl-3"><span className="text-neutral-600">{zh ? "前期" : "Prior"}</span><b className="ml-1 font-mono text-neutral-300">{radar.previousCalls}</b></div>
        <div className="pl-3"><span className="text-neutral-600">{zh ? "目标变化" : "Target Δ"}</span><b className="ml-1 font-mono text-neutral-300">{signed(radar.targetShift, true)}</b></div>
        <div className="pl-3"><span className="text-neutral-600">{zh ? "反转/失效" : "Rev./invalid"}</span><b className="ml-1 font-mono text-neutral-300">{radar.counts.reverse + radar.counts.invalidate + radar.counts.close}</b></div>
      </div>
      <div className="grid grid-cols-5 divide-x divide-line/60 border-b border-line/60 bg-white/[.015]">
        {(Object.keys(COPY) as SvChangeKind[]).map((kind) => (
          <div key={kind} className="px-3 py-2 text-center">
            <div className={`font-mono text-[13px] font-bold ${COPY[kind].tone}`}>{radar.counts[kind]}</div>
            <div className="text-[8px] text-neutral-600">{zh ? COPY[kind].zh : COPY[kind].en}</div>
          </div>
        ))}
      </div>
      <div className="divide-y divide-line/60">
        {radar.changes.slice(0, 5).map(({ kind, evidence }) => (
          <div key={evidence.candidateId} className="grid grid-cols-[46px_88px_minmax(0,1fr)_50px] items-center gap-2 px-4 py-2 text-[9px]">
            <span className={`font-semibold ${COPY[kind].tone}`}>{zh ? COPY[kind].zh : COPY[kind].en}</span>
            <span className="truncate text-neutral-400">{evidence.authorHandle || evidence.source}</span>
            <span className="truncate text-neutral-500">{evidence.evidenceSpan || evidence.summaryZh || evidence.summaryEn || evidence.callStructure}</span>
            <span className={evidence.direction === "bull" ? "text-right text-bull" : "text-right text-bear"}>{evidence.direction === "bull" ? (zh ? "看多" : "Bull") : (zh ? "看空" : "Bear")}</span>
          </div>
        ))}
        {!radar.changes.length && <div className="px-4 py-8 text-center text-[10px] text-neutral-600">{zh ? "最近 7 天没有可识别的观点变化" : "No identifiable opinion changes in the last 7 days"}</div>}
      </div>
    </section>
  );
}
