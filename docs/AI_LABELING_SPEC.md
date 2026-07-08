# Prismo 当前 AI 打标与数据分析系统规范

更新时间：2026-07-06  
适用项目：`crypto_us` / Prismo  
口径：只记录当前仍在产品中使用或仍应继续维护的 AI 系统、数据管道、标签表、Prompt、输入输出格式与主键规范。历史单站功能、旧页面、旧 Reddit-only 分析、旧叙事表、非当前产品依赖的高档逐帖分析，以及源码中仍保留但不服务当前核心体验的兼容逻辑，不纳入本文。

## 1. 当前有效架构概览

Prismo 当前的数据智能层可以理解为 5 个活跃系统：

1. **观点流 AI 标签系统**
   - 面向标的详情页的观点流、筛选、排序、正文阅读、目标价时间线。
   - 核心表：`kol_refined`, `kol_relevance`, `kol_quality`, `kol_viewpoint`, `kol_judgment`, `kol_argument`, `kol_narrative`。

2. **YouTube 视频理解系统**
   - 面向 YouTube 观点、完整口播、投资者摘要、内容目录、作者详情页。
   - 核心表：`yt_video`, `yt_analysis`, `yt_fulltext`, `yt_digest`, `yt_judgment`, `yt_creator_view`, `yt_channel`。

3. **X / Smart Voice 系统**
   - 面向 Smart Voice 投资者评分、X 可行动观点、目标价点阵、SV 筛选。
   - 核心表：`x_opinion`, `x_reply`, `sv_call_candidate`, `sv_call`, `sv_call_settlement`, `sv_investor_score`, `sv_segment_score`。

4. **全球散户社区系统**
   - 面向 Toss、雪球、Yahoo JP、Naver、PTT 等社区帖子，产出跨平台情绪、讨论度、散户视图。
   - 核心表：`gr_post`, `gr_ticker_region`, `gr_ticker`, `gr_quote`, `retail_sentiment_daily`, `retail_volume_daily`, `retail_newcomers_daily`。

5. **整体数据与叙事派生系统**
   - 面向标的详情页整体数据、异动归因、KOL/散户分歧、叙事轮动页面。
   - 核心输出：`kol_sentiment_daily`, `kol_volume_daily`, `kol_newcomers_daily`, `web/lib/data/overallData.json`, `web/lib/data/narrativeRotation.json`。

当前产品最重要的设计原则：

- 所有观点级标签都应尽量落在 `(source, item_id, ticker)` 粒度。
- 所有可点击内容必须保留原始源 ID，例如 `tweet_id`, `video_id`, `gr_post.id`。
- YouTube 是独立强管道，不走 `kol_refined`，而是由 `yt_analysis` / `yt_digest` / `yt_judgment` 直接供前端使用。
- X 的可行动观点由 SV 系统补充；普通 X 观点由 `x_opinion` + `kol_*` 表补标签。
- `gr_post` 只负责原始全球社区数据和轻量情绪；如果要进入观点流，需要进入 `kol_refined` / `kol_relevance` / `kol_quality` / `kol_viewpoint` / `kol_judgment`。

## 2. 当前模型路由

实际调用统一经过 `pipeline/common/llm.py`。当前活跃产品管道主要使用：

| 能力 | 当前用途 | 实际模型 |
| --- | --- | --- |
| `LOW` | KOL 提炼、相关度、质量、视角、目标价、翻译、论点综合、摘要、情绪批量打分、整体数据归因 | `qwen-flash` |
| Gemini | YouTube 视频原生理解、完整口播还原 | `pipeline/common/gemini.py` |

说明：

- 当前文档只描述活跃产品管道；历史兼容命令与旧的高档逐帖分析不作为有效 AI 系统记录。
- 代码里仍可能保留历史命令或兼容字段，但如果前端当前核心体验不依赖它们，就不在本文作为有效系统描述。
- 源码注释中部分“DeepSeek flash”字样是历史遗留；按当前路由，`LOW` 实际走 Qwen 低档模型。

## 3. 当前本地数据覆盖

来自本地 `data/dev.db` 当前快照：

| 表 / 文件 | 行数 | 当前用途 |
| --- | ---: | --- |
| `x_opinion` | 884,133 | X 原始观点流 |
| `gr_post` | 127,870 | Toss / 雪球 / YahooJP / Naver / PTT 等全球社区原始帖子 |
| `kol_refined` | 8,224 | 观点流提炼、双语理由和要点 |
| `kol_relevance` | 10,644 | 观点与指定标的相关度 |
| `kol_quality` | 9,789 | 高质量筛选 |
| `kol_viewpoint` | 7,089 | 投资视角分类 |
| `kol_argument` | 1,662 | 视角内论点聚合 |
| `kol_narrative` | 691 | 视角内叙事综合 |
| `kol_judgment` | 849 | 非 YouTube 来源的目标价/买卖价/周期 |
| `yt_video` | 1,499 | YouTube 视频元数据 |
| `yt_analysis` | 1,464 | YouTube 观点分析 |
| `yt_fulltext` | 726 | YouTube 完整口播 |
| `yt_digest` | 693 | YouTube 投资者摘要与内容目录 |
| `yt_judgment` | 1,464 | YouTube 目标价/周期/关键位 |
| `yt_creator_view` | 894 | YouTube 作者×标的综合观点 |
| `yt_channel` | 725 | YouTube 频道粉丝数、简介等作者信息 |
| `sv_call_candidate` | 49,430 | Smart Voice 候选 X call |
| `sv_call` | 49,430 | Smart Voice 结构化 call |
| `sv_investor_score` | 1,157 | 投资者 SV 分数 |
| `kol_sentiment_daily` | 1,208 | KOL 每日净情绪 |
| `kol_volume_daily` | 5,625 | KOL 每日讨论度 |
| `retail_sentiment_daily` | 1,697 | 散户每日净情绪 |
| `retail_volume_daily` | 5,676 | 散户每日讨论度 |
| `retail_newcomers_daily` | 2,511 | 散户每日新增参与者 |
| `kol_newcomers_daily` | 838 | KOL 每日新增参与者 |
| `web/lib/data/overallData.json` | 构建期 JSON | 整体数据异动归因、KOL/散户分歧 |
| `web/lib/data/narrativeRotation.json` | 构建期 JSON | 叙事轮动页面 |

