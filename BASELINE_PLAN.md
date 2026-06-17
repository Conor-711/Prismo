# 基线情报系统 · 初版数据分析方案（待评审）

> 状态：**v3 / 研究阶段 · 待你评审**。本文是设计规格，尚未动代码、未改 ARCHITECTURE.md。**算法尚未定型**（§0.5、§5-bis）。
> 目标：把现有「实时舆情看板」升级为「**有 3 个月统计基线、能识别偏离与意图、能从噪音里挑信号**」的情报系统。
> 起草日期：2026-06-16。
> v2 增补：每论坛满 3 个月（§1.3、§4）；跨论坛可比性=各论坛独立基线+标准化后再比（§2.6）；结构性看涨偏差校正（§2.7，Miller 1977）；反讽+本土化用语识别（§6）；可演进/可回测的算法架构预设（§5-bis）。
> **v3 校正（按你第三轮反馈）**：明确「**抓异动为主、保真为承重地基**」的目的定位（§0.5）；纠正「给空头加权」的方法论错误——**非对称归决策、不归测量**，基线保持无偏（§2.7 科学性说明）；算法**研究方法论驱动选型**（EDA 先行/评估先行/冠军-挑战者/FDR/反身性混杂控制，§5-bis）。

---

## 0. 你已拍板的四个方向（本方案的地基）

| # | 决策 | 含义 |
|---|---|---|
| 1 | **分层漏斗打标** | 全量帖+采样评论用 DeepSeek flash 打 情绪/立场/意图（便宜，喂所有基线）；仅高互动/高质量帖送千问 HIGH 深析（双语论据，进 UI）。 |
| 2 | **ETF 当标的 + 期权当信号** | SPY/QQQ/IWM… 当普通标的进宇宙；calls/puts/0dte/strike 等期权语言抽成「杠杆/方向意图」信号，挂到**底层标的**。 |
| 3 | **增强主线 + 新增基线层** | 主 `posts/comments/item_analysis` 就地扩展（意图字段、ETF/期权、补爬评论）；另起一套**与来源无关的基线层**表（每标的×每维度的长期分布+偏离）。一套数据两层。 |
| 4 | **异动告警 + 情境化看板都要** | 底层是「相对自身 3 月常态」的偏离检测引擎；上层把偏离喂给带基线带/百分位/regime 的看板。 |

---

## 0.5 目的与研究阶段定位（v3 校正）

**两个目的、有主次，且不冲突：**
1. **【主】抓异动、从噪音里提信号** —— 价值在于发现「脱离预期」的信号，给用户交易决策**机会**（不是建议）。本质上这是一个**异常 / 变点检测**问题：先建「正常」的模型，再标出低概率的偏离。
2. **【次，但承重】尽可能科学还原每个论坛真实样貌** —— 这**不是与主目的竞争的目标，而是主目的的地基**：异常检测的「正常模型」若有偏，假阳/漏报必然增多。所以**保真是为抓异动服务的**——哪里的失真会制造假异动或掩盖真异动（反讽→假情绪波动、机器人刷量→假声量尖峰、季节性→假工作日异常），就在哪里投入保真；与抓异动无关的保真不优先。

**研究阶段，不过早定算法**：下文所有具体方法（z / robust-z / EWMA / 分位 / STL / BOCPD…）一律是**候选、不是结论**。选型由**评估驱动**（见 §5-bis：回测 / 合成注入 / 事件研究），用冠军-挑战者并行跑、版本戳记录、让数据选方法。把架构做成可插拔 + 可版本，正是为了**保持开放**，而非现在拍板。

---

## 1. 三个硬约束（先对齐预期，避免做无用功）

