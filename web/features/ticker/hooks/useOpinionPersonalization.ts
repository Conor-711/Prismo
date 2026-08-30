"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  EMPTY_PERSONAL_PREFS,
} from "@/features/ticker/opinionExplorerConstants";
import {
  isPersonalConfigured,
} from "@/features/ticker/opinionExplorerLogic";
import type {
  PersonalPrefs,
  SortMode,
} from "@/features/ticker/opinionExplorerTypes";

export function useOpinionPersonalization({
  symbol,
  sort,
  setSort,
  onPersonalChange,
}: {
  symbol?: string;
  sort: SortMode;
  setSort: (sort: SortMode) => void;
  onPersonalChange?: () => void;
}) {
  const [personal, setPersonal] = useState<PersonalPrefs>(EMPTY_PERSONAL_PREFS);
  const [personalDraft, setPersonalDraft] = useState<PersonalPrefs>(EMPTY_PERSONAL_PREFS);
  const personalKey = useMemo(() => `bsmart:opinion-personal:${symbol || "global"}`, [symbol]);
  const personalConfigured = isPersonalConfigured(personal);
  const defaultSort: SortMode = personalConfigured ? "personal" : "rel";

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(personalKey);
      const parsed = raw ? ({ ...EMPTY_PERSONAL_PREFS, ...JSON.parse(raw) } as PersonalPrefs) : EMPTY_PERSONAL_PREFS;
      setPersonal(parsed);
      setPersonalDraft(parsed);
      setSort(isPersonalConfigured(parsed) ? "personal" : "rel");
    } catch {
      setPersonal(EMPTY_PERSONAL_PREFS);
      setPersonalDraft(EMPTY_PERSONAL_PREFS);
      setSort("rel");
    }
  }, [personalKey, setSort]);

  useEffect(() => {
    const sync = (event: Event) => {
      const detail = (event as CustomEvent<{ symbol?: string; prefs?: PersonalPrefs }>).detail;
      if (!detail?.prefs || (detail.symbol || "global") !== (symbol || "global")) return;
      const next = { ...EMPTY_PERSONAL_PREFS, ...detail.prefs };
      setPersonal(next);
      setPersonalDraft(next);
      setSort(isPersonalConfigured(next) ? "personal" : "rel");
    };
    window.addEventListener("bsmart:opinion-personal-update", sync);
    return () => window.removeEventListener("bsmart:opinion-personal-update", sync);
  }, [setSort, symbol]);

  const applyPersonal = useCallback(() => {
    const next = { ...EMPTY_PERSONAL_PREFS, ...personalDraft };
    setPersonal(next);
    setPersonalDraft(next);
    try {
      if (isPersonalConfigured(next)) window.localStorage.setItem(personalKey, JSON.stringify(next));
      else window.localStorage.removeItem(personalKey);
    } catch {
      /* localStorage 不可用时仅当前会话生效 */
    }
    setSort(isPersonalConfigured(next) ? "personal" : "rel");
    onPersonalChange?.();
  }, [onPersonalChange, personalDraft, personalKey, setSort]);

  const clearPersonal = useCallback(() => {
    setPersonal(EMPTY_PERSONAL_PREFS);
    setPersonalDraft(EMPTY_PERSONAL_PREFS);
    try { window.localStorage.removeItem(personalKey); } catch { /* ignore */ }
    if (sort === "personal") setSort("rel");
    onPersonalChange?.();
  }, [onPersonalChange, personalKey, setSort, sort]);

  return {
    personal,
    personalDraft,
    setPersonalDraft,
    personalConfigured,
    defaultSort,
    applyPersonal,
    clearPersonal,
  };
}
