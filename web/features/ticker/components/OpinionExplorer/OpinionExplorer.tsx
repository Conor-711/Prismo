"use client";

// 标的页「个体观点 · KOL」的观点浏览器（替代原 按KOL/按视角/按热度 三 tab）：
//   顶部 = 筛选条（平台[品牌 logo] / 时间[指定起始日期 + 5 个区间模板] / 语言[简中·英·日·韩·繁中] / 质量）
//   下方 = 主从布局：左窄列 = 帖文卡列表（头像+handle+开头），右宽栏 = 选中帖的完整正文（含原文/译文切换 + 回原帖）
// 全部筛选在前端做；默认按「相关性」降序排（最相关的在前）。数据来自 lib/kolQueries.getKolOpinions。
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useFavorites } from "@/components/favorites/FavoritesProvider";
import { staticDataUrl } from "@/lib/site";
import type { KolOpinion } from "@/shared/market/mockDetail";
import type { SvTickerBoard } from "@/features/smart-account/svMock";
import { OpinionFilterBar } from "@/features/ticker/components/OpinionExplorer/filterBar";
import { OpinionListPane } from "@/features/ticker/components/OpinionExplorer/listPane";
import { Reader } from "@/features/ticker/components/OpinionExplorer/reader";
import { useOpinionFilters } from "@/features/ticker/hooks/useOpinionFilters";
import { useOpinionPersonalization } from "@/features/ticker/hooks/useOpinionPersonalization";
import { useSelectedOpinion } from "@/features/ticker/hooks/useSelectedOpinion";
import { useOpinionSorting } from "@/features/ticker/hooks/useOpinionSorting";
import { getOpinionSvMeta } from "@/features/ticker/opinionExplorerLogic";
import type {
  SortMode,
} from "@/features/ticker/opinionExplorerTypes";

