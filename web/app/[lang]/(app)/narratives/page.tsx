import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { PageHeader, Panel } from "@/components/ui";
import { SentScore } from "@/components/prismo/Bits";
import { TickerLogo } from "@/components/prismo/TickerLogo";
import { Module, Counter, Counters, Delta } from "@/components/prismo/DetailBits";
import { NarrativeRankChart, NarrativeSentimentChart, NarrativeShareChart } from "@/components/prismo/NarrativeRotationCharts";
import { fmtCompact, fmtPct, timeAgo } from "@/lib/format";
import {
  getNarrativeRotation,
  narrativeText,
  trendLabel,
  type NarrativeLeader,
} from "@/lib/narrativeRotation";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return {
    title: zh ? "叙事轮动 · Prismo" : "Narrative rotation · Prismo",
    description: zh
      ? "跨社区固定板块叙事的热度排名、讨论占比与情绪变化。"
      : "Cross-community fixed sector narratives by rank, discussion share and sentiment rotation.",
  };
}

function rankMove(row: NarrativeLeader, zh: boolean) {
  if (row.rankDelta == null) return <span className="text-neutral-600">—</span>;
  if (row.rankDelta === 0) return <span className="text-neutral-500">{zh ? "持平" : "flat"}</span>;
  return <Delta value={row.rankDelta} digits={0} />;
}

