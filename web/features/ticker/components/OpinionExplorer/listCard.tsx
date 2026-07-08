"use client";

import type { KolOpinion } from "@/shared/market/mockDetail";
import type { RecommendationReason } from "@/features/ticker/opinionExplorerTypes";
import { Avatar, SOURCE, STANCE, mmdd, pickOriginal } from "@/shared/market/kolPresentation";
import { PlatformIcon } from "./controls";

export function ListCard({
  o,
  zh,
  active,
  recReason,
  onClick,
}: {
  o: KolOpinion;
  zh: boolean;
  active: boolean;
  recReason?: RecommendationReason;
  onClick: () => void;
}) {
  const src = SOURCE[o.source];
  const st = STANCE[o.stance];
  const { base, trans, canTranslate } = pickOriginal(o, zh);
  const preview = canTranslate ? trans : base;
  const excerpt = preview.replace(/\s+/g, " ").trim().slice(0, 84);
  return (
    <li>
      <div
        className={`relative flex w-full overflow-hidden border-b border-line/70 transition ${
          active ? "bg-elevated/80" : "bg-transparent hover:bg-white/[.025]"
        }`}
      >
        <span className="absolute left-0 top-0 h-full w-[3px]" style={{ background: st.color }} aria-hidden />
        {active && <span className="absolute right-0 top-0 h-full w-[3px] bg-reddit" aria-hidden />}
        <button
          onClick={onClick}
          title={zh ? st.zh : st.en}
          className="flex min-w-0 flex-1 gap-2.5 py-3 pl-4 pr-3 text-left"
        >
          <Avatar src={o.avatar} color={src.color} name={o.author} size={26} />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5">
              <span className="min-w-0 truncate text-[12.5px] font-medium text-cream">{o.author}</span>
              <span className="ml-auto flex shrink-0 items-center gap-1.5">
                <PlatformIcon src={o.source} size={12} />
                <span className="font-mono tabular text-[10.5px] text-neutral-600">{mmdd(o.day)}</span>
              </span>
            </div>
            <p className="mt-1 line-clamp-2 text-[12px] leading-snug text-neutral-400">{excerpt}</p>
            {recReason && (
              <div className="mt-1.5 inline-flex max-w-full items-center gap-1 rounded bg-[#57D7BA]/10 px-1.5 py-0.5 text-[10.5px] font-medium text-[#57D7BA] ring-1 ring-inset ring-[#57D7BA]/25">
                <span className="h-1 w-1 shrink-0 rounded-full bg-[#57D7BA]" />
                <span className="truncate">{zh ? recReason.zh : recReason.en}</span>
              </div>
            )}
          </div>
        </button>
      </div>
    </li>
  );
}
