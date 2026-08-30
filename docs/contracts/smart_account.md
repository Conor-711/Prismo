# Smart Account Contract

Smart Account 是 bSmart 用于发现和评估公开市场观点作者的产品域；Score 是作者或观点的具体数值评分。

## Canonical Terminology

- 产品、页面和功能统一称为 `Smart Account`。
- 具体分数、分数列和筛选指标统一称为 `Score`。
- 新增 UI、metadata、报告和文档不得使用旧产品名或用旧缩写代指 Score。
- 正式路由为 `/smart-account`、`/smart-account/leaderboard`、`/investors/smart-account/[investorId]` 和 `/data/smart-account-ticker/[symbol]`。

历史数据库和构建产物仍保留 `sv_*` 表、`sv`/`platformSv` 字段、`smart_voice` Python 包、`smartVoice.json` 与 `smartVoice*` TypeScript adapter。这些名称属于兼容层；在没有数据库迁移和双读验证前不得直接重命名。兼容层进入产品界面时必须映射为 `Score`。

## Author Score Meta

| 字段 | 类型 | 说明 |
|---|---|---|
| `investor_id` | string | 标准作者 ID |
| `ticker` | string | 标的 |
| `source` | string | 平台 |
| `score` | number | Score 分数 |
| `rank` | number | 标的内排名 |
| `percentile` | number | 标的内百分位，0 表示最头部，100 表示最尾部 |
| `n_effective` | number | 截至 `updated_at` 按结算时间衰减后的有效样本量 |
| `settled_calls` | number | 已结算观点数 |
| `updated_at` | ISO datetime | 更新时间 |

## Client Leaderboard Read Model

Web 与 iOS 的 Smart Account 榜单属于同一个产品和排名事实，不得各自建立独立作者模型。客户端接口
`GET /v1/smart-accounts` 是现有 Web 排名的只读投影，字段含义如下：

| 客户端字段 | 排名真源 | 说明 |
|---|---|---|
| `rank` | 全局正式排名 | 跨平台展示时使用，不由客户端重新计算 |
| `platformRank` | 平台内正式排名 | 选择单一平台时使用 |
| `platformPercentile` | 平台内 `rank / population` | Top / Middle / Bottom 区间筛选依据，范围 `0–1` |
| `score` / `scoreChange` | `sv` 与上次快照差值 | UI 统一显示为 Score，不显示旧产品名 |
| `confidence` | 排名置信度 | `observing / low / medium / high` |
| `effectiveSamples` | `n_eff` | 经周期化时间衰减后的有效样本量 |
| `settledCalls` | `settled_calls` | 实际已结算观点数 |
| `activeDays` / `coveredTickers` | 作者证据统计 | 用于说明样本覆盖，不参与客户端重算 |
| `specialty` / `horizon` / `style` | 赛道、周期与主风格子分数 | 支持 AND 语义的叠加筛选 |
| `topTickers` | 主要覆盖标的 | 用于作者画像和搜索 |
| `marketSelectionScore` | 相对 SPY 能力轴 | 可空，不得用综合 Score 伪造 |
| `industrySelectionScore` | 相对行业 ETF 能力轴 | 可空，不得用 SPY 回填 |
| `rationale` | 评分解释 | 只描述历史已结算证据和限制 |

MVP 使用 mock 时可以使用虚构作者和观点，但必须保留以上排名字段、区间语义、样本解释与筛选规则；mock
只验证产品交互，不代表任何真实作者表现。Internal Alpha 从隔离 Mock API 读取同一契约，Release 不得内嵌
fixture JSON。

## Author Evidence Read Model

实时观点流与作者历史证据是两个不同契约：

- `GET /v1/smart-account-updates` 只服务主动提醒和最新观点流，继续限定各平台正式榜单 Top 25% 作者；
- `GET /v1/smart-accounts/{accountId}/evidence` 服务作者详情，覆盖所有正式榜单作者，不得因作者不在实时池而返回空详情；
- 后者读取既有 `sv_call`、`sv_call_candidate`、`sv_call_settlement` 和 `price_daily`，不能在客户端重算 Call 或 Score。

每位作者的详情证据集必须有界，默认最多 7 条，并平衡选择近期 Call、代表性命中与代表性失误。不得只展示最佳案例。单条证据至少保留：

