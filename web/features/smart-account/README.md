# Smart Account Feature

`web/features/smart-account` 承接跨页面 Smart Account 展示模块。

归属原则：

- Score 算法、作者分、标的分、组合分的产品展示归属本 feature。
- Score 原始计算与 pipeline 规则归属 `pipeline/domain` / `docs/architecture/05-smart-account.md`。
- 平台头像、来源配色等通用展示基础件从 `web/shared/market/kolPresentation.tsx` 引入。

当前已迁移：

- `components/SmartVoiceModules.tsx`
- `components/SmartVoiceWorkspace.tsx`
- `components/SmartVoiceMarketView.tsx`：按各平台正式 Top/Bottom 10% 作者聚合高 Score 新关注、集中看多/看空、高低 Score 分歧和作者净人数突变，负责筛选状态与榜单编排。
- `components/SmartVoiceMarketDetail.tsx`：展示当前与历史覆盖人数、方向，以及可回到原帖或视频的代表性证据。
- `smartVoiceMarketModel.ts`：市场发现视图使用的纯格式化、指标选择和证据分组规则。高 Score 新关注默认观察 7D：平台 Top 10% 作者在当前窗口发布 actionable call、且该作者此前 180 天没有覆盖同一标的时计为一位新增作者；此前 180 天没有任何当前 Top 10% 作者覆盖的标的标记为“全新进入”，否则标记为“新作者加入”。每位作者/标的在当前窗口只取最新 call。该发现信号不修改作者 Score，也不等同于已回测交易策略。
- `components/PublicSmartVoiceLeaderboard.tsx`：`/[lang]/smart-account/leaderboard` 独立公共页面主体，提供公开页面摘要、评分口径和全高榜单工作区；不经过应用侧边栏壳，也不要求登录。
- `components/SmartVoiceLeaderboardView.tsx`：公共榜单复用的交互工作区，只负责筛选状态、列表编排和作者选择。
- `components/SmartVoiceLeaderboardProfile.tsx`：榜单右侧作者画像、分数解释和价格走势代表作。
- `components/SmartVoiceFilterSelect.tsx`：榜单内统一的可访问筛选下拉控件。
- `leaderboardModel.ts`：榜单筛选、能力分和格式化所需的纯模型函数；不得在 React 组件内复制 Score 派生逻辑。
- `components/SmartVoiceRepresentativeChart.tsx`：在真实收盘价折线上以方向气泡展示作者对代表标的的已结算观点，保留 Score 贡献、方向超额和原始来源。
- `components/SmartVoicePortfolioView.tsx`：公域作者详情的跟随观点等权组合视图，展示净值、SPY 对照、CAGR、年度收益、风险和成本敏感性。
- `components/SmartVoiceLiveView.tsx`：high/medium confidence 或平台 Top 10% 作者近 60 天的最新 actionable call，按来源限额合并。
- `components/HyperliquidSmartMoneyView.tsx`：Hyperliquid HIP-3 TradFi 链上聪明钱工作台，按资产类别、时间窗和资金流排序浏览高分地址当前仓位、净主动成交流和原始成交证据。
- `components/SmartVoiceInvestorProfile.tsx`：作者分数解释、历史观点证据与作者级组合回测双视图。
- `svMock.ts`
- `svMock/types.ts`
- `svMock/constants.ts`
- `svMock/generated.ts`
- `svMock/scoring.ts`
- `index.ts`

应用内工作台保留“标的发现、实时活动、链上聪明钱”，投资者榜通过明确入口跳转到独立公共页面。前两者的社媒 Score 语义保持为公开观点和历史结算表现，不代表作者真实持仓；“链上聪明钱”只使用独立的 Hyperliquid 地址评分和真实成交/仓位数据，不与社媒作者排名混合。
