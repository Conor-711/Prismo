# Smart Account 当前排名审计报告

> 审计时间：2026-07-18 19:10 CST
> 数据真源：`data/dev.db`（2026-07-18 16:49 修改，4.4 GB）
> 前端快照：`web/lib/data/smartVoice.json`（2026-07-18 15:24 导出）
> 评分版本：`v1.8-transcript-lifecycle`

## 1. 结论摘要

1. 当前共有 **2,041 位已评分作者**，其中 X 1,430、YouTube 350、Reddit 261；尚无雪球和 Toss 作者进入正式评分表。
2. 全局榜第一名是 X 作者 **@aleabitoreddit，SV_Global=164**；第二名 **@wey_how12640，160**；第三名 **@seedy19tron，155**。
3. **全局前 30 名全部来自 X**。YouTube 第一名 `@trendspider` 的全局排名为第 54，Reddit 第一名 `u/tomato241` 的全局排名为第 179。
4. 这不代表 YouTube 或 Reddit 没有优质作者。当前 YouTube 无 high-confidence 作者，Reddit 全部处于 observing，置信度折算会把平台内高分拉回 100 附近。因此跨平台使用时，**平台内排名比全局名次更有解释力**。
5. 全局分数高度集中：中位数 100，2,041 人中有 1,249 人位于 99–101；只有 32 人达到 120，95 人达到 110。
6. 全局 Top 10% 的分数门槛是 103，但共有 296 人达到 103。因为分数是整数且大量并列，Top 10% 成员还依赖 `raw_z`、置信度、`n_eff` 和已结算 call 数的顺序，**不能只用 `Score >= 103` 判断是否属于 Top 10%**。
7. 评分覆盖 51,769 条 actionable call，其中 37,348 条进入结算体系，占 72.1%。1D 结算成熟度为 97.9%，180D 仅为 33.7%，长期能力分仍明显受未成熟样本限制。

## 2. 排名口径

### 2.1 从观点到作者分

每条可执行观点会按 1D、5D、20D、60D、90D、180D 六个周期，相对 SPY 结算方向性超额收益。评分不是只看终点涨跌，还综合：

- 周期终点是否命中；
- 周期内最大有利超额；
- 正向持续天数占比；
- 从峰值回撤的惩罚；
- 观点质量、明确性、周期匹配和同帖证据预算；
- 同日重复观点合并、反向观点覆盖和观点生命周期结束。

作者原始能力为收缩后的贡献 z-score：

```text
z = Σ contribution / sqrt(expected variance)
n_eff = (Σ weight)^2 / Σ(weight^2)
raw_z = z × n_eff / (n_eff + 30)
```

`n_eff` 是跨周期加权后的有效证据量，不等于帖子数，因此可能高于 `settled_calls`。

### 2.2 平台分与全局分

作者先在自己的平台内部做稳健标准化：

```text
SV_Platform = 100 + 10 × robust_z(raw_z within platform)
```

其中 100 代表同平台合格作者的中位基线。平台分随后受两类上限约束：

- **可靠性上限**：observing 109、low 123、medium 145、high 180；
- **集中度上限**：过度依赖单一标的时限制为 118、126 或 135。

最后按证据置信度折算为全局分：

```text
SV_Global = 100 + (SV_Platform - 100) × confidence_factor
```

| 置信度 | 条件 | 折算因子 |
|---|---:|---:|
| high | `n_eff >= 60` 且 `calls >= 80` | 1.00 |
| medium | `n_eff >= 25` 且 `calls >= 35` | 0.85 |
| low | `n_eff >= 10` 且 `calls >= 15` | 0.65 |
| observing | 未达到以上条件 | 0.35 |

全局同分时依次按 `raw_z`、置信度、`n_eff`、已结算 call 数排序。平台榜同分时优先 `n_eff` 和已结算 call 数。

### 2.3 平台正式排名池