export function OpinionExplorer({
  symbol,
  opinions,
  zh,
  fill = false,
  currentPrice,
  overview,
  svBoard,
}: {
  symbol?: string;
  opinions: KolOpinion[];
  zh: boolean;
  fill?: boolean;
  currentPrice?: number | null;
  overview?: React.ReactNode;
  svBoard?: SvTickerBoard | null;
}) {
  const [sort, setSort] = useState<SortMode>("rel"); // 排序：推荐 / 相关度 / 热度 / 最新
  const [completeOpinions, setCompleteOpinions] = useState<{
    symbol: string;
    opinions: KolOpinion[];
  } | null>(null);
  const [completeXOpinions, setCompleteXOpinions] = useState<KolOpinion[] | null>(null);
  const completeXRequested = useRef<string | null>(null);
  const [opinionContent, setOpinionContent] = useState<{
    symbol: string;
    loaded: boolean;
    byId: Record<string, Pick<KolOpinion, "orig" | "trans" | "quote">>;
  }>({ symbol: "", loaded: false, byId: {} });
  const [youtubeContent, setYoutubeContent] = useState<{
    symbol: string;
    loaded: boolean;
    byId: Record<string, Pick<KolOpinion, "orig" | "ytSegments">>;
  }>({ symbol: "", loaded: false, byId: {} });
  useEffect(() => {
    if (!symbol) return;
    const controller = new AbortController();
    fetch(staticDataUrl(`/data/ticker-opinions/${encodeURIComponent(symbol.toUpperCase())}`), {
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Ticker opinion export returned ${response.status}`);
        return response.json();
      })
      .then((payload: { opinions?: KolOpinion[] }) => {
        if (Array.isArray(payload.opinions)) {
          setCompleteOpinions({ symbol, opinions: payload.opinions });
        }
      })
      .catch((error: unknown) => {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          console.error("Failed to load ticker opinion pool", error);
        }
      });
    return () => controller.abort();
  }, [symbol]);
  const loadCompleteXOpinions = useCallback(() => {
    if (!symbol) return;
    const normalizedSymbol = symbol.toUpperCase();
    if (completeXRequested.current === normalizedSymbol) return;
    completeXRequested.current = normalizedSymbol;
    const controller = new AbortController();
    fetch(staticDataUrl(`/data/x-opinions/${encodeURIComponent(normalizedSymbol)}`), {
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`X opinion export returned ${response.status}`);
        return response.json();
      })
      .then((payload: { opinions?: KolOpinion[] }) => {
        if (Array.isArray(payload.opinions)) setCompleteXOpinions(payload.opinions);
      })
      .catch((error: unknown) => {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          console.error("Failed to load complete X opinion pool", error);
          completeXRequested.current = null;
        }
      });
  }, [symbol]);
  const mergedOpinions = useMemo(() => {
    const baseOpinions = completeOpinions && completeOpinions.symbol === symbol
      ? completeOpinions.opinions
      : opinions;
    const byId = new Map(baseOpinions.map((opinion) => [opinion.id, opinion]));
    if (completeXOpinions) {
      for (const opinion of completeXOpinions) byId.set(opinion.id, opinion);
    }
    if (youtubeContent.symbol === symbol) {
      for (const [id, content] of Object.entries(youtubeContent.byId)) {
        const opinion = byId.get(id);
        if (opinion) byId.set(id, { ...opinion, ...content });
      }
    }
    if (opinionContent.symbol === symbol) {
      for (const [id, content] of Object.entries(opinionContent.byId)) {
        const opinion = byId.get(id);
        if (opinion) byId.set(id, { ...opinion, ...content });
      }
    }
    return [...byId.values()];
  }, [completeOpinions, opinions, completeXOpinions, opinionContent, symbol, youtubeContent]);

  const { configured: trackingConfigured, isSaved } = useFavorites();
  const filters = useOpinionFilters({ opinions: mergedOpinions, svBoard, isSaved });
  const { resetFilters: resetOpinionFilters, resetFiltersForOpinion } = filters;
  const {
    personal,
    personalDraft,
    setPersonalDraft,
    personalConfigured,
    defaultSort,
    applyPersonal,
    clearPersonal,
  } = useOpinionPersonalization({ symbol, sort, setSort });

  const { filtered, personalRank } = useOpinionSorting({
    opinions: mergedOpinions,
    baseFiltered: filters.baseFiltered,
    platformFilter: filters.platformFilter,
    sort,
    personalConfigured,
    personal,
    currentPrice,
    svIndex: filters.svIndex,
  });
  const selection = useSelectedOpinion({
    opinions: mergedOpinions,
    filtered,
    hasOverview: Boolean(overview),
    defaultSort,
    setSort,
    resetFiltersForOpinion,
  });
  useEffect(() => {
    const selected = selection.selected;
    if (!symbol || selected?.source !== "youtube" || selected.ytSegments?.length) return;
    if (youtubeContent.symbol === symbol && youtubeContent.loaded) return;
    const controller = new AbortController();
    fetch(staticDataUrl(`/data/youtube-content/${encodeURIComponent(symbol.toUpperCase())}`), {
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`YouTube content export returned ${response.status}`);
        return response.json();
      })
      .then((payload: { content?: Record<string, Pick<KolOpinion, "orig" | "ytSegments">> }) => {
        setYoutubeContent({
          symbol,
          loaded: true,
          byId: payload.content && typeof payload.content === "object" ? payload.content : {},
        });
      })
      .catch((error: unknown) => {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          console.error("Failed to load YouTube full content", error);
          setYoutubeContent({ symbol, loaded: true, byId: {} });
        }
      });
    return () => controller.abort();
  }, [selection.selected, symbol, youtubeContent.loaded, youtubeContent.symbol]);
  useEffect(() => {
    const selected = selection.selected;
    if (!symbol || !selected || selected.source === "youtube") return;
    if (selected.orig || selected.trans || selected.quote) return;
    if (opinionContent.symbol === symbol && opinionContent.loaded) return;
    const controller = new AbortController();
    fetch(staticDataUrl(`/data/opinion-content/${encodeURIComponent(symbol.toUpperCase())}`), {
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Opinion content export returned ${response.status}`);
        return response.json();
      })
      .then((payload: { content?: Record<string, Pick<KolOpinion, "orig" | "trans" | "quote">> }) => {
        setOpinionContent({
          symbol,
          loaded: true,
          byId: payload.content && typeof payload.content === "object" ? payload.content : {},
        });
      })
      .catch((error: unknown) => {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          console.error("Failed to load opinion content", error);
          setOpinionContent({ symbol, loaded: true, byId: {} });
        }
      });
    return () => controller.abort();
  }, [opinionContent.loaded, opinionContent.symbol, selection.selected, symbol]);
  const hasFilter = filters.hasActiveFilters || sort !== defaultSort;
  const resetFilters = () => {
    resetOpinionFilters();
    setSort(defaultSort);
    selection.clearSelection();
  };
  const selectedSvMeta = selection.selected ? getOpinionSvMeta(selection.selected, filters.svIndex.byKey) : null;

  return (
    <div className={fill ? "flex h-full min-h-0 flex-col" : ""}>
      <OpinionFilterBar
        zh={zh}
        fill={fill}
        query={filters.query}
        onQueryChange={(value) => { filters.setQuery(value); selection.clearSelection(); }}
        stanceFilter={filters.stanceFilter}
        onStanceFilterChange={(value) => { filters.setStanceFilter(value); selection.clearSelection(); }}
        svFilter={filters.svFilter}
        onSvFilterChange={(value) => { filters.setSvFilter(value); selection.clearSelection(); }}
        svIndexCount={filters.svIndex.count}
        svLowBound={filters.svLowBound}
        svHighBound={filters.svHighBound}
        personalConfigured={personalConfigured}
        personalActive={sort === "personal" && personalConfigured}
        personalDraft={personalDraft}
        setPersonalDraft={setPersonalDraft}
        onPersonalSave={() => { applyPersonal(); selection.clearSelection(); }}
        onPersonalClear={() => { clearPersonal(); selection.clearSelection(); }}
        currentPrice={currentPrice}
        trackedAuthorsOnly={filters.trackedAuthorsOnly}
        onTrackedAuthorsOnlyChange={(value) => { filters.setTrackedAuthorsOnly(value); selection.clearSelection(); }}
        trackingConfigured={trackingConfigured}
        maxDay={filters.maxDay}
        sinceEff={filters.sinceEff}
        dateInputMinDay={filters.dateInputMinDay}
        onSinceChange={(value) => { filters.setSince(value); selection.clearSelection(); }}
        langs={filters.langs}
        availableLangs={filters.availability.lang}
        onLangsChange={(value) => { filters.setLangs(value); selection.clearSelection(); }}
        hiQ={filters.hiQ}
        onHiQChange={(value) => { filters.setHiQ(value); selection.clearSelection(); }}
        hasFilter={hasFilter}
        onReset={resetFilters}
      />

      {/* 主从：左列表 / 右侧 overview 或正文。 */}
      <div className={`mt-3 flex flex-col gap-3 lg:flex-row ${fill ? "min-h-0 flex-1 overflow-hidden lg:items-stretch" : "lg:items-start"}`}>
        <OpinionListPane
          zh={zh}
          fill={fill}
          platformFilter={filters.platformFilter}
          availablePlatforms={filters.availablePlatforms}
          sourceCounts={filters.sourceCounts}
          baseCount={filters.baseFiltered.length}
          opinions={filtered}
          selectedId={selection.selected?.id ?? null}
          sort={sort}
          personalConfigured={personalConfigured}
          svSortAvailable={filters.svIndex.count > 0}
          personalRank={personalRank}
          onClearPlatform={() => { filters.clearPlatformFilter(); selection.clearSelection(); }}
          onSelectPlatform={(source) => {
            if (source === "x") loadCompleteXOpinions();
            filters.selectPlatform(source);
            selection.clearSelection();
          }}
          onSortChange={setSort}
          onSelectOpinion={selection.selectOpinion}
        />
        <div className={`min-w-0 ${fill ? "min-h-0 overflow-hidden lg:flex-1" : "lg:flex-1"}`}>
          {selection.selected ? (
            <Reader
              o={selection.selected}
              zh={zh}
              showT={selection.showTranslation}
              setShowT={selection.setShowTranslation}
              fill={fill}
              recReasons={sort === "personal" && personalConfigured ? personalRank.get(selection.selected.id)?.reasons ?? [] : []}
              svRank={selectedSvMeta ? {
                rank: selectedSvMeta.rank,
                count: filters.svIndex.count,
                percentile: selectedSvMeta.percentile,
                score: selectedSvMeta.score,
              } : undefined}
              onBack={overview ? selection.clearSelection : undefined}
            />
          ) : overview ? (
            overview
          ) : null}
        </div>
      </div>
    </div>
  );
}
