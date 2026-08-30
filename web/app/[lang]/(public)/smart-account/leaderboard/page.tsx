import type { Metadata } from "next";
import { PublicSmartAccountLeaderboard } from "@/features/smart-account";
import { buildSmartVoiceLeaderboardData } from "@/features/smart-account/svLeaderboardData";
import { getSmartVoiceBoard, getSmartVoiceDetailInvestors } from "@/features/smart-account/svMock";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";
import { getSmartVoiceOverviewStats } from "@/server/queries/smartVoiceQueries";
import { getSmartVoiceRepresentativeEvidence } from "@/server/queries/smartVoiceInvestorQueries";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const title = zh ? "Smart Account 投资者榜" : "Smart Account Investor Ranking";
  const description = zh
    ? "基于公开投资观点的历史结算表现、有效样本、擅长周期与赛道，浏览跨平台 Smart Account 投资者排名。"
    : "Explore cross-platform Smart Account investor rankings based on settled public calls, effective samples, horizon strength and sector expertise.";
  return {
    title: `${title} · bSmart`,
    description,
    openGraph: { title: `${title} · bSmart`, description, type: "website" },
    twitter: { title: `${title} · bSmart`, description, card: "summary_large_image" },
  };
}

export default function PublicSmartAccountLeaderboardPage() {
  const board = getSmartVoiceBoard();
  const profileIds = getSmartVoiceDetailInvestors(board).map((investor) => investor.id);

  return (
    <PublicSmartAccountLeaderboard
      boardMeta={{
        totalInvestors: board.totalInvestors ?? board.investors.length,
        updatedAt: board.updatedAt,
        scoringVersion: board.scoringVersion,
      }}
      leaderboard={buildSmartVoiceLeaderboardData(board)}
      stats={getSmartVoiceOverviewStats()}
      profileIds={profileIds}
      representativeEvidence={getSmartVoiceRepresentativeEvidence(profileIds)}
    />
  );
}