1. **Reddit 评论拿不到「赞/踩分票」**：Reddit 只给评论的**净分 `score`**，无单独赞踩、无评论级 upvote_ratio。帖子能拿 `score`+`upvote_ratio`（可反推近似 up/down）。→ 「赞/踩」对 Reddit 评论只落净分；日本 Yahoo（そう思う/いいえ）、Naver（추천/비추천）有真·分票，雪球只有赞。各源能力差异写进 schema 的 `source` 维度，基线**按源分别建**，不跨源硬比绝对值。
2. **Reddit 没有「浏览量」**：API/Arctic 都不给 view 数。Reddit 的「曝光」用 `score + num_comments + 板块订阅数` 做代理。浏览量字段只对 jp/kr/cn 有真值（已在 `asia_posts/gr_post`）。
3. **所有论坛都做满 3 个月**（你的要求，已采纳为硬目标）。各源历史**可达但取法不同**，逐源给回填策略：
   - **Reddit**：Arctic Shift 档案库，按时间分页直接回填 90 天，最稳，做基线锚。
   - **PTT**：综合板**不删帖**，`/bbs/Stock/index{N}.html` 索引页可一路往回翻到 3 个月前（页多但可达）；按 `M.{epoch}` 解析发文时间，翻到越界即停。
   - **Yahoo JP / Naver**：论坛接口支持翻页（page 参数），可回到 90 天；慢，需限速 + 断点续。
   - **雪球**：`status.json?page=N` 可分页回看，但过 WAF 高频 ~1500 次后会被挑战。→ **分多浏览器会话/分多天、按标的分块、幂等可续**地采，把 40 标的×~30 页摊到几轮跑完。
   各源实际覆盖窗仍**入库记录 + UI 标注**（窗口达标=正常基线；个别源若某段缺数=带加宽、降置信，不报假异动）。

---

## 2. 五个方法论问题的解法

### 2.1 基线如何定义
对每个 `(标的, 维度, 来源)`，用**只回看过去的滚动窗** `[t−90d, t−1]`（绝不含 t 之后数据，杜绝未来函数）建经验分布，日粒度。两种统计口径按维度选：

- **有界维度**（情绪 −1..1、多空比 0..1）：用**均值/标准差**，z 检验。
- **计数/重尾维度**（声量、互动、期权提及）：先 `log1p` 进对数空间，用**中位数 + MAD（稳健）**，避免少数爆帖把均值/方差拉飞。
- **季节性**：先去周内效应——估每周 7 天的乘性因子 `dow_factor[w]`（周末 Reddit 量天然低），把序列除以因子再算统计量；盘中维度同理去小时效应。
- **双速基线**：长期窗给「稳定常态」(均值/分位)，叠一条 **EWMA**（α≈0.3，约近 6 天权重）给「短期预期」。今天的「意外量」= 实测 − EWMA 预期，其**显著性**用长期 σ 衡量。
- **样本下限保护**：当日样本太少的维度→带加宽、标 `sparse`、降置信，**不报警**（防小样本假阳性）。

落库：`metric_daily`（原始序列）→ `metric_baseline`（每序列的滚动统计参数，每日更新）。

### 2.2 偏离基线的阈值如何定义
- **计数/重尾**：稳健 z `rz = 0.6745·(y − median)/MAD`（y=log1p 值）。`|rz|≥2` = 显著，`≥3.5` = 极端。
- **有界维度**：去季节后标准 z，`|z|≥2` 显著、`≥3` 极端；并行算**百分位**（≥p95 / ≤p5）。
- **双门控降假阳**（沿用并泛化现有 `is_spike=z≥1 且 recent≥2`）：报警需**同时**满足 ① 统计显著（z 或百分位）且 ② 绝对量达标（当日量 ≥ `min_abs` 且 ≥ `k×自身中位数`）。
- **自校准**：所有阈值都以「该标的自己的 σ/百分位」表达，因此 50 帖/天的大票和 5 帖/天的小票各按各自常态判断——这正是 z-score 能跨标的比较的精髓。
- 阈值全部放配置（`min_abs/k/z_notable/z_extreme/window_days`），方便回测调参。

### 2.3 意图与行为如何分类
用**两条正交轴**（比单个大标签更可分析），由 flash 批量打标产出，每标签带 `conviction`：

- **意图 intent（这帖在「做什么」）**：`info_share`（DD/分析/转新闻）、`info_seek`（提问求助）、`trade_signal`（喊单/方向判断）、`position_disclosure`（晒持仓/盈亏）、`hype`（FOMO 鼓动）、`fud`（唱空恐吓）、`macro`（宏观）、`meme_noise`（玩梗/灌水）。
- **动作 action（隐含交易）**：`buy_add`、`sell_trim`、`hold`、`short`、`hedge`、`none`；外加 `derivative` 标记（来自期权抽取器）。