| 字段 | 说明 |
|---|---|
| `sourcePostId` / `sourceURL` | 原始平台事实与可回溯链接 |
| `originalText` | 完整原文；不得被摘要替代 |
| `translatedTextZH/EN` | 已保存的完整忠实译文；缺失时保持空值，不得用分析摘要伪造 |
| `evidenceSpan` | 支持结构化 Call 的逐字证据片段 |
| `thesis` / `direction` / `horizon` / `targetPrice` / `invalidation` | bSmart 结构化解释层，UI 必须与原文分区展示 |
| `publishedAt` / `ingestedAt` / `processedAt` | 发布、采集和处理审计时间 |
| `authorScoreAsOf` / `callScoringVersion` | 作者分数快照时间与 Call 算法版本 |
| `settlement` | 方向化命中、标的收益、相对 SPY 超额、相对行业 ETF 超额及结算版本 |
| `priceEvidence` | 真实日线价格窗口；只为每位作者的代表证据附带，控制客户端负载 |

历史收益是观点发布后的市场背景，不证明作者真实持仓、成交质量、主观意图或因果关系。详情页必须明确展示该限制。

## 前端筛选

Score 区间筛选使用 `percentile`：

- Top 25%：`0 <= percentile <= 25`
- Middle 50%：`25 < percentile < 75`
- Bottom 25%：`75 <= percentile <= 100`
- 自定义区间：用户选择 `[low, high]`

前端不得重新计算 `score`，只能基于已导出的 `percentile` 或 `rank` 过滤。

## Hyperliquid TradFi Wallet Contract

Hyperliquid 链上地址与社媒作者是两套身份和评分空间。`Onchain Score` 为 0–100 的地址历史成交能力分，
不得映射为社媒 `score`、`rank` 或 `platformBands`。构建期导出
`web/lib/data/hyperliquidSmartMoney.json`，根节点必须包含 `version`、`scoringVersion`、
`generatedAt`、`summary`、`leaderboard` 和 `markets`。

`leaderboard` 地址对象至少保留 `address`、`score`、`confidence`、`classification`、
`closedFillCount`、`activeDays`、`netPnl`、`winRate`、`profitFactor`、`maxDrawdownPnl` 和
`topMarkets`；成交证据保存在对应标的窗口。`classification=algorithmic` 或历史截断的地址不得进入
合格榜和高分地址集合。

标的对象按跨 DEX symbol 聚合，窗口限定为 `1d/3d/7d`，至少包含高分地址多空数量、
当前净仓位名义金额、净主动资金流、成交量和证据。`signal` 只能为
`bullish/bearish/neutral/insufficient`；少于 3 个独立高分地址必须使用 `insufficient`，
不得把单一地址方向展示为链上共识。

## Version And Time Semantics

Call 抽取与作者排名分别版本化：

- `callScoringVersion = v1.8-transcript-lifecycle`：结构化 Call 和完整口播证据版本；
- `scoringVersion = v2.1-dual-benchmark-moderate-decay`：双基准积分结算、温和时间衰减、作者聚合、平台排名和全局排名版本。

作者排名使用 `docs/smart_account/GLOBAL_ALGORITHM.md` 定义的周期化半衰期，从
`exit_day` 开始衰减。`n_effective`、平台资格、置信度和集中度均使用衰减后证据；
`settled_calls` 仍是截至 `as_of_day` 的实际已结算 Call 去重数量。历史榜单只允许
读取 `exit_day < as_of_day` 的结果，当日或未来结算不得参与。时间衰减只作为
近期性修正，不应主导作者资格；默认半衰期为 `1D=60`、`5D=75`、`20D=150`、
`60D=300`、`90D=450`、`180D=675` 个自然日。

## Dual-Baseline Ability Contract

每位作者的 `abilities` 必须同时保留两个独立能力轴：

| 字段 | 含义 |
|---|---|
| `marketSelection` | 相对 SPY 的积分式方向超额，衡量全市场选股能力 |
| `industrySelection` | 相对行业 ETF 的积分式方向超额，衡量行业内选股能力；无法可靠映射时为空 |
| `industryBlendWeight` | 行业能力进入综合 Platform Score（遗留键 `SV_Platform`）的实际权重，随有效样本增加且小于 0.5 |

导出根节点的 `platformScoringVersions` 记录各平台当前已落库的评分版本。
平台分批迁移时，产品不得把根节点 `scoringVersion` 当作所有平台都已完成重算的证据。

