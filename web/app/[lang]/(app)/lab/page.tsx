import type { Metadata } from "next";
import { PrivateSmartVoiceExperiment } from "@/features/smart-voice";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";
import { getPrivateSmartVoiceExperiment } from "@/server/queries/privateSmartVoiceExperiment";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  return {
    title: `${zh ? "Prismo 实验室" : "Prismo Lab"} · Private Smart Voice`,
    description: zh
      ? "在 Prismo 实验室中查看公开 Telegram 投资频道的历史喊单、价格走势与 Private SE/SV 报告。"
      : "Explore historical calls, price paths and a Private SE/SV report for a public Telegram investing channel in Prismo Lab.",
  };
}

export default function LabPage() {
  return <PrivateSmartVoiceExperiment data={getPrivateSmartVoiceExperiment()} />;
}