价值：可建**意图基线**（如某票常态 60% info_share，今天 70% hype → 叙事 regime 变了），并支撑 2.4 的「拥挤+一边倒=反向」规则。

### 2.4 如何从噪音的海量数据中找价值
**分层降噪 → 偏离即价值 → 拥挤反向**：
1. **硬过滤**：近重复文本哈希去重、bot/复读机启发式、ticker 碰撞 allow/deny + 邻近规则（部分已有）、最短长度。
2. **质量门**：`quality_score`（已存在）把「干货 DD」与「灌水」分开，低质不进信号但进声量。
3. **加权而非等权**：每条按 `log(1+score)·quality·作者影响力` 加权——2000 赞的 DD 远重于 50 条一句话梗。即「来源加权、不让单一声音主导」。
4. **价值=偏离不是水位**：头条产出是「**相对自身基线**，谁在声量/情绪/意图/期权偏度上异常」。
5. **拥挤/反向叠加层**（有学术支撑：异常高讨论度的标的随后常跑输）：`声量≥p95 且 |净情绪|≥p90 且 hype 意图≥p90` → 标 **过热/拥挤**，列为反转候选。这是竞品没做好、能差异化的「价值信号」。
6. **复合信号分**：把 声量-z、情绪-Δ、意图迁移、期权 call/put 偏度、质量加权净情绪合成一个可排序分，每条附**白话「为什么」**。

### 2.5 情绪分布与极值基线如何分析
不要把情绪压成一个均值：
- **存整条分布**：每标的每日存情绪**分桶直方图**（极空…极多）+ **离散度**（std）+ **极化指数**（双峰系数 `BC=(skew²+1)/kurt`）+ 偏度。
- **极化本身是信号**：均值≈0 可能是「真中性」也可能是「多空对撕」（双峰）——后者风险/机会都更大，要区分。
- **极值基线**：每标的取其 90 天「日均情绪」分布的经验 **p1/p5/p95/p99**，定义「它最多空/最多头到什么程度」。今天读数表达为**它自身历史里的百分位** →「情绪处于近 3 月第 97 百分位（极度贪婪区）」。对齐 S-Score 的 |z|>2 极端 / >4 极极端惯例，但**逐标的自校准**。
- **市场级恐惧贪婪**（现有 `market_mood`）同样接基线层 → 输出归一化指数而非裸均值。

### 2.6 跨论坛可比性：各论坛独立基线 + 标准化后再比（你的第 2 问）
**结论：每个 `论坛 × 标的 × 维度` 各建独立基线，不设统一的绝对基线。** 理由与做法：
- 各论坛的「中性点 / 方差 / 季节性 / 结构偏差 / 噪音率」都不同（WSB 梗多极端、Naver 情绪化、PTT 偏分析、雪球术语体系不同、Yahoo JP 有持股认证）。**绝对情绪值跨论坛不可比**，硬比会把「天生更乐观的论坛」误判成「更看多」。
- z-score / 百分位的本质就是「拿每个实体跟它自己的历史比」——把基线 key 直接扩到 `(标的, 维度, **论坛 source**)`（schema 已含 `source` 维）。
- **比较/聚合一律在标准化空间**（z 或百分位），不比原始绝对值。现有 gr_* 的「共识 / 分歧」改成基于**论坛相对 z**，而非裸情绪：例如「TSM 在台湾 −1.8σ 但在大陆 +0.5σ」远比「台湾 −0.10 vs 大陆 +0.07」可靠。
- **全球聚合情绪 = 各论坛相对偏离的「置信度加权平均」**（样本多/历史长的论坛权重高），而非把不同标尺的原始分相加。
- 新增 **「论坛画像表」`forum_profile`**：记每论坛结构常数——`μ_sentiment`（结构性看涨偏差，见 §2.7）、典型方差、`dow_factors`、噪音率、**俚语词典版本号**（见 §6）。跨论坛视图只读标准化列。

