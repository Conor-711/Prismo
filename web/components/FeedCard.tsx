"use client";

import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { SentPill, TickerChip, ThemeTag, SubredditChip } from "./ui";
import { AuthorLink } from "./author/AuthorLink";
import { IconUpvote, IconDownvote, IconComment } from "./icons";
import { timeAgo, fmtCompact } from "@/lib/format";
import type { FeedRow } from "@/lib/queries";
import { SaveButton } from "./favorites/SaveButton";
import { postSnapshotFromFeed } from "@/lib/favorites";

export function FeedCard({ p, tickerBase = "/ticker" }: { p: FeedRow; tickerBase?: string }) {
  const { lang, dict } = useLocale();
  const isZh = lang === "zh";
  const title = isZh && p.title_zh ? p.title_zh : p.title;
  const tldr = isZh && p.tldr_zh ? p.tldr_zh : p.tldr;
  return (
    <div className="panel rounded-2xl panel-hover flex overflow-hidden">
      {/* 投票轨（Reddit 招牌） */}
      <div className="flex flex-col items-center gap-0.5 py-3 w-11 shrink-0 bg-white/[.015]">
        <IconUpvote className="w-[18px] h-[18px] text-reddit" />
        <span className="font-mono font-bold text-[13px] text-reddit tabular leading-none">{fmtCompact(p.score)}</span>
        <IconDownvote className="w-[18px] h-[18px] text-neutral-600" />
      </div>

      {/* 内容 */}
      <div className="min-w-0 flex-1 p-3.5 pl-3">
        <div className="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-xs text-neutral-500">
          <SubredditChip name={p.subreddit} />
          {p.author && (
            <span className="inline-flex items-center gap-1 truncate">
              · <AuthorLink name={p.author} size={15} />
            </span>
          )}
          <span>· {timeAgo(p.created, lang)}</span>
          {p.flair && (
            <span className="px-1.5 py-0.5 rounded-full bg-white/[.06] text-neutral-400 text-[10px] font-medium">{p.flair}</span>
          )}
        </div>

        <LocaleLink
          href={`/post/${p.id}`}
          className="mt-1 block font-medium text-cream hover:text-reddit transition leading-snug"
        >
          {title}
        </LocaleLink>

        {tldr && <p className="mt-1.5 text-sm text-neutral-400 leading-relaxed line-clamp-2">{tldr}</p>}

        <div className="mt-2.5 flex flex-wrap items-center gap-x-2 gap-y-1.5">
          <span className="inline-flex items-center gap-1 text-xs text-neutral-500 font-medium">
            <IconComment className="w-3.5 h-3.5" /> {fmtCompact(p.comments)}
          </span>
          <SentPill stance={p.stance} />
          {p.quality >= 0.7 && <span className="text-[11px] font-bold metal-text m-gold">{dict.common.highSignal}</span>}
          {(p.tickers.length > 0 || p.themes.length > 0) && <span className="w-px h-3.5 bg-line mx-0.5" />}
          {p.tickers.slice(0, 5).map((t) => (
            <TickerChip key={t.ticker} ticker={t.ticker} size="xs" base={tickerBase} />
          ))}
          {p.themes.slice(0, 2).map((t) => (
            <ThemeTag key={t}>{t}</ThemeTag>
          ))}
          <span className="ml-auto shrink-0">
            <SaveButton kind="post" refId={p.id} snapshot={postSnapshotFromFeed(p)} size="xs" />
          </span>
        </div>
      </div>
    </div>
  );
}
