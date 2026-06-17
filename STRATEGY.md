# Prismo 产品策略：aha moment 与主打功能

> 目的：综合调研主流美股网站，定位 Prismo 作为「Reddit 美股垂类分析站」的**独有价值**，据此优化 UX 并确定主打功能。核心原则：**最大化利用 Reddit 社区信息**去满足投资者的真实需求。

## 一、竞品全景（19 个美股站归类）

| 类别 | 代表 | 提供什么 |
|---|---|---|
| 行情 / 新闻 / 图表（已商品化） | Yahoo Finance、MarketWatch、CNBC、Bloomberg | 报价、新闻、自选股 |
| 基本面 / 估值 / 评级 | Morningstar（护城河+公允价值）、GuruFocus（GF Value）、Finviz（筛选器+热力图）、Seeking Alpha（Quant 评级） | 财务、估值、评分 |
| 官方文件 | SEC EDGAR | 10-K/10-Q/8-K/13F/Form 4 原始申报 |
| 分析师聚合 & 可信度 | TipRanks（分析师排名 + Smart Score + 目标价）、Seeking Alpha（众包文章） | 把"谁说的、准不准"量化 |
| 聪明钱 / 机构 / 国会 | WhaleWisdom、Dataroma、InsiderMonkey（13F）、StockCircle（guru+国会）、QuiverQuant（国会交易=招牌） | 跟踪机构/名人/议员持仓 |
| 宏观 | FRED | 美联储宏观数据 |
| **社交 / 散户情绪（Prismo 的赛道）** | StockTwits、QuiverQuant（WSB 提及分）、**ApeWisdom / SwaggyStocks / YoloStocks** | **Reddit/WSB 提及量 + 简单词袋情绪** |

- trackserenity.xyz：未检索到公开信息（疑似新/小众），暂存疑、不作为参照。

## 二、关键洞察：现有 Reddit 工具只回答「多吵」，不回答「在吵什么、靠不靠谱」

- **ApeWisdom**：被动看板，~30 个子版每小时提及量，**无告警、无语义分析、无自定义**。被当作 WSB 情绪的"参考数据集"，但仅止于计数。
- **SwaggyStocks**：实时 WSB 词袋情绪（多/空/中）、Max Pain、期权工具——刻意不用重型 NLP，所以也只有"量+粗情绪"。
- **QuiverQuant**：把 WSB 降维成一个"Meme Score"提及分，只是它众多另类数据（国会/内部人/对冲基金/游说）中的**一个信号**，并非深度 Reddit 分析。

→ 它们都把 Reddit 最有价值的东西——**长篇 DD（深度研究帖：几千字的真实多空论证、催化剂、数字）——丢掉了，只留下一个"提及计数器"。**

→ **空白区**：没有任何工具把 Reddit 的**「论点本身」结构化**——它在说什么、质量如何、谁在说、可不可信、信念在如何变化。

## 三、aha moment

> **对任意一只股票，立刻看到 Reddit 上最聪明的散户研究者*真正在讲的多头逻辑 ⚔ 空头逻辑*——AI 蒸馏、带原帖出处、按作者可信度加权、并随时间追踪信念转向——让你比大众、也比华尔街更早抓住论点。**

体温计（提及量，ApeWisdom/Quiver/StockTwits 给的）vs 研究分析师（结构化论点 + 质量 + 可信度）。**后者只有 Reddit 有素材，且现有工具都不做。**

## 四、投资者「待办任务」(JTBD) → 功能映射

1. **我持有/关注 X，社区的论点是什么、我漏了什么？** → 个股情报页（Ticker DD Digest）= **主打**
2. 什么在"早期"真正积累信念（不只是量在涨）？ → 异动 / 新兴信号（信念+质量上升）
3. 这条看法靠谱吗？谁是可信的声音？ → 作者可信度（按战绩/质量排名，类比 TipRanks 排分析师）
4. 大众注意力整体往哪走？ → Mindshare / 市场情绪（已有）

## 五、主打功能：个股情报页「Reddit DD, distilled」

把现有 `/ticker/[symbol]` 升级为旗舰「情报报告」：

- ⚔ **多头论点 vs 空头论点**：AI 从真实 DD 帖蒸馏，每条带原帖链接 + 情绪。
- 📈 **信念趋势**：多空随时间（量 + 质 加权），一眼看转向。
- 📄 **高质量 DD 帖**：按 quality 排（深度研究，不是 meme 热度）。
- 🎙 **可信声音**：哪些有战绩 / 高质量的作者在讨论它。
- 🗓 **催化剂 / 关注日期**：社区在盯的事件。
- 🧭 上下文：mindshare 排名、整体情绪、来自哪些子版。

> 现有数据已支撑大部分：`item_analysis` 的 `bull_points/bear_points/quality_score/tldr/themes`、`ticker_rollup` 小时序列、作者榜。主要是**聚合 + UX 升级**，后端改动可控。

## 六、UX 布局优化（围绕主打）

- **头部第一入口 = 搜索/直达任意个股的 Reddit 情报**（直接服务 JTBD-1）。
- **首页按 JTBD 重排**：搜索条 → 异动（早期信念） → Mindshare/情绪（总览） → 当前高质量 DD 帖流（非 meme）。
- **导航**：看板 / 个股情报（搜索入口） / 异动 / 叙事 / 作者可信度。
- **个股页 = 核心产品面**（情报报告），其余页面都是导流到它的发现层。

## 来源（节选）
- ApeWisdom — apewisdom.io ；SwaggyStocks — swaggystocks.com
- QuiverQuant — quiverquant.com ；StockCircle — stockcircle.com
- （其余为公开常识：Yahoo/Bloomberg/Morningstar/Finviz/SEC EDGAR/Seeking Alpha/TipRanks/Fool/FRED/StockTwits/WhaleWisdom/Dataroma/InsiderMonkey）