### 2.7 结构性看涨偏差的校正（你的第 4 问，Miller 1977）
**学术依据**：做空比做多难（融券成本/可得性/心理门槛），**看空意见无法充分表达**——Miller (1977)「短卖受限 + 意见分歧 → 价格由最乐观者决定 → 系统性高估」；实证上高分歧+卖空受限的票未来回报偏低（即看涨过头）。所以论坛情绪**天然正偏，这是系统性偏差、不是信号**。从根上校正，分四层：
1. **测「偏离」不测「水位」（主解法）**：每论坛有自己的基线（§2.6）后，结构性看涨就**变成了基线本身（零点）**。我们不问「是不是 +0.3」，只问「相对本论坛常态，今天是不是 +2σ」。一个常态 +0.3 的论坛掉到 +0.1，**即使仍为正也是看空信号**——偏差被标准化自动吸收掉。
2. **显式去均值 + 论坛自有中性线**：估每论坛长期均值 `μ_forum`（落 `forum_profile`），图上「中性线」画在 `μ_forum` 而非 0，展示 `s − μ_forum`。
3. **看空的「稀有性」放在「评分层」体现，绝不在「基线/估计层」加权**（回应你的提问，详见下「科学性说明」）。不对原始看空帖人为乘权重，而是：① 单独给「**看空占比** b(t)=空/(多+空)」建基线——常态 10% 的论坛今天冲到 25%，在 b(t) 自己的序列上就是约 +4σ 的强异常，**稀有性由它自身的低均值/低方差自动放大，无需手调权重**；② 用**惊奇度 / 似然**评分（surprise = −log P(今日 | 基线)），罕见配置自动得高分（这才是「稀有事件 bit 多」的正确实现——在评分层，不是篡改样本）；③ 叠加 `derivative_mention` 的 **put 语言 / call-put 偏度**，作为不依赖「写空头长文」的独立看空通道。
4. **优先二阶、抗水位偏差的信号**：变化率 Δ情绪、**极化/分歧**（多空对撕，免疫均值偏差）、看空占比 z、put 偏度——都不受论坛整体正偏影响；极端看多+拥挤再叠 §2.4 反向旗（Miller 实证：看涨过头→未来低回报，正是反转候选）。

> **科学性说明（回应「给空头更高权重是否伤基线的科学性」）**：会——**如果在估计层加权**。那等于系统性把「正常」往下拉，估计量有偏（E[θ̂]≠θ），基线不再忠实于论坛，§0.5 的第 2 目的破产。所以用**三层分离**：
> - **估计层（基线）= 无偏**：忠实测量论坛真实状态（含它结构性的看涨），不对任何一方加权。这保证科学性。
> - **检测层（异常分）= 有原则的非对称**：通过「给看空占比单独建基线 + 惊奇度评分」自然让稀有的看空更突出——**不是手动权重，是统计本身给的**。
> - **决策层（给用户）= 可透明非对称**：若看空异动更可操作，可在排序/告警用一个**显式、可调、可文档化**的效用函数抬权——但与测量隔离，不污染基线。
>
> 一句话：**非对称属于「决策」，不属于「测量」。** 不要跟「论坛的乐观」比，要跟「论坛自己的乐观基线」比；空头的"更值钱"靠 给看空占比单独建基线 + 惊奇度评分 + 决策层效用 来实现，而非给样本乘权重。

---

## 3. 数据库更新（schema）

**A. 既有表就地扩展**
- `ticker_meta`：+ `asset_class String(16)`（equity|etf|adr|index，默认 equity），ETF 宇宙据此纳入。
- `item_analysis`：+ `intent String(24)`、`action String(16)`、`tone String(16)`（sincere|ironic|joke，反讽轴）、`conviction Float`、`horizon String(16)`（scalp|swing|long|none，选填）、`algo_version String(16)`、`model`（已可记）。（`quality_score` 已有，复用作降噪门。）
- `comments`：列够用（Reddit 评论只有净 `score`）；变化在**采集范围与是否参与分析**（见 §4），不在列。
- `posts`：不加列；近似 up/down 在查询期由 `score + upvote_ratio` 算（`ups=score·r/(2r−1), downs=ups−score`）。

