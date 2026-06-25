# Advanced-Mindshare → 股票 移植可行性分析

> 3 角色独立分析 + 交叉评审 + 综合（2026-06-20）。数字均在 `data/prismo_snapshot.db` + `experiments/prices_cache.json` 实测复核。
> 方法学源：`equity1000/mindshare/ADVANCED_MINDSHARE.md`(v25)。产品规格映射见 `PRODUCT_SPEC_FEASIBILITY.md`。

## 一句话
advanced-mindshare 是为 **Twitter 加密代币**设计的机制引擎，靠三根支柱：① 固定 circle-size 分母 ② KOL 关注/smart-engagement 图 ③ 每标的 ≥60–90 天日级历史。**Prismo 三根都不达标**（karma 全 0 无关注图、论坛无固定用户基数、美区仅 11 个日历日）。能原样活的只有不吃长历史、不吃社交图的：自归一化 penetration、entropy、当日量加权方向。**而"NVDA/MU 排名太低"是对的，是方法学伪影——线上 `trending` 按尖峰速度 z 排名，机械埋葬长期在场的大盘股；改按 penetration，NVDA #10→#2。**

## Q1 指标移植裁定
| 指标 | 裁定 | 股票化改法 |
|---|---|---|
| penetration_rate | 需改（最高价值） | 弃固定 12,400；用**当日相对分母**：`标的当日独立作者 / 当日该市场全部活跃作者`，按 us/cn 分市场 |
| penetration_ma7 | 能但数据受限 | 仅 ≥20 活跃日的 dense 名字可信；us 只 ~5 点 |
| att_60d（60日分位） | 暂不能（数据墙） | 需 60 日点；用 expanding+跨截面分位临时替代，标低置信 |
| vel_zscore（速度/动量） | 机制能但当前被误用为主排名 | 降为次级"加速中"徽章；在 penetration_ma7.diff 上算 + 量地板 |
| dir_smooth（方向 z） | 需改+数据受限 | raw_dir=bull−bear（先 COALESCE 25 行错标）；EMA/滚动 z 仅 cn dense 够 |
| **dir_smooth_vw_pct（量加权方向 expanding 分位）** | **方向族最佳，定为生产默认** | 全名字适用，从第1天可算；修"小局部高 vs 大绝对高"（NIO/BABA 回音室的解药） |
| entropy_ma7 | 能，最干净 | 3 桶映射 stance；共识阈值用跨截面分位临时替代 |
| daily_se / se_z60（KOL 互动） | **不能，无诚实替代** | 无关注图、karma 全 0；只能 `quality_score×log(1+score+ncom)` 当**内容质量代理**，≠KOL/聪明钱 |
| low-liq 路径 | 能，且成唯一路径 | 每个标的都"低流动"（日均独立 mentioners 最高 38）→ vw expanding 分位设为默认，plain-z 删 |
| regime 决策树 | 暂不能（最吃历史） | 用跨截面分位出 provisional v1 标签 |

## Q2 数据充分度
四大硬依赖：① 固定分母=缺但可替代；② 关注图=缺、不跑爬虫不可补；③ ≥60–90 日历史=缺（us 11 天、0 标的≥30 天 us、全库仅 BABA36/NIO31）；④ 每帖意见分=有（stance 100%）。**1 满足 / 1 可替代 / 2 硬阻塞。**
- **今天高保真**：当值 penetration、entropy、量加权方向、子版块广度、集中度HHI。
- **中保真(历史限)**：penetration_ma7 及"vs近期变化"，仅 cn dense 名字真。
- **历史阻塞(~60–90天后解锁)**：att_60d、vel z、dir z、regime —— 约规格 80% 字段。
- **特征阻塞(需爬虫/抽取)**：smart/KOL、intent/tone/horizon、期权（原文有料可正则）。
- **跨区(jp/kr/tw)**：仅聚合 forum_mindshare.json（@120 封顶、14天、无日序，且在 equity1000 不在 Prismo 云）→ 跨区 penetration/velocity/entropy 不可建。

