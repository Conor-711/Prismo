import type { Metadata } from "next";
import { SmartVoiceWorkspace } from "@/features/smart-voice";
import { getSmartVoiceBoard, getSmartVoiceDetailInvestors } from "@/features/smart-voice/svMock";
import { buildSmartVoiceLeaderboardData } from "@/features/smart-voice/svLeaderboardData";
import { getSmartVoiceLiveCalls, getSmartVoiceMarketData, getSmartVoiceOverviewStats } from "@/server/queries/smartVoiceQueries";
import { getSmartVoiceRepresentativeEvidence } from "@/server/queries/smartVoiceInvestorQueries";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  return {
    title: `${zh ? "Smart Voice 工作台" : "Smart Voice Workbench"} · Prismo`,
    description: zh
      ? "发现高 SV 作者集中关注的标的、投资者排行榜与实时有效观点。"
      : "Discover ticker concentration, investor rankings and live actionable calls from high-SV voices.",
  };
}

export default function SmartVoicePage({ params }: { params: { lang: string } }) {
  const board = getSmartVoiceBoard();
  const marketData = getSmartVoiceMarketData(24);
  const liveCalls = getSmartVoiceLiveCalls(320);
  const stats = getSmartVoiceOverviewStats();
  const profileIds = getSmartVoiceDetailInvestors(board).map((investor) => investor.id);
  const representativeEvidence = getSmartVoiceRepresentativeEvidence(profileIds);
  const leaderboard = buildSmartVoiceLeaderboardData(board);
  return (
    <SmartVoiceWorkspace
      boardMeta={{
        totalInvestors: board.totalInvestors ?? board.investors.length,
        updatedAt: board.updatedAt,
        scoringVersion: board.scoringVersion,
      }}
      leaderboard={leaderboard}
      marketData={marketData}
      liveCalls={liveCalls}
      stats={stats}
      profileIds={profileIds}
      representativeEvidence={representativeEvidence}
    />
  );
}
