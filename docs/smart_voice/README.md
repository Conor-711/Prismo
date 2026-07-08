# Smart Voice Architecture Guide

本文件是 Smart Voice 的总入口文档。后续新对话或新 Agent 接手 Smart Voice 相关任务时，应先阅读本文件，再按任务读取对应的核心算法和平台 adapter 文件。

## 1. 先读顺序

推荐阅读顺序：

```text
1. docs/smart_voice/README.md
2. SV_ALGORITHM.md
3. docs/smart_voice/GLOBAL_ALGORITHM.md
4. 当前任务涉及的平台文件：
   - docs/smart_voice/TWITTER_ALGORITHM.md
   - docs/smart_voice/YOUTUBE_ALGORITHM.md
   - docs/smart_voice/REDDIT_ALGORITHM.md
   - docs/smart_voice/XUEQIU_ALGORITHM.md
   - docs/smart_voice/TOSS_ALGORITHM.md
5. pipeline/domain/smart_voice/v0.py 和 pipeline/jobs/smart_voice/workflows.py
```

文件职责：

```text
SV_ALGORITHM.md
= Smart Voice 的共用核心算法：call schema、权重、结算、路径评分、生命周期、聚合、置信度。

docs/smart_voice/GLOBAL_ALGORITHM.md
= 跨平台总分语义：SV_Platform 如何转成 SV_Global。

平台文件
= 各平台 adapter 规则：内容单元、候选召回、字段映射、样本门槛、噪声过滤、平台调参。

pipeline/domain/smart_voice/v0.py / v0_impl.py
= 当前核心实现。

pipeline/jobs/smart_voice/workflows.py
= 当前 job 编排入口。
```

不要把五个平台的完整算法复制成五份。平台文件只写“这个平台如何进入共用核心算法”，共用的市场结算和打分逻辑应保留在核心算法中。

## 2. 产品语义

Smart Voice 不是粉丝数榜，也不是内容质量榜。它衡量的是：

```text
在 Prismo 已收集的投资者宇宙中，谁的公开市场观点更值得用户优先阅读。
```

核心原则：

- 准确性优先，内容质量只影响该 call 的责任权重。
- 一个简单但持续正确的观点，应该高于写得很好但经常错误的观点。
- 非行动性内容不进入 SV 结算，例如纯新闻、纯情绪、纯复盘炫耀、无方向宏观评论。
- 当前阶段只做美股股票和 ETF，暂不做 options、futures、crypto。

## 3. 两层分数

Smart Voice 有两层分数：

```text
SV_Platform
= 平台内分数。100 是该平台合格投资者的中位数。

SV_Global
= Global 榜单分数。它比较的是“一个投资者在自己平台中有多突出”，再按置信度折算。
```

不要把所有平台直接放在同一个原始分布里归一化。不同平台不是同一张试卷：

- X 高频、短文本、及时性强。
- YouTube 低频、长内容、基本面解释强。
- Reddit 长文 DD 和社区异质观点多。
- 雪球中文投资者讨论和长线持仓复盘更多。
- Toss 是韩国股票社区，提供韩语本地投资者视角。

因此先计算各自平台内的 `SV_Platform`，再转成 `SV_Global`。

## 4. Global 公式

平台内分数：

```text
raw_z = shrunk contribution z-score from settled calls
SV_Platform = 100 + 10 * robust_z(raw_z inside platform)
```

Global 分数：

```text
platform_deviation = (SV_Platform - 100) / 100
SV_Global = 100 + 100 * platform_deviation * confidence_factor
```

默认置信度系数：

```text
high      1.00
medium    0.85
low       0.65
observing 0.35
```

例子：

```text
X 投资者：
  SV_Platform = 160
  confidence = high
  SV_Global = 160

YouTube 作者：
  SV_Platform = 150
  confidence = medium
  SV_Global = 142.5
```

底部投资者也进入 Global。如果某人显著低于本平台基线，则：

```text
SV_Platform < 100
SV_Global < 100
```

