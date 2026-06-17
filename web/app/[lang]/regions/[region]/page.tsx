import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel, SectionTitle } from "@/components/ui";
import { Kpi, SentScore, StanceBar, RegionBadge } from "@/components/prismo/Bits";
import { getGrRegionSummary, getGrRegionDetail, getGrPosts, getGrUsPosts, type GrPostRow } from "@/lib/globalQueries";
import { REGION_ORDER, regionLabel, regionSource, regionColor, isRegion } from "@/lib/regions";
import { fmtCompact, timeAgo } from "@/lib/format";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export const dynamicParams = false;
export function generateStaticParams() {
  return REGION_ORDER.map((region) => ({ region }));
}

export function generateMetadata({ params }: { params: { lang: string; region: string } }): Metadata {
  const zh = params.lang === "zh";
  const r = isRegion(params.region) ? regionLabel(params.region, zh ? "zh" : "en") : params.region;
  return { title: `${r} · ${zh ? "区域详情" : "Region"} · Prismo` };
}

export default function RegionDetail({ params }: { params: { lang: string; region: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const region = params.region;
  if (!isRegion(region)) notFound();

  const rows = [...getGrRegionDetail(region)].filter((d) => d.post_count > 0);
  const summary = getGrRegionSummary().find((s) => s.region === region);
  const byPosts = [...rows].sort((a, b) => b.post_count - a.post_count);
  const topBull = [...rows].sort((a, b) => b.sentiment_avg - a.sentiment_avg).slice(0, 5);
  const topBear = [...rows].sort((a, b) => a.sentiment_avg - b.sentiment_avg).slice(0, 5);
  const name = (t: { name_zh: string; name_en: string }) => (zh ? t.name_zh || t.name_en : t.name_en || t.name_zh);

  // 代表帖：取帖量前 3 标的
  const posts: GrPostRow[] = [];
  for (const t of byPosts.slice(0, 3)) {
    posts.push(...(region === "us" ? getGrUsPosts(t.ticker, 2) : getGrPosts(region, t.ticker, 2)));
  }
  posts.sort((a, b) => b.likes + b.comments - (a.likes + a.comments));

  return (
    <div className="space-y-6">
      <LocaleLink href="/regions" className="inline-flex items-center gap-1 text-xs text-neutral-500 hover:text-reddit transition">
        ← {zh ? "区域总览" : "All regions"}
      </LocaleLink>

      <div className="flex flex-wrap items-start justify-between gap-4 pb-4 border-b border-line">
        <div className="flex items-center gap-3">
          <span className="w-4 h-4 rounded-full" style={{ background: regionColor(region) }} />
          <div>
            <h1 className="font-display font-extrabold text-cream text-2xl tracking-tight">{regionLabel(region, lang)}</h1>
            <div className="text-sm text-neutral-500">{regionSource(region)}</div>
          </div>
        </div>
        {summary && (
          <div className="grid grid-cols-3 gap-2">
            <Kpi label={zh ? "平均情绪" : "Avg sentiment"} value={(summary.avg_sentiment > 0 ? "+" : "") + summary.avg_sentiment.toFixed(2)} />
            <Kpi label={zh ? "讨论帖" : "Posts"} value={fmtCompact(summary.posts)} />
            <Kpi label={zh ? "标的" : "Tickers"} value={summary.tickers} />
          </div>
        )}
      </div>

      {/* 最看多 / 最看空 */}
      <div className="grid md:grid-cols-2 gap-4">
        {[{ t: zh ? "最看多" : "Most bullish", list: topBull, a: "bull" }, { t: zh ? "最看空" : "Most bearish", list: topBear, a: "bear" }].map((col) => (
          <section key={col.a}>
            <SectionTitle title={col.t} accent={col.a as "bull" | "bear"} />
            <Panel className="p-2">
              {col.list.map((t) => (
                <LocaleLink key={t.ticker} href={`/tickers/${t.ticker}`} className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-white/[.04] transition">
                  <span className="font-mono font-bold text-cream text-[15px] w-16 shrink-0">{t.ticker}</span>
                  <span className="text-xs text-neutral-500 truncate flex-1">{name(t)}</span>
                  <span className="text-[11px] text-neutral-600 tabular">{fmtCompact(t.post_count)}</span>
                  <SentScore score={t.sentiment_avg} className="w-14 text-right" />
                </LocaleLink>
              ))}
            </Panel>
          </section>
        ))}
      </div>

      {/* 全部标的 */}
      <section>
        <SectionTitle title={zh ? "该区全部标的" : "All tickers in region"} accent="reddit" icon="trend" />
        <div className="overflow-x-auto rounded-xl ring-1 ring-inset ring-line">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-[11px] uppercase tracking-wider text-neutral-500 bg-white/[.02]">
                <th className="text-left font-medium px-3 py-2.5">{zh ? "标的" : "Ticker"}</th>
                <th className="text-left font-medium px-3 py-2.5 hidden sm:table-cell">{zh ? "名称" : "Name"}</th>
                <th className="text-left font-medium px-3 py-2.5 w-40">{zh ? "多空" : "Stance"}</th>
                <th className="text-right font-medium px-3 py-2.5">{zh ? "帖数" : "Posts"}</th>
                <th className="text-right font-medium px-3 py-2.5">{zh ? "情绪" : "Sentiment"}</th>
              </tr>
            </thead>
            <tbody>
              {byPosts.map((t) => (
                <tr key={t.ticker} className="border-t border-line hover:bg-white/[.03] transition">
                  <td className="px-3 py-2.5"><LocaleLink href={`/tickers/${t.ticker}`} className="font-mono font-bold text-cream hover:text-reddit transition">{t.ticker}</LocaleLink></td>
                  <td className="px-3 py-2.5 text-neutral-400 truncate max-w-[200px] hidden sm:table-cell">{name(t)}</td>
                  <td className="px-3 py-2.5"><StanceBar bull={t.bull_pct} bear={t.bear_pct} neutral={Math.max(0, 1 - t.bull_pct - t.bear_pct)} /></td>
                  <td className="px-3 py-2.5 text-right text-neutral-300 tabular">{fmtCompact(t.post_count)}</td>
                  <td className="px-3 py-2.5 text-right"><SentScore score={t.sentiment_avg} /></td>
                </tr>
              ))}
              {byPosts.length === 0 && <tr><td colSpan={5} className="px-3 py-8 text-center text-sm text-neutral-600">{zh ? "该区暂无标的数据。" : "No tickers in this region yet."}</td></tr>}
            </tbody>
          </table>
        </div>
      </section>

      {/* 代表帖 */}
      {posts.length > 0 && (
        <section>
          <SectionTitle title={zh ? "代表讨论" : "Representative discussion"} accent="amber" icon="doc" />
          <Panel className="p-2">
            {posts.slice(0, 10).map((p, i) => {
              const tone = p.stance === "bull" ? "bg-bull" : p.stance === "bear" ? "bg-bear" : "bg-neutral-500";
              const inner = (
                <div className="flex items-start gap-2.5 px-3 py-2.5 rounded-lg hover:bg-white/[.04] transition">
                  <span className={`mt-1.5 w-1.5 h-1.5 rounded-full shrink-0 ${tone}`} />
                  <div className="min-w-0 flex-1">
                    <div className="text-[13.5px] text-cream leading-snug line-clamp-2">{p.title || p.body || "—"}</div>
                    <div className="mt-1 flex flex-wrap items-center gap-x-2 text-[11px] text-neutral-600">
                      <span className="font-mono text-neutral-500">{p.ticker}</span>
                      {p.likes > 0 && <span>· ▲ {fmtCompact(p.likes)}</span>}
                      {p.comments > 0 && <span>· 💬 {fmtCompact(p.comments)}</span>}
                      {p.created && <span>· {timeAgo(p.created, lang)}</span>}
                    </div>
                  </div>
                </div>
              );
              return p.url ? <a key={i} href={p.url} target="_blank" rel="noreferrer noopener" className="block">{inner}</a> : <div key={i}>{inner}</div>;
            })}
          </Panel>
        </section>
      )}
    </div>
  );
}
