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
- `kol_*`：KOL/Smart Account 相关派生。
- `gr_*`：全球散户和跨社区零售数据。
- `yt_*`：YouTube 专属数据。

## 雪球作者池表

- `xueqiu_author_pool`：domain 生成的版本化发现池；记录发现门槛、发布者隔离、Top 300 正式池和 warm reserve 顺序，可由发现 CSV 重算。
- `xueqiu_author_crawl_job`：platform 维护的作者时间线分页、重试、登录阻塞和一年窗口断点；可重建任务，但游标属于运行状态。
- `xueqiu_raw_post`：作者时间线与标的搜索共同复用的 raw 真源；进入部署快照。
- `xueqiu_post_ticker`：从作者正文提取的多对多标的映射；可从 raw 重算。

## YouTube Score 作者池表

- `yt_author_pool_run` / `yt_author_pool`：domain 生成的版本化作者池、媒体分类、选择排名和运行规则；可从频道发现与画像重算。
- `yt_channel_upload_checkpoint`：platform 维护的一年 uploads playlist 回填状态；属于运行状态。
- `yt_channel_upload` / `yt_channel_upload_pool`：normalized 视频元数据和版本化作者池归属；进入本地部署快照。
- `yt_channel_upload_relevance` / `yt_channel_upload_ticker`：domain 生成的版本化视频相关性及多 ticker 映射；可从上传元数据重算。
- `sv_call_candidate` / `sv_call` / `sv_call_settlement`：跨平台标准化 evidence、LLM 结构化 call 和确定性价格结算。
- `sv_investor_score` / `sv_segment_score`：可重算的当前评分结果；`sv_investor_score_snapshot` 保存跨运行比较快照。

## Hyperliquid Smart Money 表

- `hl_tradfi_instrument`：当前官方 TradFi HIP-3 市场目录，可从 API 重建；运行中按小时刷新。
- `hl_trade_tape`：WebSocket 公开成交不可变事实，包含真实买卖双方；是持续索引启动后的地址发现真源，进入运行备份。
- `hl_wallet`：地址发现累计值、fills 游标、历史上限、画像时间和错误 checkpoint；属于运行状态，不可用导出 JSON替代。
- `hl_fill`：按地址标准化的可审计成交，用于精确 opened/increased/reduced/closed/flipped 和 Onchain Score。
- `hl_wallet_state_snapshot` / `hl_wallet_position_snapshot`：不可变账户及仓位快照；平仓以 size=0 tombstone 保存。
- `hl_wallet_state` / `hl_wallet_position`：当前状态投影，可从最新快照重建。
- `hl_wallet_portfolio` / `hl_wallet_ledger`：低频表现曲线与非资金费资本活动。
- `hl_wallet_score` / `hl_asset_signal`：可从 fills、当前仓位和快照重算的领域派生层。

`fills_backfill_complete=1` 表示已完成当前官方可提供范围的补齐；`fills_truncated=1` 单独表示触及最近 10,000 条源数据上限。后者不得进入正式方向评分。

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
- Score：`docs/contracts/smart_account.md`
- Smart Money：`docs/contracts/smart_money.md`
- 叙事：`docs/contracts/narrative.md`

数据库表可以不同，但导出给前端的对象必须满足对应 contract。

## 可重算原则

- Raw 和 normalized 数据优先长期保存。
- Analysis 数据通常可增量补算，不应轻易删除。
- Rollup 和 export 数据应该可以从上游重算。
- 部署快照必须包含静态站构建所需的所有本地内容表。