| 平台 | 已评分 | 达到平台资格 | 资格率 | 资格门槛 |
|---|---:|---:|---:|---|
| X | 1,430 | 533 | 37.3% | `n_eff >= 8` 且 `calls >= 10` |
| YouTube | 350 | 257 | 73.4% | `n_eff >= 4` 且 `calls >= 5` |
| Reddit | 261 | 154 | 59.0% | `n_eff >= 3` 且 `calls >= 4` |
| 雪球 | 0 | 0 | - | `n_eff >= 5` 且 `calls >= 8` |
| Toss | 0 | 0 | - | `n_eff >= 5` 且 `calls >= 8` |

平台资格只决定是否进入平台分布，不等于 high confidence。例如 Reddit 有 154 人达到平台资格，但全部仍是 observing。

## 3. 全局排名 Top 30

| 排名 | 作者 | 来源 | Score | 置信度 | n_eff | 已结算 Call | 主要标的 |
|---:|---|---|---:|---|---:|---:|---|
| 1 | @aleabitoreddit | X | 164 | high | 411.8 | 507 | NBIS、IREN |
| 2 | @wey_how12640 | X | 160 | high | 347.3 | 363 | MU、LITE |
| 3 | @seedy19tron | X | 155 | high | 207.6 | 178 | NKTR、ABVX |
| 4 | @King0ftheCharts | X | 150 | high | 114.9 | 96 | IBIT、MARA |
| 5 | @spacemnke | X | 147 | high | 258.4 | 233 | NVDA、AMD |
| 6 | @d_pavlos | X | 145 | high | 144.8 | 167 | META、NVDA |
| 7 | @Yeah_Dave | X | 142 | high | 170.7 | 155 | EOSE、ASTS |
| 8 | @SanCompounding | X | 141 | high | 111.2 | 172 | MU、NBIS |
| 9 | @Chartradamus | X | 135 | high | 489.5 | 424 | QQQ、ASTS |
| 10 | @Biotech2k1 | X | 134 | high | 327.2 | 344 | XBI、SOFI |
| 11 | @CorleoneDon77 | X | 134 | high | 155.5 | 136 | AAPL、BE |
| 12 | @jdmarkman | X | 134 | high | 773.3 | 473 | AMD、SMX |
| 13 | @AnthonySandford | X | 132 | high | 662.3 | 635 | NVDA、TSLA |
| 14 | @Yam_Trades | X | 132 | high | 298.8 | 392 | QQQ、RBLX |
| 15 | @AlexfromBabylon | X | 127 | medium | 56.6 | 42 | IREN、ASTS |
| 16 | @AorakiTrading | X | 126 | medium | 50.2 | 47 | ASTS、RKLB |
| 17 | @SebastinPatron3 | X | 126 | medium | 99.2 | 75 | QQQ、IWM |
| 18 | @jiahanjimliu | X | 126 | high | 121.2 | 96 | IREN、NBIS |
| 19 | @alshfaw | X | 125 | high | 1,748.8 | 1,323 | SMH、IWM |
| 20 | @EricJhonsa | X | 124 | medium | 61.9 | 63 | PSIX、NVDA |
| 21 | @Simply0DTE | X | 123 | medium | 50.6 | 40 | QQQ、CRWV |
| 22 | @harmongreg | X | 123 | high | 213.8 | 130 | AMAT、HD |
| 23 | @Tradr_G | X | 122 | medium | 95.4 | 61 | RGTI、IONQ |
| 24 | @TraderJonesy | X | 122 | high | 280.5 | 247 | TSLA、QQQ |
| 25 | @Mr_Derivatives | X | 122 | high | 80.4 | 82 | NVDA、CAR |
| 26 | @daniel_koss | X | 121 | medium | 57.1 | 58 | NBIS、IREN |
| 27 | @JonahLupton | X | 121 | high | 84.4 | 119 | TMDX、HIMS |
| 28 | @commonsenseplay | X | 120 | medium | 63.7 | 60 | TLT、QBTS |
| 29 | @SuperDuperInvst | X | 120 | medium | 68.4 | 69 | USAR、WKEY |
| 30 | @TheShortBear | X | 120 | medium | 39.8 | 35 | UNH、MSTR |

前 30 名中 high 20 人、medium 10 人，没有 low 或 observing。全局前 100 名中 X 92 人、YouTube 8 人；置信度构成为 high 35、medium 41、low 24。

## 4. 分平台排名

