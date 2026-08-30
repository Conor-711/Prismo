# bSmart iOS MVP 市场需求与竞品研究

> 研究日期：2026-08-03
> 研究范围：美国个人股票投资者、持仓智能、社交投资信息、链上 Smart Money、iOS 投资应用
> 结论性质：基于公开一手资料、竞品官方说明及 App Store 近期评论的桌面研究，不替代用户访谈与付费实验。

## 1. 执行结论

市场已经验证了三个独立需求：

1. 用户希望系统主动解释“我的持仓为什么变化”。Robinhood 的持仓摘要已经有接近 100 万客户使用。
2. 年轻投资者大量使用社交媒体做投资决策，但同时面临信任、诈骗和信息质量问题。
3. 用户愿意追踪可验证的真实仓位和链上 Smart Money；AfterHour、Nansen 均证明了这一行为，但两者分别偏向封闭社区和 Crypto/交易终端。

bSmart 的可占据空白不是任何单项数据，而是：

> **针对用户真实持仓，把链下 Smart Account、链上 Smart Money、市场与基本面信息合成为少量、可追溯、可行动的投资事件。**

竞争边界需要重新认识。Nansen 已于 2026 年支持 Hyperliquid 上的股票与指数永续合约、Smart Money 排名、钱包表现和交易。因此，“提供股票链上资金”本身已经不足以构成壁垒。bSmart 的壁垒应来自：

- 跨平台链下观点的历史验证；
- 链下观点与链上真实仓位的确认/背离；
- 用户成本价和持仓占比带来的个性化影响判断；
- 高精度事件筛选和低噪声提醒；
- 每条结论对应的证据链与原始来源。

## 2. 市场需求证据

| 事实 | 数据 | 产品含义 |
| --- | --- | --- |
| 股票投资是广泛市场 | 2025 年 62% 美国成年人持有股票；家庭收入 10 万美元以上人群为 87% | 市场足够大，但 62% 不能直接当作 bSmart 的 TAM |
| 主动投资者规模可观 | 2024 年 34% 美国成年人持有退休账户之外的证券投资；其中 80% 持有个股 | MVP 聚焦个股持仓是合理入口 |
| 年轻投资者高度依赖社交信息 | 18-34 岁投资者中，60% 使用社交媒体/论坛做投资决策，61% 会依据 finfluencer 推荐 | Smart Account 解决的是强需求，不是边缘功能 |
| 社交信息存在明显可信度问题 | FINRA 研究显示社交媒体用户和 finfluencer 关注者更易遭遇诈骗，且投资知识并未同步提高 | 产品必须展示历史验证、证据来源和不确定性，而不是只生成 AI 结论 |
| 持仓感知摘要已有真实使用 | Robinhood Cortex Digests 截至 2026 Q1 已被接近 100 万客户使用 | “我的持仓发生了什么”已得到行为验证 |
| 真实仓位可提升社交信任 | AfterHour 官方称有 20 万以上投资者/交易者、4 亿美元以上连接组合资产、690 万以上交易信号 | 用户确实重视“说了什么”之外的仓位证据 |
| 专家评价和组合分析已有需求 | TipRanks 称 Smart Portfolio 有超过 50 万用户 | 作者/分析师历史表现与持仓分析已有成熟需求 |

### 2.1 不能直接得出的结论

- 公开资料不能可靠计算“持有热门美股、依赖社交媒体、愿意连接持仓、又关注链上股票”的精确交集，因此暂不建议制作夸大的 TAM 数字。
- 竞品用户数和 App Store 评价数不能证明付费意愿。
- Hyperliquid 股票永续合约是衍生品价格和仓位证据，不等于美股现货持仓，也不代表所有美股投资者的资金行为。

## 3. 目标用户的真实张力

FINRA 数据显示，社交投资信息使用率随组合规模上升而下降：组合低于 5 万美元的人群中，48% 使用社交媒体、47% 关注 finfluencer；组合达到 50 万美元以上时，比例降至 20% 和 15%。

这意味着：

- 年轻、社交驱动的投资者需求最强，但通常更价格敏感；
- 资产更高的投资者更可能付费，但不能用“finfluencer 跟单”作为主要价值表达；
- 产品应以“持仓事件监控”作为主叙事，以 Smart Account 和 Smart Money 作为证据层。

建议 MVP 的首要切入人群是：

