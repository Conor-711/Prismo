# Smart Voice Feature

`web/features/smart-voice` 承接跨页面 Smart Voice 展示模块。

归属原则：

- SV 算法、作者分、标的分、组合分的产品展示归属本 feature。
- SV 原始计算与 pipeline 规则归属 `pipeline/domain` / `docs/architecture/05-smart-voice.md`。
- 平台头像、来源配色等通用展示基础件从 `web/shared/market/kolPresentation.tsx` 引入。

当前已迁移：

- `components/SmartVoiceModules.tsx`
- `components/SmartVoiceWorkspace.tsx`
- `components/SmartVoiceMarketView.tsx`：按各平台正式 Top/Bottom 10% 作者聚合标的集中看多/看空和高低 SV 分歧，支持 X/YouTube/Reddit 多选及 24H/3D/7D/30D/90D 窗口；集中方向保留多空 call 和带符号加权净强度，并独立展示每位平台作者只取最新 call 的一人一票净人数/共识度，以及与前一等长窗口比较的净人数变化率、突变状态和排名；右侧提供当前/前期可回到原帖或视频的代表性证据。
- `components/SmartVoiceLeaderboardView.tsx`：按来源、完整平台分位和观点周期浏览作者榜；右栏使用更宽但仍窄于主榜的响应式宽度，并展示前后分位作者的价格走势代表作。
- `components/SmartVoiceRepresentativeChart.tsx`：在真实收盘价折线上以方向气泡展示作者对代表标的的已结算观点，保留 SV 贡献、方向超额和原始来源。
- `components/SmartVoiceLiveView.tsx`：high/medium confidence 或平台 Top 10% 作者近 60 天的最新 actionable call，按来源限额合并。
- `components/SmartVoiceInvestorProfile.tsx`：作者分数解释和历史证据。
- `svMock.ts`
- `svMock/types.ts`
- `svMock/constants.ts`
- `svMock/generated.ts`
- `svMock/scoring.ts`
- `index.ts`

独立工作台借鉴 Nansen Smart Money 的“标的发现、榜单、实时活动、对象画像”信息架构，但产品语义保持为公开观点和历史结算表现。SV 不代表作者真实持仓、资金流或链上交易。
