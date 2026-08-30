# Smart Money Contract

Smart Money 表示 Hyperliquid HIP-3 代币化股票及其他 TradFi 永续市场中的公开伪名账户。它是公开链上账户的绩效、仓位和变化证据，不代表传统券商现货持仓、已识别机构或社媒作者本人。

## 数据源

生产环境默认以 Hyperdash 为主数据源：

- 账户池直接使用 Hyperdash `Equities Focused` 系统组；
- 账户分数直接使用 Hyperdash `Copy Score 0–100`，bSmart 不二次重算或修改；
- 绩效、胜率、Sharpe、回撤、交易风格、账户规模、30 天曲线和主要资产来自 Hyperdash GraphQL；
- 当前仓位来自 Hyperdash `traderPerpPositionsTooltip` 快照；
- bSmart 仅做字段标准化、30 天窗口裁剪、仓位快照差分、原子发布与客户端投影。

`pipeline/platforms/hyperliquid/` 的官方只读 API 管线继续保留，用于来源审计、诊断和 Hyperdash 不可用时的显式降级；它不再是默认生产排名来源。客户端和 API 必须公开 `source`、`scoreSource`、`sourceUpdatedAt`，不得把降级数据伪装成 Hyperdash 数据。

## 数据范围

- 只保留并发布最近 30 天；
- 可展示窗口只有 1D、7D、30D；
- 每个账户最多 90 个曲线点、20 条仓位变化、12 个当前仓位和 10 个主要资产；
- 仅将带 HIP-3 DEX 前缀的 TradFi 市场纳入 bSmart 的资产和仓位列表，过滤普通 Crypto 资产；
- 榜单默认最多发布 Hyperdash `Equities Focused` 前 100 个账户。

## `SmartMoneySignal`

稳定字段：

- `id` / `address`：公开链上地址，仅用于证据追溯，不作为默认用户身份展示；
- `walletLabel`：Hyperdash 原始名称或地址缩写，仅用于兼容和审计；
- `displayName`：由账户池统一分配的单个匿名名字；同一账户池内不得重复，不附加姓氏、首字母或数字，也不代表已识别真实身份；
- `avatarVariant`：稳定的左向边牧头像组合编号；6 种专业角色母版与 9 种强调色形成 54 个不重复组合，当前账户池内不得重复；头像统一使用非写实的几何编辑插画风格；
- `rank`、`tier`、`score`；
- `scoreSource`：生产主源固定为 `hyperdash-copy-score`；
- `source`：`hyperdash`、`hyperdash_cached` 或 `hyperliquid_fallback`；
- `sourceUpdatedAt`：上游快照生成时间；
- `changedAt`：最近一条纳入产品的仓位变化时间。

账户分析字段包括：

- `style`、`sizeCohort`、`pnlCohort`；
- `accountValue`、`totalNotional`、`unrealizedPnl`；
- `netPnl`、`winRate`、`sharpe`、`maxDrawdownPercent`；
- `periodMetrics`：1D、7D、30D 曲线和变化值；
- `currentPositions`、`assetPerformance`、`recentTrades`。

Hyperdash 当前没有返回的指标必须使用空值或兼容默认值，不得由 bSmart 猜测。`components` 在 Hyperdash 来源下为空，因为 Copy Score 的内部权重属于上游方法，不得伪造分项。

## `SmartMoneyMovement`

Movement 来自相邻 Hyperdash 当前仓位快照的可复现差分：

- `action` 为 opened、increased、reduced、closed 或 flipped；
- `direction` 表示该变化的多空影响；
- `notionalBefore`、`notionalAfter` 与 `notionalChange` 必须一致；
- `evidenceURL` 指向对应 Hyperdash 公开账户页；
- `accountDisplayName` 与 `avatarVariant` 复用同一账户的稳定匿名身份；
- 首次观察到一个账户时只建立基线，不生成虚假 movement；
- 相同仓位没有变化时不得重复生成事件。

Hyperliquid 降级源生成的 movement 仍应指向官方交易浏览器。客户端不得把快照差分描述成一笔已验证的单独成交。

## 代表性开仓证据

`smart-money-evidence` 为每个账户保留最多 3 个代表市场，供详情页按账户延迟加载：

- 只统计 `opened`、`increased`、`flipped`，不把减仓和平仓当成开仓；
- 按可观察的累计新增敞口排序，同一市场最多展示 10 个开仓点；该排序不参与、也不修改上游 Copy Score；
- 每个开仓点保留观察时间、价格、价格依据、方向、新增敞口和原始证据链接；`reported` 表示上游记录价格，`nearest_4h_close` 表示旧快照缺少价格时采用最接近观察时刻的 4 小时收盘价；
- K 线必须来自相同 Hyperliquid 合约的 `candleSnapshot` 4h 数据，禁止用股票或 ETF 价格替代衍生品合约；
- Hyperdash 仓位快照差分只能表述为“观察到的开仓/加仓变化”，不得宣称是可执行成交；Hyperliquid fill 降级记录同样采用这一保守的统一表达；
- `assetNetPnl` 仅为该市场的观察期背景数据，不参与代表性开仓排序。

Client API 使用 `GET /v1/smart-money/{accountId}/evidence` 返回该集合，iOS 不得在客户端重新计算排序或开仓状态。

## 客户端身份表达

- 默认页面将账户展示为“匿名资金账户”，使用稳定匿名姓名和左向侧脸边牧头像；
- 不得把匿名姓名描述成账户所有者的真实姓名、机构身份或 KYC 结果；
- 原始地址、来源平台和交易记录继续保留在“原始记录”中；
- `Whale` / “巨鲸”和 `PNL` 属于传统交易用户可理解的术语，允许保留；
- `Kraken`、`Shark`、`Dolphin`、`Fish`、`Crab`、`Shrimp` 等层级不得直接展示给普通用户，应映射为超大额、大额、中型或小型账户。

## 健康与降级

- 正常状态：`primarySource=hyperdash`、`activeSource=hyperdash`；
- 默认每 10 分钟刷新一次；Hyperdash 短暂失败时保留最近成功快照，`activeSource=hyperdash_cached`；
- 快照超过 `BSMART_HYPERDASH_MAX_STALE_SECONDS` 后才允许使用保留的 `hyperliquid_fallback`；
- 没有新鲜主源或合格降级快照时 `/ready` 返回 503；
- 失败响应或不完整仓位批次不得覆盖最后成功的原子 manifest。

## 数据责任

- `pipeline/platforms/hyperdash/`：Hyperdash GraphQL 请求与标准化；
- `pipeline/jobs/smart_voice/hyperdash_live.py`：轮询、快照差分、缓存、降级和健康状态；
- `pipeline/jobs/smart_voice/smart_money_publish.py`：来源无关的原子集合/manifest 发布；
- `pipeline/platforms/hyperliquid/`：官方 Hyperliquid 审计与显式降级适配器；
- `services/smart_money_ingest/`：单实例监督和 PostgreSQL Read Model 发布；
- 客户端不得重算 Copy Score、账户层级或数据新鲜度。

## 外部依赖

Hyperdash 的聚合数据和 Copy Score 是第三方产品能力。正式商业发布前必须确认其 API 使用许可、调用额度和稳定性约定。适配器必须保持可替换，不能让第三方字段渗透到 iOS 业务模型之外。