低置信度的顶部或底部都会被拉回 100 附近，避免小样本冲榜或过度惩罚。

## 5. 端到端流程

整体流程：

```text
platform raw content
-> platform adapter candidate recall
-> sv_call_candidate
-> LLM structured call extraction
-> sv_call
-> market settlement
-> sv_call_settlement
-> investor aggregation
-> platform normalization
-> global deviation ranking
-> sv_investor_score / sv_segment_score
-> web/lib/data/smartVoice.json
```

每个平台都必须先把内容转换成统一的 structured call，再进入共用结算逻辑。

## 6. 统一结构化 Call

所有平台最终都要写入 `sv_call` 语义。核心字段：

```text
source
content_id / tweet_id
investor_id
author_handle
created_at
language
ticker
direction
horizon_bucket
horizon_explicit
target_price
conviction_score
evidence_score
specificity_score
call_weight
call_type
ticker_role
ticker_relevance
investor_style
call_structure
lifecycle_action
entry_status
evidence_span
summary_zh
summary_en
```

当前 SQLite 物理表仍使用历史字段名 `tweet_id`。在 schema 完全迁移前，各平台映射如下：

```text
X:        tweet_id = tweet id
YouTube:  tweet_id = video id
Reddit:   tweet_id = post id
Xueqiu:   tweet_id = post id
Toss:     tweet_id = content id
```

未来应迁移到：

```text
content_id
platform_content_id
platform_author_id
canonical_investor_id
content_type
```

## 7. 内容单元与 Evidence Budget

Smart Voice 的证据单位不是 ticker mention，而是平台内容单元：

```text
X:        one tweet
YouTube:  one video
Reddit:   one post
Xueqiu:   one post / article
Toss:     one post / opinion item
```

如果一个内容单元产生多个 ticker call，这些 call 必须共享内容级 evidence budget。

原因：

```text
一个视频讲 10 只股票，不应该获得 10 倍权重。
一条 tweet 列出 30 个 ticker，不应该算 30 个强观点。
```

当前共用规则：

```text
post_weight_cap =
  if n_calls <= 1: 1.8
  else: min(2.8, 1.15 + 0.35 * sqrt(n_calls))
```

## 8. 市场结算

所有平台共用结算逻辑：

```text
entry_price = call 创建时间之后第一个可用交易收盘价
benchmark = SPY
return = ticker return
benchmark_return = SPY return
excess_return = return - benchmark_return
```

方向命中：

```text
bull: excess_return > 0
bear: excess_return < 0
```

当前 horizon：

```text
1D, 5D, 20D, 60D, 90D, 180D
```

结算不是只看终点，还看窗口路径：

- endpoint persistence
- max favorable opportunity
- positive day share
- retracement penalty

核心细节以 `SV_ALGORITHM.md` 为准。

## 9. Call Lifecycle

如果同一投资者对同一 ticker 后续出现明确反向 actionable call，旧 call 需要提前关闭：

```text
same investor + same ticker + later opposite actionable call
-> closes older call for horizons not yet naturally settled
```

这避免两个错误：

- 不惩罚作者已经明确反转之后的长期结果。
- 不奖励作者已经放弃后旧观点继续碰巧正确。

## 10. 平台样本门槛

默认 qualified threshold：

```text
X:
  n_eff >= 8
  settled_calls >= 10

YouTube:
  n_eff >= 4
  settled_calls >= 5

Reddit:
  n_eff >= 3
  settled_calls >= 4

Xueqiu:
  n_eff >= 5
  settled_calls >= 8

Toss:
  n_eff >= 5
  settled_calls >= 8
```

如果某个平台早期数据太少，合格投资者少于 8 个，可以临时使用该平台全部 scoreable investors 作为 baseline，但必须保留 confidence cap。

## 11. 平台 Adapter 差异

### X

文件：`TWITTER_ALGORITHM.md`

特点：

- 高频短文本。
- 更适合短线、技术、flow/momentum、快速反转。
- 噪声高，样本门槛较高。

