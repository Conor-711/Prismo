"use client";

import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { SentPill, TickerChip, SubredditChip } from "./ui";
import { RedditMark, SnooCharacter } from "./reddit";
import { IconUpvote, IconComment, IconArrow, IconFlame } from "./icons";
import { timeAgo, fmtCompact } from "@/lib/format";
import type { AlphaRow } from "@/lib/queries";

// 橙底之上的「玻璃」叠色——用内联 rgba，绕开 globals.css 对 white/α 工具类的明暗翻转，
// 保证在橙色场上两种主题都呈白色玻璃质感。
const GLASS: React.CSSProperties = {
  background: "rgba(255,255,255,0.16)",
  boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.28)",
};

// 首页头牌：过去 24 小时 Reddit 社区含金量最高的 3 条 Alpha。
// 整个模块以 Reddit 专属橙红 (#FF4500) 为主题色，置于首页最上方、视觉最强。
export function TodaysAlpha({ alphas, tickerBase = "/ticker" }: { alphas: AlphaRow[]; tickerBase?: string }) {
  const { lang, dict } = useLocale();
  const t = dict.dashboard;
  if (!alphas.length) return null;

  return (
    <section className="alpha-hero relative overflow-hidden rounded-2xl text-white">
      {/* 左上高光 */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{ background: "radial-gradient(120% 80% at 0% 0%, rgba(255,255,255,.20), transparent 55%)" }}
      />

      <div className="relative p-5 sm:p-7">
        {/* 头部：左=品牌/标题/副文案，右=Reddit 吉祥物 */}
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex items-center gap-3.5">
              <span className="grid place-items-center w-12 h-12 rounded-2xl shrink-0" style={GLASS}>
                <RedditMark size={28} />
              </span>
              <div>
                <h2 className="font-display font-extrabold text-white text-[clamp(23px,3.2vw,32px)] leading-none tracking-tight drop-shadow-sm">
                  {t.alphaTitle}
                </h2>
              </div>
            </div>
            <p className="mt-3 max-w-lg text-[13px] leading-relaxed text-white/85">{t.alphaSub}</p>
          </div>
          {/* Reddit 吉祥物（宇航员 Snoo），橙底上的白灰角色对比最佳；高度压低，避免标题与卡片间留白 */}
          <SnooCharacter
            n={1}
            className="hidden md:block h-16 lg:h-20 w-auto -mt-2 -mr-1 shrink-0 drop-shadow-[0_10px_18px_rgba(0,0,0,.30)]"
          />
        </div>

        {/* 卡片 */}
        <div className="mt-4 grid md:grid-cols-3 gap-3.5">
          {alphas.map((a, i) => (
            <article
              key={a.id}
              className="alpha-card group relative flex flex-col overflow-hidden rounded-xl bg-card ring-1 ring-inset ring-line p-4 shadow-xl shadow-black/25 transition hover:-translate-y-1"
            >
              {/* 巨号水印序号 */}
              <span className="pointer-events-none absolute -right-1 -top-3 font-display font-extrabold text-[64px] leading-none text-reddit/[.08] select-none">
                {i + 1}
              </span>

              <div className="relative flex items-center gap-2">
                <span
                  className={`grid place-items-center w-6 h-6 rounded-full text-[11px] font-extrabold metal-fill ${
                    i === 0 ? "m-gold" : i === 1 ? "m-silver" : "m-bronze"
                  }`}
                >
                  {i + 1}
                </span>
                <div className="flex flex-wrap items-center gap-1.5 min-w-0">
                  {a.tickers.slice(0, 3).map((tk) => (
                    <TickerChip key={tk.ticker} ticker={tk.ticker} size="xs" base={tickerBase} />
                  ))}
                </div>
                <SentPill stance={a.stance} className="ml-auto shrink-0" />
              </div>

              <LocaleLink
                href={`/post/${a.id}`}
                className="relative mt-3 block font-display font-bold text-cream hover:text-reddit transition leading-snug line-clamp-2"
              >
                {lang === "zh" && a.title_zh ? a.title_zh : a.title}
              </LocaleLink>

              {/* 核心 alpha：社区最强的一条论点（橙色高亮，呼应模块主题色） */}
              <div className="relative mt-3 rounded-lg p-3 bg-reddit/10 ring-1 ring-inset ring-reddit/25">
                <div className="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-reddit mb-1">
                  <IconFlame className="w-3 h-3" />
                  {t.alphaEdge}
                </div>
                <p className="text-[13px] text-neutral-300 leading-relaxed line-clamp-4">
                  {lang === "zh" && a.edge_zh ? a.edge_zh : a.edge}
                </p>
              </div>

              <div className="relative mt-auto pt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-neutral-500">
                <SubredditChip name={a.subreddit} className="text-[11px]" />
                <span className="inline-flex items-center gap-1">
                  <IconUpvote className="w-3.5 h-3.5 text-reddit" />
                  <span className="font-mono tabular text-reddit">{fmtCompact(a.score)}</span>
                </span>
                <span className="inline-flex items-center gap-1">
                  <IconComment className="w-3.5 h-3.5" />
                  {fmtCompact(a.comments)}
                </span>
                <span>· {timeAgo(a.created, lang)}</span>
                <LocaleLink
                  href={`/post/${a.id}`}
                  className="ml-auto inline-flex items-center gap-1 text-reddit font-semibold hover:gap-1.5 transition-all shrink-0"
                >
                  {t.alphaCta}
                  <IconArrow className="w-3.5 h-3.5" />
                </LocaleLink>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
