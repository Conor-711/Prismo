import type { Metadata } from "next";
import { PrivateSmartVoiceExperiment } from "@/features/smart-voice";
import { getPrivateSmartVoiceExperiment } from "@/server/queries/privateSmartVoiceExperiment";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  return {
    title: `${zh ? "私域 Smart Voice 实验" : "Private Smart Voice Experiment"} · Prismo`,
    description: zh
      ? "公开 Telegram 投资频道的历史喊单、价格走势与 Private SE/SV 实验报告。"
      : "Historical calls, price paths and a Private SE/SV experiment for a public Telegram investing channel.",
  };
}

export default function PrivateSmartVoiceExperimentPage() {
  return <PrivateSmartVoiceExperiment data={getPrivateSmartVoiceExperiment()} />;
}