## 4. 源 ID 与主键规范

所有站内跳转、图表点位、正文阅读、去重和跨表 join 都依赖源 ID。

| 来源 | 原始表 | 原始 ID | AI 标签 join key | 说明 |
| --- | --- | --- | --- | --- |
| X | `x_opinion` | `tweet_id` | `source='x', item_id=tweet_id, ticker` | 普通观点、互动数、热门回复 |
| X Smart Voice | `sv_call_candidate`, `sv_call` | `tweet_id`, `candidate_id` | `candidate_id = tweet_id:ticker` | 一个 tweet 可产生多个 ticker call |
| YouTube | `yt_video` | `id` / `video_id` | `source='youtube', item_id=video_id, ticker` | 视频、摘要、正文、目标价均用 `video_id` |
| Toss | `gr_post` | `id` | `source='toss', item_id=gr_post.id, ticker` | 韩国 Toss 社区 |
| 雪球 | `gr_post` | `id` | `source='xueqiu', item_id=gr_post.id, ticker` | 中国社区 |
| Yahoo JP | `gr_post` | `id` | `source='yahoojp', item_id=gr_post.id, ticker` | 原始 `gr_post.source='yahoo_jp'`，观点层映射为 `yahoojp` |
| Naver | `gr_post` | `id` | 当前主要用于散户聚合 | 如进入观点流，应使用 `source='naver'` |
| PTT | `gr_post` | `id` | 当前主要用于散户聚合 | 如进入观点流，应使用 `source='ptt'` |

硬性规则：

- `tweet_id`、`video_id`、`gr_post.id` 不能丢。
- 不要用内部自增 ID 替代源 ID。
- 所有观点级 AI 输出必须能回查到原始内容、作者、发布时间、平台、ticker。
- 多 ticker 内容必须以 `(source, item_id, ticker)` 为粒度打标签。

## 5. 观点流 AI 标签系统

观点流由 `web/lib/kolQueries.ts` 读取并合成。当前前端核心逻辑：

- X：`x_opinion` + `kol_*` + `sv_*`
- YouTube：`yt_video` + `yt_analysis` + `yt_fulltext` + `yt_digest` + `yt_judgment`
- 社区文本：`gr_post` 中的雪球 / Toss / YahooJP 等 + `kol_*`
- 排序和筛选：`kol_relevance`, `kol_quality`, `kol_viewpoint`, `kol_judgment`, `sv_call`

### 5.1 KOL 观点精炼

实现：`pipeline/domain/opinions/kol_refine.py`（由 `pipeline/jobs/kol/workflows.py` 编排）
命令：`make kol-refine`  
输出表：`kol_refined`  
粒度：`source + item_id + ticker`

覆盖来源：

```text
x / xueqiu / toss / yahoojp
```

代码中候选 loader 仍可处理更多来源，但当前产品文档只把以上文本社区作为有效输入口径。YouTube 不走该表，直接复用 `yt_analysis`。

输入格式：

```text
标的 {ticker}。来源：{source label}（系统初判立场：{hint}，仅供参考，可推翻）。原文：
{title + body, max 2000 chars}
```

当前 Prompt：

```text
你是金融观点提炼器。给定某社区用户/博主关于一只美股的发言（语言可能为中/英/日/韩），
提炼 ta 对该股的核心立场与理由，并给出双语结果。务必『提炼』而非照抄或直译原文。
仅输出 JSON，不要多余文字：
{
  "stance":"bull|bear|neutral",
  "reason_zh":"说明 ta 为什么看多/看空/中性（第三人称，1-2句、把核心逻辑讲清，≤80字）",
  "reason_en":"why, third-person, 1-2 sentences capturing the core logic (≤55 words)",
  "points_zh":["要点1","要点2"],
  "points_en":["point1","point2"],
  "quote_zh":"ta 原话里最能代表其观点的一句，忠实翻译成中文（≤50字，保留原语气，不要改写或提炼）",
  "quote_en":"the single most representative sentence ta actually wrote, faithful English (not paraphrased, ≤40 words)"
}

points 填 ta 给出的具体信息（催化剂/财务数据/价格目标/风险/逻辑链），2-4 条，保留关键细节。
quote 与 reason 不同：reason 是你的提炼，quote 是 ta 本人说的原话。
若信息太少无法判断理由，reason 写「未给出明确理由」/ "no clear thesis given"，stance 取 neutral，quote 留空。
```

输出：

```json
{
  "stance": "bull",
  "reason_zh": "作者认为 MU 的数据中心需求仍在支撑盈利上行。",
  "reason_en": "The author sees data-center demand supporting MU's earnings upside.",
  "points_zh": ["HBM 需求强", "供给纪律改善", "估值仍低于周期高点"],
  "points_en": ["HBM demand remains strong", "Supply discipline is improving", "Valuation is still below prior cycle highs"],
  "quote_zh": "数据中心需求仍然强劲。",
  "quote_en": "Data-center demand remains strong."
}
```

### 5.2 相关度打分

实现：`pipeline/domain/opinions/kol_relevance.py`（由 `pipeline/jobs/kol/workflows.py` 编排）
命令：`make kol-relevance`  
输出表：`kol_relevance`  
粒度：`source + item_id + ticker`

输入：

```text
标的：MU
内容：
{text[:1500]}
```

当前 Prompt：

