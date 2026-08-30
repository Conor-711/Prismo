# Frontend Architecture

前端采用 Next.js App Router。目标是把路由、业务模块、通用 UI 和数据查询分开，避免页面和组件继续横向膨胀。

## 目标目录

```text
web/
  app/                         # Next.js 路由层，只做页面组装和 metadata/static params
  features/                    # 按业务域组织的产品模块
    dashboard/
    ticker/
    narrative/
    investor/
    region/
    search/
    tracking/
    smart-account/
    auth/
  shared/                      # 跨业务复用基础设施
    ui/
    layout/
    charts/
    icons/
    formatting/
    i18n/
  server/                      # 构建期/服务端取数边界
    db/
    queries/
  lib/                         # 迁移期保留；旧查询和工具逐步迁到 features/server/shared
  components/                  # 迁移期保留；旧组件逐步迁到 features/shared
```

Tailwind 的 content 扫描必须覆盖 `app`、`components`、`features` 和 `shared`。迁移组件到新目录后，如果这里遗漏 `features/shared`，新目录中的响应式宽度、网格和任意值类不会进入生成 CSS，会导致页面布局退回到全宽流式形态。

## 路由层规则

`web/app` 中的 `page.tsx` 应只做四件事：

1. 解析路由参数。
2. 调用 feature query 或 server query。
3. 组装 feature shell。
4. 提供 metadata / generateStaticParams。

路由层不应该包含复杂筛选、排序、图表配置、阅读器状态或平台适配逻辑。

## Feature 模块规则

每个 `web/features/<domain>/` 推荐结构：

```text
components/       # 该业务域专属组件
hooks/            # 状态、筛选、排序、交互逻辑
queries/          # 该业务域取数入口，最终可转调 server queries
types.ts          # 该业务域消费的稳定类型
constants.ts      # 筛选项、枚举、展示常量
index.ts          # 对外导出，页面只从这里拿模块
```

示例归属：

- 总览页工作台、跨区信号与总览视图模型：`web/features/dashboard/`。
- 标的详情页观点流：`web/features/ticker/`。
- 叙事轮动图和详情页：`web/features/narrative/`。
- YouTube 作者详情：`web/features/investor/`。
- 搜索页：`web/features/search/`。
- Smart Account 展示模块：`web/features/smart-account/`。
- 追踪/自选页：`web/features/tracking/`。
- 侧边栏和 viewport 工作区：`web/shared/layout/`。
- Dropdown、SegmentedControl、Tooltip、Skeleton：`web/shared/ui/`。
- 迷你图和通用图表展示件：`web/shared/charts/`。
- 跨页面 KOL/观点展示基础件：`web/shared/market/kolPresentation.tsx`。
- 跨页面标的 logo：`web/shared/market/TickerLogo.tsx`。

Feature 层可以通过 `import type` 引用 `web/server/queries` 暴露的类型，但不能运行时导入
server query 函数。真实取数仍由 `web/app` 路由层或未来的 feature query adapter 触发，
feature component 接收已经组装好的 view model。

## 查询层规则

查询函数分三层：

1. `web/server/db/`：数据库连接和低级安全查询工具。
2. `web/server/queries/`：平台无关或跨页面复用的 SQL 查询。
3. `web/features/<domain>/queries/`：面向页面的 view model 组装。

迁移期间，`web/lib/*Queries.ts` 可以继续存在，但新增复杂查询不应继续堆进单个大文件。

`web/features` 对 `@/server/*` 的引用必须是 type-only import。`scripts/check_architecture.py`
会检查这一点，避免客户端组件不小心把服务端 SQL 查询打包进 UI 模块。

## 组件拆分阈值

满足任一条件就必须拆分：

- 单文件超过 400 行。
- 同时包含 UI、筛选状态、排序算法和数据转换。
- 一个组件被两个以上页面复用。
- 一个组件需要独立测试或独立加载骨架屏。