平台榜使用 `SV_Platform`，更适合回答“这个作者在自己的内容生态里是否异常优秀”。

### 4.1 X Top 10

| 平台排名 | 作者 | SV_Platform | SV_Global | 置信度 | n_eff | Call |
|---:|---|---:|---:|---|---:|---:|
| 1 | @aleabitoreddit | 164 | 164 | high | 411.8 | 507 |
| 2 | @wey_how12640 | 160 | 160 | high | 347.3 | 363 |
| 3 | @seedy19tron | 155 | 155 | high | 207.6 | 178 |
| 4 | @King0ftheCharts | 150 | 150 | high | 114.9 | 96 |
| 5 | @spacemnke | 147 | 147 | high | 258.4 | 233 |
| 6 | @d_pavlos | 145 | 145 | high | 144.8 | 167 |
| 7 | @Yeah_Dave | 142 | 142 | high | 170.7 | 155 |
| 8 | @SanCompounding | 141 | 141 | high | 111.2 | 172 |
| 9 | @Chartradamus | 135 | 135 | high | 489.5 | 424 |
| 10 | @jdmarkman | 134 | 134 | high | 773.3 | 473 |

X 正式池的 Top 10% 门槛为 118，Top 25% 为 108；Bottom 10% 门槛为 89，Bottom 25% 为 94。

### 4.2 YouTube Top 10

| 平台排名 | 作者 | SV_Platform | SV_Global | 置信度 | n_eff | Call |
|---:|---|---:|---:|---|---:|---:|
| 1 | @trendspider | 123 | 115 | low | 23.5 | 17 |
| 2 | @investrtrades | 121 | 114 | low | 30.5 | 18 |
| 3 | @stastalksstocks | 118 | 115 | medium | 74.2 | 50 |
| 4 | @datadispatch | 118 | 112 | low | 40.1 | 24 |
| 5 | @stocknewsleo | 118 | 112 | low | 24.1 | 16 |
| 6 | @themikejonesinvesting | 118 | 112 | low | 17.9 | 15 |
| 7 | @jeremylefebvre-clips | 118 | 112 | low | 14.7 | 15 |
| 8 | @reyjayinvests | 116 | 110 | low | 31.4 | 21 |
| 9 | @ripsterchartspriceaction | 114 | 109 | low | 30.1 | 20 |
| 10 | @parkevtatevosiancfa9544 | 113 | 108 | low | 33.8 | 34 |

YouTube 正式池的 Top 10% 门槛为 109，Top 25% 为 107；Bottom 10% 门槛为 84，Bottom 25% 为 93。当前没有 high-confidence YouTube 作者，只有 4 位 medium，故平台榜应同时展示 `n_eff` 和 Call 数。

### 4.3 Reddit Top 10

| 平台排名 | 作者 | SV_Platform | SV_Global | 置信度 | n_eff | Call |
|---:|---|---:|---:|---|---:|---:|
| 1 | u/Rose-n-Chosen | 109 | 103 | observing | 17.8 | 8 |
| 2 | u/TOPS-VIDEO | 109 | 103 | observing | 17.5 | 6 |
| 3 | u/tomato241 | 109 | 103 | observing | 15.7 | 8 |
| 4 | u/NumerousFloor9264 | 109 | 103 | observing | 15.5 | 8 |
| 5 | u/aresna33 | 109 | 103 | observing | 12.6 | 9 |
| 6 | u/UNCLEJASSY | 109 | 103 | observing | 12.1 | 8 |
| 7 | u/alpha247365 | 109 | 103 | observing | 11.8 | 9 |
| 8 | u/ThetaHedge | 109 | 103 | observing | 11.3 | 5 |
| 9 | u/geneman7 | 109 | 103 | observing | 10.8 | 6 |
| 10 | u/Inside_Guava_5482 | 109 | 103 | observing | 10.1 | 9 |

Reddit 正式池的 Top 10% 门槛为 109，Top 25% 为 105；Bottom 10% 门槛为 87，Bottom 25% 为 92。头部多人被 observing 可靠性上限锁在 109，平台头部目前主要靠 `n_eff` 做并列排序，分数区分度不足。

