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
- 已迁入 platform 的入口包括 Reddit/Arctic Shift/作者池、本地样本、YouTube 视频发现/频道刷新、Toss 社区抓取、Global Retail 多区抓取/报价/雪球导入、雪球 direct crawler/长期任务、X ticker/topic 匹配、云端 X 拉取、完整 X ticker universe、SV 价格历史回填、短窗口 `price_daily` 加载和作者头像资产刷新。
- 后续新增平台实现不得落到 `pipeline/ingest`；旧 `pipeline/ingest` 仅用于兼容历史命令路径。

## 平台分类

- 高结构化平台：YouTube、X、Reddit。可以稳定拿到作者、互动、时间、正文或字幕。
- 半结构化社区：雪球、Toss、Yahoo Finance、Naver、PTT。正文可拿，但作者、粉丝、互动、历史窗口差异很大。
- 公开广播频道：Telegram public channel。公共预览页可提供频道作者、消息 ID、正文、时间、浏览量、反应和原帖链接；转发来源必须单独标记，不能自动归因给频道主。
- 受限平台：需要浏览器、登录态或 WAF 绕行的平台，必须把 crawl、raw 保存、sync 分离，避免失败时污染产品表。

雪球作者时间线属于受限平台流程：未登录只能抓作者首屏，翻页必须使用用户本人授权后保存的 Playwright storage state。会话文件必须 gitignore，平台层只能消费会话，不得接收或记录账号密码；raw 写入、ticker 扩展和 SV 分析保持分步执行。

## Telegram Public Channel MVP

`pipeline/platforms/telegram/public_channel.py` 只采集无需登录即可访问的
`t.me/s/<handle>` 公共预览历史，不加入私密群、不绕过访问控制，也不接收用户账号或会话。
标准化结果写入隔离数据库的 `telegram_public_channel` 和
`telegram_public_message`；每条消息同时保留源 HTML，转发内容保留在 raw 层但不得进入频道主
Smart Voice 证据。Call 提取、二次归属审计、行情结算和报告不属于平台层，分别落在
`pipeline/domain/smart_voice/private_*` 与 `pipeline/jobs/smart_voice/private_telegram.py`。
