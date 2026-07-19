"use client";

import { useMemo } from "react";
import type { SvSignalHorizon, SvTickerSignalData } from "@/server/queries/smartVoiceTickerSignals";
import type { SvDivergenceDiagnostic, SvMomentumDiagnostic } from "../smartVoiceSignalLogic";
import type { SvOpinionChangeRadar, SvOpportunityIndicators, SvWeightedTargetDistribution } from "../smartVoiceDecisionLogic";
import { buildExplainableAlerts, buildPlatformDiffusion, buildThesisLifecycle } from "../smartVoiceResearchLogic";
import { SmartVoiceAlertCenter } from "./SmartVoiceAlertCenter";
import { SmartVoiceAuthorAbilityMatrix } from "./SmartVoiceAuthorAbilityMatrix";
import { SmartVoicePlatformDiffusion } from "./SmartVoicePlatformDiffusion";
import { SmartVoicePortfolioRisk } from "./SmartVoicePortfolioRisk";
import { SmartVoiceThesisLifecycle } from "./SmartVoiceThesisLifecycle";

export function SmartVoiceResearchSuite({
  data,
  horizon,
  asOfDay,
  divergence,
  momentum,
  targets,
  radar,
  indicators,
  zh,
}: {
  data: SvTickerSignalData;
  horizon: SvSignalHorizon;
  asOfDay: string;
  divergence: SvDivergenceDiagnostic;
  momentum: SvMomentumDiagnostic;
  targets: SvWeightedTargetDistribution;
  radar: SvOpinionChangeRadar;
  indicators: SvOpportunityIndicators;
  zh: boolean;
}) {
  const thesis = useMemo(() => buildThesisLifecycle(data.evidence, data.thesisNarratives, asOfDay), [asOfDay, data.evidence, data.thesisNarratives]);
  const diffusion = useMemo(() => buildPlatformDiffusion(data.evidence, horizon, asOfDay), [asOfDay, data.evidence, horizon]);
  const alerts = useMemo(() => buildExplainableAlerts({ divergence, momentum, targets, radar, indicators, thesis }), [divergence, indicators, momentum, radar, targets, thesis]);
  return (
    <>
      <div className="grid border-t border-line lg:grid-cols-2">
        <SmartVoiceThesisLifecycle items={thesis} zh={zh} />
        <SmartVoicePlatformDiffusion items={diffusion} zh={zh} />
      </div>
      <SmartVoiceAuthorAbilityMatrix authors={data.authorAbilities} ticker={data.ticker} zh={zh} />
      <div className="grid border-t border-line lg:grid-cols-2">
        <SmartVoicePortfolioRisk profiles={data.peerLensProfiles} ticker={data.ticker} zh={zh} />
        <SmartVoiceAlertCenter alerts={alerts} zh={zh} />
      </div>
    </>
  );
}
