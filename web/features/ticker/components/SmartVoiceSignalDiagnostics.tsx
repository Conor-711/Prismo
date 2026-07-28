import type { SvSignalCohort, SvSignalHorizon, SvTickerSignalData, SvTickerSignalEvidence, SvTickerSignalSnapshot } from "@/server/queries/smartVoiceTickerSignals";
import {
  buildSvDivergence,
  buildSvMomentum,
  buildSvTermStructure,
  summarizeSvTargets,
  uniqueSvConditions,
} from "../smartVoiceSignalLogic";

function signed(value: number | null, digits = 2) {
  if (value == null || !Number.isFinite(value)) return "—";
  return `${value >= 0 ? "+" : ""}${value.toFixed(digits)}`;
}

function percent(value: number | null) {
  if (value == null || !Number.isFinite(value)) return "—";
  return `${value >= 0 ? "+" : ""}${(value * 100).toFixed(1)}%`;
}

function money(value: number | null) {
  if (value == null || !Number.isFinite(value)) return "—";
  return `$${value.toLocaleString(undefined, { maximumFractionDigits: value >= 100 ? 0 : 2 })}`;
}

function toneForState(state: string) {
  if (state.includes("bull")) return "text-bull";
  if (state.includes("bear")) return "text-bear";
  if (state === "accelerating") return "text-reddit";
  if (state === "fading") return "text-gold";
  return "text-neutral-300";
}

function NetMeter({ value }: { value: number | null }) {
  const net = Math.max(-1, Math.min(1, value ?? 0));
  const width = `${Math.abs(net) * 50}%`;
  const left = net >= 0 ? "50%" : `${50 - Math.abs(net) * 50}%`;
  return (
    <div className="relative h-1.5 overflow-hidden rounded-full bg-white/[.05]">
      <span className="absolute inset-y-0 left-1/2 w-px bg-neutral-500/70" />
      {value != null && <span className={`absolute inset-y-0 ${net >= 0 ? "bg-bull" : "bg-bear"}`} style={{ left, width }} />}
    </div>
  );
}

const DIVERGENCE_COPY = {
  insufficient: ["样本不足", "Insufficient"],
  aligned_bull: ["高低 SV 同向看多", "High/low SV aligned bullish"],
  aligned_bear: ["高低 SV 同向看空", "High/low SV aligned bearish"],
  bullish_divergence: ["高 SV 看多 / 低 SV 看空", "High SV bull / low SV bear"],
  bearish_divergence: ["高 SV 看空 / 低 SV 看多", "High SV bear / low SV bull"],
  mixed: ["弱分歧 / 中性", "Weak divergence / neutral"],
} as const;

const TERM_COPY = {
  insufficient: ["周期样本不足", "Insufficient horizons"],
  broad_bull: ["全周期看多", "Bullish across horizons"],
  broad_bear: ["全周期看空", "Bearish across horizons"],
  short_bull_long_bear: ["短多长空", "Short bull / long bear"],
  short_bear_long_bull: ["短空长多", "Short bear / long bull"],
  bullish_steepening: ["短端转强", "Front end strengthening"],
  bearish_steepening: ["短端转弱", "Front end weakening"],
  mixed: ["周期分化", "Mixed term structure"],
} as const;

const MOMENTUM_COPY = {
  insufficient: ["历史不足", "Insufficient history"],
  bullish_reversal: ["看多反转", "Bullish reversal"],
  bearish_reversal: ["看空反转", "Bearish reversal"],
  accelerating: ["同向加速", "Signal accelerating"],
  fading: ["信号衰减", "Signal fading"],
  stable: ["信号稳定", "Signal stable"],
} as const;