**B. 新表 · 期权信号（轻）**
```
derivative_mention(
  id PK, item_id, item_type, ticker(底层),
  direction String(8)  -- call|put|share|spread
  dte_bucket String(16)-- 0dte|weekly|monthly|leaps|unknown
  strike Float?,  moneyness String(8)? -- itm|atm|otm|unknown
  created_utc, fetched_at )
```
派生维度：每标的的 **call/put 提及比**，作为散户杠杆方向情绪代理。

**C. 新表 · 基线层（与来源无关，三件套）**
```
metric_daily(  -- 统一长序列（所有源、所有维度）
  id PK, scope(ticker|market|sector), key(标的/'*'/行业),
  market, source(all|reddit|jp|kr|tw|cn),
  dim(volume|sentiment|net_stance|bull_ratio|polarization|
      intent_hype|intent_seek|action_buy|call_put|engagement|quality...),
  bucket(day|hour), bucket_ts, value Float, n Int,
  UNIQUE(scope,key,market,source,dim,bucket,bucket_ts) )

metric_baseline(  -- 每序列的滚动统计参数（每日重算）
  id PK, scope,key,market,source,dim,bucket,
  window_days, as_of, transform(raw|log),
  mean,std,median,mad, p05,p25,p50,p75,p95,p99, ewma,
  dow_factors JSON(7), n_obs, algo_version, params_hash,
  UNIQUE(scope,key,market,source,dim,bucket) )

metric_signal(  -- 今日偏离/告警（每维度一行 + 每标的一行复合）
  id PK, scope,key,market,source,dim, as_of,
  value, expected, z, robust_z, percentile,
  regime(normal|elevated|extreme_high|depressed|extreme_low),
  is_extreme Bool, direction(up|down), sample_n, confidence, algo_version,
  composite_score Float,  -- 仅 dim='_composite' 行有
  reason Text )           -- 白话「为什么异动」

forum_profile(  -- 每论坛结构常数（支撑 §2.6 跨论坛标准化 / §2.7 去偏 / §6 词典）
  source PK, market, mu_sentiment, std_sentiment,
  dow_factors JSON(7), noise_rate, lexicon_version,
  coverage_start, coverage_days, updated_at )

algo_eval(  -- 回测/校准结果（§5-bis 让算法有据、可证伪）
  id PK, algo_version, dim, metric(precision|recall|hit_rate|sarcasm_err...),
  value, window, as_of, notes )
```
> 迁移原则不变：**绝不对云端 Supabase 直接跑建表 DDL**；我产出迁移脚本，你本地 `DATABASE_URL='sqlite:///./data/dev.db'` 验证后，由你在云端执行。基线三表 + `forum_profile`/`algo_eval` 是**派生**（可弃可重算），只进 `ALL_TABLES`/快照，不进 `sync.SOURCE_TABLES`。`derivative_mention` 属源数据，进 `SOURCE_TABLES`。

---

## 4. 爬虫更新

- **Reddit 90 天回填**（扩 `arctic_scrape`）：新增 `backfill(days=90)`，按时间分页拉**帖+评论**，幂等（按 id `merge`），可断点续。一次性重跑，之后 `make daily` 增量滚动维持 90 天窗。
- **评论纳入分析**：现状评论只为 Top 展示帖抓取、且「不参与 mention/分析」。改为：**凡提及在册标的的帖，抓其 Top N 评论（按 score，N≈30 封顶控量）→ 抽 mention → flash 打标**。评论是情绪/意图基线的重要样本。
- **期权语言抽取**：新 `ingest/derivative_extract.py` 正则 pass（calls/puts/`\d+c`/`\d+p`/strike/0dte/weeklies/LEAPS）→ `derivative_mention`，挂底层标的。
- **ETF/衍生品宇宙**：扩 `seed_tickers`，补主流 ETF（SPY/QQQ/IWM/VOO/ARKK/SOXL/TQQQ/SQQQ/XLK/XLF…）+ `asset_class`。
- **其他论坛（jp/kr/tw/cn）一律回填满 90 天**（§1.3 逐源策略：PTT 翻索引页、Yahoo/Naver 翻 page、雪球分会话/分块过 WAF），仍写 `asia_*/gr_post`，但**统一喂同一基线引擎**（引擎读跨表的统一视图）。各源实际覆盖窗记录在 `forum_profile`、UI 标注。

