import type { Metadata } from "next";
import { buildDashboardModel, DashboardWorkspace } from "@/features/dashboard";
import { getSmartVoiceBoard } from "@/features/smart-account";
import {
  getGrMeta,
  getGrQuotes,
  getGrTickerRegions,
  getGrTickers,
} from "@/server/queries/globalQueries";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return {
    title: zh ? "总览看板 · bSmart" : "Overview · bSmart",
    description: zh
      ? "跨社区美股舆情、市场信号与 Smart Account 的统一总览看板。"
      : "A unified overview of cross-community US-stock sentiment, market signals and Smart Account.",
  };
}

export default function Overview({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const model = buildDashboardModel({
    meta: getGrMeta(),
    tickers: getGrTickers(),
    cells: getGrTickerRegions(),
    quotes: getGrQuotes(),
    svBoard: getSmartVoiceBoard(),
  });

  return <DashboardWorkspace model={model} lang={lang} />;
}
