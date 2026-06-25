# 项目架构与结构（ARCHITECTURE）

> **维护约定**：本文件是项目的「活地图」。**每次对项目结构或功能有实质改动后，必须同步更新本文件对应章节**
> （新增/删除模块、改数据流、改命令、改部署方式、改 schema 等）。详见根目录 `CLAUDE.md`。
> 最近更新：2026-06-25。

---

## 1. 这是什么

**Prismo** —— 一个多语（中文默认 / English / 日本語 / 한국어）的 **多社区美股舆情聚合看板**：聚合 **Reddit / Yahoo Finance Japan / Naver / 雪球 / PTT** 五大本土散户社区，对同一批跨区美股做情绪对比、共识与分歧分析，最终渲染成一个**纯静态网站**。
（注：早期作为 Reddit 单站「redditalpha」起步——抓 Reddit 财经社区帖、逐帖大模型打标、聚合声量/情绪/异动/叙事/简报；该 Reddit 管线仍是后端基础，新增 4 区由 `gr_*` 表承载。）

- 线上地址：**https://www.redditalpha.xyz**（根域名，静态托管）
- 两个市场（market）：`us`（美股）、`cn`（中概股 + 港股 + A 股），互不污染，各出一套聚合。

> **⚠ 价值判断 / 护城河（别被「海外散户视角」叙事带偏）**：
> 1. **最有价值的内容并非「非英语散户对美股的个体看法」本身。** 韩国 Naver、日本 Yahoo 掲示板等本土股吧**单帖信息质量普遍很差**——多数是水帖、情绪宣泄、无意义 shitpost；这类内容**只有靠「量」做聚合分析才有价值**（情绪分布 / 声量异动 / 跨区分歧），逐条看几乎没有信息量。
> 2. **抓取这些股吧本身不构成技术护城河。** 爬取门槛很低（人人有个 crawling agent 都能爬），技术不是壁垒。

