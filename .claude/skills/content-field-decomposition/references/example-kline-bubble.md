# 走查样板：K 线观点气泡图（「个体观点·KOL」）

> 把 `content-field-decomposition` 用到一个**真实图表模块**的完整走查。
> 模块：标的详情页象限①「个体观点·KOL」的常驻图 `web/components/prismo/KolOpinionFlow.tsx`
> （上方价格折线 + 每日 KOL 观点头像气泡）。可作为「怎么写一份模块字段拆解」的范本。

## 0. 锁定内容单元与用户

- **内容单元**：一个气泡 = **一条 KOL 观点**（数据类型 `KolOpinion`，见 `web/lib/mockDetail.ts`）。
- **背景层**：价格折线 = 每日收盘（`KolCandle`）。气泡锚定在「该观点发布日 × 当天收盘价」的点上。
- **目标用户 / 决策**：研究某只票的投资者，想**一眼看清「谁、在哪个平台、什么时候、多大声量、什么立场」地在聊这只票**，
  并点选深入。→ 字段去留以「对这个浏览决策有没有用」为准。

## 1. 模块当前画了什么（视觉编码 → 字段）

逐一盘点图里每个编码背后是哪个字段（这是「字段→视觉映射」的反向核对）：

| 视觉/交互 | 背后字段 | 现状 |
|---|---|---|
| X 轴位置 | `day`（发布日，snap 到交易日） | ✅ |
| Y 轴位置（气泡挂在价格点上） | `KolCandle.close` | ✅ |
| 折线 | `KolCandle.close` 序列 | ✅（注：叫「K线」却只画收盘线，OHLC 未用——见缺口） |
| 气泡头像 | `avatar` / `author`（缺则首字母圆） | ✅ |
| 气泡**圈色** | `source`（X 黑/YT 红/Reddit 橙/雪球 蓝） | ✅ |
| 气泡**直径** | `interactions`（绝对值，`diameterOf`） | ✅（但用绝对值——见缺口） |
| 单日竖向堆叠顺序 | 按 `interactions` 降序 | ✅ |
| 超 5 个折叠「+N」 | 当日观点计数 | ✅ |
| 来源筛选 chips | `source`（vis 显隐） | ✅ |
| 底部区间滑块 dataZoom | `day` 时间窗 | ✅ |
| tooltip | `source`·`author`·`stance`(着色)·`interactions`·`opinionText`(=`reason`\|`text`) | ✅ |

> 反向结论已经浮现：图里**只编码了 来源 / 时间 / 互动 / 作者**，外加 tooltip 里才出现的 `stance`。
> 「内容本身」的大多数轴（视角 / 相关度 / 周期）和「作者知名度」在图上**完全没表达**。

## 2. 完整字段拆解树

```
一条 KOL 观点（一个气泡）
├─ 作者 ── author ✅ · avatar ✅ · 绝对知名度 ❌ · 平台内知名度排名 ❌
├─ 来源 ── source ✅（圈色+筛选）
├─ 互动 ── interactions 绝对值 ✅（=气泡大小）· 平台内互动排名 ❌
└─ 内容
   ├─ 投资框架 viewpoints[] ⚠（数据有 kol_viewpoint，图上没用）
   ├─ 语言 language ⚠（可派生，图上没用）
   ├─ 立场 stance ⚠（有；但只在 tooltip，未做视觉编码）
   ├─ 投资周期 horizon ❌（数据模型里根本没有）
   ├─ 相关度 relevance ⚠（有 kol_relevance，图上没用）
   ├─ 事实层 ── orig ✅ · quote ✅ · url ✅(图 tooltip 未给链接) · created/day ✅
   └─ 提炼层 ── reason ✅(tooltip) · points ⚠(有，图上没用) · trans ✅(图上没用)
背景层：KolCandle ── day ✅ · close ✅ · open/high/low ⚠（有，折线未用）
```

## 3. 字段表（该模块的最终字段 + 现状）

