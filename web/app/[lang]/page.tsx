import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel, Eyebrow } from "@/components/ui";
import { SentScore, RegionBadge, StanceBar } from "@/components/prismo/Bits";
import { TickerLogo } from "@/components/prismo/TickerLogo";
import { AsiaHeatmap } from "@/components/asia/AsiaCharts";
import { Module, Counter, Counters } from "@/components/prismo/DetailBits";
import {
  getGrMeta, getGrTickers, getGrTickerRegions, getGrRegionSummary, getGrQuotes,
} from "@/lib/globalQueries";
import type { GrQuoteRow } from "@/lib/globalQueries";
import { REGION_ORDER, regionLabel, regionSource } from "@/lib/regions";
import { fmtInt, fmtCompact, timeAgo } from "@/lib/format";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return {
    title: zh ? "总览看板 · Prismo" : "Overview · Prismo",
    description: zh
      ? "Reddit / Yahoo Finance Japan / Naver / 雪球 / PTT 五大社区的美股舆情：异动与信号优先。"
      : "Cross-community US-stock sentiment across Reddit, Yahoo Finance JP, Naver, Xueqiu and PTT — signals first.",
  };
}

// 标的行：logo + 代码 + 自定义右侧内容，整行链到详情。
function Row({ ticker, children }: { ticker: string; children: React.ReactNode }) {
  return (
    <LocaleLink href={`/tickers/${ticker}`} className="flex items-center gap-2.5 px-2.5 py-2.5 rounded-lg hover:bg-white/[.04] transition">
      <TickerLogo ticker={ticker} size={24} />
      <span className="font-mono font-bold text-cream text-[14px] shrink-0">{ticker}</span>
      {children}
    </LocaleLink>
  );
}

// 涨/跌一列（仅当 gr_quote 有行情时渲染）。
function MoversCol({ title, rows, up }: { title: string; rows: GrQuoteRow[]; up?: boolean }) {
  return (
    <div>
      <div className="px-2.5 pb-1.5 text-[11px] uppercase tracking-wider text-neutral-500">{title}</div>
      {rows.map((q) => (
        <LocaleLink key={q.ticker} href={`/tickers/${q.ticker}`} className="flex items-center gap-2.5 px-2.5 py-2 rounded-lg hover:bg-white/[.04] transition">
          <TickerLogo ticker={q.ticker} size={22} />
          <span className="font-mono font-bold text-cream text-[13.5px] flex-1">{q.ticker}</span>
          <span className="font-mono text-[12px] tabular text-neutral-400">{q.price.toFixed(2)}</span>
          <span className={`font-mono text-[12.5px] tabular w-16 text-right ${up ? "text-bull" : "text-bear"}`}>
            {q.change_pct > 0 ? "+" : ""}{q.change_pct.toFixed(2)}%
          </span>
        </LocaleLink>
      ))}
    </div>
  );
}

