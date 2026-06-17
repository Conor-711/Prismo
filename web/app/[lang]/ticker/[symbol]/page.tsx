import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { notFound } from "next/navigation";
import { SectionTitle, Eyebrow, MiniBar, ScoreNum, ThemeTag, Avatar } from "@/components/ui";
import { Sparkline } from "@/components/charts/Sparkline";
import { FeedCard } from "@/components/FeedCard";
import { TickerDDPosts } from "@/components/TickerDDPosts";
import { ShareBar } from "@/components/ShareBar";
import { SaveButton } from "@/components/favorites/SaveButton";
import { SnooMascot } from "@/components/reddit";
import { fmtInt, fmtPct, fmtCompact, sentTextClass } from "@/lib/format";
import { getTickerDetail, getAllTickerSymbols } from "@/lib/queries";
import { getDictionary, isLocale, defaultLocale, type Locale, type Dictionary } from "@/lib/i18n";
import { SITE_URL, OG_IMAGE } from "@/lib/site";

export const dynamicParams = false;

export function generateStaticParams() {
  return getAllTickerSymbols().map((symbol) => ({ symbol }));
}

// 每个标的页独立的 OG / Twitter 卡片 —— 分享链接到社媒会展开为富预览，带来免费流量。
export function generateMetadata({ params }: { params: { lang: string; symbol: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const symbol = params.symbol.toUpperCase();
  const d = getTickerDetail(params.symbol);
  const name = d.meta?.company_name || "";
  const zh = lang === "zh";
  const title = `$${symbol}${name ? ` ${name}` : ""} · Reddit ${zh ? "多空情报" : "bull vs bear"} | redditalpha`;
  const desc = zh
    ? `${symbol} 在 Reddit 财经社区的声量、情绪与 AI 提炼的多空论点 —— 比大众早一步。`
    : `${symbol}'s mindshare, sentiment and the AI-distilled bull vs bear case across Reddit's finance communities.`;
  const url = `${SITE_URL}/${lang}/ticker/${symbol}/`;
  return {
    title,
    description: desc,
    alternates: { canonical: url },
    openGraph: { title, description: desc, url, siteName: "redditalpha", type: "website", images: [{ url: OG_IMAGE, width: 1200, height: 630 }] },
    twitter: { card: "summary_large_image", title, description: desc, images: [OG_IMAGE] },
  };
}

export default function TickerPage({ params }: { params: { lang: string; symbol: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).ticker;
  const sh = getDictionary(lang).share;
  const d = getTickerDetail(params.symbol);
  if (!d.meta && !d.roll && d.posts.length === 0) notFound();

  const r = d.roll;
  const name = d.meta?.company_name || r?.name || "";
  const maxSub = Math.max(1, ...d.bySub.map((s) => s.n));

  const bull = r?.bull ?? 0;
  const bear = r?.bear ?? 0;
  const neu = r?.neutral ?? 0;
  const cTotal = bull + bear + neu;
  const pct = (n: number) => (cTotal ? Math.round((n / cTotal) * 100) : 0);

  return (
    // 无卡片分割：各模块靠区块标题 + 分隔线在页面里自然分布；双列用竖向分隔线区分。
    <div className="space-y-9">
      <div className="flex items-center justify-between gap-3">
        <LocaleLink href="/dashboard" className="text-xs text-neutral-500 hover:text-reddit transition">{t.back}</LocaleLink>
        <ShareBar path={`/${lang}/ticker/${d.ticker}`} text={sh.tickerText.replace("{s}", `$${d.ticker}`)} ticker={d.ticker} />
      </div>

      {/* ============ 头部（无卡片，底部分隔线） ============ */}
      <header className="pb-7 border-b border-line">
        <Eyebrow color="text-reddit">{t.eyebrow}</Eyebrow>
        <div className="mt-1.5 flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="font-display font-extrabold text-cream text-4xl font-mono tracking-tight">{d.ticker}</h1>
              {d.meta?.sector && (
                <span className="text-xs px-2 py-1 rounded-md bg-white/5 text-neutral-400 ring-1 ring-inset ring-white/8">
                  {d.meta.sector}
                </span>
              )}
              <SaveButton kind="ticker" refId={d.ticker} variant="follow" />
            </div>
            <div className="mt-1 text-neutral-500">{name}{d.meta?.exchange ? ` · ${d.meta.exchange}` : ""}</div>
          </div>
          {r && (
            <div className="grid grid-cols-2 sm:grid-cols-5 gap-x-6 gap-y-3">
              <Metric label={t.mindshare} value={fmtPct(r.mindshare)} accent="text-reddit" />
              <Metric label={t.sentiment} node={<span className={`font-mono ${sentTextClass(r.sentiment)}`}>{r.sentiment > 0 ? "+" : ""}{r.sentiment.toFixed(2)}</span>} />
              <Metric label={t.mentions} value={fmtInt(r.mentions)} />
              <Metric label={t.posts} value={fmtInt(r.posts)} />
              <Metric label={t.authors} value={fmtInt(r.authors)} />
            </div>
          )}
        </div>

        {cTotal > 0 && (
          <div className="mt-5">
            <div className="flex items-center justify-between text-xs text-neutral-500 mb-1.5">
              <span>{t.conviction}</span>
              <span>{cTotal} {t.convictionCount}</span>
            </div>
            <div className="flex h-2.5 rounded-full overflow-hidden bg-white/5">
              <div className="bg-bull" style={{ width: `${pct(bull)}%` }} />
              <div className="bg-neutral-600" style={{ width: `${pct(neu)}%` }} />
              <div className="bg-bear" style={{ width: `${pct(bear)}%` }} />
            </div>
            <div className="mt-2 flex justify-between text-xs">
              <span className="text-bull">{t.bull} {pct(bull)}%</span>
              <span className="text-neutral-500">{t.neutral} {pct(neu)}%</span>
              <span className="text-bear">{t.bear} {pct(bear)}%</span>
            </div>
          </div>
        )}
      </header>

      {!r && (
        <div className="flex flex-col items-center text-center gap-2.5 py-10">
          <SnooMascot className="w-12 h-14 text-neutral-400" />
          <span className="text-sm text-neutral-500">{t.noDiscussion}</span>
        </div>
      )}

      {/* ============ 主打：多空论点（无卡片） ============ */}
      {(d.bull.length > 0 || d.bear.length > 0) && (
        <section>
          <div className="flex items-center gap-2">
            <Eyebrow color="text-reddit">{t.thesisEyebrow}</Eyebrow>
            <span className="text-xs text-neutral-500">{t.thesisHint}</span>
          </div>
          <h2 className="mt-1 font-display font-extrabold text-cream text-[20px] tracking-tight">{t.thesisHeading}</h2>

          <div className="mt-5 grid md:grid-cols-2 gap-x-8 gap-y-5">
            <ThesisColumn t={t} lang={lang} tone="bull" count={bull} items={d.bull} />
            <div className="md:border-l md:border-line md:pl-8">
              <ThesisColumn t={t} lang={lang} tone="bear" count={bear} items={d.bear} />
            </div>
          </div>
        </section>
      )}

      {/* ============ 信念趋势（无卡片） ============ */}
      {d.series.length > 1 && (
        <section className="grid sm:grid-cols-2 gap-x-8 gap-y-5">
          <div>
            <div className="text-xs text-neutral-500 mb-1.5">{t.volTrend}</div>
            <Sparkline series={d.series} height={84} metric="mentions" />
          </div>
          <div className="sm:border-l sm:border-line sm:pl-8">
            <div className="text-xs text-neutral-500 mb-1.5">{t.sentTrend}</div>
            <Sparkline series={d.series} height={84} metric="sentiment" />
          </div>
        </section>
      )}

      {/* ============ 可信声音 + 催化剂（无卡片） ============ */}
      <div className="grid md:grid-cols-2 gap-x-8 gap-y-9">
        <section>
          <SectionTitle title={t.voices} hint={t.voicesHint} accent="gold" icon="trophy" />
          <div className="space-y-1">
            {d.voices.map((v) => (
              <div key={v.author} className="flex items-center gap-3 px-2 py-2 rounded-lg hover:bg-white/[.03] transition">
                <Avatar name={v.author} size={28} />
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-medium text-cream truncate">u/{v.author}</div>
                  <div className="text-[11px] text-neutral-500">{v.posts} {t.voicePosts} · {fmtCompact(v.score)} {t.voiceUpvotes}</div>
                </div>
                <div className="text-right shrink-0">
                  <div className="text-[11px] font-bold metal-text m-gold">★ {v.quality.toFixed(2)}</div>
                  <div className="text-xs"><ScoreNum score={v.sentiment} /></div>
                </div>
              </div>
            ))}
            {d.voices.length === 0 && <div className="px-2 text-sm text-neutral-600">—</div>}
          </div>
        </section>

        <section className="md:border-l md:border-line md:pl-8">
          <SectionTitle title={t.catalysts} hint={t.catalystsHint} accent="amber" icon="flame" />
          <div className="flex flex-wrap gap-2">
            {d.themes.map((th) => (
              <ThemeTag key={th.name}>{th.name} · {th.count}</ThemeTag>
            ))}
            {d.themes.length === 0 && <div className="text-sm text-neutral-600">—</div>}
          </div>
        </section>
      </div>

      {/* ============ 板块分布 + 关联叙事（无卡片） ============ */}
      <div className="grid md:grid-cols-2 gap-x-8 gap-y-9">
        <section>
          <SectionTitle title={t.bySubTitle} hint={t.bySubHint} accent="reddit" icon="layers" />
          <div className="space-y-2.5">
            {d.bySub.map((s) => (
              <div key={s.subreddit} className="flex items-center gap-3">
                <span className="text-sm text-neutral-400 w-32 truncate">r/{s.subreddit}</span>
                <MiniBar pct={(s.n / maxSub) * 100} color="bg-reddit" />
                <span className="font-mono text-xs text-neutral-500 w-8 text-right tabular">{s.n}</span>
              </div>
            ))}
            {d.bySub.length === 0 && <div className="text-sm text-neutral-600">—</div>}
          </div>
        </section>

        <section className="md:border-l md:border-line md:pl-8">
          <SectionTitle title={t.narrativesTitle} accent="neutral" icon="waves" />
          <div className="space-y-3">
            {d.narratives.map((n) => (
              <div key={n.id} className="rounded-lg bg-white/[.02] ring-1 ring-inset ring-white/6 p-3">
                <div className="font-display font-semibold text-cream text-sm">{n.name}</div>
                <p className="mt-1 text-xs text-neutral-400 line-clamp-2 leading-relaxed">{n.summary}</p>
              </div>
            ))}
            {d.narratives.length === 0 && <div className="text-sm text-neutral-600">—</div>}
          </div>
        </section>
      </div>

      {/* ============ 高质量 DD 帖（可切排序：最近/质量/热度，默认最近） ============ */}
      {d.posts.length > 0 && (
        <TickerDDPosts
          title={t.ddTitle}
          hintPre={t.ddHintPre}
          hintPost={t.ddHintPost}
          labels={{ recent: t.ddSortRecent, quality: t.ddSortQuality, score: t.ddSortScore }}
          moreLabel={t.ddMore}
          meta={d.posts.map((p) => ({ created: p.created, quality: p.quality, score: p.score }))}
        >
          {d.posts.map((p) => (
            <FeedCard key={p.id} p={p} />
          ))}
        </TickerDDPosts>
      )}
    </div>
  );
}

function Metric({ label, value, node, accent = "text-cream" }: { label: string; value?: string; node?: React.ReactNode; accent?: string }) {
  return (
    <div>
      <div className={`font-display font-bold text-lg tabular ${accent}`}>{node ?? value}</div>
      <div className="text-[11px] text-neutral-500">{label}</div>
    </div>
  );
}

function ThesisColumn({
  t,
  lang,
  tone,
  count,
  items,
}: {
  t: Dictionary["ticker"];
  lang: Locale;
  tone: "bull" | "bear";
  count: number;
  items: { id: string; point: string; point_zh: string; permalink: string; title: string }[];
}) {
  const color = tone === "bull" ? "text-bull" : "text-bear";
  const dot = tone === "bull" ? "bg-bull" : "bg-bear";
  const title = tone === "bull" ? t.bullThesis : t.bearThesis;
  const empty = tone === "bull" ? t.noBull : t.noBear;
  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <h3 className={`font-display font-bold ${color}`}>{title}</h3>
        <span className="text-xs text-neutral-500">{count} {t.stanceCount}</span>
      </div>
      {items.length === 0 ? (
        <div className="text-sm text-neutral-600">{empty}</div>
      ) : (
        <ul className="space-y-2.5">
          {items.map((it, i) => (
            <li key={i} className="text-sm text-neutral-300 leading-relaxed flex gap-2">
              <span className={`mt-1.5 w-1.5 h-1.5 rounded-full ${dot} shrink-0`} />
              <span>
                {lang === "zh" && it.point_zh ? it.point_zh : it.point}{" "}
                <LocaleLink href={`/post/${it.id}`} className="text-neutral-600 hover:text-reddit transition" title={it.title}>↗</LocaleLink>
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
