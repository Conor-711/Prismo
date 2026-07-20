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
- `components/SmartVoiceTickerSignals.tsx`
- `components/SmartVoiceSignalChart.tsx`
- `components/SmartVoiceSignalDiagnostics.tsx`
- `components/SmartVoiceDecisionSuite.tsx`
- `components/SmartVoiceWeightedTargets.tsx`
- `components/SmartVoiceChangeRadar.tsx`
- `components/SmartVoiceOpportunityStrip.tsx`
- `components/SmartVoicePersonalAssistant.tsx`
- `components/SmartVoiceResearchSuite.tsx`
- `components/SmartVoiceThesisLifecycle.tsx`
- `components/SmartVoicePlatformDiffusion.tsx`
- `components/SmartVoiceAuthorAbilityMatrix.tsx`
- `components/SmartVoicePortfolioRisk.tsx`
- `components/SmartVoiceAlertCenter.tsx`
- `smartVoiceSignalLogic.ts`
- `smartVoiceDecisionLogic.ts`
- `smartVoiceResearchLogic.ts`
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

观点浏览器只接收服务端构造的有界展示池；原始全量帖子保留在 SQLite，不应直接作为 Client Component props 下发。

标的级 SV 信号由 `web/server/queries/smartVoiceTickerSignals.ts` 读取离线派生表。首批仅 `MU`、`NVDA`、`MSTR` 使用新版聚集、回测与决策实验室，其余标的保持旧 SV 投资者模块。前端只选择周期和 Top/Bottom 分位，不重算分数或回测；高低分歧、周期结构、加速/反转和目标/失效聚合在 `smartVoiceSignalLogic.ts` 中纯派生，SV 加权目标价、观点生命周期变化、拥挤/置信度和仓位匹配在 `smartVoiceDecisionLogic.ts` 中纯派生，投资逻辑生命周期、平台扩散、作者能力、组合视角暴露与提醒在 `smartVoiceResearchLogic.ts` 中纯派生。
