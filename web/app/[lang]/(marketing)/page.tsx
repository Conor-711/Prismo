import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Eyebrow } from "@/components/ui";
import { IconLayers, IconPulse, IconTrend } from "@/components/icons";
import { getGrMeta } from "@/lib/globalQueries";
import { REGION_ORDER, regionLabel, regionSource, regionColor } from "@/lib/regions";
import { fmtInt, fmtCompact, timeAgo } from "@/lib/format";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";

// 落地页（域名根 /）：以 dict.home 的 slogan 开篇。
// 实时看板已移到 /dashboard。本页与静态导出兼容（[lang] 的 generateStaticParams 由 layout 提供）。
export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const h = getDictionary(params.lang).home;
  return { title: `Prismo · ${h.slogan}`, description: h.lede };
}

function Stat({ n, l }: { n: string; l: string }) {
  return (
    <span className="inline-flex items-baseline gap-1.5">
      <span className="font-display font-extrabold text-cream text-lg tabular">{n}</span>
      <span className="text-neutral-500">{l}</span>
    </span>
  );
}

export default function Landing({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const h = getDictionary(lang).home;
  const meta = getGrMeta();

  const steps = [
    { Icon: IconLayers, t: h.step1Title, d: h.step1Desc },
    { Icon: IconPulse, t: h.step2Title, d: h.step2Desc },
    { Icon: IconTrend, t: h.step3Title, d: h.step3Desc },
  ];

  return (
    <div className="space-y-16 pb-12">
      {/* ===== Hero ===== */}
      <section className="pt-4 sm:pt-10">
        <Eyebrow color="text-reddit">{h.eyebrow}</Eyebrow>
        <h1 className="mt-4 font-display font-extrabold text-cream tracking-tight text-[52px] sm:text-[88px] leading-[0.92]">
          {h.slogan}
          {h.sloganAlt ? (
            <span className="mt-1 block font-bold text-neutral-600 text-[30px] sm:text-[48px]">{h.sloganAlt}</span>
          ) : null}
        </h1>
        <p className="mt-6 max-w-2xl text-base sm:text-lg leading-relaxed text-neutral-400">{h.lede}</p>
        <div className="mt-8 flex flex-wrap items-center gap-3">
          <LocaleLink
            href="/dashboard"
            className="inline-flex items-center gap-1.5 rounded-full bg-reddit px-6 py-3 text-sm font-semibold text-white transition hover:bg-reddit/90"
          >
            {h.ctaPrimary} →
          </LocaleLink>
          <LocaleLink
            href="/signup"
            className="inline-flex items-center gap-1.5 rounded-full bg-reddit/10 px-6 py-3 text-sm font-semibold text-reddit ring-1 ring-inset ring-reddit/30 transition hover:bg-reddit/20"
          >
            {h.ctaSecondary}
          </LocaleLink>
        </div>
        {meta.tickers > 0 && (
          <div className="mt-8 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-neutral-500">
            <Stat n={fmtInt(meta.tickers)} l={h.tickers} />
            <span className="text-neutral-700">·</span>
            <Stat n={fmtCompact(meta.posts)} l={h.posts} />
            <span className="text-neutral-700">·</span>
            <Stat n={String(meta.regions)} l={h.regions} />
            {meta.lastUpdated && (
              <span className="text-xs text-neutral-600 tabular">· {h.updated}{timeAgo(meta.lastUpdated, lang)}</span>
            )}
          </div>
        )}
      </section>

      {/* ===== 怎么把噪音变成信号（三步）===== */}
      <section>
        <h2 className="font-display font-bold text-cream text-2xl tracking-tight">{h.howTitle}</h2>
        <div className="mt-6 grid gap-4 sm:grid-cols-3">
          {steps.map((s, i) => (
            <div key={i} className="rounded-xl bg-card ring-1 ring-inset ring-line p-5">
              <span className="grid h-10 w-10 place-items-center rounded-lg bg-reddit/10 text-reddit">
                <s.Icon className="h-5 w-5" />
              </span>
              <div className="mt-4 flex items-baseline gap-2">
                <span className="font-mono text-xs text-neutral-600 tabular">0{i + 1}</span>
                <h3 className="font-display font-bold text-cream">{s.t}</h3>
              </div>
              <p className="mt-1.5 text-sm leading-relaxed text-neutral-400">{s.d}</p>
            </div>
          ))}
        </div>
      </section>

      {/* ===== 五社区 · 五地区 ===== */}
      <section>
        <h2 className="font-display font-bold text-cream text-2xl tracking-tight">{h.commTitle}</h2>
        <p className="mt-2 max-w-2xl text-sm leading-relaxed text-neutral-400">{h.commDesc}</p>
        <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-5">
          {REGION_ORDER.map((r) => (
            <div key={r} className="rounded-xl bg-card ring-1 ring-inset ring-line p-4 text-center">
              <span className="mx-auto block h-2.5 w-2.5 rounded-full" style={{ background: regionColor(r) }} />
              <div className="mt-2.5 font-display font-bold text-cream text-sm">{regionLabel(r, lang)}</div>
              <div className="mt-0.5 text-[11px] text-neutral-500">{regionSource(r)}</div>
            </div>
          ))}
        </div>
      </section>

      {/* ===== 收尾 CTA ===== */}
      <section className="rounded-2xl bg-reddit/[.07] ring-1 ring-inset ring-reddit/20 px-6 py-10 text-center sm:px-10 sm:py-12">
        <h2 className="font-display font-extrabold text-cream text-2xl sm:text-3xl tracking-tight">{h.finalTitle}</h2>
        <p className="mx-auto mt-2.5 max-w-md text-sm leading-relaxed text-neutral-400">{h.finalDesc}</p>
        <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
          <LocaleLink
            href="/signup"
            className="inline-flex items-center gap-1.5 rounded-full bg-reddit px-6 py-3 text-sm font-semibold text-white transition hover:bg-reddit/90"
          >
            {h.ctaSecondary} →
          </LocaleLink>
          <LocaleLink
            href="/dashboard"
            className="inline-flex items-center gap-1.5 rounded-full bg-white/5 px-6 py-3 text-sm font-semibold text-cream ring-1 ring-inset ring-line transition hover:bg-white/10"
          >
            {h.ctaPrimary}
          </LocaleLink>
        </div>
      </section>
    </div>
  );
}