重点：

- cashtag 召回。
- 过滤 retweet、meme、纯新闻、复盘炫耀。
- 生命周期反转信号很重要。

### YouTube

文件：`YOUTUBE_ALGORITHM.md`

特点：

- 长内容。
- 适合基本面、估值、财报周期、目标价、风险条件。
- 视频数量少于 X，因此样本门槛更低。

重点：

- 投资者池默认 `subscriber_count >= 1000`。
- 一年窗口。
- 一个 video 是一个 evidence unit。
- transcript 是否完整是处理状态，不是质量分因子。
- full transcript 可用时优先使用；缺失时用 `yt_analysis`、`yt_digest`、`yt_judgment`、title、description、chapters 临时抽取。

### Reddit

文件：`REDDIT_ALGORITHM.md`

特点：

- 长文 DD、社区讨论、反共识信息。
- 作者身份可靠性弱于 X/YouTube。

重点：

- v1 先只做 post，不自动把 comments 并入原帖。
- 过滤纯提问、meme、删除帖、新闻转载。
- 低频高价值内容允许较低样本门槛。

### Xueqiu

文件：`XUEQIU_ALGORITHM.md`

特点：

- 中文投资者。
- 更偏持仓、估值、长线判断、跨区域信息差。

重点：

- 必须区分美股、港股、A 股 ticker。
- 当前 SV 范围只纳入美股股票和 ETF。
- 过滤纯新闻转发和无方向闲聊。

### Toss

文件：`TOSS_ALGORITHM.md`

特点：

- 韩国股票社区。
- 提供韩语本地投资者对美股/ETF 的观点。

重点：

- 韩语内容里的 ticker 映射。
- 过滤纯社交、纯情绪、纯新闻。
- 如果平台暴露组合/交易动作，只有具备明确美股/ETF 方向含义时才进入 SV。

## 12. 当前实现状态

当前核心实现文件：

```text
pipeline/domain/smart_voice/v0.py / v0_impl.py
```

当前 source 状态：

```text
x:
  candidate adapter 已实现
  extract/settle/score/export 已实现

youtube:
  candidate adapter 已实现
  extract/settle/score/export 走共用流程
  yt_video + yt_channel 是必需输入；yt_analysis / yt_digest / yt_fulltext / yt_judgment 是可选增强输入

reddit:
  candidate adapter 已实现
  extract/settle/score/export 走共用流程

xueqiu:
  平台文档已定义
  candidate adapter 待实现

toss:
  平台文档已定义
  candidate adapter 待实现
```

`SV_PLATFORMS` 包含全部五个平台：

```text
x, youtube, reddit, xueqiu, toss
```

`SUPPORTED_SOURCES` 表示当前已实现候选召回的 source：

```text
x, youtube, reddit
```

未实现 candidate adapter 的平台，如果数据库已有 candidate，仍可进入 extract/settle/score；但 candidates 阶段不会假装召回。

## 13. 执行指南

执行前先备份数据库：

```bash
cp data/dev.db data/dev.db.bak-sv-$(date +%Y%m%d-%H%M%S)
```

### X

```bash
python3 -m pipeline.manage sv-v0 \
  --stage all \
  --source x \
  --candidate-limit 50000 \
  --extract-limit 10000 \
  --extract-mode author-balanced \
  --per-author-min 20 \
  --per-author-max 80 \
  --workers 4
```

### YouTube

全量一年候选：

```bash
python3 -m pipeline.manage sv-v0 \
  --stage candidates \
  --source youtube \
  --candidate-limit 0 \
  --youtube-min-subs 1000 \
  --youtube-since-days 365 \
  --min-score 12
```

抽取所有 pending YouTube candidates：

```bash
python3 -m pipeline.manage sv-v0 \
  --stage extract \
  --source youtube \
  --extract-limit 0 \
  --extract-mode rank \
  --workers 8
```

