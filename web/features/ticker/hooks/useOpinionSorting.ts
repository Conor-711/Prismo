"use client";

import { useMemo } from "react";
import type { KolOpinion, KolSource } from "@/shared/market/mockDetail";
import {
  getOpinionSvMeta,
  personalRecommendation,
  relOf,
} from "@/features/ticker/opinionExplorerLogic";
import type {
  PersonalPrefs,
  RecommendationMeta,
  SortMode,
  SvOpinionIndex,
} from "@/features/ticker/opinionExplorerTypes";

export function useOpinionSorting({
  opinions,
  baseFiltered,
  platformFilter,
  sort,
  personalConfigured,
  personal,
  currentPrice,
  svIndex,
}: {
  opinions: KolOpinion[];
  baseFiltered: KolOpinion[];
  platformFilter: Set<KolSource>;
  sort: SortMode;
  personalConfigured: boolean;
  personal: PersonalPrefs;
  currentPrice?: number | null;
  svIndex: SvOpinionIndex;
}) {
  const personalRank = useMemo(() => {
    const m = new Map<string, RecommendationMeta>();
    for (const o of opinions) m.set(o.id, personalRecommendation(o, personal, currentPrice));
    return m;
  }, [opinions, personal, currentPrice]);

  const filtered = useMemo(() => {
    const out = baseFiltered.filter((o) => !platformFilter.size || platformFilter.has(o.source));
    out.sort((a, b) => {
      if (sort === "personal" && personalConfigured) {
        const pa = personalRank.get(a.id)?.score ?? 0;
        const pb = personalRank.get(b.id)?.score ?? 0;
        return pb - pa || relOf(b) - relOf(a) || (b.interactions || 0) - (a.interactions || 0);
      }
      if (sort === "sv") {
        const sa = getOpinionSvMeta(a, svIndex.byKey)?.score ?? 0;
        const sb = getOpinionSvMeta(b, svIndex.byKey)?.score ?? 0;
        return sb - sa || relOf(b) - relOf(a) || (b.interactions || 0) - (a.interactions || 0);
      }
      if (sort === "time") return (a.day < b.day ? 1 : a.day > b.day ? -1 : 0) || relOf(b) - relOf(a);
      if (sort === "hot") return (b.interactions || 0) - (a.interactions || 0) || relOf(b) - relOf(a);
      return relOf(b) - relOf(a) || (b.interactions || 0) - (a.interactions || 0);
    });
    return out;
  }, [baseFiltered, platformFilter, sort, personalConfigured, personalRank, svIndex.byKey]);

  return { filtered, personalRank };
}
