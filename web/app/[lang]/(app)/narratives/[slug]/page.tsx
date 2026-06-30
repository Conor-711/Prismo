import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel } from "@/components/ui";
import { SentScore } from "@/components/prismo/Bits";
import { TickerLogo } from "@/components/prismo/TickerLogo";
import { Module, Counter, Counters, flag } from "@/components/prismo/DetailBits";
import { NarrativeDetailTimeline } from "@/components/prismo/NarrativeRotationCharts";
import { fmtCompact, fmtPct } from "@/lib/format";
import {
  getNarrativeBySlug,
  getNarrativeRotation,
  getNarrativeSlugs,
  narrativeText,
  trendLabel,
} from "@/lib/narrativeRotation";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export const dynamicParams = false;

export function generateStaticParams() {
  return getNarrativeSlugs().map((slug) => ({ slug }));
}

export function generateMetadata({ params }: { params: { lang: string; slug: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const item = getNarrativeBySlug(params.slug);
  if (!item) return { title: "Narrative · Prismo" };
  return {
    title: `${narrativeText(item.category.title, lang)} · ${lang === "zh" ? "叙事详情" : "Narrative"} · Prismo`,
  };
}

function SourceRows({
  rows,
  labels,
  lang,
}: {
  rows: { source: string; count: number }[];
  labels: Record<string, { zh: string; en: string }>;
  lang: Locale;
}) {
  const total = Math.max(1, rows.reduce((s, r) => s + r.count, 0));
  return (
    <div className="space-y-3">
      {rows.map((r) => {
        const pct = (r.count / total) * 100;
        const label = labels[r.source] ? narrativeText(labels[r.source], lang) : r.source;
        return (
          <div key={r.source}>
            <div className="mb-1 flex items-center justify-between gap-3 text-[12px]">
              <span className="text-neutral-300">{label}</span>
              <span className="font-mono tabular text-neutral-500">{fmtCompact(r.count)} · {fmtPct(pct, 1)}</span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-white/[.06]">
              <div className="h-full rounded-full bg-reddit" style={{ width: `${Math.min(100, pct)}%` }} />
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default function NarrativeDetailPage({ params }: { params: { lang: string; slug: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const data = getNarrativeRotation();
  const item = getNarrativeBySlug(params.slug);
  if (!item) notFound();

  const { category, leader, series, detail } = item;
  const current = leader ?? {
    rank: null,
    previousRank: null,
    rankDelta: null,
    volume: 0,
    share: 0,
    shareDelta: 0,
    sentiment: 0,
    sentimentDelta: 0,
    trend: "quiet" as const,
  };
  const recentRows = [...series].reverse().slice(0, 10);
  const regionTotal = Math.max(1, detail.regions.reduce((s, r) => s + r.count, 0));

  return (
    <div className="space-y-5">
      <LocaleLink href="/narratives" className="inline-flex items-center gap-1 text-xs text-neutral-500 hover:text-reddit transition">
        ← {zh ? "叙事轮动" : "Narrative rotation"}
      </LocaleLink>

      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4">
        <div className="flex items-center gap-3">
          <span className="h-12 w-2 rounded-full" style={{ background: category.color }} />
          <div>
            <div className="text-[11px] font-semibold uppercase tracking-wider text-reddit">{zh ? "板块叙事" : "Sector narrative"}</div>
            <h1 className="mt-1 font-display text-2xl font-extrabold leading-none tracking-tight text-cream">{narrativeText(category.title, lang)}</h1>
            <p className="mt-2 max-w-2xl text-sm text-neutral-500">{narrativeText(category.description, lang)}</p>
          </div>
        </div>
        <span className="rounded-md bg-white/[.04] px-2.5 py-1 text-[12px] text-neutral-400 ring-1 ring-inset ring-white/10">
          {trendLabel(current.trend, lang)}
        </span>
      </div>

      <Counters>
        <Counter label={zh ? "当前排名" : "Current rank"} value={current.rank ? `#${current.rank}` : "—"} sub={current.previousRank ? `${zh ? "前窗" : "prev"} #${current.previousRank}` : "—"} tone="text-reddit" />
        <Counter label={zh ? "讨论度" : "Volume"} value={fmtCompact(current.volume)} sub={`${data.summary.recentDays}d ${zh ? "近窗" : "window"}`} />
        <Counter label={zh ? "讨论占比" : "Share"} value={fmtPct(current.share * 100, 1)} sub={`${current.shareDelta > 0 ? "+" : ""}${fmtPct(current.shareDelta * 100, 1)}`} tone={current.shareDelta >= 0 ? "text-bull" : "text-bear"} />
        <Counter label={zh ? "净情绪" : "Sentiment"} value={`${current.sentiment > 0 ? "+" : ""}${current.sentiment.toFixed(2)}`} sub={`${current.sentimentDelta > 0 ? "+" : ""}${current.sentimentDelta.toFixed(2)}`} tone={current.sentiment >= 0 ? "text-bull" : "text-bear"} />
        <Counter label={zh ? "排名变化" : "Rank move"} value={current.rankDelta == null ? "—" : `${current.rankDelta > 0 ? "+" : ""}${current.rankDelta}`} sub={zh ? "正数=上升" : "positive=up"} tone={(current.rankDelta ?? 0) >= 0 ? "text-bull" : "text-bear"} />
        <Counter label={zh ? "全窗样本" : "Window samples"} value={fmtCompact(detail.windowVolume)} sub={`${data.window.start} → ${data.window.end}`} />
      </Counters>

      <Module title={zh ? "轮动时间线" : "Rotation timeline"} icon="trend" accent="reddit" hint={zh ? "讨论度柱 + 占比线 + 情绪线" : "volume bars + share line + sentiment line"}>
        <NarrativeDetailTimeline rows={series} color={category.color} />
      </Module>

      <div className="grid lg:grid-cols-3 gap-5 items-start">
        <Module title={zh ? "来源构成" : "Source mix"} icon="layers" accent="reddit" hint={zh ? "全窗样本" : "full window"}>
          {detail.sources.length ? (
            <SourceRows rows={detail.sources} labels={data.sourceLabels} lang={lang} />
          ) : (
            <p className="text-sm text-neutral-600">{zh ? "暂无来源数据。" : "No source data."}</p>
          )}
        </Module>

        <Module title={zh ? "地区构成" : "Region mix"} icon="layers" accent="bull" hint={zh ? "全窗样本" : "full window"}>
          {detail.regions.length ? (
            <div className="space-y-3">
              {detail.regions.map((r) => {
                const pct = (r.count / regionTotal) * 100;
                return (
                  <div key={r.region}>
                    <div className="mb-1 flex items-center justify-between gap-3 text-[12px]">
                      <span className="text-neutral-300">{flag(r.region)} {r.region.toUpperCase()}</span>
                      <span className="font-mono tabular text-neutral-500">{fmtCompact(r.count)} · {fmtPct(pct, 1)}</span>
                    </div>
                    <div className="h-1.5 overflow-hidden rounded-full bg-white/[.06]">
                      <div className="h-full rounded-full bg-bull" style={{ width: `${Math.min(100, pct)}%` }} />
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <p className="text-sm text-neutral-600">{zh ? "暂无地区数据。" : "No region data."}</p>
          )}
        </Module>

        <Module title={zh ? "关联标的" : "Linked tickers"} icon="pulse" accent="amber" hint={zh ? "按出现次数" : "by mentions"}>
          {detail.topTickers.length ? (
            <div className="divide-y divide-line">
              {detail.topTickers.slice(0, 8).map((t) => (
                <LocaleLink key={t.ticker} href={`/tickers/${t.ticker}`} className="flex items-center gap-2.5 py-2.5 first:pt-0 last:pb-0 hover:opacity-80 transition">
                  <TickerLogo ticker={t.ticker} size={22} />
                  <span className="font-mono font-bold text-cream">{t.ticker}</span>
                  <span className="ml-auto font-mono text-[12px] tabular text-neutral-500">{fmtCompact(t.count)}</span>
                </LocaleLink>
              ))}
            </div>
          ) : (
            <p className="text-sm text-neutral-600">{zh ? "暂无关联标的。" : "No linked tickers."}</p>
          )}
        </Module>
      </div>

      <Module title={zh ? "每日明细" : "Daily detail"} icon="doc" accent="reddit" hint={zh ? "最近 10 天" : "last 10 days"} flush>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-white/[.02] text-[11px] uppercase tracking-wider text-neutral-500">
                <th className="py-2.5 pl-5 pr-3 text-left font-medium">{zh ? "日期" : "Day"}</th>
                <th className="px-3 py-2.5 text-right font-medium">{zh ? "排名" : "Rank"}</th>
                <th className="px-3 py-2.5 text-right font-medium">{zh ? "讨论" : "Volume"}</th>
                <th className="px-3 py-2.5 text-right font-medium">{zh ? "占比" : "Share"}</th>
                <th className="py-2.5 pl-3 pr-5 text-right font-medium">{zh ? "情绪" : "Sentiment"}</th>
              </tr>
            </thead>
            <tbody>
              {recentRows.map((r) => (
                <tr key={r.day} className="border-t border-line">
                  <td className="py-3 pl-5 pr-3 font-mono text-xs text-neutral-400">{r.day}</td>
                  <td className="px-3 py-3 text-right font-mono text-neutral-500">{r.rank ? `#${r.rank}` : "—"}</td>
                  <td className="px-3 py-3 text-right font-mono text-neutral-300">{fmtCompact(r.volume)}</td>
                  <td className="px-3 py-3 text-right font-mono text-neutral-300">{fmtPct(r.share * 100, 1)}</td>
                  <td className="py-3 pl-3 pr-5 text-right"><SentScore score={r.sentiment} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Module>

      <Panel className="p-4 text-[11px] leading-relaxed text-neutral-600">
        {zh
          ? "说明：当前页面只展示固定板块叙事的轮动指标，不展示代表原帖。板块归属由离线 pipeline 以固定关键词与标的锚点归类，后续可升级为 AI 分类。"
          : "Note: this page shows fixed sector-narrative rotation metrics only, without representative posts. Sector membership is produced offline via fixed keywords and ticker anchors, and can later be upgraded to AI classification."}
      </Panel>
    </div>
  );
}
