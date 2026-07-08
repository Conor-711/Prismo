# Narrative Rotation Jobs

`pipeline.jobs.narrative_rotation` 是跨社区固定叙事轮动导出的 job 入口。

当前通过 `pipeline.domain.narratives.rotation` 承载固定 taxonomy、归类规则与 mindshare 计算，job 层只负责传入运行参数并触发导出。
