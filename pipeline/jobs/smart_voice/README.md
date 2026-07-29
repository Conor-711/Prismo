# Smart Voice Jobs

`pipeline.jobs.smart_voice` 是 Smart Voice 相关批处理工作流入口。

当前覆盖：

- X 推文情绪打分。
- X 推文与 ticker/topic 硬匹配。
- KOL 每日净情绪、讨论度、新增 KOL。
- 散户每日净情绪、讨论度、新增散户。
- 标的详情页整体数据派生信号导出。
- SV 价格历史回填。
- Smart Voice v0 候选召回、LLM 结构化、结算、评分、导出；雪球候选默认等待版本化正式作者池一年回填全部完成。
- 单个公开 Telegram 广播频道的 Private SV MVP：隔离采集、频道主归属审计、全历史行情结算、公域合格作者校准、跟随观点组合回测和 JSON/Markdown/CSV/Web 报告；不进入公域榜单导出。
- 标的级历史时点 SV 百分位、观点聚集事件与无未来数据回测；首批详情页消费 `MU`、`NVDA`、`MSTR`。

CLI 不应直接导入旧 `pipeline.analyze.*` 实现。后续拆分时，SV 算法、评分和跨平台聚合规则应继续沉淀到 `pipeline.domain.smart_voice`。
