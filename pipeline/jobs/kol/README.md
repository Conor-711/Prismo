# KOL Jobs

`pipeline.jobs.kol` 是 KOL 观点处理工作流入口。

当前覆盖：

- KOL 观点提炼。
- 观点视角分类。
- KOL 目标价和操作周期抽取。
- KOL 论点综合。
- 原帖完整翻译。
- 相关性和质量评分。

CLI 不应直接导入 `pipeline.domain` 或旧 `pipeline.analyze`。后续拆分时，prompt、结构化输出和评分规则继续沉淀到 `pipeline.domain.opinions` 与 `pipeline.domain.target_prices`。
