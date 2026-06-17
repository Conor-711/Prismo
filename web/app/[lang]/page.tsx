import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel, PageHeader, SectionTitle } from "@/components/ui";
import { Kpi, SentScore, Consensus, RegionBadge, StanceBar } from "@/components/prismo/Bits";
import { TickerLogo } from "@/components/prismo/TickerLogo";
import { AsiaHeatmap } from "@/components/asia/AsiaCharts";
import {
  getGrMeta, getGrTickers, getGrTickerRegions, getGrRegionSummary,
} from "@/lib/globalQueries";
import { REGION_ORDER, regionLabel, regionSource } from "@/lib/regions";
import { fmtInt, fmtCompact, timeAgo } from "@/lib/format";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return {
    title: zh ? "总览看板 · Prismo" : "Overview · Prismo",
    description: zh
      ? "Reddit / Yahoo Finance Japan / Naver / 雪球 / PTT 五大社区的美股舆情总览。"
      : "Cross-community US-stock sentiment across Reddit, Yahoo Finance JP, Naver, Xueqiu and PTT.",
  };
}

export default function Overview({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";

  const meta = getGrMeta();
  const tickers = getGrTickers();
  const summary = getGrRegionSummary();
  const cells = getGrTickerRegions();

  const name = (t: { name_zh: string; name_en: string }) => (zh ? t.name_zh || t.name_en : t.name_en || t.name_zh);
  const sumByRegion = new Map(summary.map((s) => [s.region, s]));
  const regions = REGION_ORDER.filter((r) => sumByRegion.has(r));

  // 热度榜 / 共识 / 分歧
  const byPosts = [...tickers].sort((a, b) => b.total_posts - a.total_posts);
  const consensusList = tickers
    .filter((t) => t.consensus === "all_bull" || t.consensus === "all_bear")
    .sort((a, b) => b.total_posts - a.total_posts)
    .slice(0, 6);
  const divergentList = [...tickers]
    .filter((t) => (t.spread ?? 0) > 0)
    .sort((a, b) => (b.spread ?? 0) - (a.spread ?? 0))
    .slice(0, 6);

  // 跨区情绪热力：x=地区，y=Top 标的，cell=情绪
  const topForHeat = byPosts.slice(0, 12);
  const yLabels = topForHeat.map((t) => t.ticker);
  const xLabels = regions.map((r) => regionLabel(r, lang));
  const cellMap = new Map(cells.map((c) => [`${c.region}:${c.ticker}`, c.sentiment_avg]));
  const heatCells: [number, number, number][] = [];
  topForHeat.forEach((t, yi) =>
    regions.forEach((r, xi) => {
      const v = cellMap.get(`${r}:${t.ticker}`);
      if (v != null) heatCells.push([xi, yi, Math.round(v * 100) / 100]);
    })
  );

  const empty = tickers.length === 0;

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow={zh ? "PRISMO · 5 社区聚合" : "PRISMO · 5 communities"}
        title={zh ? "总览看板" : "Overview"}
        subtitle={
          zh
            ? "Reddit · Yahoo Finance Japan · Naver · 雪球 · PTT —— 同一批跨区美股在五地散户社区的情绪对比。"
            : "Reddit · Yahoo Finance Japan · Naver · Xueqiu · PTT — cross-region retail sentiment on the same US tickers."
        }
      />

      {empty ? (
        <Panel className="p-10 text-center">
          <p className="text-sm text-neutral-400">{zh ? "暂无 5 社区数据。" : "No cross-community data yet."}</p>
          <p className="mt-2 text-xs text-neutral-600">
            {zh ? "在本地运行 " : "Run "}
            <code className="px-1.5 py-0.5 rounded bg-white/[.06] text-reddit font-mono">make gr</code>
            {zh ? " 后重新构建站点。" : " locally, then rebuild the site."}
          </p>
        </Panel>
      ) : (
        <>
          {/* KPI */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <Kpi label={zh ? "标的" : "Tickers"} value={fmtInt(meta.tickers)} />
            <Kpi label={zh ? "本地讨论帖" : "Local posts"} value={fmtCompact(meta.posts)} />
            <Kpi label={zh ? "覆盖地区" : "Regions"} value={meta.regions} sub="US · CN · JP · KR · TW" />
            <Kpi label={zh ? "更新" : "Updated"} value={meta.lastUpdated ? timeAgo(meta.lastUpdated, lang) : "—"} />
          </div>

          {/* 五地区情绪 */}
          <section>
            <SectionTitle title={zh ? "五地区情绪概览" : "5-region mood"} accent="bull" icon="layers" />
            <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
              {regions.map((r) => {
                const s = sumByRegion.get(r)!;
                return (
                  <LocaleLink
                    key={r}
                    href={`/regions/${r}`}
                    className="group rounded-xl bg-card ring-1 ring-inset ring-line p-4 hover:ring-reddit/40 hover:-translate-y-0.5 transition"
                  >
                    <RegionBadge region={r} lang={lang} className="font-semibold !text-cream" />
                    <div className="mt-0.5 text-[10px] text-neutral-600">{regionSource(r)}</div>
                    <div className="mt-3 flex items-baseline justify-between">
                      <SentScore score={s.avg_sentiment} className="text-lg" />
                      <span className="text-[11px] text-neutral-500 tabular">{fmtCompact(s.posts)} {zh ? "帖" : "posts"}</span>
                    </div>
                    <div className="mt-2">
                      <StanceBar bull={s.bull_pct} bear={s.bear_pct} neutral={Math.max(0, 1 - s.bull_pct - s.bear_pct)} />
                    </div>
                    <div className="mt-2 text-[11px] text-neutral-500">{s.tickers} {zh ? "个标的" : "tickers"}</div>
                  </LocaleLink>
                );
              })}
            </div>
          </section>

          {/* 跨区情绪热力 */}
          {heatCells.length > 0 && (
            <section>
              <SectionTitle title={zh ? "跨区情绪热力" : "Cross-region sentiment heatmap"} accent="reddit" icon="flame" hint={zh ? "红=偏空 / 绿=偏多" : "red=bearish / green=bullish"} />
              <Panel className="p-4">
                <AsiaHeatmap x={xLabels} y={yLabels} cells={heatCells} rawX height={Math.max(220, yLabels.length * 26 + 60)} />
              </Panel>
            </section>
          )}

          {/* 共识 & 分歧 */}
          <div className="grid md:grid-cols-2 gap-4">
            <section>
              <SectionTitle title={zh ? "五地共识" : "Cross-region consensus"} accent="bull" />
              <Panel className="p-2">
                {consensusList.length ? consensusList.map((t) => (
                  <LocaleLink key={t.ticker} href={`/tickers/${t.ticker}`} className="flex items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-white/[.04] transition">
                    <TickerLogo ticker={t.ticker} size={22} /><span className="font-mono font-bold text-cream text-[15px] shrink-0">{t.ticker}</span>
                    <span className="text-xs text-neutral-500 truncate flex-1">{name(t)}</span>
                    <Consensus value={t.consensus} lang={lang} />
                    <SentScore score={t.avg_sentiment} className="w-14 text-right" />
                  </LocaleLink>
                )) : <p className="px-3 py-6 text-sm text-neutral-600">{zh ? "暂无共识标的。" : "No consensus tickers yet."}</p>}
              </Panel>
            </section>
            <section>
              <SectionTitle title={zh ? "地区分歧" : "Regional divergence"} accent="amber" hint={zh ? "情绪极差排序" : "by spread"} />
              <Panel className="p-2">
                {divergentList.length ? divergentList.map((t) => (
                  <LocaleLink key={t.ticker} href={`/tickers/${t.ticker}`} className="flex items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-white/[.04] transition">
                    <TickerLogo ticker={t.ticker} size={22} /><span className="font-mono font-bold text-cream text-[15px] shrink-0">{t.ticker}</span>
                    <span className="text-xs text-neutral-500 truncate flex-1">
                      {t.divergent_region ? <RegionBadge region={t.divergent_region} lang={lang} /> : name(t)}
                    </span>
                    <span className="font-mono text-[12px] tabular text-amber">Δ {(t.spread ?? 0).toFixed(2)}</span>
                  </LocaleLink>
                )) : <p className="px-3 py-6 text-sm text-neutral-600">{zh ? "暂无明显分歧。" : "No clear divergence yet."}</p>}
              </Panel>
            </section>
          </div>

          {/* 热度榜 */}
          <section>
            <SectionTitle title={zh ? "全球热度榜" : "Global buzz"} href="/tickers" accent="reddit" icon="trend" />
            <Panel className="p-2">
              {byPosts.slice(0, 10).map((t, i) => (
                <LocaleLink key={t.ticker} href={`/tickers/${t.ticker}`} className="flex items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-white/[.04] transition">
                  <span className="w-5 text-right text-xs text-neutral-600 tabular">{i + 1}</span>
                  <TickerLogo ticker={t.ticker} size={22} /><span className="font-mono font-bold text-cream text-[15px] shrink-0">{t.ticker}</span>
                  <span className="text-xs text-neutral-500 truncate flex-1">{name(t)}</span>
                  <span className="text-[11px] text-neutral-500 tabular">{t.regions_present} {zh ? "区" : "rgn"}</span>
                  <span className="text-[12px] text-neutral-400 tabular w-16 text-right">{fmtCompact(t.total_posts)}</span>
                  <SentScore score={t.avg_sentiment} className="w-14 text-right" />
                </LocaleLink>
              ))}
            </Panel>
          </section>
        </>
      )}
    </div>
  );
}
