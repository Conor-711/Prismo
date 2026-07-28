"use client";

import { useMemo } from "react";
import type { SvTickerSignalData } from "@/server/queries/smartVoiceTickerSignals";
import type { SvDivergenceDiagnostic, SvMomentumDiagnostic } from "../smartVoiceSignalLogic";
import type { SvOpinionChangeRadar, SvOpportunityIndicators, SvWeightedTargetDistribution } from "../smartVoiceDecisionLogic";
import { buildExplainableAlerts, buildThesisLifecycle } from "../smartVoiceResearchLogic";
import { SmartVoiceAlertCenter } from "./SmartVoiceAlertCenter";
import { SmartVoiceAuthorAbilityMatrix } from "./SmartVoiceAuthorAbilityMatrix";
import { SmartVoicePortfolioRisk } from "./SmartVoicePortfolioRisk";
import { SmartVoiceThesisLifecycle } from "./SmartVoiceThesisLifecycle";

export function SmartVoiceResearchSuite({
  data,
  asOfDay,
  divergence,
  momentum,
  targets,
  radar,
  indicators,
  zh,
}: {
  data: SvTickerSignalData;
  asOfDay: string;
  divergence: SvDivergenceDiagnostic;
  momentum: SvMomentumDiagnostic;
  targets: SvWeightedTargetDistribution;
  radar: SvOpinionChangeRadar;
  indicators: SvOpportunityIndicators;
  zh: boolean;
}) {
  const thesis = useMemo(() => buildThesisLifecycle(data.evidence, data.thesisNarratives, asOfDay), [asOfDay, data.evidence, data.thesisNarratives]);
  const alerts = useMemo(() => buildExplainableAlerts({ divergence, momentum, targets, radar, indicators, thesis }), [divergence, indicators, momentum, radar, targets, thesis]);
  return (
    <>
      <div className="border-t border-line">
        <SmartVoiceThesisLifecycle items={thesis} zh={zh} />
      </div>
      <SmartVoiceAuthorAbilityMatrix authors={data.authorAbilities} ticker={data.ticker} zh={zh} />
      <div className="grid border-t border-line lg:grid-cols-2">
        <SmartVoicePortfolioRisk profiles={data.peerLensProfiles} ticker={data.ticker} zh={zh} />
        <SmartVoiceAlertCenter alerts={alerts} zh={zh} />
      </div>
    </>
  );
}