```text
你给『一条帖文/视频 与 一只指定美股』打相关度分(0-100 整数)。
相关度只衡量一件事：这只票在这条内容里的「中心程度」。

档位：
90-100：整条几乎都在讲这只票，它就是主角；
70-89：这只票是主要话题，和 1-2 只并列但明显是重点之一；
40-69：只有一段在讲它，全文重点在别处；
15-39：只在结尾或某一句里顺带提到、举例带过、或在一串名单里出现一次；
1-14：只是冒出个名字/cashtag、几乎没真讲；
0：完全无关。

关键：又长又有料不等于相关。
步骤：先用一句话写出这条主要在讲什么，判断指定标的是不是主角，再打分。
输出 JSON，不要多余文字：
{"about":"这条主要在讲什么，一句话","relevance":整数}
```

输出：

```json
{"about":"这条主要讨论 MU 财报后的盈利修复", "relevance": 93}
```

### 5.3 内容质量打分

实现：`pipeline/domain/opinions/kol_quality.py`（由 `pipeline/jobs/kol/workflows.py` 编排）
命令：`make kol-quality`  
输出表：`kol_quality`  
粒度：`source + item_id`

当前 Prompt：

```text
你给『一条美股社区帖文/视频』本身作为投资分析的含金量(质量)打 0-100 分。
只看内容质量，不看它与哪只股票多相关，也不看多空立场是否正确。

高质量必须是可审计的投资分析：有明确 thesis，并至少具备两类实质内容：
具体数据/估值/财报指标、因果逻辑链、可验证证据或来源、情景/反方风险、同业或历史比较。

低质量包括：短句喊单、标题党、新闻转述、只列目标价、只说涨跌、模板化工具打分但没有来源与假设、
作者自推工具/订阅/群组、纯情绪或广告。

档位：
85-100：深度研究，有数据+逻辑+证据+风险权衡，信息密度高；
65-84：有明确观点和多条具体理由/数据，能支撑投资判断；
45-64：有观点和少量理由，但论证浅、证据不足或主要是复述；
25-44：基本只有结论/事件/目标价，理由很薄；
1-24：纯喊单、标题党、广告、灌水、几乎无投资信息；
0：无意义/spam。

仅输出 JSON：
{"quality": 整数}
```

输出：

```json
{"quality": 78}
```

补充：

- 代码里有 deterministic cap/floor，避免模型高估短帖、广告和低信息量 YouTube。
- 质量和相关度必须分开看。

### 5.4 投资视角分类

实现：`pipeline/domain/opinions/kol_viewpoint.py`（由 `pipeline/jobs/kol/workflows.py` 编排）
命令：`make kol-viewpoint`  
输出表：`kol_viewpoint`  
粒度：`source + item_id + ticker`

标签：

| key | 中文 |
| --- | --- |
| `valuation` | 估值 |
| `growth` | 业务与成长 |
| `competition` | 竞争格局 |
| `management` | 管理层 |
| `macro` | 宏观与政策 |
| `catalyst` | 催化剂 |
| `flows` | 资金与盘面 |
| `other` | 兜底 |

当前 Prompt：

```text
你是金融观点分类器。给定一条关于某只美股的已提炼观点，把它归入 7 个投资分析视角中最贴切的 1-3 个。
按相关度排序，主视角在前。

核心原则：几乎每一条有具体内容的观点都至少属于一个视角。
只有通篇是纯情绪喊单、与该股无关、或完全没有任何信息时，才返回 ["other"]。

线索：
- valuation：估值贵/便宜、市盈率市销率PEG、目标价、同业/历史对比
- growth：收入/用户/产品/毛利/现金流/TAM/AI 投入产出
- competition：对手、替代品、市占、护城河
- management：高管、内部人增减持、资本配置、裁员、诚信
- macro：利率、流动性、经济周期、政策、关税、汇率
- catalyst：财报、新品、并购、解禁、指数纳入、诉讼、IPO
- flows：价格走势、买卖点、空头比例、期权、资金流、叙事人气

仅输出 JSON：
{"viewpoints":["key",...]}
```

输出：

```json
{"viewpoints":["growth","valuation","catalyst"]}
```

### 5.5 目标价、买卖价与周期抽取

实现：`pipeline/domain/target_prices/kol_judgment.py`（由 `pipeline/jobs/kol/workflows.py` 编排）
命令：`make kol-judgment`  
输出表：`kol_judgment`  
粒度：`source + item_id + ticker`

输入：

```text
标的 {ticker}。来源：{source label}（系统初判立场：{hint}，仅供参考，不可据此编造数字）。
该股当前价约 ${price}（与此数量级严重不符的数字几乎一定不是价位）。
原文：
{text[:2000]}
```

当前 Prompt：

```text
你是金融交易参数抽取器。给定某社区用户/博主关于一只美股的发言，抽取 ta 明确写明的
『买入价位』与『卖出/目标价位』，支持区间。只输出 JSON：
{
  "buy_lo":null,
  "buy_hi":null,
  "sell_lo":null,
  "sell_hi":null,
  "price_raw":null,
  "horizon_zh":null,
  "horizon_en":null,
  "horizon_bucket":null
}

字段说明：
1. buy_lo / buy_hi：买入/加仓价位。区间填上下界；确切价两者相同。
2. sell_lo / sell_hi：卖出/止盈价位，或方向性目标价/合理估值。目标价归这一侧。
3. price_raw：价格在原文里的代表性原话短语。
4. horizon_zh / horizon_en：操作/持有周期原话短语。
5. horizon_bucket：short / mid / long。short=日内~2周；mid=2周~3个月；long=>3个月/长期持有/年度。

铁律：
- 只有作者清楚写出才填。
- 价格只填绝对数字。
- “翻倍”“涨50%”等相对幅度不是价位。
- 绝不从情绪/看多看空推断数字或周期。
- 与当前价数量级严重不符的数字剔除。
- penny pump、假设性演算、批量筛选器数字不是真实价位。
```

