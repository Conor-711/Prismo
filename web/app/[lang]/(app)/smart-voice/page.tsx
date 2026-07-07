import type { Metadata } from "next";
import { SmartVoiceWorkspace } from "@/components/prismo/SmartVoiceWorkspace";
import { getSmartVoiceBoard } from "@/lib/svMock";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  return {
    title: `${zh ? "Smart Voice 工作台" : "Smart Voice Workbench"} · Prismo`,
    description: zh
      ? "追踪投资者 Smart Voice 分布、排名、警报与典型投资者。"
      : "Track investor Smart Voice distribution, ranks, alerts and typical investor cases.",
  };
}

export default function SmartVoicePage({ params }: { params: { lang: string } }) {
  const board = getSmartVoiceBoard();
  return <SmartVoiceWorkspace board={board} />;
}