---

## 5. 算法更新（基线引擎，纯计算/低成本）

新 `analyze/baseline.py` + `analyze/signals.py`：
1. **聚合**：从 `posts/comments/item_analysis/mention/derivative_mention` + `asia_*/gr_post` 汇成 `metric_daily`（每源每维度每日 value+n）。
2. **去季节**：估 `dow_factors`，计数维度乘性去季、有界维度加性去季。
3. **建基线**：滚动 90d 算 `metric_baseline`（计数走 log+median+MAD，有界走 mean+std；全分位；EWMA）。
4. **算偏离**：今日值 → z / robust_z / 百分位 / regime；双门控判 `is_extreme`；样本定 `confidence`。
5. **复合 & 降噪**：质量/影响力加权；拥挤反向规则；合成 `composite_score` + 生成白话 `reason`，排序出**异动榜**。`trending` 表被该层取代/吸收。

公式速记：
```
去季(计数):  x' = x / dow_factor[weekday]
稳健z(计数):  y=log1p(x');  rz = 0.6745·(y−median_y)/MAD_y
z(有界):      z = (x'−mean)/std
EWMA:         e_t = α·x_t + (1−α)·e_{t−1}    (α≈0.3)
百分位:        rank(今日, 过去90d经验分布)
报警门控:      (|rz|≥2 或 pct≥.95/≤.05) 且 x≥max(min_abs, k·median)
拥挤反向:      vol.pct≥.95 且 |net_senti|≥p90 且 hype.pct≥.90
极化:          BC=(skew²+1)/kurt  ；尾部占比
```

---

## 5-bis. 算法架构预设（可演进 / 可回测 / 有据）（你的第 5 问）

**先把它当研究问题，而不是工程实现**——一个数据/算法 PhD 的做法（这一段比下面的具体方法更重要，且明确「先别定算法」）：
- **R0 先 EDA、不先建模**：刻画每论坛每指标的分布（重尾？对数正态？双峰？零膨胀？）、平稳性（「正常」本身稳不稳，还是 regime 切换？）、自相关 / 季节性、多空基率、跨论坛跨标的相关结构、混杂结构。**这一步决定哪类模型合法**——别默认高斯 z 能用，要先检验（很可能不能）。
- **先定义「异常是哪一种」**：点异常（单日尖峰）/ 情境异常（值正常但语境错，如周末高量）/ 集体异常（持续位移=变点/regime）——三类对应不同检测器，不是一招通吃。
- **评估先行、再选算法**：先建评估口径与「地面真值」——事件研究（异常是否**领先于**财报/停牌/新闻/大幅价格波动与未来收益）、**合成异常注入**（量检出力 ROC/PR、检测延迟）、严格 walk-forward 无未来函数。**先定指标（precision@k、领先时间、AUC-PR、误发现率），再让指标选方法。**
- **冠军-挑战者并行**：z / robust-z / EWMA / STL 残差 / 分位 / BOCPD / isolation-forest 等候选**并行跑、版本戳记录**，让回测选，保持开放——这正是「不过早定算法」的工程载体。
- **多重检验校正**：~500 标的 × ~10 指标天天扫 |z|>2，纯靠运气也会冒出几十个假阳——必须上 **FDR（Benjamini-Hochberg）**或更高门槛，并报告期望假阳率。（这是对上一版「|z|≥2 朴素阈值」的重要修正。）
- **混杂控制**：价格→情绪的**反身性**（最有价值的常是「价格还没反映」的情绪——可考虑对近期收益**正交化后的情绪残差**作信号）；机器人/串联刷量；ticker 碰撞；存档选择偏差。
- **不确定性量化**：每个异常分带置信（样本量、基线稳定度）；薄数据标的用层次贝叶斯向论坛/行业先验收缩，别乱报。

落到工程，为支撑上面这套「可迭代科学流程」，定四条架构原则：

