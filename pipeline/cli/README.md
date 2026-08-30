# Pipeline CLI

`pipeline/cli` 是 CLI 注册层。当前主入口 `pipeline/manage.py` 保留为兼容入口，实际实现已经迁移到这里。

目标结构：

```text
cli/
  manage.py
  registry.py
  commands/
    global_retail.py
    youtube.py
    kol.py
    smart_voice.py
    narratives.py
    deployment.py
```

CLI 文件只做：

- 参数解析。
- 调用 job/domain/platform 函数。
- 打印运行摘要。

不要在 CLI 命令里写抓取、分析、SQL 聚合或 prompt 逻辑。每个 `commands/*.py`
模块负责两件事：定义 `cmd_*` 参数适配函数，以及通过 `register_commands(sub, root)`
注册本业务组的 argparse 子命令。`registry.py` 只汇总这些注册函数。

每个命令模块只能调用自己的 job 层，例如 `commands/youtube.py` 只能调用
`pipeline.jobs.youtube`，`commands/smart_voice.py` 只能调用 `pipeline.jobs.smart_voice`。
这个所有权由 `scripts/check_architecture.py` 检查。

## 当前拆分

- `registry.py`：创建顶层 parser，并调用各命令模块的 `register_commands`。
- `commands/core.py`：数据库、样本数据、Reddit 抓取、ticker 提取、市场聚合、每日任务、统计和云同步命令适配，调用 `pipeline.jobs.core`。
- `commands/global_retail.py`：全球散户、Toss、雪球长期管道、报价命令适配，调用 `pipeline.jobs.global_retail`。
- `commands/youtube.py`：YouTube 命令适配，调用 `pipeline.jobs.youtube`。
- `commands/kol.py`：KOL 观点提炼、视角、目标价、论点、翻译、相关性和质量命令适配，调用 `pipeline.jobs.kol`。
- `commands/smart_voice.py`：X 匹配/情绪、Score v0、Score 价格历史、KOL/散户日聚合和整体信号命令适配，调用 `pipeline.jobs.smart_voice`。
- `commands/narratives.py`：叙事轮动命令适配，调用 `pipeline.jobs.narrative_rotation`。
- `commands/_utils.py`：CLI 参数解析辅助函数。
