# Smart Voice Architecture

Smart Voice 是跨平台作者可信度和观点质量系统，不应该被实现为某个页面的排序函数。

## 文档真源

算法文档位于：

- `docs/smart_voice/GLOBAL_ALGORITHM.md`
- `docs/smart_voice/TWITTER_ALGORITHM.md`
- `docs/smart_voice/YOUTUBE_ALGORITHM.md`
- `docs/smart_voice/REDDIT_ALGORITHM.md`
- `docs/smart_voice/XUEQIU_ALGORITHM.md`
- `docs/smart_voice/TOSS_ALGORITHM.md`

本文件只记录工程边界。

## 目标代码边界

```text
pipeline/domain/smart_voice/
  candidates.py        # 候选观点/作者召回
  evidence.py          # 证据标准化
  settlement.py        # 价格/事件结算
  scoring.py           # 平台内分数和 global score
  ticker_signal_schema.py  # 标的级 SV 信号表
  ticker_signal_scoring.py # 历史时点作者分数/百分位
  ticker_signals.py        # 分层聚集、事件、回测和统计
  indicator_backtest_schema.py   # 发现页指标回测表
  indicator_backtest_logic.py    # 页面/回测共用权重公式
  indicator_backtest.py          # 历史平台排名和四类滚动信号
  indicator_backtest_outcomes.py # 事件、收益、盈亏比和报告
  indicator_backtest_reporting.py # 逐事件、逐原文证据和稳健性导出
  indicator_backtest_casebook.py # 四指标成功/失败案例和原帖链接
  export.py            # web/lib/data/smartVoice.json
  README.md
```

平台专属逻辑留在 `pipeline/platforms/<platform>/`，SV 只消费标准化 evidence。

## 前端消费

前端不重新计算 SV，只消费构建期输出或查询层 view model：

- 作者榜单
- 前/后 10% SV 作者详情页
- 标的详情页 SV 筛选
- 观点流 SV 排序
- Smart Voice 独立页面

前端允许做轻量筛选，例如 Top 25% 区间过滤，但不能改变 SV 分数口径。
`/smart-voice` 使用单视窗工作台，按 Nansen Smart Money 的对象关系组织为三类入口：标的发现、投资者榜和实时观点。标的发现按各来源正式合格池的 Top/Bottom 10% `platformRank` 成员聚合，只展示高 SV 作者净方向明确的集中看多/看空标的，以及高低 SV 方向相反的分歧标的；集中方向至少要求同方向 2 条 call 和 2 位独立 Top 10% 作者，榜单展示 Top 10% 多空 call、同方向作者和加权净方向，不把中段或 Bottom 作者的计数混入。服务端一次读取近 90 天轻量 call 生成 `24H/3D/7D/30D/90D × X/YouTube/Reddit/雪球任意非空组合`，再只为最终入榜的代表性证据读取摘要、原文片段和原始链接；浏览器不接收全量原始 call。投资者榜消费四个平台各自 `platformBands.ranked` 的完整正式排名，并通过 `platformBands.observed` 提供明确标注的观察池；观察池不参与正式榜单、Top/Bottom 分位或静态作者详情生成。实时观点只消费 high/medium confidence 或平台 Top 10% 作者近 60 天的结构化 actionable call，并按来源限额后合并。作者画像沿用独立详情页。Toss 没有正式评分池时不生成占位榜单。

标的发现同时导出一套不参与当前加权排序的作者人数指标：在当前来源组合、窗口、标的和各来源 Top 10% 池内，以 `source + investor_id` 作为平台作者身份，每位作者只保留发布时间最新的 actionable call；由此计算看多作者数、看空作者数、`作者净人数 = 多 - 空` 和 `作者共识度 = 净人数 / 总作者数`。同一作者重复发帖不增加人数；跨平台身份尚未完成实体归并时按不同平台作者计数。

作者净人数突变榜把当前窗口与紧邻的前一等长窗口比较；例如 3D 比较最近 72 小时与此前 72 小时，90D 因此需要服务端读取 180D 轻量 call。`净变化 = 当前净人数 - 前期净人数`，`突变幅度 = 净变化 / max(当前作者总数, 前期作者总数, 1)`；幅度保留正负，方向反转时可超过 100%。`|净变化| >= 3`、`|突变幅度| >= 50%` 且前后两期各至少 3 位作者才标记为突变。榜单先列突变标的，再按幅度绝对值、净变化绝对值排序；一般变化继续列出但不冒充突变。右侧同时展示两期代表性原文证据。

该映射只借鉴信息架构。SV 衡量公开观点的历史结算表现，不等同于持仓、资金流、买卖成交或链上钱包活动；界面和查询层都不得将 SV 描述为真实 Smart Money 资金行为。
作者详情页只解释已导出的分数和已结算证据：`smartVoice.json` 提供 SV、排名、分段分、集中度和风格分类，
`web/server/queries/smartVoiceInvestorQueries.ts` 读取 `sv_call` / `sv_call_settlement` / `sv_call_candidate`
展示代表性加分和扣分 call。前端不得在详情页重新计算 SV。

## 标的级 SV 信号

`pipeline.manage sv-ticker-signals` 把作者 SV 转成可回测的标的信号：

1. 每个观点日仅使用该日之前已结算的观点重建作者分数和百分位，禁止未来结算泄漏。
2. 按 `Top/Bottom 10%/25%`、观点周期和 7 个自然日窗口聚合独立作者的多空方向。
3. 至少 3 位作者、同向占比至少 65%、有效声音数至少 2.5 才形成聚集事件。
4. 事件从下一交易日开盘入场，按 1/5/20/60/90/180 个交易日结算，并计算相对 SPY 的方向性超额、命中、MFE、MAE 和峰值时间。

