# YouTube Jobs

`pipeline.jobs.youtube` 是 YouTube 工作流入口层。

当前它通过 platform/domain 适配层封装了旧实现：

- `pipeline.platforms.youtube`
- `pipeline.domain.opinions.youtube`
- `pipeline.domain.target_prices.youtube`
- `pipeline.domain.authors.youtube`

CLI 不应直接导入旧 `ingest/analyze` 实现。后续拆分时，抓取和作者元信息应继续沉淀到 `pipeline/platforms/youtube`，观点分析、摘要、判断参数应继续沉淀到 `pipeline/domain/opinions` 和 `pipeline/domain/target_prices`。
