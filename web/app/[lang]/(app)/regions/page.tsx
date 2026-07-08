import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { SaveButton } from "@/components/favorites/SaveButton";
import { Panel, PageHeader, SectionTitle } from "@/components/ui";
import { SentScore, StanceBar } from "@/shared/ui/prismoBits";
import { AsiaDivergingBars } from "@/components/asia/AsiaCharts";
import { getGrRegionSummary, getGrRegionDetail } from "@/server/queries/globalQueries";
import { REGION_ORDER, regionLabel, regionSource, regionColor } from "@/shared/market/regions";
import { fmtCompact } from "@/shared/formatting/format";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return { title: zh ? "区域总览 · Prismo" : "Regions · Prismo" };
}

export default function RegionsPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const summary = getGrRegionSummary();
  const byRegion = new Map(summary.map((s) => [s.region, s]));
  const regions = REGION_ORDER.filter((r) => byRegion.has(r));

  const diverging = regions.map((r) => ({ label: regionLabel(r, lang), value: Math.round(byRegion.get(r)!.avg_sentiment * 100) / 100 }));

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow={zh ? "PRISMO · 区域" : "PRISMO · Regions"}
        title={zh ? "区域总览" : "Regions"}
        subtitle={
          zh
            ? "五个本土社区各自的整体情绪、讨论量与最看多/看空标的。点入看该区全部标的。"
            : "Each native community's overall sentiment, volume and most bullish/bearish names. Click in for the full ticker list."
        }
      />

      {regions.length === 0 ? (
        <Panel className="p-10 text-center">
          <p className="text-sm text-neutral-400">{zh ? "暂无区域数据。" : "No region data yet."}</p>
          <p className="mt-2 text-xs text-neutral-600">
            {zh ? "运行 " : "Run "}
            <code className="px-1.5 py-0.5 rounded bg-white/[.06] text-reddit font-mono">make gr</code>
            {zh ? " 后重新构建。" : " then rebuild."}
          </p>
        </Panel>
      ) : (
        <>
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {regions.map((r) => {
              const s = byRegion.get(r)!;
              const detail = getGrRegionDetail(r);
              const ranked = [...detail].filter((d) => d.post_count > 0);
              const topBull = [...ranked].sort((a, b) => b.sentiment_avg - a.sentiment_avg)[0];
              const topBear = [...ranked].sort((a, b) => a.sentiment_avg - b.sentiment_avg)[0];
              return (
                <div
                  key={r}
                  className="group rounded-xl bg-card p-5 ring-1 ring-inset ring-line transition hover:-translate-y-0.5 hover:ring-reddit/40"
                >
                  <div className="flex items-center justify-between">
                    <LocaleLink href={`/regions/${r}`} className="inline-flex min-w-0 items-center gap-2 font-display text-lg font-bold text-cream transition hover:text-reddit">
                      <span className="h-3 w-3 shrink-0 rounded-full" style={{ background: regionColor(r) }} />
                      <span className="truncate">{regionLabel(r, lang)}</span>
                    </LocaleLink>
                    <div className="flex shrink-0 items-center gap-2">
                      <SentScore score={s.avg_sentiment} className="text-lg" />
                      <SaveButton kind="region" refId={r} variant="follow" size="xs" />
                    </div>
                  </div>
                  <div className="text-[11px] text-neutral-600 mt-0.5">{regionSource(r)}</div>

                  <div className="mt-4"><StanceBar bull={s.bull_pct} bear={s.bear_pct} neutral={Math.max(0, 1 - s.bull_pct - s.bear_pct)} /></div>
                  <div className="mt-2 flex items-center justify-between text-[11px] text-neutral-500 tabular">
                    <span>{fmtCompact(s.posts)} {zh ? "帖" : "posts"}</span>
                    <span>{s.tickers} {zh ? "标的" : "tickers"}</span>
                  </div>

                  <div className="mt-4 pt-3 border-t border-line space-y-1.5 text-[12px]">
                    {topBull && (
                      <div className="flex items-center justify-between">
                        <span className="text-neutral-500">{zh ? "最看多" : "Top bull"}</span>
                        <span className="font-mono text-cream">{topBull.ticker} <SentScore score={topBull.sentiment_avg} className="text-[11px]" /></span>
                      </div>
                    )}
                    {topBear && (
                      <div className="flex items-center justify-between">
                        <span className="text-neutral-500">{zh ? "最看空" : "Top bear"}</span>
                        <span className="font-mono text-cream">{topBear.ticker} <SentScore score={topBear.sentiment_avg} className="text-[11px]" /></span>
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>

          <section>
            <SectionTitle title={zh ? "区域净情绪对比" : "Region net sentiment"} accent="bull" hint={zh ? "绿=偏多 / 红=偏空" : "green=bullish / red=bearish"} />
            <Panel className="p-4">
              <AsiaDivergingBars items={diverging} height={Math.max(180, regions.length * 42)} />
            </Panel>
          </section>
        </>
      )}
    </div>
  );
}