## 5. 头部作者的周期能力

周期分 100 代表该作者在对应周期附近处于自身证据基线；高于 100 表示该周期贡献偏强，低于 100 表示偏弱。它是作者历史能力切片，不是当前方向信号。

| 全局排名 | 作者 | 1D | 5D | 20D | 60D | 90D | 180D |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | @aleabitoreddit | 108 | 113 | 115 | **128** | 105 | 97 |
| 2 | @wey_how12640 | 95 | 111 | 119 | 129 | **130** | 116 |
| 3 | @seedy19tron | 96 | 110 | **120** | 118 | 118 | 108 |
| 4 | @King0ftheCharts | 101 | 109 | **116** | 112 | 114 | 109 |
| 5 | @spacemnke | 113 | **119** | 105 | 105 | 112 | 111 |
| 6 | @d_pavlos | 99 | 114 | **116** | 108 | 113 | 111 |
| 7 | @Yeah_Dave | 103 | 101 | **124** | 106 | 118 | 115 |
| 8 | @SanCompounding | 101 | 108 | 103 | **121** | 120 | 102 |
| 9 | @Chartradamus | 109 | 118 | **121** | 102 | 103 | 94 |
| 10 | @Biotech2k1 | **114** | 106 | 111 | 107 | 101 | 100 |

主要观察：

- @aleabitoreddit 的优势集中在 60D，180D 已低于 100；
- @wey_how12640 在 20D–180D 持续较强，但 1D 偏弱；
- @spacemnke 更偏短周期，5D 最强；
- @Yeah_Dave 明显偏 20D；
- @Chartradamus 在 5D/20D 强，但 180D 低于基线。

## 6. MU、NVDA、MSTR 专项能力榜

以下是 `sv_segment_score` 的标的专项分，不是当前看多/看空方向。专项分只要求较低的分段样本门槛，必须结合 `ticker n_eff` 和专项 Call 数阅读。

### MU

| 排名 | 作者 | 来源 | MU 分 | MU n_eff | MU Call | 全局 Score |
|---:|---|---|---:|---:|---:|---:|
| 1 | @wey_how12640 | X | 130 | 43.7 | 49 | 160 |
| 2 | @SebastinPatron3 | X | 117 | 19.3 | 17 | 126 |
| 3 | @RobertDurant7 | X | 116 | 13.3 | 8 | 114 |
| 4 | @anandragn | X | 116 | 11.9 | 7 | 114 |
| 5 | @buyholdrant | YouTube | 116 | 10.1 | 4 | 103 |

### NVDA

| 排名 | 作者 | 来源 | NVDA 分 | NVDA n_eff | NVDA Call | 全局 Score |
|---:|---|---|---:|---:|---:|---:|
| 1 | @BillBrooklyn10 | X | 119 | 26.3 | 25 | 108 |
| 2 | u/No_Turnip_1023 | Reddit | 115 | 12.7 | 3 | 102 |
| 3 | @HappyBullTrader | X | 113 | 14.4 | 33 | 106 |
| 4 | @Badie912 | X | 111 | 9.2 | 8 | 100 |
| 5 | @ai_kashiwa777 | X | 111 | 6.8 | 4 | 93 |

### MSTR

| 排名 | 作者 | 来源 | MSTR 分 | MSTR n_eff | MSTR Call | 全局 Score |
|---:|---|---|---:|---:|---:|---:|
| 1 | @nice_investment | X | 146 | 143.0 | 186 | 118 |
| 2 | @RhoRider | X | 127 | 28.8 | 26 | 112 |
| 3 | @BTCoptioneer | X | 119 | 60.0 | 52 | 115 |
| 4 | @King0ftheCharts | X | 117 | 26.9 | 21 | 150 |
| 5 | @Vince_Stanzione | X | 116 | 10.3 | 3 | 100 |

这里最可靠的专项头部是 MU 的 @wey_how12640、NVDA 的 @BillBrooklyn10，以及 MSTR 的 @nice_investment / @BTCoptioneer。只有 3–4 条专项 Call 的作者应标为“初步观察”，不应与几十或上百条样本的作者同等展示。

## 7. 较上一快照的变化

