import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { SmartVoiceInvestorProfile } from "@/features/smart-voice";
import {
  getSmartVoiceBoard,
  getSmartVoiceDetailInvestors,
  getSmartVoiceInvestor,
} from "@/features/smart-voice/svMock";
import { smartVoiceInvestorIdFromSlug, smartVoiceInvestorSlug } from "@/features/smart-voice/svInvestorLinks";
import type { SvBoard, SvInvestor, SvPlatformBand } from "@/features/smart-voice/svMock";
import { getSmartVoiceInvestorEvidence } from "@/server/queries/smartVoiceInvestorQueries";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export const dynamicParams = false;

export function generateStaticParams() {
  return getSmartVoiceDetailInvestors().map((investor) => ({ investorId: smartVoiceInvestorSlug(investor.id) }));
}

export function generateMetadata({ params }: { params: { lang: string; investorId: string } }): Metadata {
  const id = smartVoiceInvestorIdFromSlug(params.investorId);
  const profile = getSmartVoiceInvestor(id);
  const zh = params.lang === "zh";
  return { title: `${profile?.name ?? (zh ? "作者" : "Investor")} · Smart Voice · Prismo` };
}

function compactProfileBoard(board: SvBoard, profile: SvInvestor): SvBoard {
  const sourceBand = board.platformBands?.[profile.source];
  let platformBands: SvBoard["platformBands"];
  if (sourceBand) {
    const compactBand: SvPlatformBand = {
      ...sourceBand,
      ranked: [],
      observed: [],
      top25: [],
      bottom25: [],
      top10: sourceBand.top10.some((item) => item.id === profile.id) ? [profile] : [],
      bottom10: sourceBand.bottom10.some((item) => item.id === profile.id) ? [profile] : [],
    };
    platformBands = { [profile.source]: compactBand };
  }
  return {
    investors: [profile],
    bottomInvestors: [],
    x: [],
    youtube: [],
    reddit: [],
    xueqiu: [],
    toss: [],
    currentNarratives: [],
    updatedAt: board.updatedAt,
    scoringVersion: board.scoringVersion,
    totalInvestors: board.totalInvestors,
    exportedInvestors: board.exportedInvestors,
    distribution: board.distribution,
    platformBands,
  };
}

export default function SmartVoiceInvestorPage({ params }: { params: { lang: string; investorId: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const board = getSmartVoiceBoard();
  const id = smartVoiceInvestorIdFromSlug(params.investorId);
  const profile = getSmartVoiceInvestor(id, board);
  if (!profile) notFound();
  const evidence = getSmartVoiceInvestorEvidence(id);
  const profileBoard = compactProfileBoard(board, profile);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <LocaleLink href="/smart-voice" className="grid h-8 w-8 shrink-0 place-items-center rounded-lg text-neutral-500 ring-1 ring-inset ring-line transition hover:text-reddit">
          ←
        </LocaleLink>
        <span className="text-[12px] font-medium text-neutral-500">{zh ? "Smart Voice / 作者详情" : "Smart Voice / Investor detail"}</span>
      </div>
      <SmartVoiceInvestorProfile profile={profile} board={profileBoard} evidence={evidence} zh={zh} />
    </div>
  );
}