1. **分层可插拔接口**（每层定契约，实现可换、参数可调，配置在 `data/baseline.yml`）：
   - `BaselineEstimator`：mean/std｜median/MAD｜EWMA｜分位 →（路线图）STL 季节分解 / Holt-Winters / 贝叶斯收缩。
   - `Detector`：z｜robust-z｜百分位｜双门控 →（路线图）CUSUM / 在线变点(BOCPD, PELT) / HMM regime。
   - `Tagger`：flash｜千问思考 →（路线图）FinBERT / 本地模型；统一输出契约 `{sentiment, stance, intent, action, tone, conviction, quality}`。
   - `Weighting`：log-engagement × quality × author × 稀有性（§2.7）。
2. **版本戳 + 可复现**：每条 `metric_baseline / metric_signal / item_analysis` 落 `algo_version`、`params_hash`、`model`。换算法只升版本号、不破坏历史 → 可并行 A/B、可回滚、可解释「这条信号是哪套算法/参数/模型产出的」。
3. **回测/验证框架**（让「有理有据」可证伪）：留全量 `metric_signal` 历史；新 `analyze/backtest.py` 做**事件研究**——把「异动/极端」信号对齐**未来价格收益**（`asia_price` 已有日K，美股补一个免费日K源），算信号前瞻命中率 / 精确率·召回 / 是否符合 Miller 反转假设；校准集量反讽与情绪误差。结果落 `algo_eval` 表，指导调参。
4. **小样本贝叶斯收缩（路线图占位）**：薄数据标的的基线向其**所属论坛/行业先验**收缩（层次模型），防少样本下 z 乱跳；接口预留，先用「样本下限 + 加宽带」兜底。

---

## 6. AI 架构更新（三级漏斗正式化）

| 级 | 模型档 | 职责 | 成本 |
|---|---|---|---|
| **L0 全量** | DeepSeek **flash (LOW)** | 每帖+采样评论 → `{sentiment, stance, intent, action, conviction, quality}`，批量 JSON（15–30/次） | 低，喂**所有**基线 |
| **L1 汇总** | DeepSeek **pro (MID)** | 叙事/主题聚类、每日简报、**regime 变化叙述**（新） | 中 |
| **L2 深析** | 千问 **HIGH** | 仅高质量/高互动帖（漏斗顶）→ 双语 bull/bear 论据、深度 TLDR | 高但量小，集中在 UI 可见处 |

- **开 prompt 缓存**（现有 TODO）+ 批量调用，砍回填成本。
- **幂等回填**：`only_new` 按 `item_id` 持久化，可断点续（沿用现模式）。
- 近重复先用**文本哈希**去重（零成本），embedding 去重列为后续可选。

### 6.1 本土化用语识别（你的第 3 问 · 词汇）
给每论坛建**俚语/术语词典**并**注入对应论坛的打标 prompt**（few-shot + 词义对照表），让模型按本土语义解读：
- WSB: tendies / diamond hands / bagholder / to the moon / printer go brrr / drilling / `/s`
- 雪球: 韭菜 / 抄底 / 套牢 / 割肉 / 接盘 / 利好·利空 / 牛·熊
- PTT: 航海王 / 起飛 / 畢業 / 嘎空 / 低基期
- Naver: 떡상·떡락 / 존버 / 물타기 / 손절
- Yahoo JP: 爆益 / 損切り / ナンピン / ホルダー / イナゴ

词典纳入版本管理（`forum_profile` 记词典版本号），可持续扩充。

### 6.2 反讽 / 反语识别（你的第 3 问 · 语气）
纯文本反讽极难——研究共识：词典法（Loughran-McDonald / VADER）在 WSB 上**经常把正话当反、反话当正**。用**低成本筛 → 高成本裁**两段式，把贵模型只花在难句上：
1. **反讽风险标记器（零/低成本规则）**：命中 `/s`、🌈🐻/🚀 反用、"loss porn"、"totally not financial advice"、"sure it'll bounce"、全大写、**陈述动作与情绪自相矛盾**（说「all in」却配崩盘梗）等 → 标 `irony_risk`。
2. **升级裁决**：`irony_risk` 或 flash 低置信的帖 → **升级到千问思考档**重判（带本论坛词典）。普通帖留在 flash，成本可控。
3. **显式 `tone` 轴**：tagger 多输出 `tone ∈ {sincere, ironic, joke}`（落 `item_analysis`）；ironic 时按规则反转 / 中性化有效情绪。
4. **原生标签当免费监督**：Yahoo 強気/弱気、Naver 매수/매도、PTT [類別] 与模型读数**强烈不一致** → 当反讽/疑义旗，触发升级。
5. **校准集**：每论坛人工标 ~100–200 条小样本，量反讽错误率、调阈值；纳入 §5-bis 的回测/校准框架。

