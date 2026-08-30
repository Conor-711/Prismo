import type { Metadata } from "next";
import { SmartAccountWorkspace } from "@/features/smart-account";
import { getSmartVoiceBoard, getSmartVoiceDetailInvestors } from "@/features/smart-account/svMock";
import { getHyperliquidSmartMoneyData } from "@/features/smart-account/hyperliquidData";
import { getSmartVoiceLiveCalls, getSmartVoiceMarketData, getSmartVoiceOverviewStats } from "@/server/queries/smartVoiceQueries";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  return {
    title: `${zh ? "Smart Account 工作台" : "Smart Account Workbench"} · bSmart`,
    description: zh
      ? "发现高 Score 作者集中关注的标的、投资者排行榜与实时有效观点。"
      : "Discover ticker concentration, investor rankings and live actionable calls from high-scoring accounts.",
  };
}

export default function SmartAccountPage({ params }: { params: { lang: string } }) {
  const board = getSmartVoiceBoard();
  const marketData = getSmartVoiceMarketData(24);
  const liveCalls = getSmartVoiceLiveCalls(320);
  const stats = getSmartVoiceOverviewStats();
  const profileIds = getSmartVoiceDetailInvestors(board).map((investor) => investor.id);
  const hyperliquidData = getHyperliquidSmartMoneyData();
  return (
    <SmartAccountWorkspace
      boardMeta={{
        totalInvestors: board.totalInvestors ?? board.investors.length,
        updatedAt: board.updatedAt,
        scoringVersion: board.scoringVersion,
      }}
      marketData={marketData}
      liveCalls={liveCalls}
      stats={stats}
      profileIds={profileIds}
      hyperliquidData={hyperliquidData}
    />
  );
}