单条 Call 从发布后的首个可交易开盘入场。每个交易日记录累计方向超额路径，
用梯形积分得到 `A(H)`，主分数为 `70% × 平均积分分量 + 30% × 终点分量`。
所有周期都可保存为积分前缀快照，但只有 Call 的主周期拥有非零证据权重；
不得把同一 Call 的多个周期当成独立样本。

行业 ETF 映射按 `ticker override -> narrative -> sector` 执行。无法映射时不得用
SPY 冒充行业基准，该 Call 只进入 `marketSelection`。

## Platform Top / Bottom Export

`web/lib/data/smartVoice.json` 的平台内正式榜单使用 `platformBands.<source>`。导出器会为所有已有正式评分的来源生成该结构；当前有效来源为 X、YouTube、Reddit 和雪球，Toss 在评分池形成前保持缺省，不生成伪榜单：

| 字段 | 说明 |
|---|---|
| `totalCount` | 该平台获得评分的作者数 |
| `qualifiedCount` | 达到该平台正式门槛的作者数 |
| `rankedCount` | 本次参与平台分位排名的人数 |
| `population` | `qualified` 或样本不足时的 `all_scored_fallback` |
| `distribution` | 正式排名池的 `SV_Platform` 分布和 10% 阈值 |
| `ranked` | 按 `SV_Platform` 排序的完整正式排名池；作者详情和“正式排名”视图以此为准 |
| `observed` | 该平台全部已形成分数的作者；未达到正式门槛者只能进入“观察池”，不得混入正式排名 |
| `top10` / `bottom10` | 平台内前/后 10% 完整名单 |
| `top25` / `bottom25` | 平台内前/后 25% 完整名单 |
| `top25Threshold` / `bottom25Threshold` | 25% 分组边界 |

平台名单中的 `platformRank` 是平台内排名，`rank` 仍是全局排名；`platformScores[source]` 是 `SV_Platform`，`sv` 是置信折算后的 `SV_Global`。产品在平台标签下必须使用平台字段，不能从全平台 Top 200 二次筛选。

投资者榜的能力筛选只消费导出中的 `horizonScores`、`narrativeScores` 和 `concentration.dominantInvestorType / investorTypeShare`。短线、中线、长线分别聚合 `1D+5D`、`20D+60D`、`90D+180D` 的可用子 Score，优势周期是作者三个组中均分最高的组；赛道筛选要求作者存在该赛道子 Score，风格筛选匹配主风格。平台、排名带、周期、赛道、风格和搜索使用 AND 语义。周期与赛道叠加时的“能力分”只是所选子 Score 的算术均值和页面排序值，不是新的 Score，不得写回离线表、冒充 `SV_Platform` 或改变正式排名资格。

`/smart-account` 的标的聚合按每个来源正式合格池的 `platformRank` 精确划分 Top/Bottom 10%，并使用作者对应来源的 `SV_Platform` 计算加权强度，不能使用整数 Score 阈值或 `SV_Global` 近似；跨平台组合先在各平台内分组，再合并同一标的的观点。页面必须支持 X、YouTube、Reddit、雪球的任意非空组合，以及以全库最新 actionable call 时间为锚点的 24H、3D、7D、30D、90D 精确时间窗。集中看多/看空至少需要同方向 2 条 call 和 2 位独立 Top 10% 作者；排名指标是 `highBullScore - highBearScore`，列表必须显示带符号的净强度，不能用单边总强度冒充净方向。列表多空计数和作者数只统计 Top 10%，中段与 Bottom 10% 只可用于独立的分歧模块。

每个入榜标的必须提供与当前平台组合、时间窗口和方向一致的代表性证据。证据事实包含 `candidate_id`、平台、作者、发布时间、`SV_Platform`、方向、周期、原文片段和原始 URL；本地化摘要与原文片段分开显示，摘要不得替代原文。查询层先用轻量 call 计算榜单，再按最终证据 ID 回表读取正文，不能把近 90 天全量原文发送到浏览器。实时观点只纳入 high/medium confidence 或平台 Top 10% 作者的 actionable call，默认读取数据最新日向前 60 天，并按来源设置相同上限后合并，避免单一平台淹没其他来源。缺失摘要时可回退到已保存的 call 证据片段，但不得生成新观点。