输出：

```json
{
  "buy_lo": 92,
  "buy_hi": 96,
  "sell_lo": 125,
  "sell_hi": 135,
  "price_raw": "$125-135 target",
  "horizon_zh": "到年底",
  "horizon_en": "by year-end",
  "horizon_bucket": "long"
}
```

当前状态：

- 该表走严格抽取，适合“作者明确给出”。
- 如果要让目标价图表更丰富，建议新增 `price_reference`，区分“作者操作目标价 / 分析师目标价 / 估值情景价 / 技术位”。

### 5.6 原帖完整翻译

实现：`pipeline/domain/opinions/kol_translate.py`（由 `pipeline/jobs/kol/workflows.py` 编排）
命令：`make kol-translate`  
输出字段：`kol_refined.trans_zh`, `kol_refined.trans_en`

当前 Prompt：

```text
你是股票投资社区帖子的翻译器，既不是摘要器、也不是逐字机翻。
给定某社区用户/博主关于一只美股的帖子原文，把它完整翻译成自然、地道的中文和英文。

硬性要求：
1. 逐句翻译，保持相当篇幅与段落/换行；不概括、不提炼、不合并、不删细节、不加原文没有的内容；
2. 保留全部信息：数字、日期、价格、代码、公司名、事件、语气、强调；
3. 按股票/投资语境意译行话与俚语；
4. green / red 这类美股涨跌颜色必须译成涨跌/盈亏本身，不用颜色直译；
5. 若某语言已是原文语言，该字段输出清理后的原文本身。

仅输出 JSON：
{"zh":"完整自然的中文翻译","en":"full natural English translation"}
```

### 5.7 论点综合与叙事编织

实现：`pipeline/domain/opinions/kol_argument.py`（由 `pipeline/jobs/kol/workflows.py` 编排）
命令：`make kol-argument`  
输出表：`kol_argument`, `kol_narrative`  
粒度：`ticker + lens + stance + window`

输入：

- `kol_refined`
- `kol_viewpoint`
- `yt_analysis`

当前 Prompt：

```text
你是金融论点主编。下面是同一只美股、同一视角、同一立场下的多条观点。
做两件事：
1. 提炼出最关键的 2-3 个论点；
2. 把它们编织成一段连贯叙事。

论点规则：
- 合并同义观点；
- claim 写成论点本身，禁止“用户认为/作者表示”；
- 纯情绪、个人交易流水、无理由观点丢弃；
- detail 要保留具体依据、数字、事件、因果。

叙事规则：
- lead 一句话总述；
- points 3-6 个分点，每点带 supporters；
- 客观第三人称；
- 覆盖所有论点。

仅输出 JSON：
{
  "lead_zh":"",
  "lead_en":"",
  "points":[{"zh":"","en":"","supporters":[1]}],
  "arguments":[{"claim_zh":"","claim_en":"","detail_zh":"","detail_en":"","supporters":[1,2]}]
}
```

## 6. YouTube 视频理解系统

### 6.1 视频发现与频道信息

脚本：

- `pipeline/platforms/youtube/discovery.py`
- `pipeline/platforms/youtube/channels.py`

命令：

```bash
make youtube
make yt-channels
```

输出：

- `yt_video`
- `yt_channel`

`yt_channel` 保存作者信息：

- `channel_id`
- `title`
- `handle`
- `subscriber_count`
- `video_count`
- `description`

### 6.2 YouTube 观点分析

实现：`pipeline/domain/opinions/youtube_analysis.py`（由 `pipeline/jobs/youtube/workflows.py` 编排）
命令：`make youtube` / `youtube-tag`  
输出表：`yt_analysis`

输入：

```text
标的 {ticker}。频道《{channel}》。请判断该视频对 {ticker} 的观点，按系统要求输出 JSON。
```

当前 Prompt：

```text
你是金融视频观点分析器。给定一条讨论某只美股的 YouTube 视频（语言可能为英/韩/日/中），
判断 UP 主（含其引用的分析师）对该股的投资观点。仅输出 JSON：
{
  "stance":"bull|bear|neutral",
  "sentiment":-1.0~1.0,
  "conviction":0~1,
  "summary_zh":"两句中文总结",
  "summary_en":"two-sentence English summary",
  "key_points_zh":["论点1","论点2"],
  "key_points_en":["point1","point2"],
  "price_target":"若提到价格目标则填写，否则 null"
}
```

输出：

```json
{
  "stance": "bull",
  "sentiment": 0.51,
  "conviction": 0.72,
  "summary_zh": "该频道认为 MU 的存储周期正在复苏。核心依据是 HBM 需求和供给纪律改善。",
  "summary_en": "The channel sees MU's memory cycle recovering. It cites HBM demand and better supply discipline.",
  "key_points_zh": ["HBM 需求强", "库存周期改善", "估值仍有修复空间"],
  "key_points_en": ["HBM demand is strong", "Inventory cycle is improving", "Valuation has room to re-rate"],
  "price_target": "$135"
}
```

### 6.3 YouTube 完整口播

实现：`pipeline/domain/opinions/youtube_analysis.py` 的 `gen_fulltext`（由 `pipeline/jobs/youtube/workflows.py` 编排）
命令：`youtube-fulltext`  
输出表：`yt_fulltext`

当前目标：

- Gemini 真看视频。
- 只还原口播，不描述画面。
- 按语义分段。
- 多人视频保留 speaker。
- 删除赞助、订阅、宣传话术。
- 生成 `segments` JSON 和 `content_zh` 扁平文本。

输出：

```json
{
  "segments": [
    {
      "type": "speech",
      "speaker": "host",
      "text": "..."
    }
  ]
}
```

### 6.4 YouTube 投资者摘要与内容目录

实现：`pipeline/domain/opinions/youtube_digest.py`（由 `pipeline/jobs/youtube/workflows.py` 编排）
命令：`make youtube-digest`  
输出表：`yt_digest`

