# Ticker Feature

标的详情页是当前前端最复杂的业务域，后续新增能力优先在本目录实现。

目标拆分：

```text
ticker/
  components/
    TickerDetailShell.tsx
    OpinionExplorer/
    OverallData/
    TargetPrice/
  hooks/
    useOpinionFilters.ts
    useOpinionSorting.ts
    usePersonalization.ts
  queries/
    getTickerDetail.ts
    getTickerOpinions.ts
    getTickerOverallData.ts
  types.ts
  constants.ts
```

迁移原则：

- 页面路由只组装 shell，不写筛选和排序。
- 观点流消费 `docs/contracts/opinion.md` 的字段。
- SV 筛选消费 `docs/contracts/smart_voice.md` 的 percentile/rank，不在前端重算 SV。
- 目标价图表消费 `docs/contracts/judgment.md`。
- 旧 `web/components/prismo/OpinionExplorer.tsx` 仅保留兼容导出；新代码直接从 feature 路径引入。

当前已迁移：

- `index.ts`
- `opinionExplorerTypes.ts`
- `opinionExplorerConstants.ts`
- `opinionExplorerLogic.ts`
- `overallDataTypes.ts`
- `overallDataConstants.ts`
- `hooks/useOpinionFilters.ts`
- `hooks/useOpinionSorting.ts`
- `hooks/useOpinionPersonalization.ts`
- `hooks/useSelectedOpinion.ts`
- `components/KolModule.tsx`
- `components/OverlayPanel.tsx`
- `components/OverallStructureCharts.tsx`
- `components/TargetPricePanel.tsx`
- `components/TickerDetailHeader.tsx`
- `components/TickerOverviewPanel.tsx`
- `components/TickerSignalBoards.tsx`
- `components/TickerTable.tsx`
- `components/OpinionExplorer/OpinionExplorer.tsx`
- `components/OpinionExplorer/controls.tsx`
- `components/OpinionExplorer/filterBar.tsx`
- `components/OpinionExplorer/listPane.tsx`
- `components/OpinionExplorer/listCard.tsx`
- `components/OpinionExplorer/reader.tsx`
- `components/OpinionExplorer/YtReader.tsx`
- `components/OpinionExplorer/YtFullContent.tsx`
