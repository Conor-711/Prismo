"use client";

import { LocaleLink } from "@/components/i18n/LocaleLink";
import { SaveButton } from "@/components/favorites/SaveButton";
import { TickerLogo } from "@/shared/market/TickerLogo";
import { Avatar } from "@/shared/market/kolPresentation";
import type { QuickCandidate } from "../trackingTypes";

export function QuickAdd({
  zh,
  query,
  setQuery,
  candidates,
  onSeeAll,
}: {
  zh: boolean;
  query: string;
  setQuery: (value: string) => void;
  candidates: QuickCandidate[];
  onSeeAll: () => void;
}) {
  return (
    <div className="relative z-20 shrink-0">
      <div className="flex items-center gap-2">
        <div className="relative min-w-0 flex-1">
          <svg viewBox="0 0 24 24" className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-neutral-600" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <circle cx="11" cy="11" r="7" />
            <path d="M20 20l-3.5-3.5" />
          </svg>
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={zh ? "搜索并追踪标的、作者或叙事…" : "Search and follow tickers, authors or narratives…"}
            className="h-9 w-full rounded-md bg-card/70 pl-9 pr-3 text-[12.5px] text-cream ring-1 ring-inset ring-line placeholder:text-neutral-600 outline-none transition focus:ring-reddit/70"
          />
        </div>
        <button
          type="button"
          onClick={onSeeAll}
          className="h-9 shrink-0 rounded-md px-3 text-[11.5px] font-semibold text-neutral-400 ring-1 ring-inset ring-line transition hover:bg-white/[.04] hover:text-cream"
        >
          {zh ? "浏览全部" : "Browse all"}
        </button>
      </div>
      {query.trim() && (
        <div className="absolute left-0 right-0 top-[calc(100%+6px)] grid max-h-[360px] gap-1.5 overflow-y-auto rounded-md border border-line bg-[#17191d] p-2 shadow-2xl md:grid-cols-2 xl:grid-cols-3">
          {candidates.length > 0 ? candidates.map((candidate) => (
            <QuickCandidateCard key={`${candidate.kind}:${candidate.refId}`} candidate={candidate} />
          )) : (
            <div className="col-span-full px-3 py-6 text-center text-xs text-neutral-600">
              {zh ? "没有匹配的可追踪对象" : "No matching trackable items"}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function QuickCandidateCard({ candidate }: { candidate: QuickCandidate }) {
  const content = (
    <>
      <CandidateVisual candidate={candidate} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[12.5px] font-semibold text-cream">{candidate.label}</span>
        <span className="mt-0.5 block truncate text-[10.5px] text-neutral-600">{candidate.sub}</span>
      </span>
    </>
  );
  return (
    <div className="flex min-w-0 items-center gap-2 rounded-md bg-white/[.025] px-2.5 py-2 ring-1 ring-inset ring-line hover:bg-white/[.045]">
      {candidate.href ? (
        <LocaleLink href={candidate.href} className="flex min-w-0 flex-1 items-center gap-2 transition hover:opacity-85">
          {content}
        </LocaleLink>
      ) : candidate.url ? (
        <a href={candidate.url} target="_blank" rel="noreferrer noopener" className="flex min-w-0 flex-1 items-center gap-2 transition hover:opacity-85">
          {content}
        </a>
      ) : (
        <div className="flex min-w-0 flex-1 items-center gap-2">{content}</div>
      )}
      <SaveButton kind={candidate.kind} refId={candidate.refId} variant="follow" size="xs" className="shrink-0" />
    </div>
  );
}

function CandidateVisual({ candidate }: { candidate: QuickCandidate }) {
  if (candidate.ticker) return <TickerLogo ticker={candidate.ticker} size={24} />;
  if (candidate.avatar || candidate.kind === "author") {
    return <Avatar src={candidate.avatar} color={candidate.color ?? "#57D7BA"} name={candidate.label} size={24} />;
  }
  return <span className="h-3 w-3 shrink-0 rounded-sm" style={{ background: candidate.color ?? "#57D7BA" }} />;
}
