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

export default function SmartVoiceInvestorPage({ params }: { params: { lang: string; investorId: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const board = getSmartVoiceBoard();
  const id = smartVoiceInvestorIdFromSlug(params.investorId);
  const profile = getSmartVoiceInvestor(id, board);
  if (!profile) notFound();
  const evidence = getSmartVoiceInvestorEvidence(id);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <LocaleLink href="/smart-voice" className="grid h-8 w-8 shrink-0 place-items-center rounded-lg text-neutral-500 ring-1 ring-inset ring-line transition hover:text-reddit">
          ←
        </LocaleLink>
        <span className="text-[12px] font-medium text-neutral-500">{zh ? "Smart Voice / 作者详情" : "Smart Voice / Investor detail"}</span>
      </div>
      <SmartVoiceInvestorProfile profile={profile} board={board} evidence={evidence} zh={zh} />
    </div>
  );
}
