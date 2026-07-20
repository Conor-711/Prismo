"use client";

import { SaveButton } from "@/components/favorites/SaveButton";
import { Avatar, SOURCE, STANCE, pickOriginal } from "@/shared/market/kolPresentation";
import { YtReader } from "./YtReader";
import { fmtCompact } from "@/shared/formatting/format";
import type { KolJudgment, KolOpinion, TweetMetrics, TweetReply } from "@/shared/market/mockDetail";
import { LENS_LABEL } from "@/features/ticker/opinionExplorerConstants";
import { lensesOf, opinionAuthorRefId } from "@/features/ticker/opinionExplorerLogic";
import type { RecommendationReason } from "@/features/ticker/opinionExplorerTypes";
import { PlatformIcon } from "./controls";

type StatKey = "replies" | "retweets" | "likes" | "views" | "bookmarks";

const STAT_ICON: Record<StatKey, string> = {
  replies: "M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z",
  retweets: "M17 1l4 4-4 4M3 11V9a4 4 0 0 1 4-4h14M7 23l-4-4 4-4M21 13v2a4 4 0 0 1-4 4H3",
  likes: "M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 1 0-7.78 7.78L12 21.23l8.84-8.84a5.5 5.5 0 0 0 0-7.78z",
  views: "M18 20V10M12 20V4M6 20v-6",
  bookmarks: "M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z",
};

function Stat({ kind, n }: { kind: StatKey; n: number }) {
  return (
    <span className="flex items-center gap-1 text-neutral-500" title={kind}>
      <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
        <path d={STAT_ICON[kind]} />
      </svg>
      <span className="font-mono tabular text-[11px]">{fmtCompact(n)}</span>
    </span>
  );
}

function TweetStats({ m }: { m: TweetMetrics }) {
  const order: StatKey[] = ["replies", "retweets", "likes", "views", "bookmarks"];
  if (!order.some((k) => (m[k] ?? 0) > 0)) return null;
  return (
    <div className="mt-3 flex items-center gap-4 border-t border-line/60 pt-2.5">
      {order.map((k) => <Stat key={k} kind={k} n={m[k] ?? 0} />)}
    </div>
  );
}

