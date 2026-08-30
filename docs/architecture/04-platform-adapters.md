# Platform Adapter Architecture

新增平台时，不应直接把平台逻辑塞进页面查询或某个聚合脚本。每个平台都要经过统一适配流程。

## 平台适配器职责

每个 `pipeline/platforms/<platform>/` 至少应明确：

- `client`：请求、鉴权、分页、重试、限速。
- `crawler`：抓取任务和时间窗口。
- `normalizer`：把平台 payload 转成标准内容字段。
- `author`：作者元信息采集和快照。
- `README.md`：平台限制、反爬风险、字段可用性、运行命令。

## 标准输出

平台内容最终需要能映射到 Opinion contract 的核心字段：

- `source`
- `source_item_id`
- `ticker`
- `author`
- `published_at`
- `url`
- `original_text`
- `metrics`
- `language`
- `raw_payload_ref`

平台可以保留专属字段，但前端功能不应直接依赖平台私有 payload。

## 接入 checklist

1. 建立平台 README。
2. 明确 raw 表或文件落点。
3. 明确 normalized 表落点。
4. 补作者字段可用性说明。
5. 接入观点 contract。
6. 接入质量/相关性/翻译/摘要/目标价等 domain pipeline。
7. 更新 `ARCHITECTURE.md` 和本目录文档。
8. 至少提供一个单标的 smoke 命令。

## 迁移期兼容规则

- 新实现应落在 `pipeline/platforms/<platform>/`，旧 `pipeline/ingest/<name>.py` 只能作为兼容 wrapper。
- `pipeline/jobs` 和 `pipeline/cli` 不允许直接调用旧 `pipeline/ingest`。
- 已迁入 platform 的入口包括 Reddit/Arctic Shift/作者池、本地样本、YouTube 视频发现/频道刷新、Toss 社区抓取、Global Retail 多区抓取/报价/雪球导入、雪球 direct crawler/长期任务、X ticker/topic 匹配、云端 X 拉取、完整 X ticker universe、Score 价格历史回填、短窗口 `price_daily` 加载和作者头像资产刷新。
- 后续新增平台实现不得落到 `pipeline/ingest`；旧 `pipeline/ingest` 仅用于兼容历史命令路径。

## 平台分类

- 高结构化平台：YouTube、X、Reddit。可以稳定拿到作者、互动、时间、正文或字幕。
- 半结构化社区：雪球、Toss、Yahoo Finance、Naver、PTT。正文可拿，但作者、粉丝、互动、历史窗口差异很大。
- 链上交易平台：Hyperliquid。使用公开只读 Info API 获取 HIP-3 市场、成交和地址 fills；链上地址不是社媒作者，必须使用独立的身份、评分和产品契约。
- 受限平台：需要浏览器、登录态或 WAF 绕行的平台，必须把 crawl、raw 保存、sync 分离，避免失败时污染产品表。

## X realtime adapter

`pipeline/platforms/x/realtime` 以 `TweetProvider` 协议隔离供应商。当前
`TwitterAPIIOProvider` 使用版本化 `from:author` 规则接收 webhook，并每 15 分钟用高级搜索补偿；规则值必须
在 255 字符内自动拆分。高级搜索命中 20 条或返回 `has_next_page` 时必须二分 Unix 时间窗；这是 bSmart
为补偿审计采用的有界查询策略，不能被供应商分页实现细节渗透到领域层。平台层以 X 数字 user ID 识别作者，保留可变 handle；纯转发丢弃，原创、
回复与引用进入后续门禁。`post_id` 是原帖幂等键，平台层不得生成投资结论。

供应商只允许通过 `TweetProvider` 替换。紧急停用使用 `X_INGEST_ENABLED=false`；密钥、callback token 和供应商
URL 只能来自环境变量。生产原始事实写 PostgreSQL，不得恢复为本地 SQLite 在线真源。

雪球作者时间线属于受限平台流程：未登录只能抓作者首屏，翻页必须使用用户本人授权后保存的 Playwright storage state。会话文件必须 gitignore，平台层只能消费会话，不得接收或记录账号密码；raw 写入、ticker 扩展和 Score 分析保持分步执行。

## Hyperdash / Hyperliquid Smart Money

`pipeline/platforms/hyperdash/` 是生产 Smart Money 主适配器，只负责 Hyperdash GraphQL 请求、响应校验和 30 天数据标准化。默认使用 `equities` 系统组和上游 Copy Score，不得在 bSmart 平台层修改分数。账户仓位通过批量 `traderPerpPositionsTooltip` 获取；平台失败不得产生空榜覆盖最后成功快照。

Hyperdash 是外部商业依赖。生产使用前必须确认 API/再分发许可；认证、Cookie、endpoint 和限流只能通过环境变量注入，业务层不得依赖其 GraphQL 字段名。

### Hyperliquid 官方降级与审计

`pipeline/platforms/hyperliquid/` 只负责公开 Info API 的请求、限速、重试、HIP-3 TradFi
分类标准化和 SQLite 持久化。TradFi 范围由官方 `perpCategories` 动态识别为 stocks、indices、
commodities、FX 和 preipo，不用前端硬编码市场清单；合约 ID 保留 `{dex}:{coin}`，同时提供跨 DEX
聚合 symbol。

候选地址只从 `recentTrades` 的主动成交方发现，再用 `userFillsByTime` 回填。单次返回达到 2,000 条时
必须标记截断，不得把不完整历史用于正式高分地址。平台层只保存 instrument、wallet、fill、账户状态、
当前仓位、绩效曲线和资金台账事实；地址评分、算法账户排除、账户规模/PnL 分层、交易风格、风险指标和
标的资金流属于 `pipeline/domain/smart_voice/hyperliquid.py`。
运行编排位于 `pipeline/jobs/smart_voice/hyperliquid.py`，CLI 不得直接调用 client。

Hyperliquid 官方管线保留为来源审计、诊断和显式降级。它不得在 Hyperdash 主源健康时覆盖主榜，也不得把本地 Onchain Score 标记为 Hyperdash Copy Score。