function EvidenceColumn({
  title,
  evidence,
  currentPrice,
  windowDays,
  zh,
}: {
  title: string;
  evidence: SvTickerSignalEvidence[];
  currentPrice: number | null;
  windowDays: number;
  zh: boolean;
}) {
  const targets = summarizeSvTargets(evidence, currentPrice);
  const invalidations = uniqueSvConditions(evidence, "invalidationCondition");
  const triggers = uniqueSvConditions(evidence, "triggerCondition", 2);
  const targetTone = targets.dominantDirection === "bull"
    ? targets.impliedMove != null && targets.impliedMove < 0 ? "text-gold" : "text-bull"
    : targets.dominantDirection === "bear"
      ? targets.impliedMove != null && targets.impliedMove > 0 ? "text-gold" : "text-bear"
      : "text-cream";
  return (
    <div className="min-w-0 px-4 py-3">
      <div className="flex items-center justify-between gap-3">
        <div className="text-[10px] font-semibold text-neutral-300">{title}</div>
        <div className="text-[8.5px] text-neutral-600">{evidence.length} {zh ? `条近 ${windowDays} 日观点` : `views / ${windowDays}d`}</div>
      </div>
      <div className="mt-2 grid grid-cols-[128px_minmax(0,1fr)] gap-4">
        <div className="min-w-0 border-r border-line/70 pr-4">
          <div className="text-[8.5px] text-neutral-600">{zh ? "目标价中位" : "Median target"}</div>
          <div className={`mt-1 font-mono text-[17px] font-bold ${targetTone}`}>
            {money(targets.median)}
          </div>
          <div className="mt-1 text-[9px] text-neutral-500">
            {targets.count
              ? `${zh ? "多数目标区间" : "Middle 50%"} ${money(targets.low)}–${money(targets.high)} · ${targets.count} ${zh ? "个目标" : "targets"}`
              : (zh ? "无有效目标价" : "No valid targets")}
          </div>
          {!!targets.count && <div className="mt-1 text-[8.5px] text-neutral-600">{zh ? "多" : "Bull"} {targets.bullCount} · {zh ? "空" : "Bear"} {targets.bearCount} · {zh ? "已到达" : "reached"} {targets.reachedCount}</div>}
          {targets.impliedMove != null && <div className="mt-1 font-mono text-[9px] text-neutral-400">{zh ? "相对最新日线" : "vs last close"} {percent(targets.impliedMove)}</div>}
        </div>
        <div className="min-w-0">
          <div className="flex items-center justify-between text-[8.5px] text-neutral-600">
            <span>{zh ? "明确失效条件" : "Explicit invalidations"}</span>
            <span>{invalidations.length}</span>
          </div>
          <div className="mt-1.5 space-y-1.5">
            {invalidations.map((item) => (
              <div key={`${item.source}:${item.text}`} className="flex min-w-0 gap-2 text-[9px] leading-snug">
                <span className={`mt-1 h-1.5 w-1.5 shrink-0 rounded-full ${item.direction === "bear" ? "bg-bear" : item.direction === "bull" ? "bg-bull" : "bg-neutral-500"}`} />
                <span className="line-clamp-2 text-neutral-400">{item.text}</span>
                <span className="ml-auto shrink-0 uppercase text-neutral-700">{item.source}</span>
              </div>
            ))}
            {!invalidations.length && <div className="text-[9px] text-neutral-700">{zh ? `近 ${windowDays} 日观点未明确给出失效条件` : `No explicit invalidation in the last ${windowDays} days`}</div>}
          </div>
          {!!triggers.length && (
            <div className="mt-2 border-t border-line/60 pt-1.5 text-[8.5px] text-neutral-600">
              {zh ? "触发条件" : "Triggers"} · {triggers.map((item) => item.text).join(" / ")}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export function SmartVoiceSignalDiagnostics({
  data,
  top,
  bottom,
  topCohort,
  bottomCohort,
  horizon,
  cut,
  zh,
}: {
  data: SvTickerSignalData;
  top?: SvTickerSignalSnapshot;
  bottom?: SvTickerSignalSnapshot;
  topCohort: SvSignalCohort;
  bottomCohort: SvSignalCohort;
  horizon: SvSignalHorizon;
  cut: 10 | 25;
  zh: boolean;
}) {
  const divergence = buildSvDivergence(top, bottom);
  const term = buildSvTermStructure(data.current, topCohort);
  const momentum = buildSvMomentum(data.history, topCohort, horizon);
  const currentPrice = data.prices.at(-1)?.close ?? null;
  const evidenceByCohort = (cohort: SvSignalCohort) => {
    const topBand = cohort.startsWith("top");
    const threshold = Number(cohort.replace(/\D/g, ""));
    return data.evidence.filter((item) => (
      item.horizon === horizon
      && (topBand ? item.percentile <= threshold : item.percentile >= 100 - threshold)
    ));
  };
  const topEvidence = evidenceByCohort(topCohort);
  const bottomEvidence = evidenceByCohort(bottomCohort);
  const divergenceLabel = DIVERGENCE_COPY[divergence.state][zh ? 0 : 1];
  const termLabel = TERM_COPY[term.state][zh ? 0 : 1];
  const momentumLabel = MOMENTUM_COPY[momentum.state][zh ? 0 : 1];

  return (
    <div className="border-b border-line">
      <div className="border-b border-line/70 px-4 py-2">
        <div className="text-[9px] font-semibold uppercase tracking-[0.12em] text-neutral-600">{zh ? "SV 信号诊断" : "SV signal diagnostics"}</div>
      </div>
      <div className="grid divide-y divide-line/70 lg:grid-cols-3 lg:divide-x lg:divide-y-0">
        <div className="min-w-0 px-4 py-3">
          <div className="text-[8.5px] text-neutral-600">{zh ? "高低 SV 分歧" : "High/low SV divergence"}</div>
          <div className={`mt-1 text-[12px] font-semibold ${toneForState(divergence.state)}`}>{divergenceLabel}</div>
          <div className="mt-2 grid grid-cols-2 gap-3 text-[8.5px]">
            <div><span className="text-neutral-600">Top</span><b className="ml-1 font-mono text-cream">{signed(divergence.topNet)}</b><NetMeter value={divergence.topNet} /></div>
            <div><span className="text-neutral-600">Bottom</span><b className="ml-1 font-mono text-cream">{signed(divergence.bottomNet)}</b><NetMeter value={divergence.bottomNet} /></div>
          </div>
          <div className="mt-2 flex items-center justify-between text-[8.5px] text-neutral-600">
            <span>{zh ? "净分歧" : "Net spread"} <b className="font-mono text-neutral-300">{signed(divergence.spread)}</b> · {zh ? "强度" : "strength"} {divergence.strength.toFixed(0)}%</span>
            <span>{zh ? "可信覆盖" : "Coverage"} {(divergence.coverage * 100).toFixed(0)}%</span>
          </div>
        </div>

        <div className="min-w-0 px-4 py-3">
          <div className="text-[8.5px] text-neutral-600">{zh ? "Top SV 周期结构" : "Top SV term structure"}</div>
          <div className={`mt-1 text-[12px] font-semibold ${toneForState(term.state)}`}>{termLabel}</div>
          <div className="mt-2 grid grid-cols-6 gap-1.5">
            {term.points.map((point) => (
              <div key={point.horizon} className="min-w-0 text-center">
                <div className="flex h-7 items-center"><div className="w-full"><NetMeter value={point.net} /></div></div>
                <div className="text-[8px] text-neutral-600">{point.horizon}</div>
              </div>
            ))}
          </div>
          <div className="mt-2 flex items-center justify-between text-[8.5px] text-neutral-600">
            <span>{zh ? "短端" : "Short"} <b className="font-mono text-neutral-300">{signed(term.shortNet)}</b></span>
            <span>{zh ? "长端" : "Long"} <b className="font-mono text-neutral-300">{signed(term.longNet)}</b></span>
            <span>{zh ? "斜率" : "Slope"} <b className="font-mono text-neutral-300">{signed(term.slope)}</b></span>
          </div>
        </div>

        <div className="min-w-0 px-4 py-3">
          <div className="text-[8.5px] text-neutral-600">{zh ? `Top SV 加速与反转 · ${horizon}` : `Top SV momentum · ${horizon}`}</div>
          <div className={`mt-1 text-[12px] font-semibold ${toneForState(momentum.state)}`}>{momentumLabel}</div>
          <div className="mt-2 flex h-7 items-center gap-1">
            {momentum.points.map((point) => (
              <span
                key={point.day}
                className={`min-w-0 flex-1 rounded-sm ${point.weightedNet >= 0 ? "bg-bull" : "bg-bear"}`}
                style={{ height: `${Math.max(3, Math.abs(point.weightedNet) * 24)}px`, opacity: 0.35 + Math.abs(point.weightedNet) * 0.65 }}
                title={`${point.day} ${signed(point.weightedNet)}`}
              />
            ))}
          </div>
          <div className="mt-2 flex items-center justify-between text-[8.5px] text-neutral-600">
            <span>{zh ? "近 5 日变化" : "5-session delta"} <b className="font-mono text-neutral-300">{signed(momentum.delta)}</b></span>
            <span>{zh ? "作者变化" : "Voice delta"} <b className="font-mono text-neutral-300">{signed(momentum.authorDelta, 0)}</b></span>
            {momentum.reversalDay && <span>{zh ? "反转" : "Reversed"} {momentum.reversalDay.slice(5)}</span>}
          </div>
        </div>
      </div>

      <div className="flex items-center justify-between gap-3 border-t border-line/70 px-4 py-2 text-[8.5px] text-neutral-600">
        <span className="font-semibold uppercase tracking-[0.1em]">{zh ? "目标价与失效条件聚合" : "Targets and invalidation conditions"}</span>
        <span>{zh ? "最新日线" : "Last close"} {money(currentPrice)} · {data.prices.at(-1)?.day ?? "—"}</span>
      </div>
      <div className="grid divide-y divide-line/70 border-t border-line/70 lg:grid-cols-2 lg:divide-x lg:divide-y-0">
        <EvidenceColumn title={`Top ${cut}% SV · ${horizon}`} evidence={topEvidence} currentPrice={currentPrice} windowDays={data.evidenceWindowDays} zh={zh} />
        <EvidenceColumn title={`Bottom ${cut}% SV · ${horizon}`} evidence={bottomEvidence} currentPrice={currentPrice} windowDays={data.evidenceWindowDays} zh={zh} />
      </div>
    </div>
  );
}