> 持有热门科技或 Crypto 关联美股、会从 X/YouTube/Reddit 获取观点、没有时间持续核验信息的主动型个人投资者。

## 4. 竞品格局

| 竞品 | 已验证能力 | 缺口/限制 | 对 bSmart 的意义 |
| --- | --- | --- | --- |
| Robinhood Cortex | 基于账户持仓生成新闻、市场、分析师与事件摘要；Robinhood Social 开始提供验证交易 | 绑定 Robinhood 生态；没有跨平台 Smart Account 历史评分，也没有股票链上 Smart Money 证据 | 最直接验证“持仓感知事件摘要”，也是提醒体验的主要标杆 |
| Public Alpha | 组合/标的页面 AI 研究、市场异动解释、财报摘要、新闻和社交情绪 | 绑定 Public 生态；AI 输出需用户自行核验；缺少外部作者历史能力与链上资金确认 | 证明 AI 解释已经趋于基础设施，单纯聊天或摘要不是差异化 |
| Seeking Alpha | 持仓新闻与评级提醒、作者文章、量化评级、风险警告 | 内容和评级中心，用户仍需主动筛选；没有链上资金 | bSmart 不应复制文章库，应只保留与持仓事件直接相关的证据 |
| TipRanks | 分析师/博主历史评级、目标价、Smart Score、组合分析 | 偏传统分析师与结构化研究；缺少实时跨平台社交观点和链上资金 | Smart Account 必须比简单命中率更重视时点、标的、周期和可审计证据 |
| AfterHour / Blossom | 券商连接、验证仓位/交易、社交讨论和信号 | 主要验证自有社区成员，容易退化成 Feed；同步稳定性和内容噪声是风险 | bSmart 不应自建社交网络，而应评分外部作者并压缩为事件 |
| Delta | 多账户组合聚合、成本与组合分析、AI/资产分析 | 偏追踪工具，缺少观点可信度和 Smart Money | 组合同步与稳定性是基础门槛，不是可延后补救的体验细节 |
| Stocktwits | 大规模股票话题实时 Feed | 噪声、机器人、操纵和内容质量问题明显 | 不应追求帖子数量；只呈现高质量作者和转向事件 |
| Nansen | Hyperliquid 钱包、PnL、仓位、Smart Money、股票/指数永续、提醒和交易 | Crypto-first；价格高；缺少链下 Smart Account 和券商持仓成本语境 | 是 Smart Money 的直接竞品；bSmart 必须在跨证据和个人持仓解释上胜出 |

### 4.1 竞争空白

目前没有一个已调研产品同时完整提供：

1. 跨平台投资作者历史评分；
2. Hyperliquid 股票相关 Smart Money；
3. 用户美股持仓、成本价和仓位占比；
4. 链下观点与链上仓位的确认/背离；
5. 以少量事件而非 Dashboard/Feed 交付；
6. 每个 AI 结论可回溯到原帖、完整口播、链上钱包和行情。

这是基于所审查官方功能资料作出的竞争推断，不代表所有竞品未来都不会快速补齐。

## 5. iOS 市场信号

以下为 2026-08-03 通过 Apple Search API 获取的美国区数据。评价数只能作为安装和使用规模的方向性代理，不能视为 MAU。

| App | 评分 | 评分数 |
| --- | ---: | ---: |
| Robinhood | 4.29 | 4,794,707 |
| Stocktwits | 4.80 | 166,407 |
| Seeking Alpha | 4.76 | 125,556 |
| Public | 4.68 | 84,302 |
| Autopilot | 4.62 | 20,378 |
| TipRanks | 4.77 | 18,426 |
| Delta | 4.71 | 11,367 |
| Blossom | 4.75 | 2,843 |
| AfterHour | 4.54 | 806 |
| Nansen AI | 4.23 | 22 |

结论：iOS 上的投资研究、组合追踪和社交投资都有真实需求，但新兴的链上智能移动产品仍处于早期。bSmart 不能以“功能更多”取胜，需要在首屏价值和提醒质量上更快让用户感知收益。

## 6. App Store 近期评论样本

方法：抽取 9 个竞品各自最近 50 条美国区 App Store 评论，共 450 条；其中 265 条为 1-3 星。对低星评论进行关键词辅助编码，类别可重叠，仅用于发现方向，不用于推断总体比例。

