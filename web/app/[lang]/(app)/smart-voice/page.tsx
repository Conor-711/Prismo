import type { Metadata } from "next";
import { SmartVoiceWorkspace } from "@/features/smart-voice";
import { getSmartVoiceBoard, getSmartVoiceDetailInvestors } from "@/features/smart-voice/svMock";
import { getSmartVoiceLiveCalls, getSmartVoiceMarketData, getSmartVoiceOverviewStats } from "@/server/queries/smartVoiceQueries";
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
  return <SmartVoiceWorkspace board={board} marketData={marketData} liveCalls={liveCalls} stats={stats} profileIds={profileIds} />;
}