---

## 7. 管线 / 命令

- 新模块：`ingest/derivative_extract.py`、`analyze/baseline.py`、`analyze/signals.py`；扩 `arctic_scrape.backfill`、`reddit` 评论采集。
- 新 CLI / Makefile：`make backfill`（一次性 90d 回填+打标）、`make baseline`（建基线）、`make signals`（算偏离），并入 `make daily`：`…analyze → derivatives → baseline → signals → translate`。
- 配置集中：阈值/窗口/采样上限放 `data/baseline.yml` 或 `config.py`，便于回测。

---

## 8. Web 呈现（情境化看板）

- **个股页**：情绪基线带（p25–p75 灰带 + 今日点）、声量 vs 基线、意图构成 vs 自身常态、call/put 偏度、「现处近 3 月第 N 百分位」。
- **异动/偏离榜**（升级版 trending）：复合分排序 + 白话理由 + 过热/拥挤反向标。
- **分布视图**：情绪直方图 + 极化指数。
- 多语沿用 zh 源、en/ja/ko 镜像；图表复用 ECharts（父级只传可序列化 props）。

---

## 9. 分阶段落地（建议顺序，每阶段可独立验收）

| 阶段 | 内容 | 验收 |
|---|---|---|
| P0 | schema 迁移脚本（新列+基线三表+`derivative_mention`），本地 sqlite 验证 | `make stats` 见新表；tsc 通过 |
| P1 | ETF/衍生品宇宙 + 期权抽取器 | 样本帖能抽出 call/put/dte |
| P2 | Reddit 90d 回填（帖+评论）+ flash 打标 | 90d 语料入库、`item_analysis` 含 intent |
| P3 | 基线引擎 + 信号引擎 | `metric_baseline` 成形、异动榜有理由 |
| P4 | Web：个股基线带 + 异动榜 + 分布视图 | 构建出页、curl 校验 |
| P5 | 推广到 jp/kr/tw/cn（**各回填满 90 天**）+ `forum_profile` 跨论坛标准化 | 跨源基线、共识/分歧基于论坛相对 z |

---

## 10. 成本与可行性（量级估算，需回填中校准）

- Reddit 90d × ~15 板块：帖量看活跃度，**评论是量级放大器**——靠「每帖 Top 30 评论封顶 + 仅含标的帖才抓评论」两道闸控量。
- L0 flash 批量（15–30/次）+ prompt 缓存：把全量打标成本压到可接受；L2 千问只碰漏斗顶（量小）。
- 回填一次性、幂等可续；之后每日增量很轻。
- **建议先按 §0 漏斗 + Reddit 锚跑通 P0–P4，量出真实 token/时长，再决定其他论坛回填深度。**

---

## 11. 待你确认的开放点

1. **回填窗口**：已定**所有论坛满 90 天（3 个月）**。仅需确认：Reddit 锚是否要更长（如 6 个月，让基线更稳，但回填更贵）？
2. **评论采样上限**：每帖 Top 30 评论是否合适？（直接影响成本与评论级基线样本量。）
3. **拥挤/反向信号**：是否作为一等公民展示？（差异化亮点，但属「观点性」输出；我们不做投资建议，只标统计状态——需你确认调性。）
4. **行业(sector)基线**：是否要做（`scope='sector'`）？（能看「半导体板块情绪 vs 个股」，但需 sector 字典更全。）
5. **ETF 宇宙范围**：先给一批主流（指数/板块/杠杆 ETF），还是你有特定清单？

> 你确认这五点后，我把 P0 迁移脚本和 §3 的精确 DDL 先落地（本地 sqlite，不碰云端），再往下推进。
