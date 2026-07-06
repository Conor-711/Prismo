import type { Metadata } from "next";
import { PageHeader } from "@/components/ui";
import { TrackingView, type TrackingCatalog } from "@/components/prismo/TrackingView";
import { getGrTickers, getGrTickerRegions, getGrRegionSummary } from "@/lib/globalQueries";
import { getInvestorBoard, type InvestorBoard } from "@/lib/investorQueries";
import { getNarrativeRotation, trendLabel } from "@/lib/narrativeRotation";
import { REGION_ORDER } from "@/lib/regions";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";
import type { KolSource } from "@/lib/mockDetail";

// 追踪页（私密）。页面是薄壳：服务端把全部标的摘要烤进去，登录态/过滤在客户端的 TrackingView。
// [lang] 的 generateStaticParams 由 layout 提供，与 output:export 兼容。
export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const t = getDictionary(params.lang).tracking;
  return { title: `${t.title} · Prismo` };
}

export default function TrackingPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).tracking;
  const rows = getGrTickers();
  const regions = getGrTickerRegions();
  const investorBoard = getInvestorBoard();
  const narrativeData = getNarrativeRotation();
  const regionSummary = getGrRegionSummary();
  const summaryMap = new Map(regionSummary.map((r) => [r.region, r]));
  const sourceOrder: (keyof InvestorBoard)[] = ["x", "youtube", "reddit", "xueqiu", "toss", "yahoojp"];
  const catalog: TrackingCatalog = {
    authors: sourceOrder.flatMap((source) =>
      investorBoard[source].map((inv) => ({
        refId: `${source}:${inv.id}`,
        source: sourceLabel(source),
        name: inv.name,
        avatar: inv.avatar,
        url: inv.url,
        href: source === "youtube" ? `/investors/youtube/${inv.id}` : undefined,
        metric: inv.metric,
        posts: inv.posts,
        tickers: inv.tickers,
      }))
    ),
    narratives: narrativeData.categories.map((cat) => {
      const leader = narrativeData.leaderboard.find((row) => row.id === cat.id);
      return {
        refId: cat.slug,
        titleZh: cat.title.zh,
        titleEn: cat.title.en,
        descriptionZh: cat.description.zh,
        descriptionEn: cat.description.en,
        color: cat.color,
        rank: leader?.rank ?? null,
        share: leader?.share ?? 0,
        volume: leader?.volume ?? 0,
        trendZh: leader ? trendLabel(leader.trend, "zh") : "低活跃",
        trendEn: leader ? trendLabel(leader.trend, "en") : "Quiet",
      };
    }),
    regions: REGION_ORDER.map((region) => {
      const s = summaryMap.get(region);
      return {
        refId: region,
        posts: s?.posts ?? 0,
        tickers: s?.tickers ?? 0,
        avgSentiment: s?.avg_sentiment ?? 0,
        bullPct: s?.bull_pct ?? 0,
        bearPct: s?.bear_pct ?? 0,
      };
    }),
  };

  return (
    <div className="space-y-6">
      <PageHeader eyebrow="PRISMO" title={t.title} subtitle={t.subtitle} />
      <TrackingView rows={rows} regions={regions} catalog={catalog} lang={lang} />
    </div>
  );
}

function sourceLabel(source: keyof InvestorBoard): string {
  const labels: Record<KolSource, string> = {
    x: "X",
    youtube: "YouTube",
    reddit: "Reddit",
    xueqiu: "雪球",
    toss: "Toss",
    yahoojp: "Yahoo JP",
  };
  return labels[source];
}
