"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { KolOpinion } from "@/shared/market/mockDetail";
import type { SortMode } from "@/features/ticker/opinionExplorerTypes";

export function useSelectedOpinion({
  opinions,
  filtered,
  hasOverview,
  defaultSort,
  setSort,
  resetFiltersForOpinion,
}: {
  opinions: KolOpinion[];
  filtered: KolOpinion[];
  hasOverview: boolean;
  defaultSort: SortMode;
  setSort: (sort: SortMode) => void;
  resetFiltersForOpinion: (day: string) => void;
}) {
  const [showTranslation, setShowTranslation] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const selected = useMemo(
    () => selectedId ? filtered.find((o) => o.id === selectedId) ?? null : hasOverview ? null : filtered[0] ?? null,
    [filtered, hasOverview, selectedId]
  );

  const selectOpinion = useCallback((id: string) => {
    setSelectedId(id);
    setShowTranslation(false);
  }, []);

  const clearSelection = useCallback(() => {
    setSelectedId(null);
    setShowTranslation(false);
  }, []);

  useEffect(() => {
    const openOpinion = (event: Event) => {
      const detail = (event as CustomEvent<{ opinionId?: string; day?: string }>).detail;
      if (!detail?.opinionId) return;
      const target = opinions.find((o) => o.id === detail.opinionId);
      if (!target) return;
      resetFiltersForOpinion(detail.day || target.day || "");
      setSort(defaultSort);
      setSelectedId(target.id);
      setShowTranslation(false);
    };
    window.addEventListener("bsmart:open-opinion", openOpinion);
    return () => window.removeEventListener("bsmart:open-opinion", openOpinion);
  }, [defaultSort, opinions, resetFiltersForOpinion, setSort]);

  return {
    selected,
    selectedId,
    showTranslation,
    setShowTranslation,
    selectOpinion,
    clearSelection,
  };
}