投资者榜作者预览必须使用真实结算证据和 `price_daily`，不得用 mock 价格或仅把单条文字观点包装成代表作。每位可进入详情的作者分别生成 `best` / `weak` 两个候选：先按作者、ticker 和贡献正负聚合 `sum(abs(contribution))`，各取累计影响最大的 ticker，再在该 ticker 上取最多 10 条绝对贡献最高的已结算观点。图中同时保留这些观点的原始多空方向，不得因作者属于底部组而反转 stance；气泡颜色表达 bull/bear/neutral，大小表达 `abs(contribution)`，选中观点必须展示方向超额、结算日期和原始 URL。预览只展示收盘价折线，价格按 ticker 去重共享，客户端契约使用 `[day, close]` 紧凑元组。

iOS 作者详情的“代表作”口径独立于榜单头尾预览：只聚合 `contribution > 0` 的已结算 Call，按作者与 ticker 求和，取累计正向 Score 加分最高的 3 个标的。每个代表标的保留最多 10 条正贡献观点，使用真实日线 OHLC 展示 K 线，并将观点按发布时间/入场交易日落点；点的颜色表达原始多空方向，大小表达单条 `contribution`。卡片必须展示标的累计加分和观点数，且能进入最高贡献观点的完整审计证据。客户端不得从收益率或命中次数重新推导该排名。

作者人数指标与加权净强度必须并列输出，不能互相冒充：在当前平台组合、时间窗和标的内，每个正式 Top 10% 平台作者按 `source + investor_id` 去重，只保留其最新 actionable call 的方向。`author_bull_count` / `author_bear_count` 是一人一票计数，`author_net = bull - bear`，`author_consensus = author_net / (bull + bear)`；同一作者在窗口内重复发帖不得重复计数。跨平台作者实体未归并前，不得仅凭 handle 相似自动合并。该指标当前只展示，不改变既有 `highBullScore - highBearScore` 排名。

作者净人数变化使用相邻等长窗口，不得拿不同长度区间比较：`author_net_delta = current_author_net - previous_author_net`，`author_net_shift_pct = author_net_delta / max(current_author_total, previous_author_total, 1)`。变化率是有方向的作者平衡变化，发生多空反转时允许超过 `100%`。只有 `abs(author_net_delta) >= 3`、`abs(author_net_shift_pct) >= 50%` 且两个窗口各至少 3 位作者时，`author_net_abrupt=true`；无前期样本、新增覆盖或任一期少于 3 人只能标记一般变化。变化榜先按 `author_net_abrupt`、再按变化率绝对值、净变化绝对值排序，并提供当前/前期代表 call 及原始链接。

高 Score 新关注使用当前来源组合内各平台正式 Top 10% 作者，不得用全局名次代替平台名次。当前窗口内每位 `source + investor_id` 对同一 ticker 只贡献最新一条 actionable call。若该作者在窗口开始前 180 天没有覆盖该 ticker，则 `new_coverage_author_count += 1`；`new_coverage_ratio = new_coverage_author_count / current_top_author_count`。只有此前 180 天 `prior_top_author_count = 0` 时 `cohort_new=true`，否则只能称“新作者加入”，不能称该标的是市场或平台首次出现。当前实现是最新作者池的横截面发现口径，不得用于历史收益声明；历史回测必须按每个信号日重建当日平台资格、排名和 180 天基线。

YouTube 正式榜单额外要求：

- 频道粉丝不少于 2,000，且视频时长严格大于 60 秒；候选、全文、结算、评分必须使用同一资格过滤；
- 指定 `--only` 或 `--youtube-since-days` 时，候选、全文与调用抽取必须保持相同标的和时间窗口；
- `sv_call.scoring_version = v1.8-transcript-lifecycle`；
- `transcript_version = youtube-transcript-v2`，并保存 `transcript_model`；
- Call 必须来自完整 `yt_fulltext`，不得由标题、描述或摘要单独生成；
- `evidence_segment_start/end` 指向生成 Call 的口播证据段；
- `call_owner` 与 `host_endorsement` 防止把嘉宾、分析师或第三方成交归到频道名下；
- 同一作者、标的和交易日的相反方向在结算前完成反转或净额化。

## Ticker Score Signal

标的详情页信号由离线管线生成，前端只读取以下派生层：

