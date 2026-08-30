import type { Metadata } from "next";
import { PageHeader } from "@/components/ui";
import { TrackingView, type TrackingCatalog } from "@/features/tracking";
import { ViewportWorkspace } from "@/shared/layout/ViewportWorkspace";
import { getGrTickers } from "@/server/queries/globalQueries";
import { getInvestorBoard, type InvestorBoard } from "@/server/queries/investorQueries";
import { getNarrativeRotation, trendLabel } from "@/server/queries/narrativeRotation";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";
import type { KolSource } from "@/shared/market/mockDetail";

// 追踪页。页面是薄壳：服务端把全部标的摘要烤进去，本地缓存与过滤在客户端 TrackingView。
// [lang] 的 generateStaticParams 由 layout 提供，与 output:export 兼容。
export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const t = getDictionary(params.lang).tracking;
  return { title: `${t.title} · bSmart` };
}

export default function TrackingPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).tracking;
  const rows = getGrTickers();
  const investorBoard = getInvestorBoard();
  const narrativeData = getNarrativeRotation();
  const sourceOrder: (keyof InvestorBoard)[] = ["x", "youtube", "reddit", "xueqiu", "toss"];
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
        tickers: Array.from(new Set([
          ...(cat.tickers ?? []),
          ...(narrativeData.details[cat.id]?.topTickers ?? []).map((item) => item.ticker),
        ])).map((ticker) => ticker.toUpperCase()),
      };
    }),
  };

  return (
    <ViewportWorkspace className="flex min-h-0 flex-col gap-3 overflow-hidden" bottomOffset={16}>
      <PageHeader
        eyebrow="bSmart"
        title={t.title}
        subtitle={t.subtitle}
        right={(
          <div className="flex items-center gap-2 text-[11px] text-neutral-500">
            <span className="h-1.5 w-1.5 rounded-full bg-reddit" />
            {lang === "zh" ? "当前设备缓存" : "Stored on this device"}
          </div>
        )}
      />
      <TrackingView rows={rows} catalog={catalog} lang={lang} />
    </ViewportWorkspace>
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
