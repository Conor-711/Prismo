import type { Metadata } from "next";
import { OnboardingFlow } from "@/components/onboarding/OnboardingFlow";
import { getOnboardingData } from "@/lib/queries";
import { getDictionary } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const t = getDictionary(params.lang).onboarding;
  return { title: t.metaTitle, description: t.metaDesc };
}

export default function OnboardingPage() {
  const { sectors, tickers } = getOnboardingData();
  return <OnboardingFlow sectors={sectors} tickers={tickers} />;
}