| 表 | 粒度 | 说明 |
|---|---|---|
| `sv_investor_score_asof` | 日期 × 作者 | 只使用该日期前已结算观点得到的历史时点全局/平台 Score、排名、百分位和正式池资格 |
| `sv_ticker_signal_daily` | 标的 × 日期 × 观点周期 × 分组 | Top/Bottom 10%/25% 的多空数量、同向度、有效声音、平台数和聚集状态 |
| `sv_ticker_signal_event` | 连续聚集事件 | 聚集开始/结束、方向、作者集合、下一交易日入场价 |
| `sv_ticker_signal_outcome` | 事件 × 回测周期 | 收益、相对 SPY 超额、方向性超额、命中、MFE、MAE 和结算状态 |
| `sv_ticker_signal_stat` | 标的 × 分组 × 信号周期 × 回测周期 | 历史事件统计 |

约束：

- `percentile` 越小越靠前；Top 25% 为 `<=25`，Bottom 25% 为 `>=75`。
- Bottom 分组保留作者观点的原始方向，不自动做反向交易。
- 同一作者、标的、日期和周期只保留最后一条观点，避免刷屏重复计数。
- 事件入场时间必须晚于信号日；作者分数只能使用 `exit_day < asof_day` 的历史结算。
- 命中定义为方向性 SPY 超额大于 0；小于 10 个事件的统计只作观察，不应用于 Top/Bottom 排名结论。
- 首批详情页展示范围为 `MU`、`NVDA`、`MSTR`。

## Discovery Indicator Backtest

Smart Account 发现页的四类指标使用独立的无未来函数回测层：

| 表 | 粒度 | 说明 |
|---|---|---|
| `sv_indicator_signal_daily` | 标的 × 日期 × 来源范围 × 窗口 × 指标 | 当日满足产品门槛的加权净强度、作者净人数、作者净人数突变或高低 Score 分歧信号 |
| `sv_indicator_event` | 连续同向信号事件 | 把相邻交易日的同指标同方向信号合并，记录首个信号日和下一交易日入场 |
| `sv_indicator_outcome` | 事件 × 1/5/20/60/90D | 方向收益、相对 SPY 方向超额、原始/超额命中和 MFE/MAE |
| `sv_indicator_stat` | 来源范围 × 指标 × 窗口 × 持有期 × 方向 | 胜率、Wilson 95% 区间、平均/中位收益、盈亏比、利润因子和超额统计 |

`sv_investor_score_asof` 的平台历史字段为 `platform_sv`、`platform_rank_no`、`platform_population`、`platform_percentile` 和 `platform_qualified`。历史平台排名只包含当时达到对应平台 `n_eff`/已结算 Call 门槛的作者，且至少有 10 位合格作者时才形成 Top/Bottom 10% 信号。

组合年化层不得使用当前作者排名回填历史交易。集体信号必须读取 `sv_indicator_event.source_scope='x'`；作者可执行口径必须要求观点当日 `sv_investor_score_asof.platform_qualified=1`。年化结果是报告产物，不回写 `sv_investor_score`，也不得用于重新训练同一历史区间的 Score 分数。

排名事件研究同样只能使用观点发布当日的 `sv_investor_score_asof` 排名。事件强度分位必须使用严格早于信号日的历史事件计算，并设置最小历史样本；不得使用全样本中位数或分位数回填过去。参数筛选只能读取训练期指标，时间外收益不得参与候选排序。宽参数结果必须与固定前后半段、成交额过滤、成本、延迟成交和标的集中度压力结果一并输出；任何产品文案不得把样本内最高年化直接称为预期收益或可复制收益。

头部跟随、底部反向和头尾背离的事件必须按 Call 发布日的 `platform_rank_no / platform_population` 划分 Top/Bottom 10% 或 25%。滚动窗口内每位作者只保留最新 actionable Call；单侧至少 2 位作者且同向度至少 65%。底部反向必须显式翻转底部共识方向；头尾背离必须要求两侧分别达标且方向相反，不能仅凭净值差异触发。

回测必须遵守以下口径：

