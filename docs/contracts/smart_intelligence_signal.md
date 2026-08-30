# Smart Intelligence Signal Contracts

本契约定义 iOS MVP 的三个核心交付对象：`SmartAccountUpdate`、`SmartMoneyMovement` 和
`PortfolioSignal`。机器可读真源是 `contracts/openapi/bsmart-v1.yaml` 1.4.0 及以上版本。

## 边界

- `SmartAccountUpdate` 只表达合格投资作者的有效观点变化。
- `SmartMoneyMovement` 只表达合格公开链上账户的显著仓位变化。
- `PortfolioSignal` 是前两类对象与用户持仓上下文结合后的产品信号。
- 新闻、财报、价格、宏观、基本面和技术指标可以作为内部上下文，但不能成为正式信号证据源或独立触发器。
- Score、作者资格、账户资格和关系判断由服务端或 Pipeline 生成，iOS 不重算。

## SmartAccountUpdate

| 字段 | 语义 |
|---|---|
| `authorId` / `authorName` / `platform` | 稳定作者归属和原始平台 |
| `score` / `platformPercentile` | 发布当时可获得的历史 Score 与平台分位 |
| `direction` | `bullish` / `neutral` / `bearish` / `mixed` |
| `lifecycle` | `new` / `strengthened` / `weakened` / `reversed` / `closed` / `invalidated` |
| `horizon` / `targetPrice` | 观点周期和可选目标价 |
| `thesis` / `invalidation` | 核心论据和可选失效条件 |
| `publishedAt` | 原始观点发布时间，不是抓取时间 |
| `ingestedAt` / `processedAt` | 原帖进入 bSmart 与完整观点可用的时间，用于数据新鲜度审计 |
| `sourcePostId` / `sourceURL` | 平台原生帖子 ID 与原帖入口；通知幂等以原生 ID 为基础 |
| `evidenceURL` | 可选原帖、视频或口播证据入口 |
| `authorAvatarURL` / `authorFollowersCount` / `authorVerified` | 可选公开作者身份快照，用于证据展示，不参与 iOS 端评分 |
| `originalText` / `translatedText` | 完整原帖与完整忠实译文；分析、摘要不得写入译文字段 |
| `evidenceSpan` | 支持此 Call 的作者原文逐字段落，必须能回溯到 `originalText` |
| `authorScoreAsOf` / `callScoringVersion` | 发帖处理时关联的 Score 快照时间与结构化 Call 版本 |
| `priceEvidence` | 可选真实日线 OHLC 窗口，包含观点日价格、后续截止价格和区间变化 |

`platformPercentile` 使用 `0...1`。`0.04` 表示该作者处于平台头部 4%，不是 4 分。

`priceEvidence` 只用于让用户审计观点发生在行情的什么位置。`viewDay` 取观点发布当日收盘；若发布时该交易日
尚无收盘，则取此前最近一个交易日。`responsePercent` 只有在至少存在一个后续收盘时才返回。价格反应不能被描述为
观点造成了行情，也不能单独用于提高作者 Score。

## SmartMoneyMovement

| 字段 | 语义 |
|---|---|
| `accountId` / `accountLabel` | 匿名公开账户标识，不推断真实身份 |
| `accountScore` | 动作发生时的账户历史评分 |
| `market` | 公开仓位来源，例如 Hyperliquid HIP-3 |
| `action` | `opened` / `increased` / `reduced` / `closed` / `flipped` |
| `direction` | 此次动作对标的暴露的方向含义 |
| `notionalBefore` / `notionalAfter` | 变化前后名义仓位 |
| `notionalChange` | 带符号的名义仓位变化 |
| `observedAt` | 链上动作被确认的时间 |
| `evidenceURL` | 可选公开仓位或交易证据入口 |

Smart Money 不能被描述为机构、传统券商账户或某位 Smart Account 作者的真实持仓。

## PortfolioSignal

`PortfolioSignal` 负责回答三个问题：发生了什么、与用户持仓有什么关系、下一步应研究什么。

允许的 `kind`：

- `smart_account_new_view`
- `smart_account_shift`
- `smart_account_consensus`
- `smart_money_movement`
- `confirmation`
- `divergence`
- `account_leads`
- `money_leads`

`evidence` 只能引用 `smart_account` 或 `smart_money`，并通过 `referenceId` 指向不可变的上游更新。确认和
背离必须同时存在两类证据；观点领先至少存在 Smart Account 证据；资金领先至少存在 Smart Money 证据。

