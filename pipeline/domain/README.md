# Pipeline Domain

`pipeline/domain` 是跨平台业务逻辑的目标目录。

推荐领域：

```text
domain/
  opinions/
  authors/
  tickers/
  narratives/
  smart_voice/
  target_prices/
  translations/
```

规则：

- 输入应是平台标准化后的内容，而不是 raw payload。
- 输出应能映射到 `docs/contracts`。
- 领域层可以被多个 job 复用。

## 当前落点

- `opinions/youtube.py`：YouTube 观点分析、文本兜底分析、完整口播生成、摘要生成入口。
- `opinions/items.py`：通用帖子/评论 item-level 分析入口。
- `opinions/kol.py`：KOL 观点提炼、视角分类、论点综合、完整翻译、相关性评分、质量评分入口。
- `translations/core.py`：旧 Reddit 帖子、分析、评论翻译入口。
- `target_prices/youtube.py`：YouTube 目标价、周期、关键位置判断入口。
- `target_prices/kol.py`：KOL 目标价和操作周期抽取入口。
- `authors/youtube.py`：YouTube 创作者对同一标的的综合观点入口。
- `smart_voice/signals.py`：Smart Voice 情绪、讨论度、新增参与者、整体信号入口。
- `smart_voice/v0.py` / `v0_impl.py`：Smart Voice v0 候选召回、结构化抽取、结算、评分、导出入口。
- `narratives/rotation.py`：固定 taxonomy 的跨社区叙事轮动导出入口。
- `narratives/legacy.py`：旧版市场 narrative 聚类入口。
- `tickers/catalog.py`：ticker 种子和帖子提及抽取入口。
- `market/signals.py`：市场 rollup、mood、trending、brief 入口。
- `global_retail/signals.py`：全球散户帖子打标与 region/ticker 聚合入口。

这些 domain 文件现在承载平台无关实现。`pipeline/analyze` 只保留历史导入兼容 wrapper；
新增或改动平台无关的清洗、prompt、结构化输出规则时，应直接修改对应 domain 模块。