输入：

- `yt_fulltext.segments`
- `yt_analysis.summary/key_points`

当前 Prompt 目标：

- 从完整口播提炼 4-7 条投资者摘要。
- 生成 3-8 个内容章节。
- `chapters.seg` 指向 `yt_fulltext.segments` 的 speech 段下标。
- 第一章 `seg=0`。
- 章节必须按口播顺序单调递增。

输出：

```json
{
  "summary_zh": ["摘要点1", "摘要点2"],
  "summary_en": ["point 1", "point 2"],
  "chapters": [
    {"t_zh": "开场与核心观点", "t_en": "Opening thesis", "seg": 0},
    {"t_zh": "估值与目标价", "t_en": "Valuation and target", "seg": 4}
  ]
}
```

### 6.5 YouTube 目标价与关键位置

实现：`pipeline/domain/target_prices/youtube_judgment.py`（由 `pipeline/jobs/youtube/workflows.py` 编排）
命令：`make youtube-judgment`  
输出表：`yt_judgment`

输入：

- `yt_analysis.summary_zh/en`
- `yt_analysis.key_points_zh/en`
- `yt_analysis.price_target`

输出：

```json
{
  "horizon_zh": "未来 6-12 个月",
  "horizon_en": "next 6-12 months",
  "target": "$135",
  "key_levels_zh": ["$100 支撑", "$135 目标价"],
  "key_levels_en": ["$100 support", "$135 target"]
}
```

规则：

- 只抽明说内容。
- 不从情绪推断目标价。
- `target` 优先作为目标价时间线图的 YouTube 目标侧。

### 6.6 YouTube 作者×标的综合观点

实现：`pipeline/domain/authors/youtube_creator_view.py`（由 `pipeline/jobs/youtube/workflows.py` 编排）
命令：`make youtube-creator-view`  
输出表：`yt_creator_view`  
粒度：`channel_id + ticker`

输入：

- 同一 `channel_id` 下该 ticker 的多条 `yt_analysis`

输出：

```json
{
  "stance": "bull",
  "points_zh": ["该作者近期多次强调 MU 的 HBM 需求", "作者认为估值修复仍未结束"],
  "points_en": ["The creator repeatedly emphasizes MU's HBM demand", "The creator sees valuation re-rating continuing"]
}
```

用途：

- 作者详情页每个标的只显示综合判断，而不是铺开每条视频。

## 7. X / Smart Voice 系统

### 7.1 X 数据同步

脚本：`pipeline/platforms/x/cloud_pull.py` 或 `pipeline/platforms/x/complete_universe.py`
输出：

- `x_opinion`
- `x_reply`

关键字段：

- `tweet_id`
- `ticker`
- `handle`
- `created`
- `text`
- `likes`
- `retweets`
- `replies`
- `quotes`
- `views`
- `bookmarks`

### 7.2 Smart Voice Call 抽取

实现：`pipeline/domain/smart_voice/v0.py` / `pipeline/domain/smart_voice/v0_impl.py`（由 `pipeline/jobs/smart_voice/workflows.py` 编排）
命令：

```bash
make sv-v0-candidates
make sv-v0
make sv-v0-prod
```

输出：

- `sv_call_candidate`
- `sv_call`
- `sv_call_settlement`
- `sv_investor_score`
- `sv_segment_score`
- `web/lib/data/smartVoice.json`

候选 ID：

```text
candidate_id = {tweet_id}:{ticker}
```

当前 Prompt：

```text
You structure public equity-market posts into tradable calls for Smart Voice scoring.
Judge only the specified ticker, but first understand whether the post is a single-ticker call,
a basket/sector thesis, a pair trade, a portfolio update, a retrospective, or merely context.
Do not decide whether the call was correct.

If the post is news, a joke, a repost, a retrospective brag, a pure chart note without direction,
or only mentions the ticker in a watchlist with no directional implication, mark it non-actionable.
If the specified ticker is only a comparison, ecosystem reference, or context mention,
mark it non-actionable or set ticker_role to context/comparison/excluded.
If it contains a conditional trade plan, it can be actionable if direction is clear.

Return strict JSON only with these fields:
{
  "is_actionable_call": boolean,
  "direction": "bull|bear|neutral",
  "horizon_bucket": "1D|5D|20D|60D|unknown",
  "horizon_explicit": boolean,
  "target_price": number|null,
  "conviction_score": number,
  "evidence_score": number,
  "specificity_score": number,
  "call_type": "single_ticker_call|basket_call|pair_trade|sector_call|portfolio_update|retrospective|context_mention",
  "ticker_role": "primary|basket_member|context|comparison|excluded",
  "ticker_relevance": number,
  "target_price_owner": "ticker symbol if a target price belongs to a specific ticker else empty",
  "evidence_span": "short original quote supporting this ticker call",
  "summary_zh": "short Chinese summary",
  "summary_en": "short English summary",
  "exclusion_reason": "short reason if non-actionable else empty"
}
```

输出示例：

```json
{
  "is_actionable_call": true,
  "direction": "bull",
  "horizon_bucket": "20D",
  "horizon_explicit": false,
  "target_price": 135,
  "conviction_score": 0.72,
  "evidence_score": 0.66,
  "specificity_score": 0.81,
  "call_type": "single_ticker_call",
  "ticker_role": "primary",
  "ticker_relevance": 0.95,
  "target_price_owner": "MU",
  "evidence_span": "$MU to 135 if HBM guide holds",
  "summary_zh": "作者看多 MU，认为 HBM 指引若兑现将推动股价上行。",
  "summary_en": "The author is bullish on MU, citing HBM guidance as upside.",
  "exclusion_reason": ""
}
```

SV 后处理：

