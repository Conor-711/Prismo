"use client";

import { useCallback, useMemo, useState } from "react";
import type { KolOpinion, KolSource, Stance } from "@/shared/market/mockDetail";
import type { SvTickerBoard } from "@/features/smart-account/svMock";
import type { CollectionKind } from "@/lib/favorites";
import {
  DEFAULT_SV_FILTER,
  DEFAULT_WIN_DAYS,
  PLATFORMS,
} from "@/features/ticker/opinionExplorerConstants";
import {
  getOpinionSvMeta,
  highQualityFallbackScore,
  isHighQuality,
  langOf,
  opinionAuthorRefId,
  shiftDay,
  svKeysForInvestor,
} from "@/features/ticker/opinionExplorerLogic";
import type { SvOpinionIndex, SvOpinionMeta, SvRangeFilter } from "@/features/ticker/opinionExplorerTypes";

export function useOpinionFilters({
  opinions,
  svBoard,
  isSaved,
  onFilterChange,
}: {
  opinions: KolOpinion[];
  svBoard?: SvTickerBoard | null;
  isSaved: (kind: CollectionKind, refId: string) => boolean;
  onFilterChange?: () => void;
}) {
  const [platformFilter, setPlatformFilter] = useState<Set<KolSource>>(new Set());
  const [langs, setLangs] = useState<Set<string>>(new Set());
  const [stanceFilter, setStanceFilter] = useState<Set<Stance>>(new Set());
  const [since, setSince] = useState("");
  const [hiQ, setHiQ] = useState(true);
  const [svFilter, setSvFilter] = useState<SvRangeFilter>(DEFAULT_SV_FILTER);
  const [query, setQuery] = useState("");
  const [trackedAuthorsOnly, setTrackedAuthorsOnly] = useState(false);

  const notify = useCallback(() => {
    onFilterChange?.();
  }, [onFilterChange]);

  const availability = useMemo(() => {
    const plat = new Set<KolSource>();
    const lang = new Set<string>();
    for (const o of opinions) {
      plat.add(o.source);
      lang.add(langOf(o));
    }
    return { plat, lang };
  }, [opinions]);

  const { minDay, maxDay } = useMemo(() => {
    let mn = "";
    let mx = "";
    for (const o of opinions) {
      if (!o.day) continue;
      if (!mn || o.day < mn) mn = o.day;
      if (o.day > mx) mx = o.day;
    }
    return { minDay: mn, maxDay: mx };
  }, [opinions]);

  const sinceEff = since || shiftDay(maxDay, -(DEFAULT_WIN_DAYS - 1));
  const dateInputMinDay = maxDay ? shiftDay(maxDay, -364) : minDay;

  const svIndex = useMemo<SvOpinionIndex>(() => {
    const byKey = new Map<string, SvOpinionMeta>();
    const investors = svBoard?.investors ?? [];
    const count = investors.length;
    investors.forEach((inv, i) => {
      const meta: SvOpinionMeta = {
        rank: i + 1,
        percentile: count ? ((i + 0.5) / count) * 100 : 100,
        score: inv.contextualSv,
        investor: inv,
      };
      for (const key of svKeysForInvestor(inv)) byKey.set(`${inv.source}:${key}`, meta);
    });
    return { byKey, count };
  }, [svBoard]);

  const svLowBound = Math.min(svFilter.low, svFilter.high);
  const svHighBound = Math.max(svFilter.low, svFilter.high);
  const svEnabled = Boolean(svFilter.enabled && svIndex.count);

  const preQualityFiltered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return opinions.filter((o) => {
      if (trackedAuthorsOnly && (o.source === "yahoojp" || !isSaved("author", opinionAuthorRefId(o)))) return false;
      if (langs.size && !langs.has(langOf(o))) return false;
      if (stanceFilter.size && !stanceFilter.has(o.stance)) return false;
      if (sinceEff && o.day < sinceEff) return false;
      if (svEnabled) {
        const meta = getOpinionSvMeta(o, svIndex.byKey);
        if (!meta || meta.percentile < svLowBound || meta.percentile > svHighBound) return false;
      }
      if (needle) {
        const haystack = [
          o.author,
          o.orig,
          o.text?.zh,
          o.text?.en,
          o.trans?.zh,
          o.trans?.en,
          o.quote?.zh,
          o.quote?.en,
          o.channel?.handle,
          o.channel?.bio,
        ].filter(Boolean).join(" ").toLowerCase();
        if (!haystack.includes(needle)) return false;
      }
      return true;
    });
  }, [opinions, trackedAuthorsOnly, isSaved, langs, stanceFilter, sinceEff, svEnabled, svIndex.byKey, svLowBound, svHighBound, query]);

  const highQualityIds = useMemo(() => {
    if (!hiQ) return null;
    const ids = new Set<string>();
    const keyOf = (opinion: KolOpinion) => `${opinion.source}:${opinion.id}`;
    const bySource = new Map<KolSource, KolOpinion[]>();
    for (const opinion of preQualityFiltered) {
      const list = bySource.get(opinion.source);
      if (list) list.push(opinion);
      else bySource.set(opinion.source, [opinion]);
    }

    for (const rows of bySource.values()) {
      const strict = rows.filter(isHighQuality);
      strict.forEach((opinion) => ids.add(keyOf(opinion)));

      const floor = Math.ceil(rows.length * 0.1);
      if (strict.length >= floor) continue;

      rows
        .filter((opinion) => !ids.has(keyOf(opinion)))
        .sort((a, b) => highQualityFallbackScore(b) - highQualityFallbackScore(a))
        .slice(0, floor - strict.length)
        .forEach((opinion) => ids.add(keyOf(opinion)));
    }
    return ids;
  }, [hiQ, preQualityFiltered]);

  const baseFiltered = useMemo(() => {
    if (!hiQ || !highQualityIds) return preQualityFiltered;
    return preQualityFiltered.filter((o) => highQualityIds.has(`${o.source}:${o.id}`));
  }, [hiQ, highQualityIds, preQualityFiltered]);

  const sourceCounts = useMemo(() => {
    const counts: Partial<Record<KolSource, number>> = {};
    for (const o of baseFiltered) counts[o.source] = (counts[o.source] ?? 0) + 1;
    return counts;
  }, [baseFiltered]);

  const availablePlatforms = useMemo(
    () => PLATFORMS.filter((p) => availability.plat.has(p)),
    [availability.plat]
  );

  const hasActiveFilters = Boolean(
    query.trim() ||
    platformFilter.size ||
    langs.size ||
    stanceFilter.size ||
    trackedAuthorsOnly ||
    since ||
    !hiQ ||
    svFilter.enabled
  );

  const setQueryFilter = useCallback((value: string) => {
    setQuery(value);
    notify();
  }, [notify]);

  const setPlatformFilterValue = useCallback((value: Set<KolSource>) => {
    setPlatformFilter(value);
    notify();
  }, [notify]);

  const clearPlatformFilter = useCallback(() => {
    setPlatformFilter(new Set());
    notify();
  }, [notify]);

  const selectPlatform = useCallback((source: KolSource) => {
    setPlatformFilter(new Set([source]));
    notify();
  }, [notify]);

  const setLangsFilter = useCallback((value: Set<string>) => {
    setLangs(value);
    notify();
  }, [notify]);

  const setStanceFilterValue = useCallback((value: Set<Stance>) => {
    setStanceFilter(value);
    notify();
  }, [notify]);

  const setSinceFilter = useCallback((value: string) => {
    setSince(value);
    notify();
  }, [notify]);

  const setHiQFilter = useCallback((value: boolean) => {
    setHiQ(value);
    notify();
  }, [notify]);

  const setSvRangeFilter = useCallback((value: SvRangeFilter) => {
    setSvFilter(value);
    notify();
  }, [notify]);

  const setTrackedAuthorsFilter = useCallback((value: boolean) => {
    setTrackedAuthorsOnly(value);
    notify();
  }, [notify]);

  const resetFilters = useCallback(() => {
    setQuery("");
    setPlatformFilter(new Set());
    setLangs(new Set());
    setStanceFilter(new Set());
    setTrackedAuthorsOnly(false);
    setSince("");
    setHiQ(true);
    setSvFilter(DEFAULT_SV_FILTER);
    notify();
  }, [notify]);

  const resetFiltersForOpinion = useCallback((day: string) => {
    setQuery("");
    setPlatformFilter(new Set());
    setLangs(new Set());
    setStanceFilter(new Set());
    setTrackedAuthorsOnly(false);
    setSince(day);
    setHiQ(true);
    setSvFilter(DEFAULT_SV_FILTER);
    notify();
  }, [notify]);

  return {
    platformFilter,
    setPlatformFilter: setPlatformFilterValue,
    clearPlatformFilter,
    selectPlatform,
    langs,
    setLangs: setLangsFilter,
    stanceFilter,
    setStanceFilter: setStanceFilterValue,
    since,
    setSince: setSinceFilter,
    sinceEff,
    minDay,
    maxDay,
    dateInputMinDay,
    hiQ,
    setHiQ: setHiQFilter,
    svFilter,
    setSvFilter: setSvRangeFilter,
    svIndex,
    svLowBound,
    svHighBound,
    query,
    setQuery: setQueryFilter,
    trackedAuthorsOnly,
    setTrackedAuthorsOnly: setTrackedAuthorsFilter,
    availability,
    baseFiltered,
    sourceCounts,
    availablePlatforms,
    hasActiveFilters,
    resetFilters,
    resetFiltersForOpinion,
  };
}
