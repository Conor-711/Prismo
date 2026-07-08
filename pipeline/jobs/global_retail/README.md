# Global Retail Jobs

`pipeline.jobs.global_retail` 是全球散户多区数据和本土社区平台的工作流入口。

当前覆盖：

- Yahoo JP / Naver / PTT 多区散户抓取。
- 全球散户帖子情绪打标和 ticker/region 聚合。
- 浏览器导出的雪球 JSON 导入。
- 雪球直抓、历史回填、日常增量、任务运行、raw 到 `gr_post` 同步、关联标的扩展、作者快照、状态查看。
- Toss 股票社区抓取。
- 全球散户标的报价刷新。

CLI 不应直接导入旧 `pipeline.ingest.*` 或 `pipeline.analyze.*`。后续拆分时，平台细节继续沉淀到 `pipeline.platforms`，跨平台打标和聚合规则继续沉淀到 `pipeline.domain.global_retail`。
