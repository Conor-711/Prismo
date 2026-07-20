"use client";

import { useMemo } from "react";
import type { SvSignalCohort, SvSignalHorizon, SvTickerSignalData, SvTickerSignalSnapshot } from "@/server/queries/smartVoiceTickerSignals";
import {
  buildOpinionChangeRadar,
  buildOpportunityIndicators,
  buildWeightedTargetDistribution,
} from "../smartVoiceDecisionLogic";
import { buildSvDivergence, buildSvMomentum } from "../smartVoiceSignalLogic";
import { SmartVoiceChangeRadar } from "./SmartVoiceChangeRadar";
import { SmartVoiceOpportunityStrip } from "./SmartVoiceOpportunityStrip";
import { SmartVoicePersonalAssistant } from "./SmartVoicePersonalAssistant";
import { SmartVoiceWeightedTargets } from "./SmartVoiceWeightedTargets";
import { SmartVoiceResearchSuite } from "./SmartVoiceResearchSuite";

export function SmartVoiceDecisionSuite({
  data,
  horizon,
  top,
  bottom,
  topCohort,
  bottomCohort,
  zh,
}: {
  data: SvTickerSignalData;
  horizon: SvSignalHorizon;
  top?: SvTickerSignalSnapshot;
  bottom?: SvTickerSignalSnapshot;
  topCohort: SvSignalCohort;
  bottomCohort: SvSignalCohort;
  zh: boolean;
}) {
  const currentPrice = data.prices.at(-1)?.close ?? null;
  const asOfDay = data.current.map((item) => item.day).sort().at(-1) ?? data.prices.at(-1)?.day ?? "";
  const distribution = useMemo(
    () => buildWeightedTargetDistribution(data.evidence, horizon, currentPrice, asOfDay),
    [asOfDay, currentPrice, data.evidence, horizon],
  );
  const radar = useMemo(
    () => buildOpinionChangeRadar(data.evidence, horizon, asOfDay),
    [asOfDay, data.evidence, horizon],
  );
  const indicators = useMemo(
    () => buildOpportunityIndicators(top, bottom, data.evidence, horizon, asOfDay),
    [asOfDay, bottom, data.evidence, horizon, top],
  );
  const divergence = buildSvDivergence(top, bottom);
  const momentum = buildSvMomentum(data.history, topCohort, horizon);
  return (
    <div className="border-b border-line">
      <div className="flex items-center justify-between gap-3 border-b border-line/70 bg-white/[.012] px-4 py-2">
        <div>
          <span className="text-[9px] font-semibold uppercase tracking-[0.12em] text-neutral-500">{zh ? "决策实验室" : "Decision lab"}</span>
          <span className="ml-2 text-[8.5px] text-neutral-700">{topCohort} / {bottomCohort} · {horizon} · {asOfDay}</span>
        </div>
        <span className="rounded bg-reddit/10 px-1.5 py-0.5 text-[8px] font-semibold text-reddit ring-1 ring-inset ring-reddit/25">{zh ? "真实 SV" : "REAL SV"}</span>
      </div>
      <SmartVoiceOpportunityStrip indicators={indicators} divergence={divergence} targets={distribution} zh={zh} />
      <div className="grid lg:grid-cols-2">
        <SmartVoiceWeightedTargets distribution={distribution} currentPrice={currentPrice} zh={zh} />
        <SmartVoiceChangeRadar radar={radar} zh={zh} />
      </div>
      <SmartVoiceResearchSuite
        data={data}
        horizon={horizon}
        asOfDay={asOfDay}
        divergence={divergence}
        momentum={momentum}
        targets={distribution}
        radar={radar}
        indicators={indicators}
        zh={zh}
      />
      <SmartVoicePersonalAssistant data={data} fallbackHorizon={horizon} zh={zh} />
    </div>
  );
}