对比 2026-07-17 15:43 CST 快照，作者数从 2,035 增至 2,041。

### 头部变化

- @aleabitoreddit：Score 164 不变，排名从第 2 升至第 1；
- @wey_how12640：Score 164 → 160，排名从第 1 降至第 2；
- @AnthonySandford：Score 130 → 132，排名上升 2 位至第 13；
- @daniel_koss：Score 120 → 121，排名上升 4 位至第 26；
- @harmongreg：分数不变，排名上升 3 位至第 22。

### 主要上升

| 当前排名 | 作者 | 当前 Score | Score 变化 | 排名变化 |
|---:|---|---:|---:|---:|
| 171 | @AISavvyCapital | 104 | +3 | +234 |
| 132 | @HappyBullTrader | 106 | +4 | +184 |
| 166 | @vnkumarvnk | 104 | +2 | +139 |
| 127 | @Corgi4joy | 107 | +4 | +123 |
| 117 | @BillBrooklyn10 | 108 | +3 | +41 |

### 主要下降

| 当前排名 | 作者 | 当前 Score | Score 变化 | 排名变化 |
|---:|---|---:|---:|---:|
| 168 | @GlobalMacroZen | 104 | -2 | -37 |
| 43 | @thestockwhale | 116 | -18 | -32 |
| 88 | @joealertz | 111 | -2 | -24 |
| 169 | @MrTinvests | 104 | -1 | -24 |
| 178 | @traptradez | 104 | -1 | -18 |

排名变化不仅来自新观点，也可能来自新作者加入、平台稳健基线重算、证据资格变化、同日观点合并和生命周期重算。尤其 @thestockwhale 的已结算 Call 数没有增加但 `n_eff` 减少 37.5，这种变化应理解为证据重权或过滤变化，不能直接解释为一天内投资能力恶化。

## 8. 低分尾部

| 全局排名 | 作者 | 来源 | SV_Global | SV_Platform | 置信度 | n_eff | Call |
|---:|---|---|---:|---:|---|---:|---:|
| 2,041 | @itsmichaelluu | X | 40 | 40 | high | 349.9 | 449 |
| 2,040 | @candleanalysis1 | YouTube | 53 | 45 | medium | 53.0 | 47 |
| 2,039 | @TheBull_Stocks | X | 62 | 55 | medium | 38.9 | 39 |
| 2,038 | @neilsbhatia | X | 69 | 69 | high | 337.6 | 287 |
| 2,037 | @beatthedenominator | YouTube | 75 | 62 | low | 20.3 | 23 |
| 2,036 | @GDXTrader | X | 76 | 76 | high | 599.3 | 639 |
| 2,035 | @fundmyfund | X | 76 | 76 | high | 104.1 | 109 |
| 2,034 | @chad_ventures | X | 77 | 77 | high | 66.5 | 115 |
| 2,033 | @dillonwm2 | YouTube | 77 | 65 | low | 26.4 | 17 |
| 2,032 | @eyesonthecharts | YouTube | 79 | 67 | low | 20.3 | 16 |

低 Score 表示这些公开观点在当前结算框架下持续低于同平台基线，**不是自动反向交易信号**。作者可能存在对冲、仓位管理、盘中退出、未被抽取的上下文或与系统周期不匹配等情况。

## 9. 数据完整性与成熟度

### 9.1 作者与观点

| 来源 | 已评分作者 | 全部 Call | Actionable Call | 多头 | 空头 | 数据最新日期 |
|---|---:|---:|---:|---:|---:|---|
| X | 1,430 | 66,101 | 44,890 | 36,568 | 8,322 | 2026-07-16 |
| YouTube | 350 | 12,508 | 5,675 | 4,966 | 709 | 2026-07-16 |
| Reddit | 261 | 2,759 | 1,204 | 997 | 207 | 2026-07-17 |

当前三平台都明显多头偏置：X 多头占 actionable 的 81.5%，YouTube 87.5%，Reddit 82.8%。Score 能评价“作者的方向是否兑现”，但不能消除上游内容池本身的多头偏置。

数据库中的时间戳同时存在 `Z`、带小数的无时区格式，报告只比较日期，不对小时级新鲜度做跨平台精确排序。

