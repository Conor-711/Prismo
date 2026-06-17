import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel, SectionTitle } from "@/components/ui";
import { Kpi, SentScore, Consensus, RegionBadge, StanceBar } from "@/components/prismo/Bits";
import { AsiaRadar } from "@/components/asia/AsiaCharts";
import { getGrTickerSymbols, getGrTickerDetail, getGrPosts, getGrUsPosts, type GrPostRow } from "@/lib/globalQueries";
import { regionLabel, regionSource, regionColor } from "@/lib/regions";
import { fmtCompact, timeAgo } from "@/lib/format";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export const dynamicParams = false;
export function generateStaticParams() {
  return getGrTickerSymbols().map((symbol) => ({ symbol }));
}

export function generateMetadata({ params }: { params: { lang: string; symbol: string } }): Metadata {
  const zh = params.lang === "zh";
  return { title: `${params.symbol} · ${zh ? "标的详情" : "Ticker"} · Prismo` };
}

function PostRow({ p, lang }: { p: GrPostRow; lang: Locale }) {
  const tone = p.stance === "bull" ? "bg-bull" : p.stance === "bear" ? "bg-bear" : "bg-neutral-500";
  const inner = (
    <div className="flex items-start gap-2.5 px-3 py-2.5 rounded-lg hover:bg-white/[.04] transition">
      <span className={`mt-1.5 w-1.5 h-1.5 rounded-full shrink-0 ${tone}`} />
      <div className="min-w-0 flex-1">
        <div className="text-[13.5px] text-cream leading-snug line-clamp-2">{p.title || p.body || "—"}</div>
        <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11px] text-neutral-600">
          <RegionBadge region={p.region} lang={lang} />
          <span>· {p.source || regionSource(p.region)}</span>
          {p.likes > 0 && <span>· ▲ {fmtCompact(p.likes)}</span>}
          {p.comments > 0 && <span>· 💬 {fmtCompact(p.comments)}</span>}
          {p.created && <span>· {timeAgo(p.created, lang)}</span>}
        </div>
      </div>
    </div>
  );
  return p.url ? (
    <a href={p.url} target="_blank" rel="noreferrer noopener" className="block">{inner}</a>
  ) : inner;
}

export default function TickerDetail({ params }: { params: { lang: string; symbol: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const { ticker, regions } = getGrTickerDetail(params.symbol);
  if (!ticker) notFound();

  const name = zh ? ticker.name_zh || ticker.name_en : ticker.name_en || ticker.name_zh;
  const ordered = [...regions].sort((a, b) => b.post_count - a.post_count);

  // 各区代表帖
  const posts: GrPostRow[] = [];
  for (const r of ordered) {
    const rp = r.region === "us" ? getGrUsPosts(ticker.ticker, 2) : getGrPosts(r.region, ticker.ticker, 2);
    posts.push(...rp);
  }
  posts.sort((a, b) => b.likes + b.comments - (a.likes + a.comments));

  // 雷达：各区情绪（归一化 -1..1 → 0..1）
  const radarIndicators = ordered.map((r) => ({ name: regionLabel(r.region, lang), max: 1 }));
  const radarSeries = [{ name: ticker.ticker, color: "#57D7BA", value: ordered.map((r) => Math.round(((r.sentiment_avg + 1) / 2) * 100) / 100) }];

  return (
    <div className="space-y-6">
      <LocaleLink href="/tickers" className="inline-flex items-center gap-1 text-xs text-neutral-500 hover:text-reddit transition">
        ← {zh ? "标的总览" : "All tickers"}
      </LocaleLink>

      {/* 头部 */}
      <div className="flex flex-wrap items-start justify-between gap-4 pb-4 border-b border-line">
        <div className="flex items-center gap-3">
          <span className="font-display font-extrabold text-cream text-3xl tracking-tight">{ticker.ticker}</span>
          <div>
            <div className="text-sm text-neutral-400">{name}</div>
            <div className="mt-1"><Consensus value={ticker.consensus} lang={lang} /></div>
          </div>
        </div>
        <div className="grid grid-cols-3 gap-2">
          <Kpi label={zh ? "平均情绪" : "Avg sentiment"} value={(ticker.avg_sentiment > 0 ? "+" : "") + ticker.avg_sentiment.toFixed(2)} />
          <Kpi label={zh ? "覆盖地区" : "Regions"} value={`${ticker.regions_present}/5`} />
          <Kpi label={zh ? "讨论帖" : "Posts"} value={fmtCompact(ticker.total_posts)} />
        </div>
      </div>

      {/* 逐区分解 + 雷达 */}
      <div className="grid lg:grid-cols-[1fr_340px] gap-5 items-start">
        <section>
          <SectionTitle title={zh ? "各地区分解" : "By region"} accent="bull" icon="layers" />
          <div className="space-y-2.5">
            {ordered.map((r) => (
              <LocaleLink key={r.region} href={`/regions/${r.region}`} className="block rounded-xl bg-card ring-1 ring-inset ring-line p-4 hover:ring-reddit/40 transition">
                <div className="flex items-center justify-between gap-3">
                  <span className="inline-flex items-center gap-2 font-semibold text-cream">
                    <span className="w-2.5 h-2.5 rounded-full" style={{ background: regionColor(r.region) }} />
                    {regionLabel(r.region, lang)}
                    <span className="text-[11px] font-normal text-neutral-600">{regionSource(r.region)}</span>
                  </span>
                  <SentScore score={r.sentiment_avg} className="text-[15px]" />
                </div>
                <div className="mt-3"><StanceBar bull={r.bull_pct} bear={r.bear_pct} neutral={Math.max(0, 1 - r.bull_pct - r.bear_pct)} /></div>
                <div className="mt-2 flex items-center justify-between text-[11px] text-neutral-500 tabular">
                  <span>{fmtCompact(r.post_count)} {zh ? "帖" : "posts"}</span>
                  <span>{zh ? "互动" : "Engagement"} {fmtCompact(r.engagement)}</span>
                </div>
              </LocaleLink>
            ))}
          </div>
        </section>

        {ordered.length >= 3 && (
          <section>
            <SectionTitle title={zh ? "跨区情绪雷达" : "Cross-region radar"} accent="reddit" />
            <Panel className="p-3">
              <AsiaRadar indicators={radarIndicators} series={radarSeries} height={300} />
              <p className="px-2 pb-1 text-[10px] text-neutral-600">{zh ? "情绪归一化到 0–1（0.5=中性）。" : "Sentiment normalized to 0–1 (0.5 = neutral)."}</p>
            </Panel>
          </section>
        )}
      </div>

      {/* 代表帖 */}
      <section>
        <SectionTitle title={zh ? "各地区代表讨论" : "Representative discussion"} accent="amber" icon="doc" />
        <Panel className="p-2">
          {posts.length ? posts.slice(0, 12).map((p, i) => <PostRow key={`${p.region}-${i}`} p={p} lang={lang} />)
            : <p className="px-3 py-6 text-sm text-neutral-600">{zh ? "暂无代表讨论。" : "No representative posts yet."}</p>}
        </Panel>
      </section>
    </div>
  );
}