| 低星评论问题 | 命中数 | 主要集中竞品 | 含义 |
| --- | ---: | --- | --- |
| 稳定性、加载、账户连接或同步 | 94 | Delta、Autopilot、AfterHour、Seeking Alpha | 持仓数据一旦不稳定，产品核心信任立即失效 |
| 价格、广告、付费墙或强制升级 | 94 | Delta、TipRanks、Seeking Alpha、Autopilot | 用户愿意付费，但反感基础能力被突然锁住及持续推销 |
| 数据准确性、延迟或可信度 | 43 | AfterHour、Stocktwits、Robinhood/Public | 投资产品必须明确数据时间、来源和限制 |
| 社区噪声、Spam、机器人或操纵 | 30 | Stocktwits、AfterHour | 不做社区 Feed 是正确方向 |
| 隐私、安全、提现或账户控制担忧 | 29 | Robinhood、Public、Delta | 券商连接必须明确只读权限、数据用途和可撤销性 |

更值得注意的分组信号：

- Delta、Autopilot、AfterHour 的 107 条低星评论中，56 条提到稳定、连接、同步或加载问题；
- Seeking Alpha、TipRanks 的 46 条低星评论中，23 条提到价格、广告或付费墙；
- AfterHour、Stocktwits 的 61 条低星评论中，24 条提到社区噪声、Spam、机器人或操纵。

## 7. 需求优先级

### P0：MVP 必须验证

#### 1. 持仓相关的重要变化

不是市场新闻流，而是只回答：

- 我的哪只持仓发生了变化；
- 变化来自谁或什么资金；
- 与我的成本和仓位有什么关系；
- 为什么现在值得看。

#### 2. 低噪声主动提醒

立即提醒仅保留：

- 高分 Smart Account 新观点或明确转向；
- 高表现 Smart Money 显著建仓、减仓或反向；
- Smart Account 与 Smart Money 确认/背离；
- 重大基本面事件与两类证据发生联动。

其余进入每日摘要。提醒应支持频率、重要度和静默时段，避免产品变成新的信息噪声源。

#### 3. 可追溯的信任设计

每个事件必须展示：

- 结论；
- 对用户持仓的影响；
- 关键数字及其变化基线；
- 原帖/口播/链上交易/新闻来源；
- 数据更新时间；
- 不确定性和衍生品限制。

Smart Account 是经过历史评估的“观点作者”，除非有真实账户证据，否则不能写成“已验证持仓”。Smart Money 才是公开链上仓位行为。

#### 4. 数据可靠性

手动持仓 MVP 可以降低券商连接风险，但事件数据仍需满足：

- 同一事件幂等去重；
- 明确延迟状态；
- 证据缺失时降级而不是编造；
- 数据刷新失败可见；
- 推送与 App 内事件一致。

### P1：形成差异化

1. Smart Account 与 Smart Money 的确认/背离。
2. 根据成本价和持仓占比调整事件重要度，而不是给出自动交易指令。
3. 休市期间使用 Hyperliquid 股票永续观察可能的重新定价，同时明确其衍生品和流动性风险。
4. 从事件进入精简研究页，查看完整证据、历史观点和链上仓位变化。
5. 高分作者或高表现钱包首次集中提及的新标的，作为“发现”而非首页主流程。

### P2：不应进入第一版

- 自动交易和 Copy Trading；
- 自建社区 Feed；
- 全市场覆盖；
- 完整链上终端；
- 无持仓关系的泛化新闻、图表和帖子列表。

## 8. 定位与信息架构建议

### 产品主张

不建议：

> 跟踪最聪明的投资博主和链上钱包。

建议：

> **bSmart 持续监测你的美股持仓。当可信作者、真实链上资金或关键事件发生变化时，及时告诉你发生了什么、为什么与你有关，并给出可核验的下一步研究建议。**

### 四个一级场景

1. **Today**：按用户影响排序的少量事件。
2. **Portfolio**：持仓健康、今日变化和即将发生的催化剂。
3. **Research**：标的证据页，聚合高质量观点、Smart Money 和市场上下文。
4. **Smart**：Smart Account 与 Smart Money 的发现、排名和追踪。

叙事页面可以保留，但作为机会发现和研究入口，不应与持仓事件争夺首页优先级。

## 9. 价格与付费假设

当前公开价格锚点：

- Robinhood Cortex Digests 随 $5/月 Gold 提供；
- Public Premium 为 $10/月；Public Alpha 对券商用户免费，非券商用户为 $1/周；
- Delta PRO 为 $4.49/月（年付）或 $6.99/月，PRO+ 为 $8.99/月（年付）或 $13.99/月；
- Nansen Pro 为 $49/月（年付）或 $69/月。