> **🎨 UI 已按 QuiverQuant 风重建（2026-06）**：品牌 = **Prismo**（仓库 `Conor-711/Prismo`）。**设计系统（复刻 QuiverQuant）**：字体 Figtree(UI/标题)+Roboto(数据/数字 tabular)；默认深色底 `#121212`（卡片 `#161616`，靠 `#2a2d2f` 发丝边区分；图表底才用 `#202630`；**仅深色**、已彻底移除白天模式 CSS 回退与主题切换）+ 青绿强调 `#57D7BA`（Tailwind `reddit`/`amber`/`brand`/`bull` token 同值；看跌珊瑚 `#FF5C6C` 全站统一、不随地区红绿翻转；品牌渐变青绿→深松绿、去紫）+ 小圆角(2–4px) + 数据密集卡片/表格 + 等宽数字；侧边栏导航（`globals.css` CSS 变量 + `tailwind.config.ts`）。**完整设计语言宪法见 `DESIGN_LANGUAGE.md`（改 token 前后都要同步）**。
> **11 个页面**（数据全部走 `gr_*` → `lib/globalQueries.ts`）：**落地页**(`/`：中文 slogan「时间即金钱 / 两者皆盈利」hero + 「噪音→信号」三步 + 五社区五地区 + 注册/进看板 CTA，文案在 `dict.home`；**无侧栏 chrome**——`app/[lang]/(marketing)/page.tsx` + `(marketing)/layout.tsx`(品牌头 logo/语言/登录-注册 + 页脚)) · **总览看板**(`/dashboard`：实时 KPI/分歧·多空/五地区情绪/全球热度榜/跨区热力图；原 `/` 内容已迁此，侧栏「总览」指向它) · 标的总览(`/tickers`) · 标的详情(`/tickers/[symbol]`) · **投资者榜单**(`/investors`) · 追踪/自选(`/tracking`) · 区域总览(`/regions`) · 区域详情(`/regions/[region]`) · 搜索(`/search`) · Profile(`/me`) · 设置(`/account`)。**投资者榜单页**(`/investors`)：服务端 `lib/investorQueries.ts` 的 `getInvestorBoard()` 从真实数据按平台聚合活跃投资者(X=`x_opinion` 按 handle 去重推聚互动 + unavatar 头像；YouTube=`yt_video` 按 channel_id 聚播放量 + `author_avatar` 头像；Reddit=`posts`⋈`mentions` 按 author 去重帖聚互动；雪球=`gr_post` source=xueqiu 按 author 聚互动)，烤进页面壳；客户端 `components/prismo/InvestorBoard.tsx` 顶部平台过滤(全部=每平台前 6 预览/可点进看全部 24，选中=单平台完整榜)，卡片含名次/头像/外链/覆盖标的 chips/主指标(互动或播放)。入口在主侧栏(`NAV_GROUPS`，`IconTrophy`)+移动端底栏，四语标签 `dict.nav.investors`。**追踪页**(`/tracking`)：服务端把全部标的摘要(`getGrTickers`+`getGrTickerRegions`)烤进页面壳，客户端 `TrackingView` 按登录用户的 `user_collections`(kind=`ticker`) 过滤出追踪集，按情绪/热度/时间排序，逐个展示「情况」(平均情绪·共识·覆盖区/帖数/分歧·跨区多空条·各区情绪)；未登录显示登录引导、空集显示去发现标的(与 `ProfileView` 同范式)。入口在**主侧栏导航**(`components/nav.tsx` 的 `NAV_GROUPS`，星标图标 `IconStar`)与移动端底栏，四语标签 `dict.nav.tracking`。展示件在 `components/prismo/`（Bits/TickerTable/TickerSearch/TickerLogo/TrackingView + 详情页模块件 DetailCharts/DetailBits/CounterThesis/HotList）+ 复用 `components/asia/AsiaCharts`（ECharts）；地区元数据在 `lib/regions.ts`。**详情页（标的/地区）已做成图表化「模块看板」**，当前用 `lib/mockDetail.ts` 的演示数据（确定性 mock，接真实管线前占位）。**标的详情页顶部 = 四方图(身份KOL/散户 × 视角主观/客观)象限①「个体观点·KOL」**：`components/prismo/KolOpinionFlow.tsx`（client，ECharts）—— **数据已接真实**(`lib/kolQueries.ts`：价格取 `price_daily`(Yahoo 日 OHLC) + 观点取 Reddit(posts/mentions/item_analysis) + YouTube(yt_video/yt_analysis) + 雪球(gr_post source=xueqiu)；**X 真实**(云端 `tw_tweet`⋈`tw_tweet_ticker` 拉进本地 `x_opinion`，原生无情绪→取 `kol_refined` 提炼立场)；数据不足回退 `getKolFlow` mock)。**观点已 AI 提炼+双语（不再照搬原文）**：`pipeline/analyze/kol_refine.py`(`make kol-refine`) 对 reddit/x/雪球 每标的每源 **top-N(默认 20)** 各跑一次 DeepSeek(flash) → 隔离表 `kol_refined`(PK source+item_id：stance/reason_zh·en/points_zh·en/**quote_zh·en(本人忠实原话，建立可信度)**，提炼「为什么看多/看空/中性(1-2句) + 2-4 要点(**保留数字/事件细节、放宽压缩**避免长帖被压成一句) + 原话」，**提炼与翻译合一**)；YouTube 复用 `yt_analysis`(summary→reason、key_points→points，不重花 Gemini 配额)；**原帖卡(`OpinionCard`)统一展示原帖原文 + 「译」选项**(与原帖流共用 `kolShared.pickOriginal`；reason/要点不再当卡片正文、仅图表 tooltip `opinionText` 用)；**翻译只 zh/en，ja/ko 前端回退 en**（产品决策）；增量(只补未提炼，`--force` 重跑)。近 2 周价格折线(极简浅色线 + 末点品牌色标记) + 每日多源 KOL **观点头像气泡**(X/YouTube/Reddit/雪球；ECharts **custom 系列** renderItem 画**圆形头像**[圆形裁剪]+**平台品牌圈色**[X 黑 / YouTube 红 / Reddit 橙 / 雪球 蓝，`kolShared.SOURCE_RING`]，直径∝互动数，**单日竖向居中堆叠**、超 5 个折叠成 “+N”，头像缺失回退首字母圆)，点图/气泡选日期→下方列当天完整观点；来源 chips(品牌圈色点)可筛选。**KOL 模块结构**(`KolModule.tsx`)：**常驻**「股价×观点折线 K 线图」(`KolOpinionFlow`，底部 dataZoom 滑块**只控图本身**) → 下方**观点浏览器**(`OpinionExplorer.tsx`，2026-06 重构、**替代原 按KOL/按视角/按热度 三 tab**)：顶部**筛选条**(平台 / 立场 / 视角 / 时间[24h·3d·7d·14d·1mo] / 语言[按原文 CJK 粗判] / **质量**[「只看高质量」开关——开=只留 `kol_quality`≥65 的帖]) + 下方**主从阅读**(左窄列=帖文卡列表[头像+handle+立场+相关分+开头]，右宽栏=选中帖的**完整原文** + 视角标签 + 「译」+「查看原帖↗」)，列表头可切**排序**「相关度 / 最新」、**默认相关度降序**。⚠ 相关度**只做排序、不做筛选**(用户只想看高相关的，设低相关过滤无意义)。数据=`getKolOpinions(symbol)`(`kolQueries.ts`：近 ~32 天**扁平池**、不 snap 交易日，每条带 orig/trans/quote/viewpoints/**relevance**)；6 个维度筛选全在前端做。理念延续「**展示原文、不蒸馏**；AI 只做分类/翻译/相关性打分等『索引』活」。**AI 顺序：kol-refine(立场/原话) → kol-viewpoint(视角) → kol-translate(译) → kol-relevance(相关性)**(都走 LOW=千问 qwen-flash，需 `QWEN_API_KEY`)。⚠ 原帖完整度：X/雪球/Reddit=全文(Reddit 译文用 `posts.selftext`；卡片正文目前仍只显示标题、回链看全文)、YouTube=AI 摘要(无字幕)。**「译」**见 `kol_translate.py`(逐句直译、不压缩 → `kol_refined.trans_zh·en`；**目前只译已提炼 top-N**，故长尾展示帖暂无「译」)，**「相关性」**见 `kol_relevance.py`(0-100、覆盖 4 源、打全部展示帖 → `kol_relevance`，**只用于排序**)；**「质量」**见 `kol_quality.py`(0-100 内容含金量、**与标的无关**故按 source+item 去重 → 隔离表 `kol_quality`，供「只看高质量」开关)。**数据清洗**：雪球 `body` 富文本在 `kolQueries.stripHtml` 去 HTML 标签；X **纯转推**(`text` 以 `RT @` 开头)在 `xOps` 从展示中剔除(RT'd 原文被截断、源推不在库，无法还原)。**旧件 `ClassifiedOpinions.tsx` + `kol_argument`/`kol_narrative`(论点综合/叙事编织)已不再被 UI 使用**(保留在库/管线、待清理)。取文/卡片/配色在 `kolShared.tsx`(`pickOriginal`/`OpinionCard`/`Avatar`)。(象限① 管线：提炼→视角分类→翻译→相关性打分，前端=观点浏览器；2/3/4 待后续。)价格抓取器 `pipeline/ingest/price_daily.py`(Yahoo chart API、免 key、plain ticker；当前直接写**本地 `dev.db`** 的 `price_daily` 表 ~37/40 标的；⚠ 生产化需改成 session_scope 写云端 Supabase + cloud-pull，否则下次 cloud-pull 会覆盖)。X 拉取 `pipeline/ingest/x_pull.py`(云端 `tw_*`→本地 `x_opinion`)。**观点卡作者头像** `author_avatar` 表(`pipeline/ingest/author_avatars.py`)：YouTube 抓频道页 `yt3` 头像(540 ✓)、Reddit 走 app-only OAuth `icon_img`(**需 `.env` 填 `REDDIT_CLIENT_ID/SECRET`，当前为空→跳过、兜底首字母**)；X 走 `unavatar.io/twitter/{handle}`(客户端、onError 兜底)；雪球(阿里云 WAF)暂兜底。**⚠ 这些脚本须用 venv `pipeline/.venv/bin/python`**——系统 `python3` 无 python-dotenv → 读不到 `.env` 的云端 `DATABASE_URL`/凭证(会误判成 sqlite/无凭证)。标的详情头部：`TickerLogo`(第三方 CDN logo + 字母兑底) + 全称/代码·交易所(`lib/tickerMeta.ts` 预设) + 最新价/涨跌幅(来自数据层 `gr_quote`，纯静态站随构建刷新、非逐笔实时)。各列表行也带 logo。
> Reddit 单站旧页（dashboard/ticker/post/author/leaderboard/cn/onboarding）已删；**后端 pipeline 全保留**。线上 redditalpha.xyz 仍由旧 `reddit_alpha` 仓库部署、不受影响（Prismo 部署需快照含 `gr_*`，否则相关页为空）。

---

## 2. 三大系统

```
┌─────────────────┐   写入    ┌──────────────────────┐   拉快照   ┌─────────────────────┐
│ ① Python 数据管线 │ ───────▶ │ ② Supabase 云端(Postgres) │ ───────▶ │ ③ Next.js 静态网站   │
│  抓取 + AI 分析   │          │   数据的「家」(唯一真源)    │          │  构建期读快照→出 HTML │
└─────────────────┘          └──────────────────────┘          └─────────────────────┘
                                        ▲  Supabase 还存：登录账号(Auth)、埋点(app_events)、搜索榜(ticker_searches)、收藏/追踪(user_collections)
```

### ① Python 数据管线（`pipeline/`）
抓 Reddit → 抽取 ticker → 大模型逐帖打标 → 聚合（榜单/情绪/异动/叙事/简报）→ 翻译。
**写入 `DATABASE_URL`**（现已指向 Supabase 云端）。

### ② Supabase（云端 Postgres）—— 数据的家
- **管线数据**（14 张表，见第 5 节）：帖子/评论/作者/AI 分析/提及/字典 + 派生聚合表。
- **网站后端**（独立小表，RLS 保护）：`app_events`（埋点）、`ticker_searches`（搜索榜）、`user_collections`（账户收藏/追踪，仅本人可读写）、`user_profiles`（用户投资画像 = onboarding 采集，5 维：关注赛道/持仓/持有习惯(改为拖拽排序 → `habit_rank text[]`，队首兼容旧单值 `holding_habit`)/投资年龄/投资金额，仅本人可读写改）、Auth（登录）。
- 项目 ref：`wimipsiwtrqhizgmbxas`。迁移与用法见 `CLOUD_DB.md`。

### ③ Next.js 静态网站（`web/`）
Next 14 App Router，**静态导出**（`output:"export"` 仅生产）。构建期用 `node:sqlite` 读**本地快照**
`data/dev.db`（由 `make cloud-pull` 从云端拉下），生成 ~6500 个静态页面到 `web/out/`，可部署到任意静态托管。
**网站运行时不连数据库**（纯静态，无服务端攻击面）。

---

## 3. 端到端数据流

```
Arctic Shift / PRAW ──▶ posts/comments ──▶ ticker 抽取(正则) ──▶ mentions
                                                                   │
                                          大模型逐帖打标(qwen 思考模式) ──▶ item_analysis
                                                                   │
        ┌──────────────┬──────────────┬──────────────┬────────────┘
     rollups        market_mood     trending      narratives(deepseek) + brief(deepseek)
   (声量/情绪榜)     (市场情绪)      (异动z-score)   (主导叙事 / 每日简报)
        └──────────────┴──────────────┴──────────────┴──────────── translate(deepseek, 增量补中文)
                                       │
                              全部写入 Supabase 云端
                                       │  make cloud-pull
                              本地 data/dev.db 快照
                                       │  make site  (Node 22)
                                  web/out/ 静态站
```

**关键：分析是增量的** —— 逐帖打标按 `item_analysis.item_id` 持久化，只分析新帖；聚合表每次全量重算（纯 SQL，0 token）。

**作者库（优质作者聚合页）** —— `make daily` 内（主分析之后）爬「实力榜」Top 50 作者的 Reddit 历史帖，
两级模型漏斗控成本：**DeepSeek(LOW) 粗筛质量 → 仅过线帖送千问(HIGH) 深析并入库**。这些帖标记
`posts.source='author'`，**被所有实时舆情聚合/feed 排除**（`source='scan'` 过滤），只出现在作者页与其自身帖详情页。
入口：全站作者名/头像 → `/[lang]/author/[name]/`。详见 `pipeline/ingest/author_crawl.py`。

**亚洲散户舆情看板（隐藏页）** —— 把舆情看板扩到日韩台本土散户社区的实验。**近 7 天**爬三市场：
**日本 Yahoo Finance 掲示板**（`/quote/{CODE}/forum`，SSR；按 NVDA/MU/NOK/SPCX 四标的，SpaceX=SPCX pre-IPO 专板）、
**韩国 Naver**（`m.stock.naver.com/front-api/discussion/list`，foreignStock+itemCode；同四标的；`comment/counts` 补评论数）、
**台湾 PTT Stock**（`ptt.cc/bbs/Stock/`，SSR，`M.{epoch}` 解析发文时间翻「上頁」拿一周；**综合板→board 级聚合 market=`tw`/ticker=`TWSTOCK`**，标题 [類別] 当 label）。
每帖富化维度：likes/dislikes/views/comments/images/verified(持股认证)。
**两级 AI 打标**：① HIGH 千问逐帖双语深析(Top~12/格，供详情) → MID DeepSeek 每格汇总；② **LOW DeepSeek flash 给
全部帖打情绪分**(`asia_posts.sentiment`，便宜+批量，供每日时间序列/变化)。**价格**：Naver 日K(`asia_price` 表，
NVDA/MU/NOK 全序列；SPCX pre-IPO 稀疏)。全部写**隔离表** `asia_*`（market `jp`/`kr`，不污染 us/cn）。
命令 `make asia`（crawl --since-days 7 → score → analyze → summarize → price）；页面 **`/[lang]/lab/asia-pulse`** 是
**多维看板**（情绪矩阵 / 台湾区 / 跨市场分歧 / 声量榜 / 每日声量 / 主题 / **趋势+异动榜** / **价格×情绪×声量 ECharts 指数图** / 8 格详情；
无导航入口、不进 sitemap、noindex，仅 URL 直达）。**「机构级指标」区**（对标 Swaggy Stocks/Buzzberg/E*TRADE，让每个抓取维度都发挥作用）：
净情绪榜(多−空发散条) / 舆情定位气泡(净情绪×声量×互动) / 情绪日历热力(标的×日) / 声量异动 z-score(本周最反常日,σ) /
市场画像雷达(日韩台 5 维归一化) / 认证持仓 vs 大众(Naver verified 聪明钱代理) / 认可度&争议(赞踩比) / 日本自评(类 Stocktwits) / 主题情绪倾向。
新增查询 `getAsiaSentiHeat/Engagement/VerifiedSplit/JpSelfRating/ThemeStance`（`asiaQueries.ts`）+ 图表 `AsiaDivergingBars/Heatmap/Bubble/Radar/PairedBars`（`AsiaCharts.tsx`，均 Client Component，父级只传可序列化 props）。
详见 `pipeline/ingest/asia_crawl.py`、`asia_price.py`、`web/components/asia/`。

**全球散户 · 五地区看板（隐藏页 /lab/global-retail）** —— 与上面的 asia 4 标的实验**不同**：这是 ticker 中心、
**精选 ~40 支跨区高共识美股**、对比 **5 个地区**散户情绪的另一套。区 = **美国(Reddit) + 中国大陆(雪球) + 日(Yahoo) + 韩(Naver) + 台(PTT)**。
近 **14 天**。**US 区不重爬**——rollup 直接**只读**现有 Reddit `mentions×item_analysis×posts`(market=us) 算 stance/情绪（不污染主管线）；
日韩台复用 `asia_crawl.py` 的 fetch 函数（JP 板 `/quote/{SYMBOL}/forum` 美股代码直连；KR `naver_code` 由 autoComplete 解析的 reutersCode 如 NVDA.O；
TW PTT 综合板抓一遍，用繁中/英文别名从标题+正文**抽取**精选标的）。**CN(雪球)** 讨论接口在阿里云 WAF 后面、requests 直连过不去 →
用 **Claude-in-Chrome 真实浏览器**（自然过 WAF）在页面内 XHR 拉 `/query/v1/symbol/search/status.json` 导出 JSON，再 `ingest/global_retail_xueqiu.py` 收进 gr_post(region=cn)。
**打标 = DeepSeek flash 全量（不用千问）**：每帖 sentiment + 派生 stance。
跨区滚动 → `gr_ticker_region`(每 region×ticker 帖数/多空/情绪)；跨区派生 → `gr_ticker`(共识 all_bull/all_bear、分歧 divergent=某区与其余相反、情绪极差 spread)。
页面看板：五地区情绪概览+雷达 / 跨区情绪热力(标的×区) / 五地共识(共同看多·看空) / 地区分歧 / 全球定位气泡 / 全球热度榜 / **标的×五地区明细(逐区情绪条+代表帖)**。
管线：`pipeline/data/global_targets.yml`(40 标的+别名+naver码) → `ingest/global_retail_crawl.py`(+`global_retail_xueqiu.py`) → `analyze/global_retail_tag.py` → `analyze/global_retail_rollup.py`；
CLI `gr-crawl/gr-tag/gr-rollup/gr-xueqiu/gr-quote`（`gr-quote`=抓各标的最新价(Nasdaq api 主 + Yahoo 兜底) → `gr_quote` 表，`ingest/gr_quote.py`），`make gr`（含 gr-quote）/`make gr-quote`；web `lib/globalQueries.ts`。隔离表 `gr_*`（含 `gr_quote`；迁移 `supabase/migrations/…_gr_quote.sql`）。

---

## 4. 目录结构（带注释）

```
crypto_us/
├── pipeline/                  # ① Python 数据管线
│   ├── manage.py              #   统一 CLI 入口（被 Makefile 调用的所有子命令）
│   ├── daily.py               #   每日一次的全量编排（抓取→分析→聚合→翻译）
│   ├── sync.py                #   ★本地 SQLite ⇄ 云端 Supabase 同步（cloud-push / cloud-pull）
│   ├── worker.py              #   调度器（APScheduler，定时跑 daily）
│   ├── common/
│   │   ├── config.py          #   配置/环境变量（含 normalize_db_url：Supabase 串自动转 psycopg+SSL）
│   │   ├── db.py              #   SQLAlchemy 引擎/会话（sqlite 开发 / postgres 生产通用）
│   │   ├── models.py          #   ★数据模型 = schema 单一真源（14 张表）
│   │   ├── llm.py             #   ★大模型「档位路由」：LOW/MID/HIGH → 具体 provider
│   │   ├── qwen.py            #   通义千问（HIGH：逐帖打标，思考模式）
│   │   ├── deepseek.py        #   DeepSeek（MID：叙事/简报；LOW：翻译）
│   │   └── claude.py / reddit.py
│   ├── ingest/                #   抓取 + 抽取
│   │   ├── arctic_scrape.py   #   Arctic Shift 拉历史帖/评论（主力）
│   │   ├── reddit_ingest.py   #   PRAW 实时拉取
│   │   ├── author_crawl.py    #   ★作者库：爬 Top 作者历史帖（DeepSeek 粗筛→千问深析，两级漏斗控成本）
│   │   ├── asia_crawl.py      #   ★亚洲实验：爬日(Yahoo JP)/韩(Naver front-api)/台(PTT Stock)散户讨论 → 隔离表 asia_posts
│   │   ├── asia_price.py      #   亚洲实验：抓 Naver 日K收盘价 → asia_price（价格×情绪叠加图用）
│   │   ├── global_retail_crawl.py # ★全球散户：爬日韩台精选跨区美股(复用 asia fetch；PTT 别名抽取) → gr_post
│   │   ├── global_retail_xueqiu.py # ★全球散户 CN：收 Claude-in-Chrome 过 WAF 导出的雪球帖 JSON → gr_post(region=cn)
│   │   ├── ticker_extract.py  #   ★ticker 抽取器（cashtag/裸大写/公司名别名 + 停用表）
│   │   ├── seed_tickers.py    #   seed ticker 字典 → ticker_meta（含中概/港股 cn_hk_tickers.json）
│   │   └── twitter_match.py   #   ★X 推文↔标的 关键词硬匹配（无AI；读 vertical_topic_metadata.json 的 keywords，混合匹配 $cashtag/@handle/短语/单词 → tw_tweet_topic，仅 Stocks）
│   ├── analyze/              #   分析 + 聚合
│   │   ├── item_analyze.py    #   ★逐帖 AI 打标（analyze_qwen 是全站分析大脑；增量，跳过已分析）
│   │   ├── rollups.py         #   声量/情绪聚合（mindshare 归一化）
│   │   ├── market_mood.py     #   市场情绪（恐惧贪婪）
│   │   ├── trending.py        #   异动（z-score / spike）
│   │   ├── narratives.py      #   叙事聚类（deepseek 语义聚类，失败回退主题分组）
│   │   ├── brief.py           #   每日简报（deepseek 润色）
│   │   ├── asia_analyze.py    #   ★亚洲实验：逐帖打标(HIGH 千问双语)+每格汇总(MID DeepSeek overview)
│   │   ├── global_retail_tag.py    # ★全球散户：DeepSeek flash 全量打标 gr_post(sentiment+派生 stance，不用千问)
│   │   ├── global_retail_rollup.py # ★全球散户：跨区滚动 gr_ticker_region(US 读现有 Reddit) + 派生共识/分歧 gr_ticker
│   │   ├── kol_refine.py       #   ★KOL 个体观点 AI 提炼+双语：reddit/x/雪球 每标的每源 top-N → DeepSeek flash → kol_refined(stance+reason+points, zh/en；提炼与翻译合一)
│   │   ├── kol_viewpoint.py    #   ★KOL 观点 视角分类：对已蒸馏观点(kol_refined+yt_analysis) → DeepSeek flash 打 7 视角(1-3 个,首个为主) → kol_viewpoint
│   │   └── translate.py       #   翻译成中文 *_zh 列（增量、幂等；走 SQLAlchemy/DATABASE_URL，云端本地通用）
│   └── data/                  #   随仓库的字典/样本（ticker_stoplist.txt, cn_hk_tickers.json, subreddits.yml, asia_targets.yml, global_targets.yml…）
│
├── web/                       # ③ Next.js 14 静态站
│   ├── app/
│   │   ├── layout.tsx         #   根布局（主题防闪烁 + 默认 OG/metadataBase）
│   │   ├── [lang]/            #   语言段（zh|en|ja|ko）：generateStaticParams（页面数 = locales × 各内页）
│   │   │   #   layout.tsx 仅 LocaleProvider；(app)/ = 侧栏壳(Sidebar/Topbar/MobileTabBar)，(marketing)/ = 无侧栏落地页壳
│   │   │   ├── page.tsx       #     ★总览看板（异动优先：异动与信号[跨区分歧/最看多/最看空 + gr_quote 价格异动] → 其次 市场总览[KPI/五区情绪/全球热度榜/跨区情绪热力]）
│   │   │   ├── tickers/ + tickers/[symbol]/   # 标的总览(可排序表) + 标的详情(★模块看板:异动/跨区视角/海外信息差/独有叙事/多空共识/最强反方/风险温度/大家在等什么 — mock,多图表)
│   │   │   ├── regions/ + regions/[region]/   # 区域总览(5 区卡+净情绪) + 区域详情(★模块看板:地区脉搏/热榜/异动/独有叙事/本区vs全球/性格画像/注意力轮动/今日引爆 — mock,多图表)
│   │   │   ├── search/        #     搜索（客户端 ticker/公司名模糊匹配）
│   │   │   ├── me(Profile) account(设置) login/ signup/ forgot-password/ reset-password/ auth/callback/  # 账号系统
│   │   │   ├── onboarding/    #     ★首登引导向导（沉浸式全屏；采集投资画像→写 user_profiles+自动追踪持仓；?edit=1 从设置复用）
│   │   │   ├── insights(管理员看板) status(routine 运维)
│   │   │   ├── lab/global-retail/ lab/asia-pulse/   # 旧 5 地区/亚洲原型（noindex；图表组件被新页复用）
│   │   │   └── lab/dev/      #     ★测试控制台（隐藏 noindex）：按钮即时触发/重置 onboarding·收藏·埋点·PWA 自测（DevConsole）
│   │   ├── sitemap.ts / robots.ts / not-found.tsx   # SEO + 404
│   │   └── icon.png           #   favicon
│   ├── lib/
│   │   ├── db.ts              #   ★构建期用 node:sqlite 读 ../data/dev.db；库缺失/查询失败→降级空（不崩 output:export）
│   │   ├── queries.ts         #   ★所有取数 SQL（getMindshare/getTrending/getPostDetail…）
│   │   ├── asiaQueries.ts      #   亚洲实验隐藏页取数（读 asia_* 表，try/catch 包裹：表缺失返回空不崩）
│   │   ├── globalQueries.ts    #   全球散户隐藏页取数（读 gr_* 表 + US 代表帖读现有 Reddit；try/catch 兜底）
│   │   ├── investorQueries.ts   #   投资者榜单取数（getInvestorBoard：X/YouTube/Reddit/雪球 各按作者聚合互动·播放→排名；缺表返回空）
│   │   ├── i18n.ts + dictionaries/{zh,en,ja,ko}.ts # 多语（zh 为源，en/ja/ko 必须镜像同样的 key；UI 译，帖子内容 ja/ko 回退英文原文）
│   │   ├── supabase.ts / auth.ts / admin.ts    # Supabase 客户端 + 登录 + 管理员判定
│   │   ├── analytics.ts / searchCounts.ts      # 埋点 + 搜索榜（写 Supabase）
│   │   ├── favorites.ts                         # ★账户收藏/追踪：客户端读写 user_collections（RLS）
│   │   ├── profile.ts                           # ★用户投资画像：客户端读写 user_profiles（RLS）+ markOnboarded/isOnboarded（门禁标志走 user_metadata）
│   │   ├── instruments.ts                       # onboarding 持仓选择器的「广义标的」补集（ETF/杠杆反向/商品/加密/债券；个股来自 gr_ticker）
│   │   └── site.ts            #   SITE_URL（https://www.redditalpha.xyz）+ OG
│   ├── components/            #   UI 组件（Sidebar/Topbar/FeedCard/MarkdownLite… + auth/ favorites/ profile/ onboarding/ + OnboardingGate 首登门禁）
│   ├── next.config.mjs        #   output:export(仅生产) + cpus:1 串行导出 + images:unoptimized
│   └── public/               #   logo/og/avatars/communities（图片已压缩）
│
├── supabase/migrations/       # ② Supabase SQL 迁移（ticker_searches / analytics / user_collections / user_profiles 的表+RLS+RPC）
├── data/dev.db                # 本地 SQLite 快照（gitignore；由 cloud-pull 从云端拉取）
├── dashboard.html             # ★Advanced Mindshare 实验单页：由 data/prismo_snapshot.db + 可选 forum_mindshare.json 预计算指标生成的纯 HTML 看板
├── experiments/
│   ├── build_mindshare_dashboard.py # 生成 dashboard.html（penetration/entropy/方向/集中度/热力图；若找到 equity1000/forum_mindshare.json，则合并 JP/KR/US/TW 论坛 region 对比）
│   └── exp1_fwd_return_probe.py     # 论坛信号 vs 前向收益的验证探针
├── Makefile                   # ★所有常用命令入口
├── .env / .env.example        # 凭据与配置（.env gitignore：QWEN/DEEPSEEK/DATABASE_URL…）
└── 文档：README / DEPLOY / CLOUD_DB / SUPABASE_AUTH / STRATEGY / ARCHITECTURE(本文)
```

---

## 5. 数据库 schema（14 主表 + 4 亚洲 + 3 全球散户 + 3 YouTube + 1 KOL 提炼 隔离表，`pipeline/common/models.py` 为单一真源；另有**仓库外加载**的 X `tw_*`，见表末行）

| 类别 | 表 | 说明 |
|---|---|---|
| 原始 | `subreddits` `authors` `posts` `comments` | 抓来的原始内容（含 `*_zh` 译文列、`market`；`posts.source` scan/author 区分实时舆情/作者库，`authors.crawled_at` 作者库增量标记） |
| 字典/抽取 | `ticker_meta` `mentions` | ticker 字典 + 帖子↔ticker 提及（含 confidence/method） |
| AI 分析 | `item_analysis` | ★逐帖打标结果（情绪/多空/质量/主题/双语摘要/per-ticker 论据），按 item_id 持久化 |
| 派生聚合 | `ticker_rollup` `market_mood` `trending` | 声量榜 / 市场情绪 / 异动（每次全量重算，可弃） |
| 叙事/简报 | `narratives` `narrative_tickers` `narrative_posts` `daily_briefs` | 主导叙事 + 每日简报 |
| 亚洲实验(隔离) | `asia_posts` `asia_analysis` `asia_ticker_summary` `asia_price` | 日韩本土散户帖(含 `sentiment`=flash 全量打分 + views/comments/images/verified) + 千问深析 + 每格汇总 + 日K价格（market `jp`/`kr`；与 us/cn 完全隔离，实时聚合/feed 一律不读，仅供隐藏看板） |
| 全球散户(隔离) | `gr_post` `gr_ticker_region` `gr_ticker` | 日韩台+中国大陆(雪球)爬精选跨区美股的散户帖(flash 打标 sentiment+stance) + 每 region×ticker 滚动(region `us`/`cn`/`jp`/`kr`/`tw`；**US 不入 gr_post，rollup 只读现有 Reddit**；CN 经浏览器过 WAF 导入) + 每 ticker 跨区派生(共识/分歧)。与 us/cn 主表 及 asia_* 均隔离，仅供隐藏页 /lab/global-retail |
| YouTube 观点(隔离) | `yt_video` `yt_analysis` `yt_ticker_summary` | 按标的近 24h、浏览量>1000 的**全语种**财经视频(YouTube Data API)→ Gemini **混合分析**(top N 原生看视频[画面+音频] + 其余字幕，受 8h/天视频预算)出 stance/sentiment/双语摘要 → 每标的浏览量加权汇总。**两条分析路径**：① `youtube-tag` Gemini 真看视频（最准；`--workers>1` 走**并发**真看，billing 解锁 8h/天后用，~8 线程；字幕本机 IP 抓不到→一律原生 video）；② `youtube-tag-text` **无配额兜底**：用**标题+简介**跑 DeepSeek(flash) 出双语观点(mode=`text`)，覆盖 Gemini 没看的长尾、**不占 `analyzed` 旗标**→ 日后 Gemini 仍能升级覆盖。**纳入站外当地分析者**(韩 슈퍼개미/日 testa/美 FinTube)。**标的页正式模块**「YouTube 观点」；缺 key 回退 mock |
| KOL 提炼(隔离) | `kol_refined` | ★个体观点「AI 提炼+双语」：对 reddit/x/雪球 每标的每源 top-N 跑 DeepSeek(flash) → stance + **reason_zh·en**(为什么看多/看空) + **points_zh·en**(2-3 要点)，**提炼与翻译合一**(只 zh/en，ja/ko 前端回退 en)。PK source+item_id；`pipeline/analyze/kol_refine.py`/`make kol-refine`(增量、`--per-source`/`--only`/`--force`)。**标的页象限①「个体观点·KOL」** 用之替换照搬原文；YouTube 不入此表(复用 `yt_analysis`) |
| KOL 视角分类(隔离) | `kol_viewpoint` | ★把已蒸馏观点(kol_refined + yt_analysis)用 DeepSeek(flash) 分到 **7 视角**(估值/业务成长/竞争/管理层/宏观/催化剂/资金盘面，1-3 个、首个为主、纯方向性/情绪→other)。PK 同 kol_refined (source,item_id,ticker)；`pipeline/analyze/kol_viewpoint.py`/`make kol-viewpoint`(增量、无明确观点预判 other 省调用)。供**标的页 KOL 模块的「视角」分类**(`ClassifiedOpinions.tsx` 视角 tab，只展示折线图选定那天的观点)，web 经 `kolQueries.viewpointMap` 挂到观点上 |
| **X/Twitter(隔离·外部加载)** | `tw_tweet`(58万) `tw_kol` `tw_tweet_ticker` `tw_crawl_state` `tw_tweet_sentiment`(空) `tw_ticker_rollup`(空) + `tw_tweet_topic` | KOL 推文由**仓库外工具**灌入云端(14 天 bootstrap，**尚未打情绪/未聚合**)，**均不在 `models.py`**。`tw_tweet_topic` = `ingest/twitter_match.py` 的**关键词硬匹配**派生(无 AI；按 `vertical_topic_metadata.json` 每 topic 的 keyword_list 混合匹配 $cashtag/@handle/短语/单词，sigil 敏感+Unicode 分词)→ 仅留 **Stocks** vertical 并清掉「普通词」误报(Bullish→BLSH 等)；约 8.6 万 (推文,标的) 对 |

> 迁移只搬「原始+字典+AI 分析」这 7 张源表（贵、需长期保存）；派生表在云端用 `make rollup` 等重算。
> 亚洲实验 4 表 + 全球散户 3 表 + YouTube 3 表都在 `ALL_TABLES`（`cloud-pull` 会快照），但**不在** `sync.SOURCE_TABLES`；`make asia` / `make gr` / `make youtube` 写当前 `DATABASE_URL`（本地验证用 `DATABASE_URL='sqlite:///./data/dev.db'` 覆盖，勿对云端跑建表 DDL）。
> **X 的 `tw_*` 不同**：由仓库外工具直接写云端，**不在 `models.py`/`ALL_TABLES`**（故 `cloud-pull` 不快照、网站构建也不读）；`tw_tweet_topic` 由 `twitter_match.py` 用原生 DDL 自建。重跑匹配：`pipeline/.venv/bin/python -m pipeline.ingest.twitter_match`（整表重算，幂等）。

---

## 6. 大模型档位（`pipeline/common/llm.py` 为路由真源）

| 档位 | 用途 | 当前 provider |
|---|---|---|
| **HIGH** | 逐帖投资打标（思考模式，全站分析大脑，token 大头） | 通义千问 `qwen3.7-plus` |
| **MID** | 叙事聚类 / 每日简报 / 正文重排版 | DeepSeek `deepseek-v4-pro` |
| **LOW** | 翻译 + KOL 提炼/视角/论点综合（走量） | 通义千问 `qwen-flash`（原 DeepSeek flash；2026-06 DeepSeek 余额耗尽 → 切千问，`QWEN_MODEL_LOW` 可改回）。**故 KOL 三步现需 `QWEN_API_KEY`，非 DeepSeek** |
| **VIDEO**（独立 provider，不经 llm.py 档位路由） | YouTube 视频理解(画面+音频) + 字幕文本总结（「YouTube 观点」模块） | Gemini `gemini-3.5-flash`（`common/gemini.py`；`file_data` 直传 YouTube URL，preview 免费/限 8h/天） |

改模型只动 `llm.py` 路由表（Gemini 例外：在 `common/gemini.py` 由 `youtube_analyze` 直接调用）。缺 key 时各环节回退 mock 启发式，不崩。

---

## 7. 常用命令（Makefile）

| 命令 | 作用 |
|---|---|
| `make daily` | 分析过去 24h（抓取+AI 打标+聚合+翻译），直接写 `DATABASE_URL`（云端）；含作者库爬取 |
| `make crawl-authors` | 单独跑作者库：爬实力榜 Top 作者历史帖（DeepSeek 粗筛→千问深析）。需 DeepSeek key |
| `make analyze-qwen` | 真实千问逐帖打标 + 重算聚合 |
| `make asia` | 亚洲散户舆情实验：爬日(Yahoo)/韩(Naver)本土板 + 真实 AI 分析（千问逐帖 + DeepSeek 汇总）。`make asia-mock` 为零成本版 |
| `make gr` | 全球散户五地区看板：日韩台爬精选跨区美股 + DeepSeek flash 打标 + 跨区滚动(US 读现有 Reddit)。隐藏页 /lab/global-retail。CN(雪球)走 `gr-xueqiu`(收浏览器过 WAF 的导出 JSON) |
| `make youtube` | YouTube 观点：按标的搜近 24h、浏览量>1000 的全语种视频(`youtube-crawl`) + Gemini 混合分析(`youtube-tag`：top N 原生看视频+其余字幕)→ 标的页「YouTube 观点」模块。需 `YOUTUBE_API_KEY`+`GEMINI_API_KEY`；无 key 验证 `make youtube-mock`(多语种样本)。**全量真看视频**(billing)：`youtube-tag --workers 8`(并发)；**无配额兜底**：`youtube-tag-text`(标题+简介→DeepSeek 双语，mode=text) |
| `make kol-refine` | KOL 个体观点提炼：reddit/x/雪球 每标的每源 top-N 跑 DeepSeek(flash) → `kol_refined`(为什么看多/看空 + 2-3 要点，zh/en)。标的页象限①「个体观点·KOL」展示提炼而非照搬原文。增量；`pipeline.manage kol-refine --per-source/--only/--source/--force`。需 `DEEPSEEK_API_KEY` |
| `make kol-viewpoint` | KOL 观点视角分类：对已蒸馏观点(`kol_refined`+`yt_analysis`) 跑 DeepSeek(flash) → `kol_viewpoint`(7 视角 1-3 个)。供标的页 KOL 模块「按视角」视图。增量；先跑 `kol-refine` 再跑本目标；`--only/--force`。需 `DEEPSEEK_API_KEY` |
| `make kol-translate` | KOL 原帖**完整忠实翻译**(逐句、不压缩) → `kol_refined.trans_zh·en`。供观点浏览器卡片/阅读面板的「译」选项。只译已展示项、增量；与提炼解耦可独立重跑；`--source/--per-source/--since-days/--only/--force`。需 `QWEN_API_KEY`。本地测试加 `DATABASE_URL=sqlite:///./data/dev.db` 直写 `dev.db` |
| `make kol-relevance` | KOL **相关性打分** 0-100(越高=越是在讲这只票，区分「深度分析」vs「顺带列入名单」) → 隔离表 `kol_relevance`(覆盖 reddit/x/雪球+youtube)。供观点浏览器默认『相关度降序』排序(不做筛选)。增量、可独立重跑；`--only/--force/--per-source/--no-youtube`。需 `QWEN_API_KEY`。本地测试同上 |
| `make kol-quality` | KOL **帖子质量打分** 0-100(内容含金量：实质分析/数据/逻辑 vs 口号/喊单/灌水；**与标的无关**，按 source+item 去重) → 隔离表 `kol_quality`。供观点浏览器『只看高质量』开关(≥65)。覆盖 reddit/x/雪球+youtube；增量；`--only/--force/--per-source/--no-youtube`。需 `QWEN_API_KEY` |
| `make mindshare-dashboard` | 从 `data/prismo_snapshot.db` 生成根目录 `dashboard.html`：单文件实验面板，展示 penetration/entropy/量加权方向/集中度/跨市场与社区热力等 Advanced Mindshare 移植指标；若存在 `/Users/tongzheng/equity1000/forum_mindshare.json` 或 `FORUM_MINDSHARE_JSON` 指定文件，会额外嵌入 JP Yahoo / KR Naver / US Reddit / TW PTT 的 ticker×region 与 region×ticker 对比 |
| `make rollup / mood / trending / narratives / brief` | 单独重算各聚合 |
| `make cloud-init` | 一次性迁移：建表 + 上传本地源数据 + 云端重算派生表 |
| `make cloud-push` | 把本地源数据增量上传到云端 |
| `make cloud-pull` | 从云端拉快照覆盖本地 `data/dev.db`（构建前用） |
| `make site` | 构建静态站 `web/out/`（需 **Node 22**） |
| `make site-cloud` | `cloud-pull` + 构建（部署前用这个） |
| `make stats` | 打印库内统计 |
| `make demo` | 一键离线全流程（样本+mock，无需 key） |

---

## 8. 构建 & 部署

1. `nvm use 22`（**必须 Node 22**；Node 23 + 实验 SQLite 会让构建被系统 SIGKILL）。
2. `make site-cloud`（从云端拉数据 + `next build` → `web/out/`，~6500 页、cpus:1 串行 ~2–3 分钟）。
3. 部署 `web/out/` 到静态托管（自定义根域名 www.redditalpha.xyz）。详见 `DEPLOY.md`。

---

## 9. 重要约定 / 易踩坑

- **构建用 Node 22**（见上）。若构建报 `Cannot find module for page /_not-found`：先 `rm -rf web/.next web/out` 再构建（残留进程会锁住 .next）。
- **多语字典**：`dictionaries/zh.ts` 是源（`Dictionary = typeof zh`），`en.ts`/`ja.ts`/`ko.ts` 必须镜像完全相同的 key（`npx tsc --noEmit` 会强校验）。新增 locale 只需在 `i18n.ts` 的 `locales`/`isLocale`/`DICTS` 三处登记 + 加 `LanguageSwitcher` 选项；路由/sitemap 自动随 `locales` 扩展。帖子内容只有 `*_zh` 译文，故 ja/ko 渲染时回退英文原文。
- **密钥不入库**：`.env` / `web/.env.local` 已 gitignore；含 `QWEN_API_KEY`/`DEEPSEEK_API_KEY`/`DATABASE_URL`(含密码)/Supabase anon key 等，切勿提交或泄露。
- **回到纯本地**：`.env` 的 `DATABASE_URL` 改回 `sqlite:///./data/dev.db` 即可。
- **管线所有步骤必须走 SQLAlchemy（`common/db.py` 的 engine），不要裸 `sqlite3.connect`**：否则 `DATABASE_URL` 指向云端时会把结果写进本地文件、云端拿不到。`translate.py` 曾因此漏译（已修）；`format_posts.py` / `seed_demo_zh.py` 仍是裸 sqlite3，仅本地/ demo 用，勿放进 daily 云端流程。
- **管理员看板**（`/insights`）：前端只是 UX 门槛，真正鉴权在 Supabase 端（`is_admin()` 校验 JWT 邮箱）。
- **待办（省 token）**：千问/DeepSeek 的系统提示词每次逐帖重发，未确认是否走缓存计费；可启用上下文缓存。