export default function Overview({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";

  const meta = getGrMeta();
  const tickers = getGrTickers();
  const summary = getGrRegionSummary();
  const cells = getGrTickerRegions();
  const quotes = getGrQuotes();

  const name = (t: { name_zh: string; name_en: string }) => (zh ? t.name_zh || t.name_en : t.name_en || t.name_zh);
  const sumByRegion = new Map(summary.map((s) => [s.region, s]));
  const regions = REGION_ORDER.filter((r) => sumByRegion.has(r));

  // ===== 异动 / 信号 =====
  const divergent = [...tickers].filter((t) => (t.spread ?? 0) > 0).sort((a, b) => (b.spread ?? 0) - (a.spread ?? 0)).slice(0, 6);
  const bullish = [...tickers].sort((a, b) => b.avg_sentiment - a.avg_sentiment).slice(0, 6);
  const bearish = [...tickers].sort((a, b) => a.avg_sentiment - b.avg_sentiment).slice(0, 6);
  const gainers = quotes.filter((q) => q.change_pct > 0).sort((a, b) => b.change_pct - a.change_pct).slice(0, 5);
  const losers = quotes.filter((q) => q.change_pct < 0).sort((a, b) => a.change_pct - b.change_pct).slice(0, 5);
  const hasMovers = gainers.length > 0 || losers.length > 0;
  const topGainer = gainers[0], topLoser = losers[0], topDiv = divergent[0];

  // ===== 市场总览 =====
  const byPosts = [...tickers].sort((a, b) => b.total_posts - a.total_posts);
  const stanceByTicker = new Map<string, { bull: number; bear: number; neutral: number }>();
  for (const c of cells) {
    const cur = stanceByTicker.get(c.ticker) ?? { bull: 0, bear: 0, neutral: 0 };
    cur.bull += (c.bull_pct || 0) * (c.post_count || 0);
    cur.bear += (c.bear_pct || 0) * (c.post_count || 0);
    cur.neutral += (c.neutral_pct || 0) * (c.post_count || 0);
    stanceByTicker.set(c.ticker, cur);
  }

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
    <div className="space-y-5">
      {/* 页头 */}
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-2 pb-4 border-b border-line">
        <div>
          <Eyebrow color="text-reddit">{zh ? "PRISMO · 5 社区聚合" : "PRISMO · 5 COMMUNITIES"}</Eyebrow>
          <h1 className="mt-1.5 font-display font-extrabold text-cream text-[22px] leading-none tracking-tight">
            {zh ? "总览看板" : "Overview"}
          </h1>
          <p className="mt-2 text-[13px] text-neutral-500 max-w-xl">
            {zh
              ? "异动优先 —— 跨区分歧、情绪两端、价格异动；其后是市场总览。"
              : "Signals first — cross-region divergence, sentiment extremes, price movers; market overview below."}
          </p>
        </div>
        {meta.lastUpdated && (
          <span className="text-xs text-neutral-500 tabular">{zh ? "更新于 " : "Updated "}{timeAgo(meta.lastUpdated, lang)}</span>
        )}
      </div>

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
          {/* 大数字 KPI 行 */}
          <Counters>
            <Counter label={zh ? "标的" : "Tickers"} value={fmtInt(meta.tickers)} sub={`${meta.regions} ${zh ? "地区覆盖" : "regions"}`} />
            <Counter label={zh ? "本地讨论帖" : "Local posts"} value={fmtCompact(meta.posts)} sub={zh ? "五社区合计" : "5 communities"} />
            <Counter label={zh ? "覆盖地区" : "Regions"} value={String(meta.regions)} sub="US·CN·JP·KR·TW" />
            <Counter label={zh ? "今日领涨" : "Top gainer"} value={topGainer ? `+${topGainer.change_pct.toFixed(2)}%` : "—"} sub={topGainer?.ticker ?? "—"} tone="text-bull" />
            <Counter label={zh ? "今日领跌" : "Top loser"} value={topLoser ? `${topLoser.change_pct.toFixed(2)}%` : "—"} sub={topLoser?.ticker ?? "—"} tone="text-bear" />
            <Counter label={zh ? "最大分歧" : "Top divergence"} value={topDiv ? `Δ${(topDiv.spread ?? 0).toFixed(2)}` : "—"} sub={topDiv?.ticker ?? "—"} tone="text-amber" />
          </Counters>

          {/* 价格异动 */}
          {hasMovers && (
            <Module title={zh ? "价格异动" : "Price movers"} icon="flame" accent="reddit" hint={zh ? "今日领涨 / 领跌（约 15 分钟延迟）" : "today's gainers / losers (~15-min delayed)"} flush>
              <div className="p-4 grid sm:grid-cols-2 gap-x-8 gap-y-1">
                <MoversCol title={zh ? "领涨" : "Gainers"} rows={gainers} up />
                <MoversCol title={zh ? "领跌" : "Losers"} rows={losers} />
              </div>
            </Module>
          )}

          {/* 跨区分歧 · 最看多 · 最看空 */}
          <div className="grid lg:grid-cols-3 gap-5 items-start">
            <Module title={zh ? "跨区分歧" : "Divergence"} icon="flame" accent="reddit" hint={zh ? "地区最不一致" : "by spread"} flush>
              <div className="p-2">
                {divergent.length ? (
                  divergent.map((t) => (
                    <Row key={t.ticker} ticker={t.ticker}>
                      <span className="flex-1 truncate">
                        {t.divergent_region ? <RegionBadge region={t.divergent_region} lang={lang} /> : <span className="text-xs text-neutral-500">{name(t)}</span>}
                      </span>
                      <span className="font-mono text-[12px] tabular text-amber">Δ{(t.spread ?? 0).toFixed(2)}</span>
                      <SentScore score={t.avg_sentiment} className="w-12 text-right" />
                    </Row>
                  ))
                ) : (
                  <p className="px-3 py-6 text-center text-sm text-neutral-600">{zh ? "暂无明显分歧。" : "No divergence yet."}</p>
                )}
              </div>
            </Module>

            <Module title={zh ? "最看多" : "Most bullish"} icon="pulse" accent="bull" hint={zh ? "情绪居前" : "top sentiment"} flush>
              <div className="p-2">
                {bullish.map((t) => (
                  <Row key={t.ticker} ticker={t.ticker}>
                    <span className="flex-1 truncate text-xs text-neutral-500">{name(t)}</span>
                    <span className="text-[11px] text-neutral-600 tabular">{fmtCompact(t.total_posts)}</span>
                    <SentScore score={t.avg_sentiment} className="w-12 text-right" />
                  </Row>
                ))}
              </div>
            </Module>

            <Module title={zh ? "最看空" : "Most bearish"} icon="pulse" accent="bear" hint={zh ? "情绪居后" : "low sentiment"} flush>
              <div className="p-2">
                {bearish.map((t) => (
                  <Row key={t.ticker} ticker={t.ticker}>
                    <span className="flex-1 truncate text-xs text-neutral-500">{name(t)}</span>
                    <span className="text-[11px] text-neutral-600 tabular">{fmtCompact(t.total_posts)}</span>
                    <SentScore score={t.avg_sentiment} className="w-12 text-right" />
                  </Row>
                ))}
              </div>
            </Module>
          </div>

          {/* 五地区情绪 */}
          <Module title={zh ? "五地区情绪" : "Five-region mood"} icon="layers" accent="bull" hint={zh ? "点击进入区域详情" : "click into a region"} flush>
            <div className="grid grid-cols-2 lg:grid-cols-5 divide-x divide-y lg:divide-y-0 divide-line">
              {regions.map((r) => {
                const s = sumByRegion.get(r)!;
                return (
                  <LocaleLink key={r} href={`/regions/${r}`} className="group p-4 hover:bg-white/[.025] transition">
                    <RegionBadge region={r} lang={lang} className="font-semibold !text-cream" />
                    <div className="mt-0.5 text-[10px] text-neutral-600">{regionSource(r)}</div>
                    <div className="mt-3 flex items-baseline justify-between">
                      <SentScore score={s.avg_sentiment} className="text-lg" />
                      <span className="text-[11px] text-neutral-500 tabular">{fmtCompact(s.posts)} {zh ? "帖" : "posts"}</span>
                    </div>
                    <div className="mt-2"><StanceBar bull={s.bull_pct} bear={s.bear_pct} neutral={Math.max(0, 1 - s.bull_pct - s.bear_pct)} /></div>
                    <div className="mt-2 text-[11px] text-neutral-500">{s.tickers} {zh ? "个标的" : "tickers"}</div>
                  </LocaleLink>
                );
              })}
            </div>
          </Module>

          {/* 全球热度榜 */}
          <Module
            title={zh ? "全球热度榜" : "Global buzz"}
            icon="trend"
            accent="reddit"
            hint={zh ? "按讨论量排序 · Top 10" : "by volume · top 10"}
            flush
            right={<LocaleLink href="/tickers" className="text-xs text-neutral-500 hover:text-reddit transition">{zh ? "查看全部" : "View all"} →</LocaleLink>}
          >
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-[11px] uppercase tracking-wider text-neutral-500 bg-white/[.02]">
                    <th className="text-right font-medium pl-5 pr-1 py-2.5 w-8">#</th>
                    <th className="text-left font-medium px-3 py-2.5">{zh ? "标的" : "Ticker"}</th>
                    <th className="text-left font-medium px-3 py-2.5 hidden lg:table-cell">{zh ? "名称" : "Name"}</th>
                    <th className="text-center font-medium px-2 py-2.5">{zh ? "区" : "Rgn"}</th>
                    <th className="text-right font-medium px-3 py-2.5">{zh ? "帖数" : "Posts"}</th>
                    <th className="text-left font-medium px-3 py-2.5 hidden md:table-cell w-28">{zh ? "多空" : "Stance"}</th>
                    <th className="text-right font-medium pl-3 pr-5 py-2.5">{zh ? "情绪" : "Sent"}</th>
                  </tr>
                </thead>
                <tbody>
                  {byPosts.slice(0, 10).map((t, i) => {
                    const st = stanceByTicker.get(t.ticker) ?? { bull: 0, bear: 0, neutral: 0 };
                    return (
                      <tr key={t.ticker} className="border-t border-line hover:bg-white/[.03] transition">
                        <td className="pl-5 pr-1 py-3 text-right text-xs text-neutral-600 tabular">{i + 1}</td>
                        <td className="px-3 py-3">
                          <LocaleLink href={`/tickers/${t.ticker}`} className="inline-flex items-center gap-2.5 hover:text-reddit transition">
                            <TickerLogo ticker={t.ticker} size={24} />
                            <span className="font-mono font-bold text-cream">{t.ticker}</span>
                          </LocaleLink>
                        </td>
                        <td className="px-3 py-3 text-neutral-400 truncate max-w-[180px] hidden lg:table-cell">{name(t)}</td>
                        <td className="px-2 py-3 text-center text-neutral-400 tabular">{t.regions_present}</td>
                        <td className="px-3 py-3 text-right text-neutral-300 tabular">{fmtCompact(t.total_posts)}</td>
                        <td className="px-3 py-3 hidden md:table-cell"><div className="w-24"><StanceBar bull={st.bull} bear={st.bear} neutral={st.neutral} /></div></td>
                        <td className="pl-3 pr-5 py-3 text-right"><SentScore score={t.avg_sentiment} /></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Module>

          {/* 跨区情绪热力 */}
          {heatCells.length > 0 && (
            <Module title={zh ? "跨区情绪热力" : "Cross-region sentiment heatmap"} icon="flame" accent="reddit" hint={zh ? "红=偏空 / 绿=偏多" : "red=bearish / green=bullish"}>
              <AsiaHeatmap x={xLabels} y={yLabels} cells={heatCells} rawX height={Math.max(240, yLabels.length * 26 + 60)} />
            </Module>
          )}
        </>
      )}
    </div>
  );
}
