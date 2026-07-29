"use client";

import { useEffect, useMemo, useState } from "react";
import type { KolOpinion, KolSource } from "@/shared/market/mockDetail";
import { SOURCE } from "@/shared/market/kolPresentation";
import type { RecommendationMeta, SortMode } from "@/features/ticker/opinionExplorerTypes";
import { Chip } from "./controls";
import { ListCard } from "./listCard";

const INITIAL_VISIBLE = 60;
const VISIBLE_STEP = 60;

export function OpinionListPane({
  zh,
  fill,
  platformFilter,
  availablePlatforms,
  sourceCounts,
  baseCount,
  opinions,
  selectedId,
  sort,
  personalConfigured,
  svSortAvailable,
  personalRank,
  onClearPlatform,
  onSelectPlatform,
  onSortChange,
  onSelectOpinion,
}: {
  zh: boolean;
  fill: boolean;
  platformFilter: Set<KolSource>;
  availablePlatforms: KolSource[];
  sourceCounts: Partial<Record<KolSource, number>>;
  baseCount: number;
  opinions: KolOpinion[];
  selectedId: string | null;
  sort: SortMode;
  personalConfigured: boolean;
  svSortAvailable: boolean;
  personalRank: Map<string, RecommendationMeta>;
  onClearPlatform: () => void;
  onSelectPlatform: (source: KolSource) => void;
  onSortChange: (sort: SortMode) => void;
  onSelectOpinion: (id: string) => void;
}) {
  const [visibleCount, setVisibleCount] = useState(INITIAL_VISIBLE);
  useEffect(() => {
    setVisibleCount(INITIAL_VISIBLE);
  }, [opinions, platformFilter, sort]);
  useEffect(() => {
    if (!selectedId) return;
    const selectedIndex = opinions.findIndex((opinion) => opinion.id === selectedId);
    if (selectedIndex >= visibleCount) {
      setVisibleCount(Math.ceil((selectedIndex + 1) / VISIBLE_STEP) * VISIBLE_STEP);
    }
  }, [opinions, selectedId, visibleCount]);
  const visibleOpinions = useMemo(
    () => opinions.slice(0, visibleCount),
    [opinions, visibleCount]
  );

  return (
    <div className={fill ? "flex min-h-0 flex-col overflow-hidden rounded-xl bg-card/45 ring-1 ring-inset ring-line lg:w-[392px] lg:shrink-0" : "lg:w-[320px] lg:shrink-0"}>
      <div className="shrink-0 border-b border-line">
        <div className="flex items-center gap-2 overflow-x-auto px-3 pb-px pt-3">
          <button
            type="button"
            onClick={onClearPlatform}
            className={`min-w-[80px] shrink-0 border-b-2 px-2 pb-2 text-center text-[12px] font-bold transition ${platformFilter.size === 0 ? "border-reddit text-reddit" : "border-transparent text-neutral-500 hover:text-neutral-300"}`}
          >
            {zh ? "全部" : "All"} <span className="font-mono text-[10.5px] text-neutral-600">{baseCount}</span>
          </button>
          {availablePlatforms.map((p) => {
            const on = platformFilter.size === 1 && platformFilter.has(p);
            return (
              <button
                key={p}
                type="button"
                onClick={() => onSelectPlatform(p)}
                className={`min-w-[96px] shrink-0 border-b-2 px-2 pb-2 text-center text-[12px] font-bold transition ${on ? "border-reddit text-reddit" : "border-transparent text-neutral-500 hover:text-neutral-300"}`}
              >
                {SOURCE[p].label} <span className="font-mono text-[10.5px] text-neutral-600">{sourceCounts[p] ?? 0}</span>
              </button>
            );
          })}
        </div>
        <div className="flex items-center justify-between gap-2 px-3 py-2">
          <span className="text-[11px] text-neutral-500">{opinions.length} {zh ? "条结果" : "results"}</span>
          <div className="flex items-center gap-1">
            <span className="text-[11px] text-neutral-600">{zh ? "排序" : "Sort"}</span>
            {personalConfigured && <Chip active={sort === "personal"} onClick={() => onSortChange("personal")}>{zh ? "推荐" : "For You"}</Chip>}
            {svSortAvailable && <Chip active={sort === "sv"} onClick={() => onSortChange("sv")}>SV</Chip>}
            <Chip active={sort === "rel"} onClick={() => onSortChange("rel")}>{zh ? "相关度" : "Rel"}</Chip>
            <Chip active={sort === "hot"} onClick={() => onSortChange("hot")}>{zh ? "热度" : "Top"}</Chip>
            <Chip active={sort === "time"} onClick={() => onSortChange("time")}>{zh ? "最新" : "New"}</Chip>
          </div>
        </div>
      </div>
      {opinions.length === 0 ? (
        <p className="py-8 text-center text-sm text-neutral-600">{zh ? "没有符合筛选的观点" : "No posts match the filters"}</p>
      ) : (
        <ul
          className={fill ? "min-h-0 flex-1 overflow-y-auto" : "lg:max-h-[640px] lg:overflow-y-auto"}
          onScroll={(event) => {
            const list = event.currentTarget;
            if (list.scrollHeight - list.scrollTop - list.clientHeight < 240) {
              setVisibleCount((count) => Math.min(opinions.length, count + VISIBLE_STEP));
            }
          }}
        >
          {visibleOpinions.map((o) => (
            <ListCard
              key={o.id}
              o={o}
              zh={zh}
              active={selectedId === o.id}
              recReason={sort === "personal" && personalConfigured ? personalRank.get(o.id)?.reasons[0] : undefined}
              onClick={() => onSelectOpinion(o.id)}
            />
          ))}
        </ul>
      )}
    </div>
  );
}
