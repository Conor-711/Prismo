# Data Model Architecture

数据模型的目标是让“原始数据、标准化内容、AI 派生结果、产品 view model”分层清楚。

## 数据层级

1. **Raw layer**
   平台原始 payload、游标、任务、checkpoint。示例：雪球 raw/job/checkpoint 表。

2. **Normalized layer**
   跨平台标准内容。示例：`gr_post`、`yt_video`、`x_opinion`、Reddit `posts/comments/mentions`。

3. **Analysis layer**
   AI 或规则分析后的结果。示例：`item_analysis`、`yt_analysis`、`kol_refined`、`kol_viewpoint`、`kol_judgment`。

4. **Rollup layer**
   面向图表和看板的聚合。示例：`kol_sentiment_daily`、`retail_volume_daily`、`gr_ticker_region`。

5. **Export layer**
   构建期 JSON 或静态 view model。示例：`web/lib/data/narrativeRotation.json`、`overallData.json`、`smartVoice.json`。

## 表命名

- `raw_*` 或平台专属 raw 表：保存原始响应和任务状态。
- `*_analysis`：AI 分析结果。
- `*_daily`：按日聚合。
- `*_rollup`：窗口聚合。
- `*_snapshot`：作者、价格、状态等可重复刷新快照。
- `kol_*`：KOL/Smart Voice 相关派生。
- `gr_*`：全球散户和跨社区零售数据。
- `yt_*`：YouTube 专属数据。

## Schema 真源

- SQLAlchemy 主 schema 仍以 `pipeline/common/models.py` 为迁移期真源。
- 原生 sqlite 派生表必须在对应脚本中有幂等 DDL，并在本文件或 `ARCHITECTURE.md` 登记。
- Supabase 迁移必须放到 `supabase/migrations/`。
- 新表必须写明：
  - 数据层级
  - 生产者
  - 消费者
  - 是否可重算
  - 是否进入部署快照

## Contract 优先

新增跨平台功能前，先确认它消费哪个 contract：

- 观点流：`docs/contracts/opinion.md`
- 作者/KOL：`docs/contracts/author.md`
- 目标价和操作周期：`docs/contracts/judgment.md`
- SV：`docs/contracts/smart_voice.md`
- 叙事：`docs/contracts/narrative.md`

数据库表可以不同，但导出给前端的对象必须满足对应 contract。

## 可重算原则

- Raw 和 normalized 数据优先长期保存。
- Analysis 数据通常可增量补算，不应轻易删除。
- Rollup 和 export 数据应该可以从上游重算。
- 部署快照必须包含静态站构建所需的所有本地内容表。