当前活跃 React 组件均不超过 400 行，query/view model 均不超过 500 行；纯多语言数据字典豁免。
后续修改不得通过兼容入口重新聚合实现逻辑，触达阈值前应按状态编排、展示组件和纯模型拆分。

## 迁移状态

- `web/features/dashboard/index.ts`：dashboard feature public API；`buildDashboardModel.ts` 负责纯视图模型，`DashboardWorkspace.tsx` 负责单视窗三栏工作台，`DashboardSignalPanel.tsx` 负责分歧/看多/看空切换，`DashboardSkeleton.tsx` 提供与最终页面同构的加载态。
- `web/server/queries/investorQueries.ts`：投资者榜单服务端查询；`web/lib/investorQueries.ts` 仅保留兼容导出。
- `web/server/queries/creatorQueries.ts`：YouTube 作者详情服务端查询；`web/lib/creatorQueries.ts` 仅保留兼容导出。
- `web/server/queries/smartVoiceQueries.ts`：Smart Account 标的榜单服务端查询；生成高 Score 新关注、集中方向、高低分歧和作者净人数突变矩阵，高 Score 新关注用当前 Top 10% 平台作者与前 180 天作者/标的覆盖基线判断；`web/lib/smartVoiceQueries.ts` 仅保留兼容导出。
- `web/server/queries/smartVoiceInvestorQueries.ts`：Smart Account 作者详情证据查询兼容入口；类型、单作者历史证据和榜单代表观点分别由 `smartVoiceInvestorTypes.ts`、`smartVoiceInvestorEvidenceQueries.ts`、`smartVoiceRepresentativeQueries.ts` 承担。
- `web/server/queries/smartVoiceTickerSignals.ts`：标的详情页 Score 聚集/回测查询；同时提供最近 45 个交易日信号历史和近 45 日历史时点分位证据。首批只向 `MU`、`NVDA`、`MSTR` 返回新版信号，其余标的返回空并使用旧模块。
- `web/server/queries/globalQueries.ts`：全球散户 `gr_*` 标的、地区、行情查询；`web/lib/globalQueries.ts` 仅保留兼容导出。
- `web/server/queries/kolQueries.ts`：兼容聚合导出；实现已拆到 `web/server/queries/kol/`，按 shared/lookups/sources/flow/opinions/targets/arguments/daily/boards 分层组织标的详情取数。`OpinionExplorer` 的可浏览池保持有界：Reddit 按近 370 天时间倒序取最近 350 条；X 只取已完成 `kol_refined` 的观点，并按质量、相关性、互动排序取前 120 条；雪球/Toss/Yahoo JP 各取 100 条。全量原始内容留在 SQLite 供离线指标使用，避免静态/开发页面序列化数万条原帖。
- `web/server/queries/narrativeRotation.ts`：叙事轮动构建期 JSON 查询；`web/lib/narrativeRotation.ts` 仅保留兼容导出。
- `web/server/queries/overallData.ts`：整体数据派生信号构建期 JSON 查询；`web/lib/overallData.ts` 仅保留兼容导出。
- `web/server/queries/legacyRedditQueries.ts`：兼容聚合导出；旧 Reddit 单站查询实现已拆到 `web/server/queries/legacyReddit/core.ts` 和 `detail.ts`。
- `web/shared/formatting/format.ts`：跨页面格式化工具；`web/lib/format.ts` 仅保留兼容导出。
- `web/shared/market/regions.ts`：五区展示元数据；`web/lib/regions.ts` 仅保留兼容导出。
- `web/shared/market/tickerMeta.ts`：标的交易所和 logo 元数据；`web/lib/tickerMeta.ts` 仅保留兼容导出。
- `web/shared/market/mockDetail.ts`：兼容聚合导出；标的/地区 fallback 和 KOL mock 类型已拆到 `web/shared/market/mockDetail/`；`web/lib/mockDetail.ts` 仅保留兼容导出。
- `web/features/smart-account/svMock.ts`：兼容聚合导出；Score 类型、fallback 常量、generated JSON 归一化和派生评分已拆到 `web/features/smart-account/svMock/`；`web/lib/svMock.ts` 仅保留兼容导出。
- `web/features/smart-account/index.ts`：Smart Account feature public API，dashboard、叙事详情、ticker 整体数据、公共作者榜单和 Score 作者详情从这里引入 Score 展示模块。
- `web/features/smart-account/components/SmartVoiceModules.tsx`：跨页面 Score 展示组件，包含排行榜、标的页 Score 投资者、作者 Score 画像和组合 Score 模块；作者页可开启前/后 10% 展开。
- `web/features/smart-account/components/SmartVoiceInvestorProfile.tsx`：Score 作者详情页主体，展示分数解释、投资风格/分类、时间窗口和叙事/标的强弱，并通过“观点证据 / 组合回测”双视图呈现原帖、完整已结算战绩和作者级信号跟随回测。
- `web/features/smart-account/components/SmartVoicePrimitives.tsx`：Smart Account 跨模块展示基础件（分数、作者 identity、排行行、segment bar、证据 chip）。
- `web/features/smart-account/svInvestorLinks.ts`：Score 作者详情页 slug/href 编码，避免平台 ID 中的特殊字符污染路由。
- `web/features/smart-account/components/SmartVoiceWorkspace.tsx`：应用内 Smart Account 工作台 shell，仅承载标的发现与实时观点；投资者榜通过入口跳转到独立公共路由。
- `web/features/smart-account/components/PublicSmartVoiceLeaderboard.tsx`：`/[lang]/smart-account/leaderboard` 的公开页面主体，无侧边栏、无登录门槛；汇总评分规模、方法口径并承载全高 `SmartVoiceLeaderboardView`。
- `web/features/smart-account/components/SmartVoiceLeaderboardView.tsx`：公共投资者榜交互工作区，排名条件与能力条件分层排列，支持来源、正式/观察/前后分位、精确周期、优势周期、赛道、风格和作者/标的搜索的叠加筛选。
- `web/features/smart-account/components/SmartVoicePortfolioView.tsx`：公域作者详情的跟随观点组合视图，展示净值、SPY 对照、CAGR、年度收益、风险和成本敏感性。
- `web/server/queries/smartVoicePortfolioQueries.ts`：用作者真实已结算 call 与复权 `price_daily` 在构建期生成下一交易日入场、同标的最新观点覆盖、活跃标的等权的作者级组合回测。
- `web/features/narrative/index.ts`：narrative feature public API，叙事总览和详情页从这里引入叙事图表组件。
- `web/features/narrative/components/NarrativeRotationCharts.tsx`：叙事轮动图表组件，包含 mindshare 堆叠图、排名、占比、情绪和详情时间线。
- `web/features/search/index.ts`：search feature public API，搜索页从这里引入搜索组件。
- `web/features/search/components/TickerSearch.tsx`：搜索页标的搜索组件，包含输入、结果列表和热门标的。
- `web/features/tracking/index.ts`：tracking feature public API，追踪页从这里引入客户端追踪视图。
- `web/features/tracking/components/TrackingView.tsx`：追踪页客户端视图 shell，无需登录，读取当前设备 `localStorage` 中的追踪、筛选和排序；采用搜索浮层、紧凑分类标签、独立滚动清单与 Smart Account 侧栏组成的单视窗工作台。追踪页只消费 `gr_ticker` 标的聚合，不读取 `gr_ticker_region`，也不展示区域覆盖、跨区分歧或地区情绪。类型在 `trackingTypes.ts`，卡片/空态/区块在 `trackingCards.tsx`。全站追踪状态与跨标签页同步由 `FavoritesProvider` 管理，帖子/评论账户收藏仍走 Supabase。
- `web/features/investor/index.ts`：investor feature public API，投资者榜单和 YouTube 作者详情页从这里引入组件。
- `web/features/investor/components/InvestorBoard.tsx`：投资者榜单组件，包含平台过滤、作者卡和 Smart Account 排行。
- `web/features/investor/components/CreatorProfile.tsx`：YouTube 作者详情组件，包含作者档案、标的判断、视频列表和 Score 画像。
- `web/features/ticker/index.ts`：ticker feature public API，页面层从这里引入已迁移模块。
- `web/features/ticker/components/KolModule.tsx`：整体数据核心图表组合，负责一年尺度补齐、KOL/散户口径切换、Overlay/Crowding/目标价组合。
- `web/features/ticker/components/OverlayPanel.tsx`：整体数据主叠加图，负责净情绪、讨论度、分歧差、股价的同轴开关展示。
- `web/features/ticker/components/OverallStructureCharts.tsx`：整体数据底部结构图，负责新增参与者/拥挤度、观点视角×多空等辅助图表。
- `web/features/ticker/components/TargetPricePanel.tsx`：目标价与买入/卖出价时间线，负责周期/平台筛选和目标帖文定位；价格分布图由 `TargetDistributionChart.tsx` 承担，纯常量与格式化放在 `targetPriceModel.ts`。
- `web/components/onboarding/OnboardingFlow.tsx`：首登状态、持久化与步骤编排；各步骤展示件位于 `web/features/onboarding/components/OnboardingSteps.tsx`。
- `web/features/ticker/components/TickerDetailHeader.tsx`：标的详情页页头，包含基本信息、统计条、价格 sparkline 和关注入口。
- `web/features/ticker/components/TickerOverviewPanel.tsx`：标的详情页整体数据面板 shell，包含全屏看板入口和 Score 模块组合。
- `web/features/ticker/components/SmartVoiceTickerSignals.tsx`：标的级 Top/Bottom Score 观点结构、周期信号、聚集事件和置信度感知回测面板。
- `web/features/ticker/components/SmartVoiceSignalChart.tsx`：标的价格与 Top/Bottom Score 看多/看空聚集事件叠加图。
- `web/features/ticker/components/SmartVoiceSignalDiagnostics.tsx`：高低 Score 分歧、周期结构、信号加速/反转、目标价和失效条件的展示层。
- `web/features/ticker/smartVoiceSignalLogic.ts`：上述四类诊断的纯派生逻辑，不读数据库、不修改 Score 分数。
- `web/features/ticker/components/SmartVoiceDecisionSuite.tsx`：MU/NVDA/MSTR 决策实验室组合层，包含真实 Score 加权目标价、观点变化、机会/风险指标和个性化仓位助手。
- `web/features/ticker/smartVoiceDecisionLogic.ts`：决策实验室的权重、生命周期变化、拥挤/置信度和仓位匹配纯逻辑；只消费历史时点证据，不改写 Score。
- `web/features/ticker/components/SmartVoiceResearchSuite.tsx`：组合投资逻辑生命周期、平台扩散、作者能力、组合叙事风险和可解释提醒。
- `web/features/ticker/smartVoiceResearchLogic.ts`：上述研究模块的时间窗口、视角暴露、扩散、HHI 和提醒阈值纯逻辑。
- `web/features/ticker/components/TickerSignalBoards.tsx`：标的总览页信号榜，包含 KOL 与 Smart Account 两种模式。
- `web/features/ticker/components/TickerTable.tsx`：标的总览页表格，包含排序、搜索和追踪入口。
- `web/features/ticker/opinionExplorerTypes.ts`：观点流筛选、排序、个性化、Score 相关类型。
- `web/features/ticker/opinionExplorerConstants.ts`：观点流平台、语言、时间窗口、质量阈值、Score preset 等常量。
- `web/features/ticker/opinionExplorerLogic.ts`：语言识别、质量判断、Score 作者匹配、个人化推荐排序等纯逻辑；YouTube Score 优先用 `authorRefId` 中的 channel_id 命中 `youtube:<channel_id>`。
- `web/features/ticker/overallDataTypes.ts`：整体数据图表消费的 `ChartMarker`、`VolRow` 等输入类型。
- `web/features/ticker/overallDataConstants.ts`：整体数据图表的 KOL/散户平台 stack 配置。
- `web/features/ticker/hooks/useOpinionFilters.ts`：观点流筛选状态、基础过滤、时间窗口、Score index、来源计数和筛选重置。
- `web/features/ticker/hooks/useOpinionSorting.ts`：观点流个性化评分、Score 排序和最终排序。
- `web/features/ticker/hooks/useOpinionPersonalization.ts`：按标的读取/保存个人化配置，并驱动默认推荐排序。
- `web/features/ticker/hooks/useSelectedOpinion.ts`：观点流选中态、原文/译文切换和图表点位打开正文事件。
- `web/features/ticker/components/OpinionExplorer/OpinionExplorer.tsx`：观点浏览器 feature shell，组合筛选、排序、个人化、选中态和左右面板。
- `web/features/ticker/components/OpinionExplorer/controls.tsx`：观点流筛选条复用控件、平台图标、个人化配置弹窗。
- `web/features/ticker/components/OpinionExplorer/filterBar.tsx`：顶部筛选条，包含搜索、情绪、Score、个人化、追踪作者、时间、语言、质量和清空入口。
- `web/features/ticker/components/OpinionExplorer/listPane.tsx`：左侧观点流容器，包含平台 tab、结果数、排序和列表滚动区。
- `web/features/ticker/components/OpinionExplorer/listCard.tsx`：左侧观点预览卡片。
- `web/features/ticker/components/OpinionExplorer/reader.tsx`：右侧正文阅读器，包含 YouTube 精读、X 互动、作者 Score badge 和目标价摘要展示。
- `web/features/ticker/components/OpinionExplorer/YtReader.tsx`：YouTube 完整口播阅读容器，包含投资者摘要、正文模式和内容目录跳转。
- `web/features/ticker/components/OpinionExplorer/YtFullContent.tsx`：YouTube 口播正文渲染器，负责单人/多人口播分段和章节锚点。
- `web/components/bsmart/OpinionExplorer.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/SmartVoiceModules.tsx`：兼容导出，旧 import 转发到 `web/features/smart-account`。
- `web/components/bsmart/SmartVoiceWorkspace.tsx`：兼容导出，旧 import 转发到 `web/features/smart-account`。
- `web/components/bsmart/ViewportWorkspace.tsx`：兼容导出，旧 import 转发到 `web/shared/layout/ViewportWorkspace.tsx`。
- `web/components/bsmart/Bits.tsx`：兼容导出，旧 import 转发到 `web/shared/ui/bsmartBits.tsx`。
- `web/components/bsmart/CreatorProfile.tsx`：兼容导出，旧 import 转发到 `web/features/investor`。
- `web/components/bsmart/DetailBits.tsx`：兼容导出，旧 import 转发到 `web/shared/ui/detailBits.tsx`。
- `web/components/bsmart/InvestorBoard.tsx`：兼容导出，旧 import 转发到 `web/features/investor`。
- `web/components/bsmart/KolModule.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/NarrativeRotationCharts.tsx`：兼容导出，旧 import 转发到 `web/features/narrative`。
- `web/components/bsmart/OverlayPanel.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/OverallStructureCharts.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/PriceSparkline.tsx`：兼容导出，旧 import 转发到 `web/shared/charts/PriceSparkline.tsx`。
- `web/components/bsmart/TickerLogo.tsx`：兼容导出，旧 import 转发到 `web/shared/market/TickerLogo.tsx`。
- `web/components/bsmart/TickerSearch.tsx`：兼容导出，旧 import 转发到 `web/features/search`。
- `web/components/bsmart/TickerOverviewPanel.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/TargetPricePanel.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/TickerSignalBoards.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/TickerTable.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/TrackingView.tsx`：兼容导出，旧 import 转发到 `web/features/tracking`。
- `web/components/bsmart/YtReader.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/YtFullContent.tsx`：兼容导出，旧 import 不再承载实现。
- `web/components/bsmart/kolShared.tsx`：兼容导出，旧 import 转发到 `web/shared/market/kolPresentation.tsx`。
