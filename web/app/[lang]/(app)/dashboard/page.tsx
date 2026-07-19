import type { Metadata } from "next";
import { buildDashboardModel, DashboardWorkspace } from "@/features/dashboard";
import { getSmartVoiceBoard } from "@/features/smart-voice";
import {
  getGrMeta,
  getGrQuotes,
  getGrRegionSummary,
  getGrTickerRegions,
  getGrTickers,
} from "@/server/queries/globalQueries";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return {
    title: zh ? "总览看板 · Prismo" : "Overview · Prismo",
    description: zh
      ? "跨社区美股舆情、地区情绪与 Smart Voice 的统一总览看板。"
      : "A unified overview of cross-community US-stock sentiment, regional mood and Smart Voice.",
  };
}

export default function Overview({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const model = buildDashboardModel({
    meta: getGrMeta(),
    tickers: getGrTickers(),
    cells: getGrTickerRegions(),
    summary: getGrRegionSummary(),
    quotes: getGrQuotes(),
    svBoard: getSmartVoiceBoard(),
  });

  return <DashboardWorkspace model={model} lang={lang} />;
}