export default function NarrativesPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const data = getNarrativeRotation();
  const active = data.leaderboard.filter((r) => r.volume > 0);
  const top = active[0];

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow={zh ? "PRISMO · 叙事" : "PRISMO · Narratives"}
        title={zh ? "叙事轮动" : "Narrative rotation"}
        subtitle={
          zh
            ? "固定板块叙事，跨 Reddit / X / YouTube / 雪球 / Yahoo JP / Naver / PTT / Toss 聚合，观察热度排名、讨论占比与情绪转向。"
            : "Fixed sector narratives across Reddit / X / YouTube / Xueqiu / Yahoo JP / Naver / PTT / Toss, tracking rank, share and sentiment shifts."
        }
        right={<span className="text-xs text-neutral-500 tabular">{zh ? "更新于 " : "Updated "}{timeAgo(data.updated_at, lang)}</span>}
      />

      {active.length === 0 ? (
        <Panel className="p-10 text-center">
          <p className="text-sm text-neutral-400">{zh ? "暂无叙事轮动数据。" : "No narrative rotation data yet."}</p>
          <p className="mt-2 text-xs text-neutral-600">
            {zh ? "运行 " : "Run "}
            <code className="px-1.5 py-0.5 rounded bg-white/[.06] text-reddit font-mono">make narrative-rotation</code>
            {zh ? " 后重新构建。" : " then rebuild."}
          </p>
        </Panel>
      ) : (
        <>
          <Counters>
            <Counter label={zh ? "活跃板块" : "Active"} value={String(data.summary.active)} sub={`${data.categories.length} ${zh ? "个固定板块" : "fixed sectors"}`} />
            <Counter label={zh ? "讨论样本" : "Samples"} value={fmtCompact(data.summary.totalVolume)} sub={`${data.window.start} → ${data.window.end}`} />
            <Counter label={zh ? "当前第一" : "Current #1"} value={top ? `#${top.rank}` : "—"} sub={top ? narrativeText(top.title, lang) : "—"} tone="text-reddit" />
            <Counter label={zh ? "第一占比" : "#1 share"} value={top ? fmtPct(top.share * 100, 1) : "—"} sub={top ? trendLabel(top.trend, lang) : "—"} tone="text-bull" />
            <Counter label={zh ? "第一情绪" : "#1 sentiment"} value={top ? `${top.sentiment > 0 ? "+" : ""}${top.sentiment.toFixed(2)}` : "—"} sub={top ? `${top.sentimentDelta > 0 ? "+" : ""}${top.sentimentDelta.toFixed(2)}` : "—"} tone={top && top.sentiment < 0 ? "text-bear" : "text-bull"} />
            <Counter label={zh ? "当前窗口" : "Current window"} value={`${data.summary.recentDays}d`} sub={`${data.summary.windowDays}d ${zh ? "总窗" : "total"}`} />
          </Counters>

          <div className="grid xl:grid-cols-3 gap-5">
            <Module title={zh ? "热度排名变化" : "Rank rotation"} icon="trend" accent="reddit" hint={zh ? "#1 在上" : "#1 at top"}>
              <NarrativeRankChart leaders={data.leaderboard} series={data.series} />
            </Module>
            <Module title={zh ? "讨论占比变化" : "Discussion share"} icon="pulse" accent="bull" hint={zh ? "近窗 Top 6 板块" : "top 6 sectors"}>
              <NarrativeShareChart leaders={data.leaderboard} series={data.series} />
            </Module>
            <Module title={zh ? "情绪转向" : "Sentiment shifts"} icon="flame" accent="amber" hint={zh ? "绿=偏多 / 红=偏空" : "positive=bullish"}>
              <NarrativeSentimentChart leaders={data.leaderboard} series={data.series} />
            </Module>
          </div>

          <Module title={zh ? "轮动榜" : "Rotation board"} icon="layers" accent="reddit" hint={zh ? "按近窗讨论度排序" : "ranked by recent volume"} flush>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-white/[.02] text-[11px] uppercase tracking-wider text-neutral-500">
                    <th className="py-2.5 pl-5 pr-2 text-right font-medium">#</th>
                    <th className="px-3 py-2.5 text-left font-medium">{zh ? "板块叙事" : "Sector narrative"}</th>
                    <th className="px-3 py-2.5 text-right font-medium">{zh ? "讨论" : "Volume"}</th>
                    <th className="px-3 py-2.5 text-right font-medium">{zh ? "占比" : "Share"}</th>
                    <th className="px-3 py-2.5 text-right font-medium">{zh ? "排名变化" : "Rank Δ"}</th>
                    <th className="px-3 py-2.5 text-right font-medium">{zh ? "情绪" : "Sent"}</th>
                    <th className="px-3 py-2.5 text-left font-medium hidden lg:table-cell">{zh ? "关联标的" : "Tickers"}</th>
                    <th className="py-2.5 pl-3 pr-5 text-right font-medium">{zh ? "状态" : "State"}</th>
                  </tr>
                </thead>
                <tbody>
                  {data.leaderboard.map((row) => (
                    <tr key={row.id} className="border-t border-line hover:bg-white/[.03] transition">
                      <td className="py-3 pl-5 pr-2 text-right font-mono text-xs text-neutral-500">{row.rank ? `#${row.rank}` : "—"}</td>
                      <td className="px-3 py-3">
                        <LocaleLink href={`/narratives/${row.slug}`} className="group flex items-center gap-2.5">
                          <span className="h-7 w-1 rounded-full" style={{ background: row.color }} />
                          <span>
                            <span className="block font-display text-[15px] font-bold text-cream group-hover:text-reddit transition">{narrativeText(row.title, lang)}</span>
                            <span className="text-[11px] text-neutral-600">{row.previousRank ? `${zh ? "前窗" : "prev"} #${row.previousRank}` : zh ? "新近活跃" : "newly active"}</span>
                          </span>
                        </LocaleLink>
                      </td>
                      <td className="px-3 py-3 text-right font-mono tabular text-neutral-300">{fmtCompact(row.volume)}</td>
                      <td className="px-3 py-3 text-right font-mono tabular text-neutral-300">{fmtPct(row.share * 100, 1)}</td>
                      <td className="px-3 py-3 text-right font-mono tabular">{rankMove(row, zh)}</td>
                      <td className="px-3 py-3 text-right"><SentScore score={row.sentiment} /></td>
                      <td className="px-3 py-3 hidden lg:table-cell">
                        <div className="flex flex-wrap gap-1.5">
                          {row.topTickers.slice(0, 4).map((t) => (
                            <LocaleLink key={t.ticker} href={`/tickers/${t.ticker}`} className="inline-flex items-center gap-1 rounded-md bg-white/[.04] px-1.5 py-0.5 text-[11px] font-mono text-neutral-300 ring-1 ring-inset ring-white/10 hover:text-reddit transition">
                              <TickerLogo ticker={t.ticker} size={14} />{t.ticker}
                            </LocaleLink>
                          ))}
                        </div>
                      </td>
                      <td className="py-3 pl-3 pr-5 text-right text-[12px] text-neutral-400">{trendLabel(row.trend, lang)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Module>

        </>
      )}
    </div>
  );
}
