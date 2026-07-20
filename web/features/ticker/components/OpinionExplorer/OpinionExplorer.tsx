"use client";

// 标的页「个体观点 · KOL」的观点浏览器（替代原 按KOL/按视角/按热度 三 tab）：
//   顶部 = 筛选条（平台[品牌 logo] / 时间[指定起始日期 + 5 个区间模板] / 语言[简中·英·日·韩·繁中] / 质量）
//   下方 = 主从布局：左窄列 = 帖文卡列表（头像+handle+开头），右宽栏 = 选中帖的完整正文（含原文/译文切换 + 回原帖）
// 全部筛选在前端做；默认按「相关性」降序排（最相关的在前）。数据来自 lib/kolQueries.getKolOpinions。
import { useState } from "react";
import { useFavorites } from "@/components/favorites/FavoritesProvider";
import type { KolOpinion } from "@/shared/market/mockDetail";
import type { SvTickerBoard } from "@/features/smart-voice/svMock";
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
  const { configured: trackingConfigured, signedIn: trackingSignedIn, isSaved } = useFavorites();
  const filters = useOpinionFilters({ opinions, svBoard, isSaved });
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
    opinions,
    baseFiltered: filters.baseFiltered,
    platformFilter: filters.platformFilter,
    sort,
    personalConfigured,
    personal,
    currentPrice,
    svIndex: filters.svIndex,
  });
  const selection = useSelectedOpinion({
    opinions,
    filtered,
    hasOverview: Boolean(overview),
    defaultSort,
    setSort,
    resetFiltersForOpinion,
  });
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
        trackingSignedIn={trackingSignedIn}
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
          onSelectPlatform={(source) => { filters.selectPlatform(source); selection.clearSelection(); }}
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