### 9.2 结算成熟度

| 周期 | 可结算体系内 Call | 已结算 | 待结算 | 成熟度 |
|---|---:|---:|---:|---:|
| 1D | 37,348 | 36,572 | 776 | 97.9% |
| 5D | 37,348 | 30,564 | 6,784 | 81.8% |
| 20D | 37,348 | 26,564 | 10,784 | 71.1% |
| 60D | 37,348 | 20,832 | 16,516 | 55.8% |
| 90D | 37,348 | 18,715 | 18,633 | 50.1% |
| 180D | 37,348 | 12,600 | 24,748 | 33.7% |

因此当前最可信的是短中周期；60D 以上可以展示，但应同时显示成熟度或样本量，避免把未成熟的长周期分数当成稳定结论。

### 9.3 前端导出完整性

`smartVoice.json` 记录了 2,041 位作者的总体分布，但只序列化全局前 205 和后 205，共 410 位作者。根级来源列表只包含全局头部中的 X 170、YouTube 23、Reddit 7；它们不是完整的平台榜。

更重要的是，当前 `platformBands` 只正式导出 X 和 YouTube，尚未导出 Reddit。本文的 Reddit Top 10 是直接按数据库中的合格池和 `SV_Platform` 重算得到的；如果前端直接使用根级 `reddit` 数组，它只能看到全局前 205 中出现的 7 位 Reddit 作者，不能代表 Reddit 平台排名。

## 10. 当前排名的产品判断

### 已经可用

- X 的全局头部具备较强样本基础，前 14 名全部为 high confidence；
- X、YouTube 平台榜已有足够正式池，可用于来源内筛选；
- MU、NVDA、MSTR 已有专项作者能力榜，可与实时观点方向组合；
- 日级与 5D 结算成熟，可支持“近期高 Score 作者在说什么”的产品功能。

### 仍需谨慎

- 全局榜被 X 主导，不适合代替跨平台内容入口；
- YouTube 仍无 high-confidence 作者；
- Reddit 头部分数被 observing 上限压平，区分度弱；
- 前端 JSON 尚未导出 Reddit `platformBands`，当前 Reddit 标签页不具备完整平台榜数据；
- 雪球与 Toss 尚未进入正式分数，当前不是完整的跨社区 Score；
- 全局 Top 10% 阈值存在大量并列，前端应使用导出的 rank/percentile，而不是只比较分数；
- 专项标的分的最低样本门槛偏低，少于 8 个 Call 时应标记“初步观察”；
- 180D 只有三分之一证据成熟，长期能力排序仍会变化。

## 11. 推荐的页面默认展示规则

1. **默认主榜**：全局榜显示 Score、来源、置信度、`n_eff` 和 Call 数；默认将 observing 降低视觉权重。
2. **平台标签页**：使用 `SV_Platform` 和平台内 rank，不能在平台标签下继续显示全局 Score 排序。
3. **头部筛选**：优先使用导出的 Top 10%/Top 25% 成员集合；若必须用分数阈值，必须加稳定 tie-break。
4. **标的专项榜**：默认要求专项 Call >= 8；3–7 条放入“初步观察”，不要与正式头部混排。
5. **实时观点**：只显示 high/medium 或平台 Top 10% 作者的 actionable call，并明确观点方向、周期和更新时间。
6. **低分作者**：定位为风险提示和反例研究，不提供“反向跟单”按钮。
7. **跨平台总览**：同时展示全局名次与平台内名次，避免 YouTube/Reddit 被 X 的样本优势淹没。

## 12. 最终判断

当前 Score 已经是一套可解释、可审计的作者历史能力排名，X 头部尤其成熟；但它还不是完整的跨社区 Smart Money 视图。产品上最合理的解释是：

```text
SV_Global：作者相对自己平台基线的异常程度，经证据置信度折算后的全局比较。
SV_Platform：作者在本平台中的相对能力。
Ticker Score：作者在某标的上的历史专项能力。
实时观点方向：作者现在具体看多或看空什么。
```

这四个概念必须分开。排名回答“谁的历史公开观点更值得参考”，并不单独回答“现在应该买什么”。