## Q3 Sense-check（核心发现，全实测）
**用户对：sentiment 标注合理，但排名坏了——方法学伪影，非数据短缺。**
- **铁证**：线上 trending us 24h 里 **NVDA 与 GOOGL 完全相同 14 条 mentions**，却 GOOGL #1（z=2.90）、NVDA #10（z=0.64）。唯一差别是基线：NVDA `baseline_mean=0.476` vs GOOGL `0.214`——NVDA"一直被讨论"→14 条不算意外→被埋。MU #8（z=0.67）。速度排名**结构性惩罚长期热门**。
- **修复已验证**：改按当日份额 penetration 排 → SPCX 0.433、**NVDA 0.121(#2)**、GOOGL 0.119、AMZN 0.080、MSFT 0.062、AVGO 0.061、TSLA 0.058、AMD 0.052、MU 0.042(#12)。AI/半导体聚顶，契合先验。**零新数据最高 ROI 单点修复。**
- **三个独立失真源（分别修）**：
  1. **SPCX = 盘前事件尖峰**：819 条，峰值 06-12 占当天全论坛 293 mentioners 的 **68.9%**，但作者分散（top author 3.3%）→ 真事件，作"尖峰"浮出、不加冕。
  2. **BABA = 专属子版块俘获**：325 条里 **91.7%** 来自 r/Alibaba+r/BABA，作者分散 → 同名子版块降权。
  3. **NIO = 专属子版块+单作者回音室**：141 条里 **95%** 来自 r/NIO，仅 43 作者、top author 13.5%、HHI 0.068（≈NVDA 7.3×）、74%bull/4%bear → 子版块降权+单作者去重。
- **市场混合**：NVDA = us 148 + cn 20，排名器必须按 market 分区。
- **Sentiment 通过**：NVDA us +0.057（已 COALESCE）、MU +0.227（存储上行）、SPCX −0.053（高分歧）、NIO +0.463（回音室）。价格佐证（06-01→06-17）：NVDA −8.7%、MSFT −17.7%、AMZN −9.1%、TSLA −4.7% → NVDA 回撤中仍偏多 = "买主导 AI 名字的回调"，方向合理。
- **MU 低排名是真信号别强修**：Reddit 散户讨论 MU 就是比 NVDA 少（40 条/9 活跃日）。

## Q4 产品规格能满足多少
**16 模块：~3–4 今天好上线 / ~6 靠 90 天回填+retag / ~6–7 卡跨区入云或外部源。绑定约束 = 历史深度（11 us 天），不是字段覆盖。**
- ✅ 今天高保真：标的 M5 多空&分歧；地区 M2 热榜（**仅当改按 penetration 排**）；地区 M6 集中度；页头价格。
- 🟡 历史门控（规格 ~80% 字段：异动/偏离/分位/动量/regime）：今天硬算=捏造；开每日快照，~8 月底解锁；先出 expanding+跨截面分位 v1 挂低置信徽章。
- 🟡 特征缺（风险温度/性格画像/信念）：跑作者爬虫+廉价 retag(intent/tone/horizon)；期权正则可先抽。
- 🔴 上线前必修接线（零新数据）：① trending 改 penetration；② 同名子版块降权；③ COALESCE 25 行错标；④ 按 market 分区；⑤ 低流动方向用 vw expanding 分位（防 NIO 类反转）。
- ⛔ 跨区招牌模块（M2 跨区/M3 信息差/M4 独有叙事/地区 M4-M5-M8/jp-kr-tw 整页）：数据不在云、聚合封顶无日序 → K4 项目；信息差扩散时序 equity1000 也只做了广度、净新研发，作 2–3 标的灯塔 PoC，不进 v1。

## 怎么做（优先级）
1. **【零新数据，最高 ROI】热榜从 `trending.zscore` 换成当日份额 penetration**，按 market 分区 → NVDA #10→#2，本周可 demo。速度留作次级"加速中"徽章。
2. **【同批】修 4 处接线**：同名子版块降权（BABA 91.7%/NIO 95%）+ NIO 单作者去重；COALESCE 25 行；SPCX 类加 spike 标记；按 market 分区。
3. **【今天起跑时钟】立刻开每日快照**，60–90 天历史按时累积 → 解锁异动/动量/regime（~80% 字段）。
4. **【生产默认】方向统一用 `dir_smooth_vw_pct`**；plain-z 分支删，架构塌缩成单路径。
5. **【解锁特征】作者爬虫填 karma + 廉价 LLM retag(intent/tone/horizon)**；在此前"smart"一律标"内容质量代理"，不得标 KOL/影响力。
6. **【最后】K4 跨区入云**再做招牌跨区模块；信息差作 PoC。