### Smart Money 覆盖

- `available`：该股票的公开代币化美股资金数据达到最低覆盖门槛。
- `unavailable`：资金数据不足。客户端必须显示“暂无资金验证”，不能解释为中性或没有交易。

覆盖状态由服务端明确返回。`unavailable` 信号不得包含 Smart Money 证据。

### 数据状态与限制

- `dataStatus=current`：生成结论所需的数据源都在各自时效目标内更新。
- `dataStatus=delayed`：至少一条必要数据链路超过时效目标；客户端必须显示延迟，不能把缺失视为中性。
- `limitations`：生成时不可变的限制说明，例如独立作者/账户样本数、代币化美股覆盖和流动性边界。

`dataStatus` 与 `smartMoneyCoverage` 是两个维度。数据可以按时更新但没有足够 Smart Money 覆盖，也可以已有资金
覆盖但某条社媒抓取链路暂时延迟。

## TickerIntelligence

`TickerIntelligence` 是标的页的轻量聚合快照，不是第三类信号源。它只汇总：

- 当前 Smart Account 方向、最近更新和合格作者数；
- 当前 Smart Money 方向、最近动作、合格公开账户数和覆盖状态；
- 二者当前的确认、背离或领先关系；
- 最新 `PortfolioSignal` 引用和 `dataAsOf`。

价格与日内变化仅作为持仓上下文。旧 `/v1/research` 与 `TickerResearch` 保留为兼容层，新客户端使用
`/v1/intelligence` 或 `/v1/tickers/{symbol}/intelligence`。

## Portfolio context

`PortfolioPosition` 是用于个性化排序的本地优先记录。`entryKind` 区分真实持仓 `position` 与关注标的
`watchlist`。持仓可以填写股数、平均成本、`portfolioWeight` 或其中有意义的组合；成本与仓位占比均可选。
关注标的不生成虚构持仓规模。旧版 iOS 本地记录缺少 `entryKind` 时根据股数自动完成兼容推断。

### 时间语义

- `occurredAt`：达到正式信号门槛的时间。
- `dataAsOf`：生成这条结论所使用的数据截止时间，必须不早于 `occurredAt`。
- `evidence[].observedAt`：对应上游证据本身的发布时间或链上确认时间。

## 客户端职责

- 使用 `priority → 持仓权重 → occurredAt` 做个人 Feed 排序；
- 展示覆盖降级、数据截止时间和原始证据；
- 不在客户端生成信号、重算 Score 或把缺失资金数据推断成观点；
- `nextStep` 只提供研究动作，不输出直接买卖、仓位或杠杆指令。

## 用户状态与客户端缓存

`SignalUserState` 与 `PortfolioSignal` 分离。已读、保存、忽略和反馈是用户行为，不能写回或改变不可变的市场
信号事实。允许的反馈为 `useful / not_relevant / too_late / unclear`。

- iOS 在匿名激活阶段先将状态保存在本地，生产 API 通过 `PUT /v1/signals/{id}/state` 整体替换；
- 保存信号时自动取消忽略，忽略信号时自动取消保存，避免同一信号同时出现在冲突集合；
- 缓存保存最近一次成功读取的信号、上游证据对象与标的快照；网络失败时先显示缓存并标明刷新状态；
- 缓存不改变 `dataAsOf`、`dataStatus` 或证据快照，不得把“客户端刚打开”解释为“数据刚更新”。

## DailyDigestSnapshot

`DailyDigestSnapshot` 是每日摘要通知生成时保存的安装级不可变快照。它包含摘要 ID、生成时间、数据截止时间、
24 小时统计窗口、标题、摘要和当时入选的完整 `PortfolioSignal` 文档。

- 服务端按安装 ID 和用户本地日期生成确定性 ID；同一天重复规划不得改写已生成内容；
- 通知正文、`GET /v1/daily-digest` 和 iOS 日报详情必须读取同一快照；
- 未生成日报时接口返回 `404`，不能返回看似有效的空报告；
- iOS 将最新快照与其它客户端读模型一同缓存，断网时继续显示原快照；
- fixture、旧服务端或首次生成前没有快照时，iOS 可以从当前持仓信号临时聚合，但该结果不冒充已生成的服务端日报。

## 兼容策略

`InvestmentEvent` 和 `/v1/events` 是 1.0 兼容层。新客户端使用 `/v1/feed` 和 `PortfolioSignal`；旧接口在
生产 API 完成迁移、遥测确认无旧客户端使用后才能删除。