注意：如果用户明确要求“一年数据”，不要用 `per-author-max` 截断 YouTube 高产频道。可以用 author-balanced 做预算控制，但最终必须补齐所有一年窗口内 pending candidates。

结算、打分、导出：

当前实现中，`candidates` 和 `extract` 才按 `--source` 处理平台数据；`settle`、`score`、`export` 应按统一池重算。这样才能保证 `SV_Global` 的跨平台分布和导出文件一致。

```bash
python3 -m pipeline.manage sv-v0 --stage settle --source all
python3 -m pipeline.manage sv-v0 --stage score --source all
python3 -m pipeline.manage sv-v0 --stage export --source all
```

### Reddit

```bash
python3 -m pipeline.manage sv-v0 \
  --stage all \
  --source reddit \
  --candidate-limit 0 \
  --reddit-author-limit 1000 \
  --reddit-since-days 365 \
  --reddit-min-author-posts 2 \
  --extract-limit 0 \
  --workers 8
```

## 14. 输出解释

导出的 JSON：

```text
web/lib/data/smartVoice.json
```

关键字段：

```text
sv
  SV_Global，跨平台榜单用它排序。

platformScores
  SV_Platform，各平台内部归一化分数。

concentration.svPlatform
  该投资者主平台内的最终平台分。

concentration.svPlatformRaw
  置信度/集中度 cap 之前的平台分。

concentration.svGlobal
  Global 分数。

concentration.svGlobalDeviation
  平台内偏离基线并折算置信度后的 deviation。
```

`sv = 100` 表示接近自己平台的中位数。
`sv > 100` 表示高于自己平台基线。
`sv < 100` 表示低于自己平台基线。

## 15. 常见错误

不要做：

- 不要把五个平台原始 raw_z 直接放进一个池子归一化。
- 不要让一条多 ticker 内容产生线性多倍权重。
- 不要把 YouTube transcript 是否完整当作质量分因子。
- 不要把相关度分数加入质量或 SV 准入；相关度用于排序和召回，不代表投资判断能力。
- 不要把纯新闻、纯情绪、纯复盘炫耀放进 SV 结算。
- 不要在用户要求一年数据时使用作者上限导致高产作者视频被截断。
- 不要修改 `data/dev.db` 前忘记备份。

应该做：

- 先确认平台 source key。
- 先确认内容单元。
- 先确认是否只覆盖美股股票和 ETF。
- 先把内容转成统一 `sv_call_candidate`。
- 再用共用 LLM schema 转成 `sv_call`。
- 再走统一 settlement 和 scoring。
- 最后检查 `SV_Platform` 与 `SV_Global` 的语义是否正确。

## 16. 新平台接入 Checklist

接入新平台时按以下顺序做：

```text
1. 在 docs/smart_voice/ 新增或更新平台算法文件。
2. 明确 source key。
3. 明确内容单元。
4. 明确投资者 id 映射。
5. 明确 ticker 映射和资产范围。
6. 明确候选召回规则。
7. 明确噪声过滤规则。
8. 明确样本门槛。
9. 实现 candidate adapter，写入 sv_call_candidate。
10. 确认 LLM prompt 是否需要平台描述调整。
11. 跑 extract。
12. 跑 settle。
13. 跑 score。
14. 跑 export。
15. 检查 smartVoice.json 中 source 分组和 scoreSemantics。
```

接入后至少检查：

```sql
SELECT source, count(*) FROM sv_call_candidate GROUP BY source;
SELECT source, count(*) FROM sv_call GROUP BY source;
SELECT source, count(*) FROM sv_investor_score GROUP BY source;
```

## 17. 当前约定

当前阶段产品约定：

- 五个平台最终都进入 Global。
- Global 比较的是平台内偏离程度，不是同一张试卷的绝对能力。
- 顶部和底部投资者都要能进入 Global。
- 平台算法可以微调，但必须经过统一 call schema 和统一 settlement。
- YouTube 当前使用一年窗口和 `subscriber_count >= 1000` 的作者池。
- Toss 指韩国股票社区，不是 Toast。
