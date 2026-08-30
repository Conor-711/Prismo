# Smart Account Jobs

`pipeline.jobs.smart_voice` 是 Smart Account 相关批处理工作流入口。

当前覆盖：

- X 推文情绪打分。
- X 推文与 ticker/topic 硬匹配。
- KOL 每日净情绪、讨论度、新增 KOL。
- 散户每日净情绪、讨论度、新增散户。
- 标的详情页整体数据派生信号导出。
- Score 价格历史回填。
- Smart Account v0 候选召回、LLM 结构化、结算、评分、导出；雪球候选默认等待版本化正式作者池一年回填全部完成。
- 标的级历史时点 Score 百分位、观点聚集事件与无未来数据回测；首批详情页消费 `MU`、`NVDA`、`MSTR`。
- Client API Smart Account 投影：直接读取 Web 排名真源 `sv_investor_score` 与观点真源 `sv_call`，生成
  `smart-accounts.json`、Top 25% 实时池使用的 `smart-account-updates.json`，以及全体正式作者详情使用的
  `smart-account-evidence.json`；每位作者按标的汇总已结算正向 Score 贡献，保留累计加分最高的 3 个代表标的，
  每个标的最多附带 10 条加分观点及真实 OHLC 落点。该过程不重算 Score 或创建新作者池。
- Hyperliquid HIP-3 TradFi Smart Money：批处理支持动态市场目录、地址 fills 回填、独立 Onchain Score、标的仓位/资金流聚合和静态导出；持续任务 `hyperliquid-smart-money-live` 订阅全量公开 TradFi 成交，以观察成交额排序的最近 30 天 top-500 高活跃候选池控制补数边界，将活跃 fills、历史补齐与全 DEX 账户画像拆为独立后台通道，只有完整历史账户才能进入正式评分，并按分钟原子发布 Smart Money、movement、ticker intelligence 和 portfolio signal 集合及实时性/完整度健康文件。链上地址不进入社媒作者榜。

CLI 不应直接导入旧 `pipeline.analyze.*` 实现。后续拆分时，Score 算法、评分和跨平台聚合规则应继续沉淀到 `pipeline.domain.smart_voice`。
