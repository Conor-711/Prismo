# Core Jobs

`pipeline.jobs.core` 是历史核心命令的工作流入口。

当前覆盖：

- 数据库初始化和迁移。
- ticker 种子、样本数据加载、空库兜底。
- Reddit ingest、Arctic Shift 抓取、评论抓取、作者历史抓取。
- ticker 提及抽取和通用 item-level 分析。
- 旧 Reddit 帖子、分析、评论翻译。
- rollup、market mood、trending、旧版 narratives、brief。
- 每日任务、统计输出、本地/云端 DB 同步。

CLI 不应直接导入旧 `pipeline.ingest.*`、`pipeline.analyze.*`、`pipeline.common.*`。平台抓取细节沉淀到 `pipeline.platforms.reddit`，基础 ticker 识别规则沉淀到 `pipeline.common.ticker_extraction`，市场聚合规则沉淀到 `pipeline.domain.market`。