- 按 `1D/5D/20D/60D` 结算。
- 与 SPY 比较超额收益。
- 同作者同 ticker 后续反向 call 会提前关闭旧 call。
- 多 ticker tweet 做 post-level 权重 cap。
- 投资者评分做置信度、集中度、base-rate shrink。

### 7.3 X 情绪打分

实现：`pipeline/domain/smart_voice/tweet_sentiment.py`（由 `pipeline/jobs/smart_voice/workflows.py` 编排）
命令：`make tw-sentiment`  
输出：cloud `tw_tweet_sentiment`

输出：

```json
[
  {"i": 1, "s": 0.24},
  {"i": 2, "s": -0.61}
]
```

用途：

- 供 `kol_sentiment_daily` 的 X 情绪 rollup 使用。
- 注意：该表在云端，不是本地 `data/dev.db` 的核心观点表。

## 8. 全球散户社区系统

### 8.1 Toss / 全球社区抓取

活跃入口：

```bash
make toss
make gr
make gr-tag
```

核心表：

- `gr_post`
- `gr_ticker_region`
- `gr_ticker`
- `gr_quote`

当前 `gr_post` 典型来源：

- `toss`
- `xueqiu`
- `yahoo_jp`
- `naver`
- `ptt`

### 8.2 全球社区轻量情绪

实现：`pipeline/domain/global_retail/tag.py`（由 `pipeline/jobs/global_retail/workflows.py` 编排）
输出字段：`gr_post.sentiment`, `gr_post.stance`

输入：

```text
1. (kr/MU)[Toss] 本文...
2. (jp/MU)[Yahoo Finance Japan] 本文...
```

当前输出：

```json
[
  {"i": 1, "s": 0.45},
  {"i": 2, "s": -0.32}
]
```

派生规则：

- `s > 0.15` -> `bull`
- `s < -0.15` -> `bear`
- 其它 -> `neutral`

当前定位：

- 这是散户社区的轻量情绪层。
- 不等同于观点流的完整标签。
- 如果某条 Toss / YahooJP / 雪球内容要进入观点流并可被排序、筛选、展示正文，就需要进入 `kol_refined` 等 KOL 标签层。

## 9. 整体数据与时间序列派生

### 9.1 KOL 每日净情绪

实现：`pipeline/domain/smart_voice/kol_sentiment.py`（由 `pipeline/jobs/smart_voice/workflows.py` 编排）
命令：`make kol-sentiment`  
输出表：`kol_sentiment_daily`

口径：

- X：云端 `tw_tweet_ticker` + `tw_tweet_sentiment`
- YouTube：`yt_video` + `yt_analysis.sentiment`
- 雪球等：`gr_post.sentiment`
- 相关性：`kol_relevance`
- 权重：情绪 × `ln(1 + interactions)` × 相关性

### 9.2 KOL 每日讨论度

实现：`pipeline/domain/smart_voice/kol_volume.py`（由 `pipeline/jobs/smart_voice/workflows.py` 编排）
命令：`make kol-volume`  
输出表：`kol_volume_daily`

口径：

- X 直接数 `tw_tweet_ticker`
- YouTube 数 `yt_video`
- 雪球等数 `gr_post`

### 9.3 散户每日净情绪与讨论度

脚本：

- `pipeline/domain/smart_voice/retail_sentiment.py`
- `pipeline/domain/smart_voice/retail_volume.py`
- `pipeline/domain/smart_voice/retail_newcomers.py`

命令：

```bash
make retail-sentiment
make retail-volume
make retail-newcomers
```

输出：

- `retail_sentiment_daily`
- `retail_volume_daily`
- `retail_newcomers_daily`

口径：

- 全量散户社区 + 本土论坛。
- 不含 YouTube。
- `retail_sentiment_daily` 用于整体散户净情绪。
- `retail_volume_daily` 用于整体散户讨论度。

### 9.4 KOL 新增参与者

实现：`pipeline/domain/smart_voice/kol_newcomers.py`（由 `pipeline/jobs/smart_voice/workflows.py` 编排）
命令：`make kol-newcomers`  
输出表：`kol_newcomers_daily`

口径：

- X：`x_opinion` 按 handle。
- YouTube：`yt_video` 按 channel_id。
- 雪球：`gr_post(source='xueqiu')` 按 author。

### 9.5 整体数据异动归因

实现：`pipeline/domain/smart_voice/overall_signals.py`（由 `pipeline/jobs/smart_voice/workflows.py` 编排）
命令：`make overall-signals`
输出：`web/lib/data/overallData.json`

当前有效产出：

1. 情绪/讨论度异常日。
2. 用当天 KOL 推文生成一句话归因。
3. 聪明钱与散户分歧。

异动归因 Prompt：

```text
你是资深美股舆情分析师。给你某标的某一天的 KOL（X 大V）推文。
该日舆情出现异常：{ctx}。
用一句话说明为何：只点出当天最主要的催化事件或主导话题，要具体、可证伪
（提到具体事件/数据/人物/技术位/财报等），不要空话套话，不要复述指标本身。
严格输出 JSON：
{"zh":"中文一句话(≤45字)","en":"one English sentence(≤28 words)"}
```

输入：

```text
标的: MU
日期: 2026-06-20
当天 KOL 推文（按互动排序）:
- @handle (1234): tweet text...
```

输出：

```json
{
  "zh": "HBM 需求与财报预期升温推动多头讨论放量。",
  "en": "HBM demand and earnings expectations drove a surge in bullish discussion."
}
```

### 9.6 叙事轮动

实现：`pipeline/domain/narratives/rotation.py`（由 `pipeline/jobs/narrative_rotation/workflows.py` 编排）
命令：`make narrative-rotation`  
输出：`web/lib/data/narrativeRotation.json`

当前口径：

- 固定分类叙事。
- 读取 `gr_post`、`x_opinion + kol_refined`、`yt_video + yt_analysis` 等当前多社区数据。
- 生成叙事热度排名变化、讨论占比变化、情绪变化。
- 该流程主要是 taxonomy + 现有标签聚合，不依赖旧叙事表。

