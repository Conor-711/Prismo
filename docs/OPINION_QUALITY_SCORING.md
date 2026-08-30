# Opinion Quality Scoring

本文件定义 bSmart 标的详情页“高质量”观点筛选的产品语义、评分维度、默认算法与后续优化接口。它服务于跨人员协作：产品、标注、数据 pipeline、前端都应使用同一套概念讨论“高质量”。

## 目标

“高质量”不是“相关度最高”，也不是“最长文本”。它表示：

> 值得投资者客户花时间点开阅读的观点。

客户希望看到的观点通常具备以下价值之一：

- 有信息量：提供事实、数据、业务变化、财报信息、产业信息、资金动向。
- 有目标价或价位区间：包含目标价、买入区间、卖出区间、支撑位、压力位、估值区间。
- 有逻辑性：有明确因果链，而不是只有涨跌结论。
- 有新奇性：提供少见角度、信息差、反常识判断、非主流叙事。
- 有严谨性：说明假设、风险、反方条件、时间窗口、数据来源。

很少有单条帖子能同时满足全部要求，所以筛选必须宽松：只要某个维度强，或多个维度中等，就可以进入“高质量”集合。

## 非目标

- 不用相关度决定是否高质量。相关度应参与排序，不参与质量准入。
- 不把互动量当作质量本身。互动量可作为 tie-breaker，不应作为核心质量依据。
- 不把长文本等同于高质量。长文本只说明可能有信息密度，需要结合结构和内容判断。
- 不要求所有观点都可操作。严谨的反方观点、风险提示、信息差也有客户价值。

## 输入字段

当前前端与 pipeline 可使用以下字段估算质量：

- `quality_score`: 现有离线质量分，可作为弱参考。
- `reason`: AI 提炼出的判断理由。
- `points`: AI 提炼出的要点数组。
- `judgment`: 结构化价位与周期，包括 `buyLo/buyHi/sellLo/sellHi/horizon/bucket`。
- `viewpoints`: 观点视角，如 `valuation/growth/competition/management/macro/catalyst/flows/other`。
- `orig/text/trans/quote`: 原文、展示文本、译文、关键原话。
- `ytDigest`: YouTube 投资者摘要和章节，可作为提取事实、逻辑、价位、风险的内容来源。
- `ytSegments`: YouTube 口播段落，可作为提取事实、逻辑、价位、风险的内容来源。
- `source`: 来源平台。
- `action_type/is_actionable`: 买入、卖出、加仓、做空等可操作标签。

`relevance_score` 不参与高质量准入，只用于排序。

注意：YouTube 的口播是否已经完整处理，属于数据处理状态，不属于质量评分因子。当前没有完整口播时，不应因为 `ytSegments` 为空而扣分；未来口播补全后，也不应因为“有完整口播”本身加分。质量分只看从摘要、章节、口播、正文中实际提取出来的投资价值。

## 评分维度

每条观点计算 5 个子分，范围 0-100。

### 1. 信息量 `infoScore`

衡量内容是否包含客户不知道或需要复盘的信息。

高分特征：

- 明确数据、财报、营收、利润率、订单、现金流、估值倍数。
- 行业/公司/产品/监管/宏观信息。
- 作者引用具体事件、公告、会议、报告、交易行为。
- YouTube 摘要、章节或口播中提取出具体事实、数据、业务变化或产业信息。

低分特征：

- 单纯“涨了/跌了/加油/害怕”。
- 只有情绪或表态，没有新信息。
- 纯新闻标题且没有作者解读。

### 2. 目标价与价位 `priceTargetScore`

衡量是否提供客户可直接参考的价格框架。

高分特征：

- 明确目标价、买入价、卖出价、支撑位、压力位。
- 明确区间，例如 `$120-$140`、`80 以下分批买`。
- 包含周期或条件，例如 “财报后”“6 个月”“跌破 XX 失效”。

低分特征：

- 只有“看多/看空”。
- 只有“会涨/会跌”，没有价位或条件。

### 3. 逻辑性 `logicScore`

衡量是否存在可理解的推理链。

高分特征：

- 有“因为 A，所以 B”的因果链。
- 有 2 条以上可归纳的 points。
- 论点和结论一致，能解释为什么会看多/看空/观望。

低分特征：

- 只有结论，没有理由。
- 只是复制新闻，没有作者判断。
- 观点前后矛盾。

### 4. 新奇性 `noveltyScore`

衡量观点是否提供非共识角度或信息差。

高分特征：

- 反常识判断。
- 小众但合理的变量。
- 跨市场/跨区域信息差。
- 从管理层、供应链、竞争格局、资金流等角度提出新解释。

低分特征：

- 重复市场共识。
- 泛泛讨论热门叙事，没有增量。

### 5. 严谨性 `rigorScore`

衡量观点是否足够负责。

高分特征：

- 明确假设、风险、反方条件。
- 提到失效条件、时间窗口、仓位控制。
- 引用来源或数据。
- 对不确定性有承认。

低分特征：

- 绝对化喊单。
- 没有依据的情绪化表达。
- 把传闻当事实。

## 总分

默认总分：

```ts
customerQualityScore =
  infoScore * 0.25 +
  priceTargetScore * 0.20 +
  logicScore * 0.25 +
  noveltyScore * 0.15 +
  rigorScore * 0.15
```

## 通过规则

推荐使用宽松准入：

```ts
passesHighQuality =
  customerQualityScore >= 45 ||
  max(infoScore, priceTargetScore, logicScore, noveltyScore, rigorScore) >= 75 ||
  count(scores >= 55) >= 2
```

含义：