首批产品灰度只在 `MU`、`NVDA`、`MSTR` 标的详情页展示；其他标的继续使用原 SV 投资者模块。全市场历史时点评分仍可作为百分位比较基线。

Bottom 分组不是反向策略：其作者原始方向同样按“说多后涨、说空后跌”计为命中。Top/Bottom 任一分组少于 10 个事件时，前端只展示原始观察值和 Wilson 95% 命中区间，不做分组优劣结论；持有期重叠的事件也不等同于独立样本。

`pipeline.manage sv-indicator-backtest` 单独回测发现页的加权净强度、作者净人数、作者净人数突变和高低 SV 分歧。它扩展 `sv_investor_score_asof` 保存历史平台内正式池排名，按 1/3/7/30/90 个自然日窗口生成信号，把连续同向交易日合并为事件，并从下一交易日开盘计算 1/5/20/60/90 日方向收益和相对 SPY 超额；价格使用调整后收盘和同因子调整的开盘。输出写入 `sv_indicator_*` 四表及 `data/reports/sv_indicator_backtest.csv`；该流程不修改当前作者 SV 或页面榜单。

`pipeline.manage sv-indicator-report` 不重建历史信号，直接从现有结果导出逐事件长表、逐 Call 原文证据、紧凑证据和稳健性分层。分层覆盖标的、月份、方向、信号强度、前后时间段、证据审计、10/25bps 成本及同标的同策略不重叠持仓；证据层标记卖出 Put 与看空标签冲突、期权标的方向未解析和条件入场，供人工复核而不是事后删样本。报告同时固定 `all / 7D / 20D` 口径，为四个指标各选相对 SPY 超额最好 5 例和最差 5 例（每侧标的不重复），生成只引用实际参与指标计算 Call 的 `sv_indicator_casebook.md`。

标的页在离线结果之上提供四个只读诊断，不改写 SV 分数：

- **高低 SV 分歧**：比较同周期 Top/Bottom 分组的 `weighted_net`，区分同向确认、高 SV 看多/低 SV 看空和相反组合；同时展示有效声音覆盖，低覆盖不视为强信号。
- **SV 周期结构**：Top 分组按 1D/5D/20D 与 60D/90D/180D 聚合短端、长端净方向，识别全周期一致、短多长空、短空长多及期限曲线陡峭化。
- **信号加速与反转**：读取同分组/周期最近 45 个交易日序列，以近 5 个交易日的净方向变化识别加速、衰减和穿越中性区间的反转。
- **目标价与失效条件**：读取近 45 日 `sv_call`，按观点当日的历史时点百分位归入 Top/Bottom，聚合目标价中位/IQR、方向构成、已到达目标及明确触发/失效条件。目标价只保留最新日线价格 `0.2–5×` 范围，缺失条件不补 mock。

`web/features/ticker/components/SmartVoiceDecisionSuite.tsx` 在同一真实 view model 上提供可删选的决策实验模块：SV 加权目标价散点分布、7 日观点生命周期变化雷达、高低 SV 预期差/拥挤/离散度/证据置信度、投资逻辑生命周期、跨平台扩散、作者能力矩阵、三标的组合叙事风险、可解释提醒，以及复用观点流标的级配置的个性化仓位匹配。权重与仓位逻辑集中在 `smartVoiceDecisionLogic.ts`，视角生命周期、扩散、组合暴露和提醒阈值集中在 `smartVoiceResearchLogic.ts`；构建期 SQL 仍只放在 `web/server/queries/smartVoiceTickerSignals.ts`。这些模块不生成新 SV、不修改离线表，也不把匹配度描述为买卖建议。

## 数据要求

每个平台接入 SV 前必须提供：

- 作者唯一 ID
- 内容唯一 ID
- 标的映射
- 发布时间
- 原始观点或摘要
- 明确 stance 或可推导 stance
- 质量/相关性输入
- 可结算目标或观点方向

缺少结算条件的平台可以先作为 discovery source，不直接进入正式 SV 排名。

## YouTube 作者池阶段

YouTube 使用版本化 500 人 creator pool。platform 层按 uploads playlist 回填一年视频并维护 checkpoint；domain 层以 `youtube-title-v3` 规则映射美股 ticker；Smart Voice 只消费最新池内、当前映射版本且置信度 `>= 0.90`、频道粉丝 `>= 2000`、视频时长 `> 60` 秒的 evidence。候选、全文队列、结算与评分共用该资格过滤；`--only` 与 `--youtube-since-days` 同步约束候选、全文和抽取阶段。LLM 按作者均衡分配 20 至 40 条抽取预算，正式资格仍由 `n_eff >= 4` 且 `settled_calls >= 5` 决定。抽取默认按 Qwen LOW、DeepSeek low、Gemini 回退，可用 `SV_EXTRACT_PROVIDERS` 调整，并在 `sv_call.model` 记录实际成功模型。粉丝数只作资格门槛，频道终身视频量和播放量只参与发现或候选排序，不直接增加 SV。

## 雪球作者池阶段

雪球先建立 discovery pool，再进入 SV evidence：首版按粉丝 ≥500（或认证）且历史发帖 ≥300 召回，隔离明显媒体/机构发布者，正式池取 Top 300 位创作者，其余作为 warm reserve。随后按作者回填一年帖子；`sv-v0 --source xueqiu --stage candidates` 默认设置完整性闸门，正式池全部 `done` 前拒绝召回，完成后只消费 selected creator 的原创、美股映射帖子。只有满足美股相关帖子、可结算观点和 `n_eff` 门槛的作者才进入正式雪球 SV 池。粉丝、认证和平台历史发帖数只参与发现，不参与 SV 准确性得分。