输出结构核心：

```json
{
  "version": 1,
  "updated_at": "2026-07-06T00:00:00Z",
  "window": {"start": "2026-06-15", "end": "2026-07-06", "days": ["..."]},
  "categories": [],
  "leaderboard": [],
  "series": {},
  "details": {}
}
```

## 10. 已有标签与缺口

### 10.1 已有且可复用

| 能力 | 主要表 | 状态 |
| --- | --- | --- |
| 观点立场 | `kol_refined.stance`, `yt_analysis.stance`, `sv_call.direction`, `gr_post.stance` | 已有 |
| 观点摘要 | `kol_refined`, `yt_analysis`, `yt_digest` | 已有 |
| 观点完整翻译 | `kol_refined.trans_zh/en` | 已有 |
| 相关度排序 | `kol_relevance.score` | 已有 |
| 高质量筛选 | `kol_quality.score` | 已有 |
| 视角筛选 | `kol_viewpoint.viewpoints` | 已有 |
| 视角论点 | `kol_argument`, `kol_narrative` | 已有 |
| 目标价/周期 | `kol_judgment`, `yt_judgment`, `sv_call.target_price` | 部分已有 |
| YouTube 完整正文 | `yt_fulltext`, `yt_digest` | 已有 |
| YouTube 作者画像 | `yt_channel`, `yt_creator_view` | 已有 |
| X Smart Voice | `sv_call`, `sv_investor_score` | 已有 |
| 散户情绪 | `gr_post.sentiment`, `retail_sentiment_daily` | 已有 |
| KOL/散户时间序列 | `kol_*_daily`, `retail_*_daily` | 已有 |

### 10.2 仍需补齐

| 缺口 | 建议新增 | 原因 |
| --- | --- | --- |
| 统一观点标签层 | `opinion_label` | 当前前端需要跨多张表合并，后续个性化与 SV 筛选会越来越复杂 |
| 全来源可行动性 | `opinion_actionability` | 现在 SV 只覆盖 X，其它来源缺少统一 `action_type` |
| 目标价更高召回 | `price_reference` | 当前 `kol_judgment` 很严格，适合高置信点，不适合承载所有目标价表达 |
| 作者画像统一 | `author_profile` | YouTube 有 `yt_channel`，X/雪球/Toss/YahooJP 作者画像还不统一 |
| 个性化排序解释 | `personalized_opinion_score` 或前端派生 | 用户成本价、仓位、周期偏好需要解释型排序 |
| SV 百分位缓存 | `sv_percentile` | 前端按 Top 25% / 中部区间筛选需要快速读取 |

## 11. 建议新增统一表：opinion_label

这是下一步最重要的结构化层。它不是替代现有表，而是把当前散落的标签汇总成前端和推荐系统可直接读取的统一视图。

```sql
CREATE TABLE IF NOT EXISTS opinion_label (
  source TEXT NOT NULL,
  item_id TEXT NOT NULL,
  ticker TEXT NOT NULL,
  source_native_id TEXT,
  canonical_id TEXT NOT NULL,

  author_id TEXT,
  author_handle TEXT,
  author_name TEXT,
  author_profile_url TEXT,
  author_followers INTEGER,

  created_at TEXT,
  url TEXT,
  lang TEXT,
  title TEXT,
  raw_text TEXT,
  translated_text_zh TEXT,

  stance TEXT,
  sentiment REAL,
  relevance_score INTEGER,
  quality_score INTEGER,
  conviction_score REAL,

  viewpoints_json TEXT,
  thesis_type TEXT,
  action_type TEXT,
  is_actionable INTEGER,

  summary_zh TEXT,
  summary_en TEXT,
  points_zh_json TEXT,
  points_en_json TEXT,
  quote_zh TEXT,
  quote_en TEXT,

  buy_lo REAL,
  buy_hi REAL,
  sell_lo REAL,
  sell_hi REAL,
  target_price REAL,
  price_raw TEXT,
  horizon_zh TEXT,
  horizon_en TEXT,
  horizon_bucket TEXT,

  sv_investor_id TEXT,
  sv_percentile REAL,
  sv_score REAL,
  sv_call_id TEXT,

  label_version TEXT,
  labeled_at TEXT,
  PRIMARY KEY (source, item_id, ticker)
);
```

建议生成方式：

1. X：`x_opinion` + `kol_*` + `sv_call`
2. YouTube：`yt_video` + `yt_analysis` + `yt_fulltext` + `yt_digest` + `yt_judgment` + `kol_relevance` + `kol_quality` + `kol_viewpoint`
3. 社区文本：`gr_post` + `kol_refined` + `kol_relevance` + `kol_quality` + `kol_viewpoint` + `kol_judgment`

## 12. 建议新增：全来源 Actionability Prompt

当前 `sv_call` 已经很好地解决了 X 的可行动 call，但其它来源还没有统一 actionability。建议新增：

表：`opinion_actionability`  
粒度：`source + item_id + ticker`

输入：

```json
{
  "source": "youtube",
  "item_id": "7-rjKHooC70",
  "ticker": "MU",
  "current_price": 123.45,
  "author": "Channel Name",
  "created_at": "2026-06-20",
  "text": "summary + key points + fulltext excerpt"
}
```

Prompt：