因此 bSmart 的 $10-$20/月方向有市场参照，但必须证明它比普通组合追踪多出的价值：

- 跨券商；
- 跨平台 Smart Account；
- 股票链上 Smart Money；
- 持仓成本和仓位相关的事件优先级；
- 明显低于人工研究的信息成本。

建议首轮只做价格实验，不立即锁定：

- A 组：$9.99/月，降低首次付费阻力；
- B 组：$14.99/月，测试跨证据事件的溢价；
- 年付折扣在确认月付留存后再开放，避免用折扣掩盖产品价值不足。

## 10. 建议的 MVP 验证

### 实验一：事件价值

招募 30-50 名目标用户，手动添加 3-10 只持仓，运行两周。

验证：

- 用户是否打开持仓事件，而不是泛化市场内容；
- 哪类事件被标为“有用”“太晚”“噪声”或“不可理解”；
- Smart Account、Smart Money、确认/背离四类证据各自的打开与保存行为；
- 用户是否从事件进入原始证据。

### 实验二：提醒容忍度

随机测试：

- 仅高优先级即时推送；
- 高优先级即时推送 + 每日摘要。

观察通知关闭、App 删除、事件打开和次周留存，找到频率上限。

### 实验三：付费价值

在用户阅读至少 5 个有效事件后展示真实价格页，测试 $9.99 与 $14.99。不能只问“愿不愿意付费”，应记录进入支付、试用和续费行为。

### MVP 最关键的未决问题

1. 传统美股用户是否会把 Hyperliquid 股票永续仓位视为有用的领先证据。
2. 用户是否愿意手动输入成本价和仓位占比，以及是否因此认为提醒明显更相关。
3. 哪一种事件能形成每周稳定价值，而不依赖极端行情。
4. Smart Account 历史评分能否显著提高用户对社交观点的信任。
5. 用户愿意为何种“减少研究时间”或“降低遗漏风险”的结果付费。

## 11. 资料来源

- [Gallup：2025 年美国股票持有率](https://news.gallup.com/poll/266807/percentage-americans-owns-stock.aspx)
- [FINRA Foundation：2024 NFCS 投资者报告](https://finrafoundation.org/InvestorReport2024)
- [FINRA Foundation：Social Media & Finfluencers，2026-04](https://www.finrafoundation.org/sites/finrafoundation/files/2026-03/FINRA_Foundation_Research_Brief_Social_Media_Finfluencers.pdf)
- [SEC Investor Advisory Committee：Finfluencer 建议](https://www.sec.gov/files/approved-finfluencer-recommendations-20241210.pdf)
- [Robinhood 2026 Q1 业绩与 Cortex 使用数据](https://investors.robinhood.com/news-releases/news-release-details/robinhood-reports-first-quarter-2026-results)
- [Robinhood Cortex Digests](https://robinhood.com/us/en/support/articles/cortex-digests/)
- [Public Alpha](https://help.public.com/en/articles/9354354-what-is-alpha)
- [Public Premium](https://help.public.com/en/articles/6097323-public-premium)
- [Seeking Alpha Portfolio Tracker](https://help.seekingalpha.com/what-are-the-key-features-of-seeking-alphas-portfolio-tracker)
- [TipRanks Smart Portfolio](https://www.tipranks.com/news/labs/the-smartest-way-to-analyze-your-portfolio-just-got-smarter)
- [AfterHour 官方数据](https://www.afterhour.com/)
- [Delta PRO / PRO+](https://delta.app/academy/post/introducing-delta-pro-pro-more-power-more-choice)
- [Nansen：Hyperliquid Smart Money 与股票永续](https://nansen.ai/post/what-are-tokenized-stocks-and-how-do-you-trade-them)
- [Nansen Pro 价格](https://academy.nansen.ai/en/help/articles/9412804-about-nansen-pro)
- [Hyperliquid HIP-3](https://hyperliquid.gitbook.io/hyperliquid-docs/hyperliquid-improvement-proposals-hips/hip-3-builder-deployed-perpetuals)
- [Apple Search API](https://itunes.apple.com/search?term=Robinhood&country=us&entity=software&limit=1)
- [Apple App Store Customer Reviews RSS](https://itunes.apple.com/us/rss/customerreviews/page=1/id=938003185/sortby=mostrecent/json)