function TweetReplies({ replies, zh }: { replies: TweetReply[]; zh: boolean }) {
  if (!replies?.length) return null;
  return (
    <div className="mt-3 border-t border-line/60 pt-3">
      <div className="mb-2 flex items-center gap-1.5 text-[11px] font-semibold text-neutral-400">
        <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d={STAT_ICON.replies} />
        </svg>
        {zh ? "热门评论" : "Top replies"}
      </div>
      <ul className="space-y-2">
        {replies.map((r, i) => (
          <li key={i} className="flex gap-2 rounded-lg bg-ink/40 px-2.5 py-2 ring-1 ring-inset ring-line/70">
            <Avatar src={r.avatar} color={SOURCE.x.color} name={r.author} size={22} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-1.5 text-[11px]">
                <span className="min-w-0 truncate font-medium text-neutral-300">{r.author}</span>
                {r.likes > 0 && (
                  <span className="ml-auto flex shrink-0 items-center gap-0.5 text-neutral-500">
                    <svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                      <path d={STAT_ICON.likes} />
                    </svg>
                    <span className="font-mono tabular">{fmtCompact(r.likes)}</span>
                  </span>
                )}
                {r.url && r.url !== "#" && (
                  <a href={r.url} target="_blank" rel="noreferrer" className={`shrink-0 text-neutral-600 transition hover:text-[#57D7BA] ${r.likes > 0 ? "" : "ml-auto"}`}>↗</a>
                )}
              </div>
              <p className="mt-0.5 whitespace-pre-line text-[12px] leading-snug text-neutral-400">{r.text}</p>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

const BUCKET_LABEL: Record<"short" | "mid" | "long", { zh: string; en: string }> = {
  short: { zh: "短线", en: "short" },
  mid: { zh: "中线", en: "mid" },
  long: { zh: "长线", en: "long" },
};

const fmtPrice = (n: number) => (n >= 10 ? Math.round(n).toLocaleString() : String(+n.toFixed(2)));
const fmtRange = (lo: number, hi: number) => (hi > lo ? `$${fmtPrice(lo)}–$${fmtPrice(hi)}` : `$${fmtPrice(lo)}`);

function JudgmentLine({ j, zh }: { j: KolJudgment; zh: boolean }) {
  const items: { label: string; text: string; color: string }[] = [];
  if (j.buyLo != null) items.push({ label: zh ? "买入" : "Buy", text: fmtRange(j.buyLo, j.buyHi ?? j.buyLo), color: "#57D7BA" });
  if (j.sellLo != null) items.push({ label: zh ? "卖出/目标" : "Sell/target", text: fmtRange(j.sellLo, j.sellHi ?? j.sellLo), color: "#FF5C6C" });
  const horizon = j.horizon ? (zh ? j.horizon.zh : j.horizon.en) : "";
  const bk = j.bucket ? (zh ? BUCKET_LABEL[j.bucket].zh : BUCKET_LABEL[j.bucket].en) : "";
  if (!items.length && !horizon) return null;
  return (
    <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg bg-elevated/60 px-3 py-2 text-[12px] ring-1 ring-inset ring-line">
      <span className="text-[10px] uppercase tracking-wide text-neutral-500">{zh ? "作者明确给出" : "Stated"}</span>
      {items.map((it) => (
        <span key={it.label} className="flex items-center gap-1">
          <span className="text-neutral-500">{it.label}</span>
          <span className="font-mono tabular font-semibold" style={{ color: it.color }}>{it.text}</span>
        </span>
      ))}
      {horizon && (
        <span className="flex items-center gap-1">
          <span className="text-neutral-500">{zh ? "周期" : "Horizon"}</span>
          <span className="text-neutral-200">{horizon}{bk ? `（${bk}）` : ""}</span>
        </span>
      )}
    </div>
  );
}

type SvRankMeta = {
  rank: number;
  count: number;
  percentile: number;
  score: number;
};

function SvRankBadge({ meta, zh }: { meta: SvRankMeta; zh: boolean }) {
  const count = Math.max(1, Math.floor(meta.count || 1));
  const rank = Math.max(1, Math.floor(meta.rank || 1));
  const topPct = Math.max(1, Math.min(100, Math.ceil((rank / count) * 100)));
  const score = Math.round(meta.score);
  return (
    <span
      className="shrink-0 rounded bg-[#57D7BA]/10 px-1.5 py-0.5 font-mono tabular text-[11px] text-[#57D7BA] ring-1 ring-inset ring-[#57D7BA]/35"
      title={zh ? `SV 排名 #${rank}/${count}，百分位 ${Math.round(meta.percentile)}%，分数 ${score}` : `SV rank #${rank}/${count}, percentile ${Math.round(meta.percentile)}%, score ${score}`}
    >
      {zh ? `SV ${score} · 前 ${topPct}%` : `SV ${score} · top ${topPct}%`}
    </span>
  );
}

export function Reader({
  o,
  zh,
  showT,
  setShowT,
  fill = false,
  recReasons = [],
  svRank,
  onBack,
}: {
  o: KolOpinion;
  zh: boolean;
  showT: boolean;
  setShowT: (v: boolean) => void;
  fill?: boolean;
  recReasons?: RecommendationReason[];
  svRank?: SvRankMeta;
  onBack?: () => void;
}) {
  const src = SOURCE[o.source];
  const st = STANCE[o.stance];
  const { base, trans, canTranslate } = pickOriginal(o, zh);
  const showOriginal = showT && canTranslate;
  const displayText = showOriginal ? base : (canTranslate ? trans : base);
  const hasLink = !!o.url && o.url !== "#";
  const lensKeys = lensesOf(o);
  const authorRefId = opinionAuthorRefId(o);
  const canTrackAuthor = o.source !== "yahoojp";
  return (
    <div
      data-reader-scroll
      className={`rounded-xl bg-card px-4 py-3.5 ring-1 ring-inset ring-line ${fill ? "h-full overflow-y-auto overflow-x-hidden" : "lg:max-h-[640px] lg:overflow-y-auto lg:overflow-x-hidden"}`}
    >
      {onBack && (
        <button
          type="button"
          onClick={onBack}
          className="mb-3 inline-flex items-center gap-1.5 text-[12px] font-medium text-neutral-400 transition hover:text-reddit"
        >
          ← {zh ? "返回概览" : "Back to overview"}
        </button>
      )}
      <div className="flex items-center gap-2.5">
        <Avatar src={o.avatar} color={src.color} name={o.author} size={34} />
        <div className="min-w-0 flex-1">
          <div className="flex min-w-0 items-center gap-2">
            <div className="truncate text-[14px] font-semibold text-cream">{o.author}</div>
            {canTrackAuthor && <SaveButton kind="author" refId={authorRefId} variant="follow" size="xs" className="shrink-0" />}
          </div>
          <div className="flex items-center gap-1.5 text-[11px]" style={{ color: src.color }}>
            <PlatformIcon src={o.source} size={12} />
            <span>{src.label} · {o.day}</span>
          </div>
          {o.source === "youtube" && o.channel && (
            <div className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[10.5px] text-neutral-500">
              {typeof o.channel.subscribers === "number" && o.channel.subscribers >= 0 && (
                <span><b className="font-semibold text-neutral-300">{fmtCompact(o.channel.subscribers)}</b> {zh ? "粉丝" : "subs"}</span>
              )}
              {typeof o.channel.videos === "number" && o.channel.videos > 0 && (
                <span><b className="font-semibold text-neutral-300">{fmtCompact(o.channel.videos)}</b> {zh ? "视频" : "videos"}</span>
              )}
              {o.channel.handle && <span className="truncate text-neutral-600">{o.channel.handle}</span>}
            </div>
          )}
        </div>
        <span className="shrink-0 text-[12px] font-medium" style={{ color: st.color }}>{zh ? st.zh : st.en}</span>
        {o.source !== "x" && <span className="shrink-0 font-mono tabular text-[12px] text-neutral-500">{fmtCompact(o.interactions)}</span>}
        {svRank && <SvRankBadge meta={svRank} zh={zh} />}
        {typeof o.quality === "number" && (
          <span className="shrink-0 rounded bg-elevated px-1.5 py-0.5 font-mono tabular text-[11px] text-neutral-400" title={zh ? "帖子质量(含金量)" : "post quality"}>
            {zh ? "质 " : "Q "}{o.quality}
          </span>
        )}
        {typeof o.relevance === "number" && (
          <span className="shrink-0 rounded bg-elevated px-1.5 py-0.5 font-mono tabular text-[11px] text-neutral-400" title={zh ? "与本标的相关度" : "relevance to ticker"}>
            {zh ? "相关 " : "rel "}{o.relevance}
          </span>
        )}
      </div>
      {o.source === "youtube" && o.channel?.bio && (
        <p className="mt-2 line-clamp-2 whitespace-pre-line text-[11.5px] leading-snug text-neutral-500">{o.channel.bio}</p>
      )}
      {lensKeys.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1">
          {lensKeys.slice(0, 4).map((k) => (
            <span key={k} className="rounded bg-elevated px-1.5 py-px text-[10.5px] text-neutral-400">
              {zh ? LENS_LABEL[k]?.zh : LENS_LABEL[k]?.en}
            </span>
          ))}
        </div>
      )}
      {o.judgment && o.source !== "youtube" && <JudgmentLine j={o.judgment} zh={zh} />}
      {recReasons.length > 0 && (
        <div className="mt-3 rounded-lg bg-[#57D7BA]/10 px-3 py-2 ring-1 ring-inset ring-[#57D7BA]/30">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-[#57D7BA]">{zh ? "推荐理由" : "Why this ranks higher"}</div>
          <div className="mt-1.5 flex flex-wrap gap-1.5">
            {recReasons.map((r) => (
              <span key={r.zh} className="rounded bg-card/70 px-2 py-1 text-[11.5px] text-neutral-200 ring-1 ring-inset ring-line/80">
                {zh ? r.zh : r.en}
              </span>
            ))}
          </div>
        </div>
      )}
      {o.source === "youtube" && o.ytSegments && o.ytSegments.length ? (
        <YtReader segments={o.ytSegments} digest={o.ytDigest} judgment={o.judgment} zh={zh} noCollapse />
      ) : (
        displayText && (
          <p className="mt-3 whitespace-pre-line text-[14.5px] leading-relaxed text-neutral-100">
            {displayText}
          </p>
        )
      )}
      {o.source === "x" && o.metrics && <TweetStats m={o.metrics} />}
      <div className="mt-3 flex items-center gap-3 text-[11.5px]">
        {canTranslate && (
          <button onClick={() => setShowT(!showT)} className="text-neutral-500 transition hover:text-[#57D7BA]">
            {showOriginal ? (zh ? "看译文" : "Translation") : (zh ? "看原文" : "Original")}
          </button>
        )}
        {hasLink && (
          <a href={o.url} target="_blank" rel="noreferrer" className="text-neutral-500 transition hover:text-[#57D7BA]">
            {zh ? "查看原帖 ↗" : "View original ↗"}
          </a>
        )}
      </div>
      {o.source === "x" && o.replies && <TweetReplies replies={o.replies} zh={zh} />}
    </div>
  );
}