- 总体中等以上可以通过。
- 单一强价值可以通过，例如清晰目标价。
- 两个中等价值可以通过，例如有信息量 + 有逻辑。

## 当前前端启发式

在 pipeline 尚未产出 5 个子分前，前端可用以下启发式估算：

### 信息量

加分来源：

- `points.length >= 2`
- `ytDigest` 或 `ytSegments` 中提取出具体事实、数据、业务变化、产业信息、资金动向
- 文本包含财报、营收、利润率、订单、现金流、估值、竞争、监管、AI、数据中心、降息等信息词
- 正文长度达到一定阈值，但不能单独决定通过

不加分/不扣分：

- `ytSegments` 是否存在或是否完整，不直接影响质量分。
- `ytDigest` 是否存在，不直接影响质量分；只有摘要中提取出的有效内容才参与评分。

### 目标价与价位

加分来源：

- `judgment.buyLo/buyHi/sellLo/sellHi` 存在
- `judgment.horizon` 或 `judgment.bucket` 存在
- 原文包含 `$123`、`120-140`、`支撑位`、`压力位`、`target`、`PT` 等价位表达

### 逻辑性

加分来源：

- `reason` 长度足够
- `points.length >= 2`
- 文本含 because/therefore/so/原因/因为/所以/理由/근거/왜なら 等因果表达

### 新奇性

加分来源：

- `viewpoints` 包含非 `other` 视角
- 文本含 contrarian、反共识、市场忽视、低估、信息差、资金迁移等表达
- 与主流热度相反但有理由的观点

### 严谨性

加分来源：

- 文本含 risk、unless、if、however、but、风险、假设、除非、失效、stop loss、position sizing 等表达
- 有明确时间窗口或条件
- 有来源、数据或原话引用

## 来源差异

### Reddit

适合承担高质量主体来源。长文、DD、复盘、个人模型都可能有客户价值。

建议：

- 不要求 `quality_score >= 80`。
- 只要信息量/逻辑/价位任一强项即可通过。
- 过滤纯提问和低信息情绪帖。

### PTT

容易出现新闻转载和板规模板文本。不能因为长文本或 `quality_score` 高就直接通过。

建议：

- 纯 `[新聞]` 且没有作者解读时降低逻辑性与新奇性。
- Re 文、心得、标的分析可保留。
- 若同一新闻映射多个 ticker，应降低标的特异性，但不属于质量准入的硬条件。

### Naver

多数为短评论，适合情绪信号；进入高质量需要明显信息或明确操作。

建议：

- 有清晰买卖/价位/逻辑时通过。
- 单句情绪表达默认不通过。

### Yahoo Finance / Yahoo JP

多数为短句或匿名观点，主要用于情绪信号；作者不做追踪。

建议：

- 默认较难通过高质量。
- 有明确价位、明确买卖逻辑、或明显信息差时可以通过。
- 不要因为 native label 或简单关键词就判为高质量。

### YouTube

YouTube 最终会有完整口播，因此“是否已有完整口播”不能作为质量评分因子。当前口播缺失通常只是数据处理尚未完成，不代表观点低质量。

建议：

- 从 `ytDigest`、章节、`ytSegments` 中提取到的事实、逻辑、目标价、时间周期、风险条件是加分项。
- 目标价/时间周期/章节结构是强加分项。
- 口播完整性只记录为 pipeline 状态，例如 `transcript_status: pending | partial | complete | unavailable`，不进入 `customer_quality_score`。
- 在口播未完成时，允许用现有摘要、标题、描述、章节、评论聚合先给临时质量分；口播补全后重新计算内容维度。

## Pipeline 推荐输出

后续建议新增或扩展离线表，输出以下字段：

```json
{
  "source": "reddit",
  "item_id": "...",
  "ticker": "NVDA",
  "info_score": 0,
  "price_target_score": 0,
  "logic_score": 0,
  "novelty_score": 0,
  "rigor_score": 0,
  "customer_quality_score": 0,
  "quality_reasons": [
    "has explicit target range",
    "explains margin risk with data"
  ],
  "quality_flags": {
    "is_news_repost": false,
    "has_author_analysis": true,
    "has_price_level": true,
    "has_risk_condition": true,
    "is_low_information_reaction": false
  },
  "processing_status": {
    "transcript_status": "complete"
  }
}
```

推荐表名：

- `kol_customer_quality`

推荐主键：

- `(source, item_id, ticker)`

## 前端使用方式

当 `customer_quality_score` 存在：

```ts
isHighQuality = row.customer_quality_score >= 45 ||
  Math.max(
    row.info_score,
    row.price_target_score,
    row.logic_score,
    row.novelty_score,
    row.rigor_score
  ) >= 75 ||
  count([
    row.info_score,
    row.price_target_score,
    row.logic_score,
    row.novelty_score,
    row.rigor_score
  ].filter((x) => x >= 55)) >= 2
```

当离线分数不存在：

- 使用当前前端启发式。
- `quality_score` 只作为弱参考。
- `relevance_score` 不参与是否高质量。

## 调参原则

每次调参时记录：

- 通过率：整体与分 source。
- 被过滤的高价值漏判样例。
- 通过的低价值误判样例。
- 对客户阅读体验的影响。

推荐目标：

- “高质量”不是少数精品池，而是一个客户愿意阅读的候选池。
- 默认通过率可以在 20%-45% 区间内，根据页面噪声调整。
- 如果某来源天然短噪声高，可以降低其通过率；但不能完全封死强价值短观点。

## 版本记录

- 2026-07-06：v0.2，明确 YouTube 口播完整性是数据处理状态，不作为质量评分因子。
- 2026-07-06：v0.1，定义客户价值导向的质量评分，不把相关度纳入质量准入。
