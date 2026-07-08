# Pipeline Jobs

`pipeline/jobs` 是完整任务编排的目标目录。

示例：

```text
jobs/
  global_retail/
  ticker_detail/
  narrative_rotation/
  youtube_fulltext/
  smart_voice/
```

Job 层负责：

- 读取运行参数。
- 编排 platform/domain 模块。
- 控制窗口、批次、断点续跑。
- 输出运行报告。

Job 层不应承担平台解析细节或核心算法实现。

## 当前落点

- `youtube/workflows.py`：YouTube 抓取、频道刷新、视频分析、完整口播、摘要、判断参数、创作者综合观点等工作流入口。
- `smart_voice/workflows.py`：X 情绪打分、KOL/散户 rollup、整体数据派生信号导出入口。
- `narrative_rotation/workflows.py`：跨社区固定叙事轮动导出入口。
- `global_retail/workflows.py`：全球散户多区抓取、打标、聚合、Toss、雪球长期管道、报价入口。
- `core/workflows.py`：数据库、样本数据、Reddit 抓取、ticker 提取、通用分析、市场聚合、每日任务、统计和云同步入口。
- `kol/workflows.py`：KOL 观点提炼、视角分类、目标价判断、论点综合、翻译、相关性和质量评分入口。

迁移原则：

- CLI 只能调用 job 函数。
- job 编排 platform/domain 模块，不应直接调用旧 `pipeline/analyze` 实现。
- job 不直接调用旧 `pipeline/ingest`；如仍需旧平台接入实现，应通过 `pipeline/platforms` adapter 间接调用。
- 当一个 job 需要复用复杂规则时，应把规则下沉到 `pipeline/domain`。
