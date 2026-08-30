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
- Score 筛选消费 `docs/contracts/smart_account.md` 的 percentile/rank，不在前端重算 Score。
- 目标价图表消费 `docs/contracts/judgment.md`。
- 旧 `web/components/bsmart/OpinionExplorer.tsx` 仅保留兼容导出；新代码直接从 feature 路径引入。

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
- `components/TargetDistributionChart.tsx`
- `targetPriceModel.ts`
- `components/TickerDetailHeader.tsx`
- `components/TickerOverviewPanel.tsx`
- `components/SmartVoiceTickerSignals.tsx`
- `components/SmartVoiceShiftChart.tsx`
- `components/SmartVoiceSignalChart.tsx`
- `components/SmartVoiceSignalDiagnostics.tsx`
- `components/SmartVoiceDecisionSuite.tsx`
- `components/SmartVoiceWeightedTargets.tsx`
- `components/SmartVoiceChangeRadar.tsx`
- `components/SmartVoiceOpportunityStrip.tsx`
- `components/SmartVoicePersonalAssistant.tsx`
- `components/SmartVoiceResearchSuite.tsx`
- `components/SmartVoiceThesisLifecycle.tsx`
- `components/SmartVoiceAuthorAbilityMatrix.tsx`
- `components/SmartVoicePortfolioRisk.tsx`
- `components/SmartVoiceAlertCenter.tsx`
- `smartVoiceSignalLogic.ts`
- `smartVoiceDecisionLogic.ts`
- `smartVoiceResearchLogic.ts`
- `smartVoiceOverviewLogic.ts`
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

标的级 Score 信号由 `web/server/queries/smartVoiceTickerSignals.ts` 读取离线派生表。首批仅 `MU`、`NVDA`、`MSTR` 使用新版变化看板，其余标的保持旧 Score 投资者模块。`TickerOverviewPanel` 在同一容器 banner 中提供“市场数据 / Score”切换，两个看板原位互斥渲染，不得再次把 Score 模块堆到市场数据底部。

Score 默认看板只保留四项顶层指标：7 日 Score 转向、变化广度、Score 目标修正和价格-Score 背离。内部精确值必须同时提供状态解释、起止值、作者或目标样本和可用历史位置；不把跨平台确认度、观点拥挤度、周期迁移或信号可信度作为独立顶层指标。四项指标在 `smartVoiceOverviewLogic.ts` 中基于已落库的历史时点 Score、真实 Call 和价格纯派生，组件不得重算作者 Score。历史表现沿用离线事件与结果表，不能将样本内收益描述为未来预期。

目标价模块按职责拆分：`TargetPricePanel` 只编排筛选、时间线和正文定位，
`TargetDistributionChart` 独立渲染价格分布图，`targetPriceModel` 保存颜色、筛选类型和纯格式化逻辑。
新增目标价算法字段应先进入服务端契约，不能在两个图表组件中分别推导。