✅=图已用 · ⚠=数据已有但本图未用（多在下方 OpinionExplorer 用）· ❌=数据缺失

| 字段 key | 归属 | 取值/类型 | 来源 | 本图用途 | 现状 |
|---|---|---|---|---|---|
| `day` | 内容·时间 | YYYY-MM-DD | 原始 | X 轴 / 时间窗 | ✅ |
| `close`（及 OHLC） | 背景·价格 | 数值 | `price_daily` | 折线 / 气泡锚点 | ✅（OHLC ⚠ 未用） |
| `source` | 来源 | x\|youtube\|reddit\|xueqiu | 原始 | 圈色 + 筛选 | ✅ |
| `author` / `avatar` | 作者·身份 | 文本 / URL | 原始/抓取 | 气泡脸 + tooltip | ✅ |
| `interactions` | 互动·绝对值 | 数值 | 求和 | 气泡大小 + 堆叠 + tooltip | ✅ |
| `stance` | 内容·立场 | bull\|neutral\|bear | AI 分类 | 仅 tooltip 着色 | ⚠ 未做视觉编码 |
| `reason` | 内容·提炼 | 双语一句话 | AI 提炼 | tooltip 正文 | ✅ |
| `viewpoints[]` | 内容·投资框架 | 7 视角多标签 | `kol_viewpoint` | —（本图未用） | ⚠ |
| `relevance` | 内容·相关度 | 0-100 | `kol_relevance` | —（本图未用） | ⚠ |
| `language` | 内容·语言 | zh/en/ja/ko | 解析 | —（本图未用） | ⚠ |
| `points[]` / `trans` / `quote` / `url` | 内容·事实+提炼 | 文本 | AI / 原始 | 部分仅下游用 | ⚠/✅ |
| `engagement_rank`（按平台） | 互动·排名 | 1..N / 分位 | 计算派生 | 应替代/辅助气泡大小 | ❌ |
| `author_fame_abs` / `author_fame_rank` | 作者·知名度 | 分数 / 排名 | 派生（可借 InvestorBoard 聚合） | KOL 权重 | ❌ |
| `horizon` | 内容·周期 | 短/中/长 | AI 分类 | 周期筛选 | ❌ |

## 4. 缺口清单（按对用户价值排序的 backlog）

1. **`stance` 没有视觉编码（只在 tooltip）。** 多空是投资者第一关心的轴，却要 hover 才看得到——
   一眼看不出某天是「一片看多」还是「多空打架」。建议：气泡加第二圈/光晕表立场，或当日做多空分色堆叠。
   *字段已有，纯前端编码工作。*
2. **气泡大小用 `interactions` 绝对值，跨平台不可比（违反原语①）。** YouTube 5 万赞会碾压 Reddit 2 千 upvote，
   大小误导。应改用 **`engagement_rank` / 平台内分位**（新派生字段）来定大小，或至少按平台归一。
3. **`author_fame` 缺失——一个「KOL」图却不知道谁是 KOL。** 大小＝声量而非权威。补「作者绝对知名度 + 平台内排名」
   （可复用 `investorQueries` 的按作者聚合），让真·大 V 更突出。
4. **`viewpoints` / `relevance` 图上未利用。** 数据都已产出（kol_viewpoint / kol_relevance），却只在下方浏览器用。
   可给气泡图加「视角」「相关度」筛选，或用相关度决定哪些气泡显示、哪些并入「+N」（低相关的折叠）。
5. **`horizon`（短/中/长线）数据模型缺失。** 当冲客与长线党关心的观点不同，值得新增一个 AI 分类步骤
   （类似 `kol_viewpoint`）产出该字段。
6. **OHLC 已有却只画收盘线。** 模块名为「K 线」，可选真上 K 线蜡烛以兑现名字（或更新文案）。

> 拆解的最大价值在第 4 节：1、2、4 是「字段已有、只差用上」的低成本高回报项；3、5 是要补管线的新字段。