- 作者在某日的分数只使用 `exit_day < asof_day` 的结算；观点按发布日当时的平台排名分组，不用当前排名回填。
- 日信号在当日结束后形成，从下一交易日开盘进入；连续同向日只算一个事件，防止把持仓期内重复信号当成独立交易。
- `weighted_net` 复用发现页未归一化的 `SV_Platform × Call 权重 × 置信度 × 样本修正` 净和；至少需要同方向 2 条 Call 和 2 位作者。
- `author_net` 每位 `source + investor_id` 只取窗口内最新 Call，回测触发要求 `abs(author_net) >= 2` 且主方向至少 2 位作者。
- `author_net_shift` 只回测产品定义的突变事件，方向取 `author_net_delta` 的符号；`high_low_divergence` 的交易方向跟随 Top 10%，不反向解释 Bottom 10%。
- 原始胜率为方向收益大于 0；超额胜率为相对 SPY 的方向超额大于 0。`payoff_ratio = 平均正方向收益 / abs(平均负方向收益)`，`profit_factor = 正方向收益之和 / abs(负方向收益之和)`。
- 跨标的事件及不同窗口可能重叠，Wilson 区间只描述事件样本的不确定性，不等同于完全独立交易的统计显著性，也不是含手续费、滑点和仓位约束的组合回测。
- 回测价格优先使用 `adj_close`，入场开盘按 `open * adj_close / close` 同因子调整；明细报告必须保留事件状态、成本敏感性和同标的同策略入场时的未平仓数量。
- `sv_indicator_event_evidence*.csv` 必须能从事件追溯到 `candidate_id`、发帖日平台排名、权重/作者票、摘要、原始证据和 URL；期权方向未解析、看空标签与卖出 Put 冲突、条件入场分别使用审计标记，不得静默删除。
- `sv_indicator_casebook.md` 固定使用全平台、7 日信号窗和 20 个交易日结果；四个指标各取相对 SPY 超额最好 5 个与最差 5 个不同标的，引用证据必须满足 `used_by_indicator=1` 并保留原始 URL。

## Segment Score Vertical Backtest

子 Score 垂直回测用于验证“某一能力子类中的高排名作者集中判断”是否具有与该子类匹配的预测价值。它不得使用当前 `sv_segment_score` 回填历史，必须建立独立的历史时点派生层：

| 表 | 粒度 | 说明 |
|---|---|---|
| `sv_segment_score_asof` | 日期 × 子类别 × 作者 × 来源 | 只使用 `exit_day < asof_day` 的已结算证据重建子 Score、排名、百分位和资格 |
| `sv_segment_signal_daily` | 标的 × 日期 × 子类别 × 来源范围 × 窗口 × 排名带 | 子 Score Top 10%/25% 作者的滚动集中方向 |
| `sv_segment_event` | 连续同向垂直信号 | 聚集开始/结束、作者集合、下一交易日入场价 |
| `sv_segment_outcome` | 事件 × 回测周期 | 方向收益、相对 SPY 超额、命中、MFE、MAE 和状态 |
| `sv_segment_stat` | 子类别 × 窗口 × 排名带 × 回测周期 | 样本量、胜率、Wilson 区间、收益、盈亏比和利润因子 |

首版稳定子类别为：

- `horizon`: `1D/5D/20D/60D/90D/180D`，子 Score 衡量作者全部有效判断在对应后续周期的历史表现；主结论只使用与子 Score key 相同的 outcome horizon。
- `narrative`: 固定美股赛道 taxonomy，例如 `semis`、`ai_infra`、`software`、`crypto`；作者排名和信号标的必须属于同一赛道。
- `investor_type`: `fundamental/technical/event_driven/macro/flow_momentum/mixed`；作者历史证据和新 Call 必须使用相同分析类型，`unknown` 不进入正式垂直事件。

回测约束：

- 子 Score 资格默认要求该子类 `n_eff >= 4` 且至少 5 个已结算 Call；同一来源和子类别至少 10 位合格作者才形成分位。
- 集中事件按每位 `source + investor_id` 的窗口内最新 Call 去重，至少 3 位作者、主方向占比至少 65%、主方向有效声音至少 2.5。
- 默认比较 Top 10% 和 Top 25%，使用子 Score 及其历史样本强度计算观点权重，不读取 `SV_Global` 或当前平台排名。
- 信号窗口使用自然日，事件在信号日结束后形成，并从下一交易日调整后开盘进入；连续同向交易日合并为一个事件。
- 时间周期子 Score 可导出全部 outcome horizon 供稳健性检查，但“短/中/长周期能力有效”的正式结论必须基于匹配周期，不能从其他周期择优替代。
- 不同子类别、窗口和标的的事件可能重叠；统计结果是信号研究，不等同于含手续费、滑点、仓位和相关性约束的组合业绩。