```text
你是投资观点结构化分析器。给定一条关于指定美股的内容，判断它是否构成对该标的有操作含义的观点。
你只分析指定 ticker，不评价观点是否正确。

请输出严格 JSON：
{
  "is_actionable": boolean,
  "action_type": "buy|add|hold|trim|sell|short|watch|avoid|unknown",
  "stance": "bull|bear|neutral",
  "horizon_bucket": "short|mid|long|unknown",
  "conviction_score": 0.0,
  "evidence_score": 0.0,
  "specificity_score": 0.0,
  "thesis_type": "valuation_gap|growth_catalyst|risk_warning|technical_entry|macro_liquidity|earnings_reaction|insider_flow|portfolio_strategy|news_recap|other",
  "target_price": null,
  "buy_zone": {"lo": null, "hi": null},
  "sell_zone": {"lo": null, "hi": null},
  "risk_flags": ["..."],
  "evidence_span": "原文中最能支持该判断的一小段",
  "summary_zh": "一句中文总结",
  "summary_en": "one-line English summary",
  "exclusion_reason": "若 is_actionable=false，说明原因；否则空字符串"
}

规则：
1. 新闻转述、纯情绪、广告、复盘炫耀、无方向 watchlist，不算 actionable。
2. 条件式计划可以算 actionable，但必须有明确方向和条件。
3. 目标价、买入区间、卖出区间只能来自原文显式内容，不能从情绪推断。
4. thesis_type 只选一个主类型。
5. 如果内容主要不是在讲指定 ticker，is_actionable=false，并说明是 context mention。
```

输出表：

```sql
CREATE TABLE IF NOT EXISTS opinion_actionability (
  source TEXT NOT NULL,
  item_id TEXT NOT NULL,
  ticker TEXT NOT NULL,
  is_actionable INTEGER NOT NULL,
  action_type TEXT,
  stance TEXT,
  horizon_bucket TEXT,
  conviction_score REAL,
  evidence_score REAL,
  specificity_score REAL,
  thesis_type TEXT,
  target_price REAL,
  buy_lo REAL,
  buy_hi REAL,
  sell_lo REAL,
  sell_hi REAL,
  risk_flags_json TEXT,
  evidence_span TEXT,
  summary_zh TEXT,
  summary_en TEXT,
  exclusion_reason TEXT,
  model TEXT,
  labeled_at TEXT,
  PRIMARY KEY (source, item_id, ticker)
);
```

## 13. 建议新增：个性化推荐排序层

个性化推荐不建议写进原始 AI 标签表，而应作为派生排序层。

用户输入：

- 成本价：精确值或区间
- 仓位方向：做多 / 做空 / 观望
- 持仓占比：精确值或区间
- 操作习惯：短线 / 中线 / 长线 / 目标价偏好
- SV 偏好：Top X% / 中部 / 尾部区间

推荐使用 deterministic score：

```text
fit_score =
  0.30 * quality_score
+ 0.25 * relevance_score
+ 0.15 * horizon_match
+ 0.15 * position_need_match
+ 0.10 * target_price_match
+ 0.05 * sv_percentile_bonus
```

LLM 只用于生成解释，不用于直接排序：

```text
你是投资信息推荐解释器。给定用户对某只股票的可选持仓信息，以及一条结构化观点标签，
解释为什么这条观点值得或不值得该用户优先阅读。
不要提供投资建议，不判断观点对错，只解释匹配关系。

输出严格 JSON：
{
  "fit_reason_zh": "一句话说明为什么适合/不适合",
  "risk_note_zh": "若用户仓位或成本价使该观点特别重要，说明风险；否则空字符串",
  "fit_tags": ["..."]
}
```

## 14. 当前推荐运行顺序

单个标的开发时尽量使用 `--only`，避免无意义全量重跑。

```bash
# 1. 原始数据
make toss
make youtube
make yt-channels

# 2. 全球社区轻量情绪
make gr-tag

# 3. YouTube
make youtube-digest
make youtube-judgment
make youtube-creator-view

# 4. 观点流标签
make kol-refine
make kol-relevance
make kol-quality
make kol-viewpoint
make kol-judgment
make kol-translate
make kol-argument

# 5. X / SV
make tw-sentiment
make sv-v0

# 6. 时间序列
make kol-sentiment
make kol-volume
make retail-sentiment
make retail-volume
make retail-newcomers
make kol-newcomers

# 7. 派生看板
make overall-signals
make narrative-rotation

# 8. 静态站点
make site
```

## 15. 产品层读取关系

| 产品功能 | 主要读取 |
| --- | --- |
| 标的详情页观点流 | `web/lib/kolQueries.ts` |
| 观点搜索/筛选/排序 | `kol_relevance`, `kol_quality`, `kol_viewpoint`, `kol_refined`, `yt_analysis`, `sv_call` |
| YouTube 正文阅读 | `yt_fulltext`, `yt_digest` |
| 投资者摘要 | `yt_digest`, `yt_judgment`, `yt_analysis` |
| 目标价时间线 | `kol_judgment`, `yt_judgment`, `sv_call.target_price` |
| 高质量开关 | `kol_quality` |
| SV 筛选 | `sv_investor_score`, `sv_call`, `sv_segment_score` |
| 整体数据图表 | `kol_sentiment_daily`, `kol_volume_daily`, `retail_sentiment_daily`, `retail_volume_daily`, `price_daily`, `overallData.json` |
| 作者榜单 | `web/lib/investorQueries.ts`, `x_opinion`, `yt_video`, `gr_post`, `yt_channel` |
| YouTube 作者详情 | `web/lib/creatorQueries.ts`, `yt_video`, `yt_analysis`, `yt_judgment`, `yt_creator_view`, `yt_channel` |
| 叙事轮动 | `web/lib/data/narrativeRotation.json` |

## 16. 最小下一步

优先级：

1. 做 `opinion_label` 聚合层，先不改现有表。
2. 把 `tweet_id / video_id / gr_post.id` 作为前端点击跳转的统一源 ID。
3. 给非 X 来源补 `opinion_actionability`。
4. 把 `sv_percentile` 缓存到聚合层，支撑 Top 25% / 中部区间 / 尾部区间筛选。
5. 为目标价图表新增 `price_reference`，不要直接放宽 `kol_judgment` 的严格规则。
6. 个性化推荐第一版用 deterministic score，LLM 只写解释。
