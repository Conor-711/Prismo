"use client";

import type { SvDivergenceDiagnostic } from "../smartVoiceSignalLogic";
import type { SvOpportunityIndicators, SvWeightedTargetDistribution } from "../smartVoiceDecisionLogic";

function level(value: number, zh: boolean) {
  if (value >= 70) return zh ? "高" : "High";
  if (value >= 40) return zh ? "中" : "Medium";
  return zh ? "低" : "Low";
}

function tone(value: number, inverse = false) {
  const elevated = value >= 70;
  if (inverse) return elevated ? "text-bear" : value >= 40 ? "text-gold" : "text-bull";
  return elevated ? "text-reddit" : value >= 40 ? "text-neutral-300" : "text-neutral-500";
}

export function SmartVoiceOpportunityStrip({
  indicators,
  divergence,
  targets,
  zh,
}: {
  indicators: SvOpportunityIndicators;
  divergence: SvDivergenceDiagnostic;
  targets: SvWeightedTargetDistribution;
  zh: boolean;
}) {
  const cards = [
    {
      label: zh ? "高低 SV 预期差" : "High/low SV gap",
      value: `${indicators.divergence.toFixed(0)}/100`,
      detail: divergence.spread == null
        ? (zh ? "样本不足" : "Insufficient")
        : `${zh ? "方向差" : "Direction gap"} ${divergence.spread >= 0 ? "+" : ""}${divergence.spread.toFixed(2)}`,
      tone: tone(indicators.divergence),
    },
    {
      label: zh ? "观点拥挤风险" : "Thesis crowding",
      value: level(indicators.crowding, zh),
      detail: `${zh ? "拥挤度" : "Crowding score"} ${indicators.crowding.toFixed(0)}/100`,
      tone: tone(indicators.crowding, true),
    },
    {
      label: zh ? "目标价离散度" : "Target dispersion",
      value: targets.dispersion == null ? "—" : `${(targets.dispersion * 100).toFixed(0)}%`,
      detail: `${targets.count} ${zh ? "个明确目标价" : "explicit targets"}`,
      tone: targets.dispersion != null && targets.dispersion > 0.5 ? "text-gold" : "text-neutral-300",
    },
    {
      label: zh ? "证据置信度" : "Evidence confidence",
      value: `${indicators.confidence.toFixed(0)}/100`,
      detail: indicators.freshnessDays == null ? (zh ? "无近期证据" : "No recent evidence") : `${zh ? "最新" : "latest"} ${indicators.freshnessDays}d`,
      tone: tone(indicators.confidence),
    },
  ];
  return (
    <div className="border-b border-line">
      <div className="flex items-center justify-between border-b border-line/60 px-4 py-2">
        <h3 className="text-[10px] font-semibold text-neutral-300">{zh ? "多空分歧机会扫描" : "Bull/bear divergence scanner"}</h3>
        <span className="text-[8px] font-semibold uppercase text-reddit">SV</span>
      </div>
      <div className="grid sm:grid-cols-2 xl:grid-cols-4">
        {cards.map((card) => (
          <div key={card.label} className="min-w-0 border-b border-line/60 px-4 py-3 odd:border-r sm:[&:nth-last-child(-n+2)]:border-b-0 xl:border-b-0 xl:border-r xl:last:border-r-0">
            <div className="text-[8.5px] text-neutral-600">{card.label}</div>
            <div className={`mt-1 font-mono text-[15px] font-bold ${card.tone}`}>{card.value}</div>
            <div className="mt-1 truncate text-[8.5px] text-neutral-600">{card.detail}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