## Ticker Signal Diagnostics

`web/server/queries/smartVoiceTickerSignals.ts` 在上述派生表之外返回两类只读证据：

| 字段 | 窗口 | 说明 |
|---|---|---|
| `history` | 每个周期/分组最近 260 个交易日 | `weighted_net`、作者数、有效声音、同向度和聚集状态；用于计算约一年尺度的变化分位 |
| `evidence` | 最新信号日向前 45 个自然日 | 观点当日 Score/百分位/置信度、Call 权重与质量、目标价、生命周期、触发/失效条件和口播证据 |

诊断口径：

- 高低 Score 分歧使用同周期 Top/Bottom 的加权净方向差，`weighted_net` 的范围为 `[-1,1]`。
- 周期结构的短端为 1D/5D/20D，长端为 60D/90D/180D；只比较已有数据，不用缺失周期补值。
- 加速/反转比较当前值与约 5 个交易日前的值；`[-0.1,0.1]` 为中性死区，跨越死区后才称为方向反转。
- 目标价/失效条件必须按观点发布日的 `sv_investor_score_asof.percentile` 归组，不能用当前作者排名回填历史观点。
- 目标价在最新日线价格 `0.2–5×` 之外时不进入聚合；已被当前价格穿越的目标保留但标记为“已到达”。

### Ticker Score Overview

标的整体数据在同一容器中切换“市场数据”和“Score 数据”，不得把 Score 看板继续堆叠在市场数据下方。Score 看板默认顶层指标为：

- `Score 转向`：Top 10%/25% 指定观点周期的 `weighted_net` 相对七日前变化，范围限制为 `[-100,100]`；同时显示起止值和可用历史变化分位。
- `变化广度`：最近七日与前七日按 `source + investor_id` 比较，每位作者只保留窗口内最新 Call；显示转多、转空、稳定、新进入和有效作者人数。
- `Score 目标修正`：使用观点发布日 Score、证据质量、Call 权重和时间衰减得到的目标价加权中位数，比较最近七日与前七日。
- `价格-Score 背离`：标准化七日 Score 转向与 20 个交易日价格收益后计算差异，以 `σ` 展示，并给出同期价格变化和历史同级别交易日数量。

顶层指标不得加入跨平台确认度、观点拥挤度、周期迁移或信号可信度。精确数字必须与状态文案、比较过程和样本量一起展示；`Score 转向 +38` 表示观点状态相对七日前提高 38 分，不是上涨概率或预期收益。

## Ticker Decision Lab

`MU`、`NVDA`、`MSTR` 的整体数据可在上述真实证据上做只读决策派生，但不得修改作者 Score：

- **Score 加权目标价**：权重由观点发布日 Score 百分位、置信度、Call 权重、证据质量和时间衰减组成；页面输出加权中位数、多数目标区间、明确目标数和看多权重。
- **观点变化雷达**：比较最近 7 日与前 7 日，按同一作者历史 Call 区分新开、加强、反转、失效和关闭，并显示目标中位数变化。
- **机会/风险诊断**：展示高低 Score 预期差、观点拥挤度、目标价离散度、证据置信度和信号新鲜度。
- **个性化仓位匹配**：读取用户为当前标的保存的可选成本、仓位、方向、周期、目标和止损，仅生成可解释的匹配提示；不得写回 Score 或描述为自动投资建议。
- **投资逻辑生命周期**：用 `kol_viewpoint` 的视角标签拆分最近 7 日与前 7 日的 Score 加权多空结构，并以 `kol_narrative(window=1mo)` 作为可阅读的多空逻辑摘要。
- **作者能力矩阵**：总 Score 与该标的已结算 Call 的命中率、方向超额、样本量和主要风格分开展示；标的表现不得覆盖全局 Score。
- **组合叙事风险**：用户输入 MU/NVDA/MSTR 情景权重后，以三标的真实视角分布计算投资逻辑暴露和集中度。
- **可解释提醒**：仅由公开阈值触发分歧、反转、拥挤、目标价偏离和生命周期提醒，每条提醒必须展示触发原因。

目标价权重必须使用观点发布日的 `sv_investor_score_asof`，不得使用当前排名产生未来信息泄漏。个性化配置只保存在用户浏览器，并与观点流的个性化排序共享同一个标的级配置键。
