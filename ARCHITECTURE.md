# 项目架构与结构（ARCHITECTURE）

> **维护约定**：本文件是项目的「活地图」。**每次对项目结构或功能有实质改动后，必须同步更新本文件对应章节**
> （新增/删除模块、改数据流、改命令、改部署方式、改 schema 等）。详见根目录 `CLAUDE.md`。
> 最近更新：2026-07-19。

---

## 0. 架构文档导航与模块边界

根目录 `ARCHITECTURE.md` 保持为项目活地图，记录当前系统事实、数据真源、主要目录和关键命令。长期设计边界已拆到专题文档：

- `docs/architecture/00-overview.md`：系统总览、当前真源和迁移策略。
- `docs/architecture/01-frontend.md`：Next.js 前端 feature/shared/server 边界。
- `docs/architecture/02-pipeline.md`：Python 管线 platforms/domain/jobs/cli 边界。
- `docs/architecture/03-data-model.md`：raw/normalized/analysis/rollup/export 数据层级。
- `docs/architecture/04-platform-adapters.md`：新增平台适配器规范。
- `docs/architecture/05-smart-voice.md`：Smart Voice 工程边界。
- `docs/architecture/06-deployment.md`：静态构建、数据快照与部署。
- `docs/architecture/07-conventions.md`：命名、文件大小、验证和文档同步规则。
- `docs/architecture/08-development-rules.md`：后续新功能开发落点、禁止落点、常见场景和验证清单。

跨平台产品契约位于 `docs/contracts/`：`opinion`、`author`、`ticker`、`judgment`、`smart_voice`、`narrative`。新增平台、观点筛选、SV、目标价、叙事等功能前，先确认 `docs/architecture/08-development-rules.md` 和对应 contract。

**迁移期规则**：现有 `web/lib/*Queries.ts`、`web/components/prismo/*`、`pipeline/manage.py`、`pipeline/ingest`、`pipeline/analyze` 继续可用；新增复杂功能优先落到目标边界 `web/features`、`web/shared`、`web/server`、`pipeline/platforms`、`pipeline/domain`、`pipeline/jobs`、`pipeline/cli`。`pipeline/ingest` 和 `pipeline/analyze` 现在只作为历史导入/命令路径兼容层保留，新增平台或分析实现不得继续写入旧目录。前端 Tailwind content 必须覆盖 `web/features` 和 `web/shared`，否则迁移后的组件样式不会被生成。

**边界检查**：结构性改动后运行 `python3 scripts/check_architecture.py`。该脚本目前强制检查：`pipeline/cli` 只能调用 `pipeline/jobs`，`pipeline/jobs` 不得直连旧 `pipeline/ingest`/`pipeline/analyze`，平台/domain 层不反向依赖上层；前端禁止迁移后的 feature/shared/server 回流到旧 Prismo 组件或旧 query 文件。

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
> **主要页面**（数据多走 `gr_*` → `lib/globalQueries.ts`；投资者/作者页另走 `investorQueries`/`creatorQueries`；Smart Voice 作者详情读 `smartVoice.json` + `smartVoiceInvestorQueries`；叙事页走构建期 JSON）：**落地页**(`/`，无侧栏 chrome) · **总览看板**(`/dashboard`，单视窗三栏工作台：市场信号/五区情绪、跨区热力/全球热度榜、Smart Voice 精简榜；长列表模块内滚动) · **叙事轮动**(`/narratives` + `/narratives/[slug]`，固定板块叙事的跨社区热度排名/讨论占比/情绪转向；入口在桌面侧栏，移动底栏暂不扩容；只做 zh/en 内容，ja/ko 回退英文) · 标的总览(`/tickers`) · 标的详情(`/tickers/[symbol]`；`MU/NVDA/MSTR` 首批展示历史时点 Top/Bottom SV 聚集、无泄漏回测、SV 加权目标价、观点变化雷达、预期差/拥挤风险、投资逻辑生命周期、跨平台扩散、作者能力矩阵、三标的组合叙事风险、可解释提醒和个性化仓位匹配，其余标的保留旧 SV 投资者模块) · 投资者榜单(`/investors`) · YouTube 作者页(`/investors/youtube/[channelId]`) · Smart Voice 工作台(`/smart-voice`，借鉴 Nansen Smart Money 的信息架构，单视窗展示高 SV 标的集中方向、高低 SV 分歧、X/YouTube/Reddit/雪球完整平台排名、明确分层的全部已评分作者观察池和近 60 天最新 actionable call；标的聚合使用各来源正式平台 rank 成员，支持四平台任意非空组合及 24H/3D/7D/30D/90D 窗口，集中方向至少需要 2 条同向 call 和 2 位独立 Top 10% 作者，右侧按同口径展示净强度、原文证据及原始链接，并独立展示按每位作者最新 call 去重的一人一票净人数/共识度，以及与前一等长窗口比较的作者净人数突变幅度、状态和排名；观察池不参与正式分位信号，实时流按来源限额且不声称真实持仓或资金流) · SV 作者详情(`/investors/smart-voice/[investorId]`，正式平台排名作者的分数解释、风格分类与代表性 call) · 追踪/自选(`/tracking`) · 区域总览(`/regions`) · 区域详情(`/regions/[region]`) · 搜索(`/search`) · Profile(`/me`) · 设置(`/account`)。**叙事轮动页**不再使用旧 Reddit-only `narratives` 表，也不把财报/政策/估值等事件或驱动因素作为叙事板块；离线 `make narrative-rotation` 从 `gr_post`、Reddit `posts+item_analysis`、`x_opinion+kol_refined`、`yt_video+yt_analysis` 读取内容，先按最新源日期把时间窗口下推到各平台 SQL，再按固定板块 taxonomy 归入一个主叙事，输出 `web/lib/data/narrativeRotation.json`；Web 端 `lib/narrativeRotation.ts` + `components/prismo/NarrativeRotationCharts.tsx` 渲染顶部三张轮动图、轮动榜与详情页来源/地区/标的分布，暂不展示代表原帖。
> **标的页『目标价 × 操作周期』(2026-06-29 新增)**：① **观点检索/正文提炼**——每条观点抽到时在 reader 多显一行「作者明确给出 买入/卖出/目标价 + 周期(原话+档)」(`OpinionExplorer` 的 `JudgmentLine`)；`getKolOpinions` 汇总 Reddit/YouTube/雪球/Toss/Yahoo JP/X。浏览器端观点池是有界展示层，不是原始数据真源：Reddit 按近 370 天时间倒序取最近 350 条，X 仅纳入已进入 `kol_refined` 的观点并按质量、相关性、互动排序取前 120 条，雪球/Toss/Yahoo JP 各取 100 条；全量原帖仍保留在 SQLite 并用于离线日指标，避免 mega-cap 单页把数万条 X 帖文序列化成百 MB HTML。② **整体数据**——`KolModule` 底部通过 `web/features/ticker/components/TargetPricePanel.tsx` 渲染目标价时间线/价格分布/筛选入口，旧 `web/components/prismo/TargetPricePanel.tsx` 只保留兼容导出。抽取层=独立表 `kol_judgment`(reddit/x/雪球/Toss/Yahoo JP，见 §5)+ YouTube 复用 `yt_judgment`；**只抽作者明说、反臆造**，价格在 `kolQueries.judgmentMap` 按**现价 0.2–5× band 剔噪**(penny-pump/假设估值/$1225 这类数量级离谱者置空)。取数 `getKolTargetPrices`(复用 `getKolOpinions` 池，judgment 挂到 `KolOpinion.judgment`)。`make kol-judgment`。
> Reddit 单站旧页（dashboard/ticker/post/author/leaderboard/cn/onboarding）已删；**后端 pipeline 全保留**。线上 redditalpha.xyz 仍由旧 `reddit_alpha` 仓库部署、不受影响（Prismo 部署需快照含 `gr_*`，否则相关页为空）。

---

## 2. 三大系统

> **⚠ 两站两套数据、互不干扰（2026-06）**：本仓库 = **prismo.today**（完整多社区），数据真源 = **本地 `data/dev.db`**（含 gr_*/yt_*/kol_* 等云端没有的独有层）；旧站 **redditalpha.xyz** = `Conor-711/reddit_alpha` 仓库（只 Reddit），数据 = 下面的 Supabase 云端。**Prismo 不再 `cloud-pull`**（它会用「只有 Reddit 核心」的云端快照覆盖本地、抹掉独有层 = 之前『数据消失』元凶；已在 Makefile 锁死：`site-cloud`=`make site`、`cloud-pull` 默认拒绝、`clean` 不删 db）。出站 `make site` 读本地 dev.db。

```
┌─────────────────┐  写本地   ┌──────────────────────┐   读本地   ┌─────────────────────┐
│ ① Python 数据管线 │ ───────▶ │ ② 本地 data/dev.db       │ ───────▶ │ ③ Next.js 静态网站   │
│  抓取 + AI 分析   │  (默认)   │  Prismo 唯一真源(gr/yt/kol)│  构建期    │  读 dev.db → 出 HTML │
└─────────────────┘          └──────────────────────┘          └─────────────────────┘
        │  只读拉 tw_*(X)            ▲ Supabase 云端 = redditalpha 的 Reddit 核心
        └──────────────────────────┘   + Prismo 的 web 后端(Auth/app_events/收藏)，ref wimipsiwtrqhizgmbxas
```

### ① Python 数据管线（`pipeline/`）
抓 Reddit → 抽取 ticker → 大模型逐帖打标 → 聚合（榜单/情绪/异动/叙事/简报）→ 翻译；+ 5 社区 `gr_*`、YouTube `yt_*`、KOL `kol_*` 等扩展层。
**Prismo 内容写本地 `data/dev.db`**（`DATABASE_URL='sqlite:///./data/dev.db'`）。**X 数据 `tw_*` 从云端只读拉**（`kol_sentiment.py`/`kol_volume.py` 的 `_cloud_url()` 直接读 `.env` 拿云端串）。

### ② 数据真源 = 本地 `data/dev.db`（Prismo）
- Reddit 核心（14 表）+ **Prismo 独有层** `gr_*`(5 社区)/`yt_*`(YouTube)/`kol_*`/`x_opinion`/`price_daily`/`author_avatar` 等（这些云端**没有**）。
- **推荐部署路径：Cloudflare Pages Direct Upload**。本地用 Node 22 + `node:sqlite` 读取 `data/dev.db` 构建 `web/out/`，再 `make cf-deploy` 上传 zh/en 静态产物；Cloudflare 运行时不需要 Node 服务，也不重新构建。
- Railway/Dockerfile 仍可作为备用部署路径：用**提交进仓库的压缩数据快照**构建（线上=本地）。原始 `data/dev.db` 被 Git 和 Docker context 忽略，不再走 Git LFS。更新数据后运行 `make snapshot-db`：压缩结果不超过 90MB 时只提交 `data/dev.db.xz`，超过时只提交普通 Git 分片 `data/dev.db.xz.part-*` 和 manifest `data/dev.db.xz.parts`。Docker 按 manifest/单文件顺序还原。改数据前用 `make backup-db` 写项目外轮换备份。
- **Supabase 云端**（`wimipsiwtrqhizgmbxas`，**不是 Prismo 的内容家**）：① redditalpha.xyz 的 Reddit 核心；② Prismo 的 **web 后端**（`app_events`/`ticker_searches`/`user_collections`/`user_profiles`/Auth，走 `NEXT_PUBLIC_*`）；③ Prismo 只读的 `tw_*`(X)。见 `CLOUD_DB.md`。

### ③ Next.js 静态网站（`web/`）
Next 14 App Router，**静态导出**（`output:"export"` 仅生产）。构建期用 `node:sqlite` 读**本地 `data/dev.db`**
（Prismo 真源，**不再 cloud-pull**），生成 ~6500 个静态页面到 `web/out/`，可部署到任意静态托管。
**网站运行时不连数据库**（纯静态，无服务端攻击面）。

---

## 3. 端到端数据流

```
平台 API / 浏览器导出 / 外部快照
        │
        ▼
pipeline ingest / platforms(目标边界) ──▶ raw / normalized tables
        │                                      │
        ▼                                      ▼
pipeline analyze / domain / jobs ──────▶ analysis / rollup tables
        │                                      │
        └────────────── 写入本地 data/dev.db ◀─┘
                                               │
                    构建期 JSON(web/lib/data/*.json) + node:sqlite 查询
                                               │
                                               ▼
                                      Next.js export → web/out/
```

**关键：Prismo 内容默认写本地 `data/dev.db`，出站 `make site` 读取本地真源。** Supabase 不再是 Prismo 内容家，只承担 redditalpha 旧站核心、Prismo web 后端、以及部分 `tw_*` 外部数据读取。分析层保持增量：逐帖打标按稳定内容 ID 持久化，只分析新内容；rollup/export 层应可重算。

**作者库（优质作者聚合页）** —— `make daily` 内（主分析之后）爬「实力榜」Top 50 作者的 Reddit 历史帖，
两级模型漏斗控成本：**DeepSeek(LOW) 粗筛质量 → 仅过线帖送千问(HIGH) 深析并入库**。这些帖标记
`posts.source='author'`，**被所有实时舆情聚合/feed 排除**（`source='scan'` 过滤），只出现在作者页与其自身帖详情页。
入口：全站作者名/头像 → `/[lang]/author/[name]/`。详见 `pipeline/platforms/reddit/authors.py`（旧 `pipeline/ingest/author_crawl.py` 为 wrapper）。

**全球散户 · 五地区数据层** —— 这是 ticker 中心、
**精选 ~40 支跨区高共识美股**、对比 **5 个地区**散户情绪的另一套。区 = **美国(Reddit) + 中国大陆(雪球) + 日(Yahoo) + 韩(Naver) + 台(PTT)**。
近 **14 天**。**US 区不重爬**——rollup 直接**只读**现有 Reddit `mentions×item_analysis×posts`(market=us) 算 stance/情绪（不污染主管线）；
日韩台复用 `platforms/global_retail/asia_sources.py` 的共享 fetch 函数（JP 板 `/quote/{SYMBOL}/forum` 美股代码直连；KR `naver_code` 由 autoComplete 解析的 reutersCode 如 NVDA.O；
TW PTT 综合板抓一遍，用繁中/英文别名从标题+正文**抽取**精选标的）。**CN(雪球)** 讨论接口在阿里云 WAF 后面、requests 直连过不去 →
用 **Claude-in-Chrome 真实浏览器**（自然过 WAF）在页面内 XHR 拉 `/query/v1/symbol/search/status.json` 导出 JSON，再由 `platforms/global_retail/xueqiu_export.py` 收进 gr_post(region=cn)。
**打标 = DeepSeek flash 全量（不用千问）**：每帖 sentiment + 派生 stance。
跨区滚动 → `gr_ticker_region`(每 region×ticker 帖数/多空/情绪)；跨区派生 → `gr_ticker`(共识 all_bull/all_bear、分歧 divergent=某区与其余相反、情绪极差 spread)。
正式页面消费：总览、标的、区域与追踪页读取 `gr_*`，展示五地区情绪、跨区热力、共识/分歧、全球热度榜与代表帖。
管线：`pipeline/data/global_targets.yml`(40 标的+别名+naver码) → `platforms/global_retail`/legacy ingest 抓取 → `domain/global_retail` 打标与聚合；
CLI `gr-crawl/gr-tag/gr-rollup/gr-xueqiu/gr-quote`（`gr-quote`=抓各标的最新价(Nasdaq api 主 + Yahoo 兜底) → `gr_quote` 表，实际实现 `platforms/global_retail/quotes.py`，旧 `ingest/gr_quote.py` 为 wrapper），`make gr`（含 gr-quote）/`make gr-quote`；web `lib/globalQueries.ts`。隔离表 `gr_*`（含 `gr_quote`；迁移 `supabase/migrations/…_gr_quote.sql`）。

**雪球 SV 作者池（2026-07-10）**：作者发现样本先写 `xueqiu_author_snapshot`，`domain/authors/xueqiu_pool.py` 按版本把候选写入 `xueqiu_author_pool`；首版门槛为粉丝 ≥500（或认证）且平台历史发帖 ≥300，明显媒体/机构发布者单独标记，正式池取 Top 300 位创作者，其余为 warm reserve。`platforms/xueqiu/author_timeline.py` 为每位候选建立 `xueqiu_author_crawl_job`，通过已登录 Playwright 会话按作者回填一年时间线，正文继续写 `xueqiu_raw_post`，随后统一扩展 `xueqiu_post_ticker`。雪球未登录会话只能读取作者首屏；首次运行 `make xueqiu-author-auth` 由用户本人完成登录，会话仅保存到 gitignore 的 `.xueqiu_storage_state.json`，不保存密码。常用入口：`make xueqiu-author-plan/auth/run/drain/status`；`drain` 以小批次和自适应冷却持续消耗正式作者池：部分成功固定退避 30 分钟，仅整批零成功才指数退避且最长 1 小时；SQLite 写锁、连接重置和浏览器导航超时会自动重试，超过 10 分钟未更新的 `running` 任务会保留游标恢复为 `pending`。`domain/smart_voice/v0_impl.py` 的 `xueqiu` 候选适配器只消费该版本中 `selected=1` 且回填完成的作者，并默认要求正式池全部完成后才放行候选召回；转发内容被排除，粉丝/认证/发现排名不进入 SV 得分。

---

## 4. 目录结构（带注释）

```
crypto_us/
├── pipeline/                  # ① Python 数据管线
│   ├── manage.py              #   统一 CLI 入口（被 Makefile 调用的所有子命令）
│   ├── daily.py               #   每日一次的全量编排（抓取→分析→聚合→翻译）
│   ├── sync.py                #   ★本地 SQLite ⇄ 云端 Supabase 同步（cloud-push / cloud-pull）
│   ├── worker.py              #   调度器（APScheduler，定时跑 daily）
│   ├── cli/                   #   目标边界：CLI 注册与参数解析（迁移期 README，manage.py 后续拆入）
│   ├── platforms/             #   目标边界：Reddit/X/YouTube/雪球/Toss 等平台适配器
│   │   ├── reddit/            #   Reddit PRAW/Arctic/作者池抓取（旧 ingest/reddit_* 为 wrapper）
│   │   ├── local/             #   本地样本数据加载（旧 ingest/sample_loader.py 为 wrapper）
│   │   ├── youtube/           #   YouTube 视频发现、频道刷新（旧 ingest/youtube_* 为 wrapper）
│   │   ├── toss/              #   Toss 社区抓取（旧 ingest/toss.py 为 wrapper）
│   │   ├── x/                 #   X 推文↔标的硬匹配、云端 X 拉取、完整 X ticker universe（旧 ingest/twitter_match.py/x_pull.py/load_complete_x_ticker_universe.py 为 wrapper）
│   │   ├── market_data/       #   SV 价格历史回填、短窗口 price_daily 加载（旧 ingest/sv_price_history.py/price_daily.py 为 wrapper）
│   │   ├── author_assets/     #   作者头像等跨平台作者资产刷新（旧 ingest/author_avatars.py 为 wrapper）
│   │   ├── global_retail/     #   全球散户多区抓取、雪球导入与报价
│   │   └── xueqiu/            #   雪球 direct crawler 与长期任务管道
│   ├── domain/                #   目标边界：opinions/authors/tickers/narratives/SV/target_prices 跨平台逻辑；smart_voice/ticker_signal_* 负责标的历史信号，indicator_backtest* 负责发现页四指标无泄漏回测、证据审计、细分报告和成功/失败案例集
│   ├── jobs/                  #   目标边界：完整任务编排（global_retail/ticker_detail/youtube_fulltext/SV）
│   ├── common/
│   │   ├── config.py          #   配置/环境变量（含 normalize_db_url：Supabase 串自动转 psycopg+SSL）
│   │   ├── db.py              #   SQLAlchemy 引擎/会话（sqlite 开发 / postgres 生产通用）
│   │   ├── models.py          #   ★数据模型 = schema 单一真源（14 张表）
│   │   ├── ticker_extraction.py #  基础 ticker 抽取（platform/domain 共用）
│   │   ├── llm.py             #   ★大模型「档位路由」：LOW/MID/HIGH → 具体 provider
│   │   ├── qwen.py            #   通义千问（HIGH：逐帖打标，思考模式）
│   │   ├── deepseek.py        #   DeepSeek（MID：叙事/简报；LOW：翻译）
│   │   └── claude.py / reddit.py
│   ├── ingest/                #   旧抓取兼容区；只保留 wrapper，新增实现不要继续放这里
│   │   ├── arctic_scrape.py   #   兼容 wrapper；实际实现见 platforms/reddit/arctic.py
│   │   ├── reddit_ingest.py   #   兼容 wrapper；实际实现见 platforms/reddit/realtime.py
│   │   ├── author_crawl.py    #   兼容 wrapper；实际实现见 platforms/reddit/authors.py
│   │   ├── asia_crawl.py      #   兼容 wrapper；实际实现见 platforms/global_retail/asia_sources.py
│   │   ├── global_retail_crawl.py # 兼容 wrapper；实际实现见 platforms/global_retail/regional.py
│   │   ├── global_retail_xueqiu.py # 兼容 wrapper；实际实现见 platforms/global_retail/xueqiu_export.py
│   │   ├── toss.py             # 兼容 wrapper；实际实现见 platforms/toss/community.py
│   │   ├── ticker_extract.py  #   兼容 wrapper；实际实现见 common/ticker_extraction.py
│   │   ├── seed_tickers.py    #   兼容 wrapper；实际实现见 domain/tickers/seeding.py
│   │   ├── price_daily.py     #   兼容 wrapper；实际实现见 platforms/market_data/short_window_prices.py
│   │   ├── x_pull.py          #   兼容 wrapper；实际实现见 platforms/x/cloud_pull.py
│   │   ├── load_complete_x_ticker_universe.py # 兼容 wrapper；实际实现见 platforms/x/complete_universe.py
│   │   ├── author_avatars.py  #   兼容 wrapper；实际实现见 platforms/author_assets/avatars.py
│   │   └── twitter_match.py   #   兼容 wrapper；实际实现见 platforms/x/ticker_match.py
│   ├── analyze/              #   分析 + 聚合
│   │   ├── item_analyze.py    #   ★逐帖 AI 打标（analyze_qwen 是全站分析大脑；增量，跳过已分析）
│   │   ├── rollups.py         #   声量/情绪聚合（mindshare 归一化）
│   │   ├── market_mood.py     #   市场情绪（恐惧贪婪）
│   │   ├── trending.py        #   异动（z-score / spike）
│   │   ├── narratives.py      #   叙事聚类（deepseek 语义聚类，失败回退主题分组）
│   │   ├── brief.py           #   每日简报（deepseek 润色）
│   │   ├── global_retail_tag.py    # ★全球散户：DeepSeek flash 全量打标 gr_post(sentiment+派生 stance，不用千问)
│   │   ├── global_retail_rollup.py # ★全球散户：跨区滚动 gr_ticker_region(US 读现有 Reddit) + 派生共识/分歧 gr_ticker
│   │   ├── kol_refine.py       #   ★KOL 个体观点 AI 提炼+双语：reddit/x/雪球/Toss/Yahoo JP 每标的每源 top-N → DeepSeek flash → kol_refined(stance+reason+points, zh/en；提炼与翻译合一)
│   │   ├── kol_viewpoint.py    #   ★KOL 观点 视角分类：对已蒸馏观点(kol_refined+yt_analysis) → DeepSeek flash 打 7 视角(1-3 个,首个为主) → kol_viewpoint
│   │   ├── kol_judgment.py     #   ★KOL 目标价+操作周期 抽取：reddit/x/雪球/Toss/Yahoo JP 原帖**只抽明说**的 买入/卖出/目标价(现价锚点剔噪)+周期 → kol_judgment(独立表，复用 kol_refine._load 候选池)；YouTube 复用 yt_judgment
│   │   ├── tweet_sentiment.py  #   ★X 推文情绪打分：tw_tweet_topic 命中推文 flash 批量 -1..1 → **云端** tw_tweet_sentiment（供每日净情绪）
│   │   ├── kol_sentiment.py    #   ★KOL 每日净情绪 rollup：跨平台 情绪×ln(1+互动)×相关性 加权净值 → 本地 kol_sentiment_daily（混合读本地三源+云端 X）
│   │   ├── retail_sentiment.py #   ★整体散户 每日净情绪 rollup：全量散户+本土论坛(Naver/YahooJP/PTT/Toss)、不含 YouTube → 本地 retail_sentiment_daily（X 走 tw_tweet_ticker⋈tw_tweet_sentiment）
│   │   ├── retail_volume.py    #   ★整体散户 每日讨论度 rollup：同口径计数 → 本地 retail_volume_daily
│   │   ├── retail_newcomers.py #   ★整体散户 每日新增散户 rollup：各平台首次参与该标的讨论的去重作者数(Reddit 发帖+评论 / 5 论坛；不含 X/YouTube) → 本地 retail_newcomers_daily
│   │   ├── kol_newcomers.py    #   ★KOL 每日新增 KOL rollup：X(x_opinion)/YouTube(yt_video)/雪球(gr_post) 首次讨论该标的的去重作者数 → 本地 kol_newcomers_daily
│   │   ├── overall_signals.py  #   ★整体数据『异动归因 + 聪明钱↔散户分歧』(仅 KOL，qwen-flash) → 构建期 JSON web/lib/data/overallData.json（读本地 daily 序列 + retail_sentiment_daily + /tmp/<ticker>_x6m.jsonl + /tmp/mt_* 技能缓存；_skill_map 复刻 gen_topinvestors 的 z。讨论方面/新叙事 2026-06-28 已下线）
│   │   ├── narrative_rotation.py # ★叙事轮动：固定板块 taxonomy、跨社区内容归类 → 构建期 JSON web/lib/data/narrativeRotation.json（排名变化/讨论占比/情绪变化；不读旧 narratives 表）
│   │   └── translate.py       #   翻译成中文 *_zh 列（增量、幂等；走 SQLAlchemy/DATABASE_URL，云端本地通用）
│   └── data/                  #   随仓库的字典/样本（ticker_stoplist.txt, cn_hk_tickers.json, subreddits.yml, global_targets.yml…）
│
├── web/                       # ③ Next.js 14 静态站
│   ├── app/
│   │   ├── layout.tsx         #   根布局（主题防闪烁 + 默认 OG/metadataBase）
│   │   ├── [lang]/            #   语言段（zh|en|ja|ko）：generateStaticParams（页面数 = locales × 各内页）
│   │   │   #   layout.tsx 仅 LocaleProvider；(app)/ = 侧栏壳(Sidebar/MobileTabBar)，(marketing)/ = 无侧栏落地页壳
│   │   │   ├── dashboard/     #     ★总览看板路由（取数后交给 features/dashboard；单视窗三栏、模块内滚动、专用骨架屏）
│   │   │   ├── narratives/ + narratives/[slug]/ # ★叙事轮动总览 + 详情（构建期 narrativeRotation.json；固定板块、跨社区、暂不展示原帖）
│   │   │   ├── tickers/ + tickers/[symbol]/   # 标的总览(可排序表 + 上方 **三个 KOL 排行榜** `KolRankBoards`：看多/看空=`getKolBullBearBoards`(kol_sentiment_daily 近14天 net 跨标的聚合、scope gr_ticker、top/bottom 5)、**情绪变化最大**=`getKolSentimentSwings`(同窗口劈前7/后7天，比**看多占比** n_bull/(bull+bear) 的 pp 变化、按 |Δ| top5；用占比非 net 以免被大票声量主导)) + 标的详情(★模块看板:个体观点·KOL[真实] + 异动/跨区视角/独有叙事/多空共识/风险温度/大家在等什么 — mock,多图表；海外信息差/最强反方/独立 YouTube 观点 模块已删)
│   │   │   ├── regions/ + regions/[region]/   # 区域总览(5 区卡+净情绪) + 区域详情(★模块看板:地区脉搏/热榜/异动/独有叙事/本区vs全球/性格画像/注意力轮动/今日引爆 — mock,多图表)
│   │   │   ├── search/        #     搜索（客户端 ticker/公司名模糊匹配）
│   │   │   ├── me(Profile) account(设置) login/ signup/ forgot-password/ reset-password/ auth/callback/  # 账号系统
│   │   │   ├── onboarding/    #     ★首登引导向导（沉浸式全屏；采集投资画像→写 user_profiles+自动追踪持仓；?edit=1 从设置复用）
│   │   │   ├── status(routine 运维)
│   │   ├── sitemap.ts / robots.ts / not-found.tsx   # SEO + 404
│   │   └── icon.png           #   favicon
│   ├── lib/
│   │   ├── db.ts              #   ★构建期用 node:sqlite 读 ../data/dev.db；库缺失/查询失败→降级空（不崩 output:export）
│   │   ├── queries.ts         #   ★所有取数 SQL（getMindshare/getTrending/getPostDetail…）
│   │   ├── globalQueries.ts    #   全球散户正式页面取数（读 gr_* 表 + US 代表帖读现有 Reddit；try/catch 兜底）
│   │   ├── investorQueries.ts   #   投资者榜单取数（getInvestorBoard：X/YouTube/Reddit/雪球 各按作者聚合互动·播放→排名；缺表返回空）
│   │   ├── creatorQueries.ts    #   YouTube 作者页取数（getYoutubeCreator：单频道 ①标的判断 tickerJudgments[yt_analysis 立场/观点/论据/目标价 ⋈ price_daily 当时价→现在价+命中,含中性,按标的归组]/②代表性标的/③互动最高视频；getYoutubeChannelIds 供 generateStaticParams）
│   │   ├── smartVoiceInvestorQueries.ts # SV 作者详情证据取数（sv_call + sv_call_settlement + sv_call_candidate，展示加分/扣分代表性 call）
│   │   ├── i18n.ts + dictionaries/{zh,en,ja,ko}.ts # 多语（zh 为源，en/ja/ko 必须镜像同样的 key；UI 译，帖子内容 ja/ko 回退英文原文）
│   │   ├── supabase.ts / auth.ts / admin.ts    # Supabase 客户端 + 登录 + 管理员判定
│   │   ├── analytics.ts        # 埋点（写 Supabase）
│   │   ├── favorites.ts                         # ★账户收藏/追踪：客户端读写 user_collections（RLS）
│   │   ├── profile.ts                           # ★用户投资画像：客户端读写 user_profiles（RLS）+ markOnboarded/isOnboarded（门禁标志走 user_metadata）
│   │   ├── instruments.ts                       # onboarding 持仓选择器的「广义标的」补集（ETF/杠杆反向/商品/加密/债券；个股来自 gr_ticker）
│   │   └── site.ts            #   SITE_URL（https://www.redditalpha.xyz）+ OG
│   ├── features/              #   目标边界：按业务域组织 dashboard/ticker/narrative/investor/region/search/tracking/SV；dashboard 承接总览纯视图模型、单视窗三栏工作台；ticker 承接详情页头、Overview/KolModule、价格/Top-Bottom SV 聚集与回测，以及高低分歧/周期结构/加速反转/目标失效诊断；smart-voice 承接跨页 SV 展示模块、工作台和作者详情；其余 feature 各自承接页面业务
│   ├── shared/                #   目标边界：跨业务 UI/layout/charts/icons/formatting/i18n/market；已承接 KOL 平台/立场/头像/原文译文、TickerLogo、PriceSparkline、ViewportWorkspace、Bits/DetailBits 展示基础件
│   ├── server/                #   目标边界：构建期 DB/query 边界（迁移期 lib/db.ts 与 *Queries.ts 继续可用）
│   ├── components/            #   迁移期旧 UI 组件（Sidebar/FeedCard/MarkdownLite…；复杂新逻辑不要继续堆入）
│   ├── next.config.mjs        #   output:export(仅生产) + cpus:1 串行导出 + images:unoptimized
│   └── public/               #   logo/og/avatars/communities（图片已压缩）
│
├── supabase/migrations/       # ② Supabase SQL 迁移（ticker_searches / analytics / user_collections / user_profiles 的表+RLS+RPC）
├── data/dev.db                # 本地 SQLite —— **Prismo 唯一真源**（gitignore，不进入 Git/Docker context）
├── data/dev.db.xz             # 小于等于 90MB 时的单文件部署快照（二选一）
├── data/dev.db.xz.part-*      # 大于 90MB 时的普通 Git 分片快照（二选一）
├── data/dev.db.xz.parts       # 分片 manifest；存在时 Docker 启用分片还原
├── data/dev.db.snapshot.json  # 快照时间、体积、SHA-256 与文件清单
├── Makefile                   # ★所有常用命令入口
├── .env / .env.example        # 凭据与配置（.env gitignore：QWEN/DEEPSEEK/DATABASE_URL…）
├── docs/architecture/         # 架构专题文档（前端、管线、数据、平台、SV、部署、约定）
├── docs/contracts/            # 跨平台产品契约（Opinion/Author/Ticker/Judgment/SV/Narrative）
└── 文档：README / DEPLOY / CLOUD_DB / SUPABASE_AUTH / STRATEGY / ARCHITECTURE(本文)
```

---

## 5. 数据库 schema（14 主表 + 4 亚洲 + 3 全球散户 + 3 YouTube + 1 KOL 提炼 隔离表，`pipeline/common/models.py` 为单一真源；另有**仓库外加载**的 X `tw_*`，见表末行）

| 类别 | 表 | 说明 |
|---|---|---|
| 原始 | `subreddits` `authors` `posts` `comments` | 抓来的原始内容（含 `*_zh` 译文列、`market`；`posts.source` scan/author 区分实时舆情/作者库，`authors.crawled_at` 作者库增量标记） |
| 字典/抽取 | `ticker_meta` `mentions` | ticker 字典 + 帖子↔ticker 提及（含 confidence/method） |
| AI 分析 | `item_analysis` | ★逐帖打标结果（情绪/多空/质量/主题/双语摘要/per-ticker 论据），按 item_id 持久化；真实分析按 `ITEM_ANALYSIS_PROVIDERS` 在 Claude/Qwen/Gemini 间回退并记录实际成功模型，全部失败时保留待处理，不写 mock 冒充真实结果 |
| 派生聚合 | `ticker_rollup` `market_mood` `trending` | 声量榜 / 市场情绪 / 异动（每次全量重算，可弃） |
| 叙事/简报 | `narratives` `narrative_tickers` `narrative_posts` `daily_briefs` | 主导叙事 + 每日简报 |
| 叙事轮动(构建期 JSON) | `web/lib/data/narrativeRotation.json` | **新 `/narratives` 页面数据源**：固定板块 taxonomy 的跨社区叙事轮动；由 `make narrative-rotation` 从 `gr_post`、Reddit、X、YouTube 聚合生成，记录每日 rank/share/sentiment 与详情来源/地区/标的分布；**不使用旧 Reddit-only `narratives` 表**，不把财报/政策/估值等事件项作为板块 |
| Smart Voice 指标回测(本地派生) | `sv_investor_score_asof` `sv_indicator_signal_daily` `sv_indicator_event` `sv_indicator_outcome` `sv_indicator_stat` | 历史时点平台正式池 SV/排名 → 发现页四类指标的 1/3/7/30/90D 滚动信号 → 连续同向事件 → 下一交易日开盘后的 1/5/20/60/90D 调整价方向收益、相对 SPY 超额、胜率、Wilson 区间、盈亏比和利润因子；`make sv-indicator-backtest` 全量重建，`make sv-indicator-report` 另导出逐事件、逐原文证据、成本/时间/标的/强度/质量/不重叠持仓细分 CSV 及 40 例原帖证据案例集 |
| 全球散户(隔离) | `gr_post` `gr_ticker_region` `gr_ticker` | 日韩台+中国大陆(雪球)爬精选跨区美股的散户帖(flash 打标 sentiment+stance) + 每 region×ticker 滚动(region `us`/`cn`/`jp`/`kr`/`tw`；**US 不入 gr_post，rollup 只读现有 Reddit**；CN 经浏览器过 WAF 导入) + 每 ticker 跨区派生(共识/分歧)。与 us/cn 主表隔离，供正式页面读取 |
| YouTube 观点(隔离) | `yt_video` `yt_analysis` `yt_ticker_summary` | 按标的近 24h、浏览量>1000 的**全语种**财经视频(YouTube Data API)→ Gemini **混合分析**(top N 原生看视频[画面+音频] + 其余优先读取 `yt_fulltext` 完整口播/在线字幕，再回退低清原生视频)出 stance/sentiment/双语摘要 → 每标的浏览量加权汇总。**两条分析路径**：① `youtube-tag` Gemini 视频/口播分析，支持 `--since-days`、`--min-subscribers`、`--min-duration-seconds` 精确限制产品候选，`--workers>1` 走并发付费模式；幂等判定同时校验 `yt_analysis.ticker == yt_video.ticker`，同一视频被新 ticker 搜索命中后会自动重分析；② `youtube-tag-text` **无配额兜底**：用**标题+简介**跑 LOW 档出双语观点(mode=`text`)，覆盖 Gemini 没看的长尾、**不占 `analyzed` 旗标**→ 日后 Gemini 仍能升级覆盖。**纳入站外当地分析者**(韩 슈퍼개미/日 testa/美 FinTube)。YouTube 数据经 `kolQueries.youtubeOps` 并入标的页**观点浏览器**(`OpinionExplorer`)；展示口径要求频道 `yt_channel.subscriber_count >= 2000` 且视频 `duration_s > 60`，目标价时间线、YouTube 相关性/质量候选、KOL 情绪/讨论度/新增 KOL 日序列都使用同一口径；详情阅读器按 channel_id 匹配 YouTube 作者 SV 并显示具体 SV 分数。**原独立『YouTube 观点』模块已移除**(与浏览器重复，删 `YouTubeOpinions.tsx`+`youtubeQueries.ts`)；缺 key 回退 mock |
| YouTube 完整口播(隔离) | `yt_fulltext` | 视频「完整口播」：Gemini 真看视频→**只还原口播**(不描述画面)成有序段落 `{type:speech, speaker, text}`：**按语义分段**(3-6 句/段) + **行内 Markdown 划重点**(`**加粗**`关键结论/数据/标的、`*斜体*`转折，克制)；**多人(访谈/播客)每段标 `speaker`、独白留空**；剔赞助订阅VIP二维码宣传。列 content_zh(扁平**纯文本**,去 Markdown)+segments(JSON 有序带 Markdown)。前端 `YtFullContent.tsx`(被 `YtReader.tsx` 包裹，见 `yt_digest` 行)：行内 Markdown 渲染(`inline`/`RichText`)；单人→限行宽分段长文、多人→按说话人分回合对话排版；传入 chapters 时在对应 speech 段前插**章节标题+锚点 `data-ch`**。`youtube-fulltext --only/--per-ticker/--force/--no-frames`。⚠ 旧档 `visual` 段(关键帧)代码休眠、新提示不产出(下载/OCR 配方备查见 memory `project-youtube-fulltext`) |
| YouTube 投资者摘要+目录(本地派生) | `yt_digest` | YouTube 正文阅读容器 `YtReader.tsx` 的两个新模块：① **投资者摘要**(`summary_zh/en`：整段口播精华/话题 AI 提成 4-7 分点，放正文上方)；② **内容目录**(`chapters`=有序章节 `{t_zh,t_en,seg}`，seg=起始 **speech 段下标**→`YtFullContent` 据此埋 `data-ch` 锚点 + 章节标题；右侧目录点击→正文平滑滚到该段、折叠时先自动展开)。③ **正文默认折叠到 ~72vh(约一屏)**、`展开更多`/`收起`。`youtube_digest.py`/`make youtube-digest` 读 `yt_fulltext` 口播文本跑 **LOW 档(qwen-flash，不重看视频)**，校验 seg 单调/夹紧；增量、原生 DDL 不入 models.py、写本地；web `ytDigestMap`(kolQueries)→YtReader。需 `QWEN_API_KEY` |
| YouTube 判断参数(本地派生) | `yt_judgment` | 作者页「① 标的判断」每条判断的结构化 chip：从**已有** `yt_analysis`(summary+key_points+price_target)抽 `horizon_zh/en`(时间周期)·`target`(目标价，规整成 `$X`/`$X–Y`)·`key_levels_zh/en`(关键位置=支撑/阻力/突破位/形态/均线)。`youtube_judgment.py`/`make youtube-judgment` 跑 **LOW 档(qwen-flash，纯文本不重看视频)**，**只抽明说、缺则 null**(776 条 ~105 有值、target 69>price_target 60)；增量、裸 sqlite3 写本地、不入 models.py(同 `yt_digest` 范式)；web creatorQueries `safe` LEFT JOIN(表缺失不影响)、目标价结构化优先于原始 `price_target`。需 `QWEN_API_KEY` |
| YouTube 作者×标的综合(本地派生) | `yt_creator_view` | 作者页「① 标的判断」**每标的综合**：把**同一博主对同一标的**的多条视频判断(已蒸馏 summary+key_points+stance)综合成 `stance`(整体立场)+`points_zh/en`(**3-5 条关键判断**，合并去重)。PK=(channel_id,ticker)。`youtube_creator_view.py`/`make youtube-creator-view` 跑 **LOW 档(qwen-flash，读已蒸馏文本不重看视频)**，**忠实综合不臆造**；增量、裸 sqlite3 写本地、不入 models.py(同 `yt_digest`/`yt_judgment` 范式)；web creatorQueries `safe` 按 channel 查、缺则回退最新一条判断的 key_points。让作者页每标的只显示一段综合而非铺开每条视频(原太繁杂)。635 对 0 失败。需 `QWEN_API_KEY` |
| KOL 提炼(隔离) | `kol_refined` | ★个体观点「AI 提炼+双语」：对 reddit/x/雪球/Toss/Yahoo JP 每标的每源 top-N 按 Qwen LOW → DeepSeek low → Gemini 兜底（`KOL_REFINE_PROVIDERS` 可改顺序）→ stance + **reason_zh·en**(为什么看多/看空) + **points_zh·en**(2-3 要点)，**提炼与翻译合一**(只 zh/en，ja/ko 前端回退 en)。PK source+item_id；实现 `pipeline/domain/opinions/kol_refine.py`，命令 `make kol-refine`(增量、`--per-source`/`--only`/`--force`)。**标的页象限①「个体观点·KOL」** 用之替换照搬原文；YouTube 不入此表(复用 `yt_analysis`) |
| KOL 目标价+周期(隔离) | `kol_judgment` | ★个体观点的『目标价 + 操作周期』结构化抽取：对 reddit/x/雪球/Toss/Yahoo JP 每标的每源 top-N 跑 **LOW(qwen-flash)** 从**原帖**抽 `buy_price`/`sell_price`/`target_price`(各 nullable、区间取中点、原文留 `price_raw`) + `horizon_zh/en`(原话) + `horizon_bucket`(short/mid/long)。**只抽明说、反臆造**：prompt 喂**当前价锚点**(`_price_map`)剔数量级离谱者 + 拒 penny-pump/假设估值/相对幅度。PK 同 kol_refined (source,item_id,ticker)；实现 `pipeline/domain/target_prices/kol_judgment.py`(复用 `kol_refine._load`)，命令 `make kol-judgment`(增量、`--only`/`--force`)。**标的页『整体数据』散点(`TargetPricePanel`) + 『观点检索』正文提炼行** 用之；YouTube 不入此表(复用 `yt_judgment`)；web `kolQueries.judgmentMap` 再按现价 **0.2–5× band 二次剔噪**($1225 这类砍掉)。需 `QWEN_API_KEY` |
| KOL 视角分类(隔离) | `kol_viewpoint` | ★把已蒸馏观点(kol_refined + yt_analysis)用 DeepSeek(flash) 分到 **7 视角**(估值/业务成长/竞争/管理层/宏观/催化剂/资金盘面，1-3 个、首个为主、纯方向性/情绪→other)。PK 同 kol_refined (source,item_id,ticker)；实现 `pipeline/domain/opinions/kol_viewpoint.py`，命令 `make kol-viewpoint`(增量、无明确观点预判 other 省调用)。供**标的页观点流的「视角」分类**，web 经 `kolQueries.viewpointMap` 挂到观点上 |
| KOL 每日净情绪(本地派生) | `kol_sentiment_daily` | ★折线图下方绿/红面积子面板的数据。每 (ticker,day) 跨平台把『提到该标的的帖子』按 **情绪 × ln(1+互动) × 相关性** 加权求和 = **无界净情绪 net**(>0 偏多/绿，<0 偏空/红，量纲随声量×情绪放大，Kaito 风)。源：本地 Reddit(`item_analysis.sentiment_score`)/雪球(`gr_post.sentiment`)/YouTube(`yt_analysis.sentiment`) + **云端 X**(`tw_tweet_topic`⋈`tw_tweet`⋈`tw_tweet_sentiment`，relevance 用关键词命中 `strong` 代理)；YouTube 只计入频道粉丝 ≥2000 且时长 >60 秒的视频。`kol_sentiment.py`/`make kol-sentiment`(整表重算；**原生 DDL 自建、不入 models.py**；混合读本地+云端、勿加 sqlite 覆盖)。⚠ `vertical_topic_metadata.json` 漏掉 NVDA/TSLA/AAPL/MSFT → 这些大票暂无 X 贡献。**⚠ `tw_tweet` 现已空 0 行** → `tw_tweet_topic⋈tw_tweet` 现返 0、net_x 是陈旧快照；散户版 `retail_sentiment` 已改走稳定的 `tw_tweet_ticker⋈tw_tweet_sentiment`，KOL 版待同样迁移 |
| KOL 每日讨论度(本地派生) | `kol_volume_daily` | ★『每日讨论度』堆叠条状子面板的数据。每 (ticker,day) 跨平台**计数**当天讨论该标的的帖子+视频：n_reddit(mentions⋈posts 去重)/n_xueqiu(gr_post)/n_youtube(yt_video，频道粉丝 ≥2000 且时长 >60 秒) + **n_x = 本地 `x_opinion`**；可选用云端 `tw_tweet_ticker` 补充（设置 `KOL_VOLUME_CLOUD_X=1`，按 `(tweet_id,ticker)` 去重，云端侧仍**不 join `tw_tweet`**）。n_total=四者和。`kol_volume.py`/`make kol-volume`(整表重算；原生 DDL、不入 models.py；默认本地、勿加 sqlite 覆盖) |
| 整体散户 每日净情绪(本地派生) | `retail_sentiment_daily` | ★KOL 模块切到「整体散户」时的绿/红面积数据。与 KOL 同形状(net + net_<平台>)，**人群口径=全量散户**、平台=X/Reddit/雪球/**Naver/YahooJP/PTT/Toss**(本土论坛)、**不含 YouTube**。加权 net += 情绪×相关性×**(1+ln(1+互动))**——`(1+…)` 基座让无互动数据的源(Yahoo JP 引擎不给赞/评)仍按「一帖一票」计入。**X 走稳定的 `tw_tweet_ticker`⋈`tw_tweet_sentiment`**（⚠ `tw_tweet` 现已空 0 行→KOL 版 net_x 已陈旧；散户版改用稳定链接表、代价是无逐帖互动→权重退化为基座 1.0）。`retail_sentiment.py`/`make retail-sentiment`(整表重算；原生 DDL、不入 models.py；混合本地+云端、勿加 sqlite 覆盖) |
| 整体散户 每日讨论度(本地派生) | `retail_volume_daily` | ★「整体散户」视图的堆叠条状数据。每 (ticker,day) 同口径**计数**：n_reddit/n_xueqiu/n_naver/n_yahoojp/n_ptt/n_toss(gr_post 按 source) + **n_x = 直接数 `tw_tweet_ticker`**，n_total=各平台和。`retail_volume.py`/`make retail-volume`(整表重算；原生 DDL、不入 models.py) |
| 整体散户 每日新增散户(本地派生) | `retail_newcomers_daily` | ★「整体散户」视图第三块『每日新增散户』堆叠条状。每 (ticker,day) 计**首次参与该标的讨论的去重作者数**(用户对该平台×标的最早出现日计 1)：n_reddit(posts⋈mentions + comments⋈父帖 mentions)/n_xueqiu/n_naver/n_yahoojp/n_ptt/n_toss(gr_post 按 source)，n_total=各平台和。**不含 X**(云端 `tw_tweet_ticker` 无作者列)/**YouTube**(创作者非散户)。`retail_newcomers.py`/`make retail-newcomers`(纯本地、整表重算；原生 DDL、不入 models.py)。⚠ "数据集内首次"在数据窗起点偏高(Toss 仅 06-14 起) |
| KOL 每日新增 KOL(本地派生) | `kol_newcomers_daily` | ★「KOL」视图第三块『每日新增 KOL』堆叠条状。每 (ticker,day) 计**首次讨论该标的的去重作者数**，平台=**有身份/粉丝象征的 X / YouTube / 雪球**(不含 Reddit/匿名源)：n_x(`x_opinion` 按 handle)/n_youtube(`yt_video` 按 channel_id，频道粉丝 ≥2000 且时长 >60 秒的视频首次出现)/n_xueqiu(`gr_post` 按 author)，n_total=三者和。**X 用本地 `x_opinion`**(含作者)而非散户版云端 tw_tweet_ticker。`kol_newcomers.py`/`make kol-newcomers`(纯本地、整表重算；原生 DDL、不入 models.py) |
| YouTube 频道作者(本地) | `yt_channel` | YouTube 正文(OpinionExplorer 阅读面板)作者头像旁的**基础信息**：`subscriber_count`(粉丝)/`video_count`(视频)/`description`(简介)/`handle`(@)。`platforms/youtube/channels.py`/`make yt-channels` 用 **Data API `channels.list`**(part=snippet,statistics) 按 `yt_video.channel_id` 全集刷新(~540 频道/11 次调用、1 配额/次)；直接写本地(同 author_avatar)、不入 models.py；web `ytChannelMap`(kolQueries)→Reader。需 `YOUTUBE_API_KEY` |
| **X/Twitter(隔离·外部加载)** | `tw_tweet`(58万) `tw_kol` `tw_tweet_ticker` `tw_crawl_state` `tw_tweet_sentiment`(空) `tw_ticker_rollup`(空) + `tw_tweet_topic` | KOL 推文由**仓库外工具**灌入云端(14 天 bootstrap，**尚未打情绪/未聚合**)，**均不在 `models.py`**。`tw_tweet_topic` = `platforms/x/ticker_match.py` 的**关键词硬匹配**派生(无 AI；按 `vertical_topic_metadata.json` 每 topic 的 keyword_list 混合匹配 $cashtag/@handle/短语/单词，sigil 敏感+Unicode 分词)→ 仅留 **Stocks** vertical 并清掉「普通词」误报(Bullish→BLSH 等)；约 8.6 万 (推文,标的) 对 |

> 迁移只搬「原始+字典+AI 分析」这 7 张源表（贵、需长期保存）；派生表在云端用 `make rollup` 等重算。
> 全球散户 3 表 + YouTube 3 表都在 `ALL_TABLES`（`cloud-pull` 会快照），但**不在** `sync.SOURCE_TABLES`；`make gr` / `make youtube` 写当前 `DATABASE_URL`（本地验证用 `DATABASE_URL='sqlite:///./data/dev.db'` 覆盖，勿对云端跑建表 DDL）。
> **X 的 `tw_*` 不同**：由仓库外工具直接写云端，**不在 `models.py`/`ALL_TABLES`**（故 `cloud-pull` 不快照、网站构建也不读）；`tw_tweet_topic` 由 X 平台适配器用原生 DDL 自建。重跑匹配：`make tw-match` 或 `pipeline/.venv/bin/python -m pipeline.manage tw-match`（整表重算，幂等）。

---

## 6. 大模型档位（`pipeline/common/llm.py` 为路由真源）

| 档位 | 用途 | 当前 provider |
|---|---|---|
| **HIGH** | 逐帖投资打标（思考模式，全站分析大脑，token 大头） | 通义千问 `qwen3.7-plus` |
| **MID** | 叙事聚类 / 每日简报 / 正文重排版 | DeepSeek `deepseek-v4-pro` |
| **LOW** | 翻译 + KOL 提炼/视角/论点综合（走量） | 通义千问 `qwen-flash`（原 DeepSeek flash；2026-06 DeepSeek 余额耗尽 → 切千问，`QWEN_MODEL_LOW` 可改回）。**故 KOL 三步现需 `QWEN_API_KEY`，非 DeepSeek** |
| **GEMINI** | YouTube 视频理解(画面+音频) + 字幕文本总结；KOL/逐帖分析 fallback；也可承接统一档位文本任务 | Gemini（`common/gemini.py`；设置 `LLM_PROVIDER=gemini` 时 LOW/MID/HIGH 显式切到 `GEMINI_MODEL`） |

默认 LOW/MID/HIGH 仍按 `llm.py` 路由表运行；可用 `LLM_PROVIDER=qwen|deepseek|gemini` 对一次任务显式切换 provider，`model` 字段记录实际选择。YouTube 视频理解及带独立 fallback 的批任务仍可直接调用 `common/gemini.py`。真实逐帖分析全部 provider 失败时保留待处理，不静默写 mock。

---

## 7. 常用命令（Makefile）

| 命令 | 作用 |
|---|---|
| `make daily` | 分析过去 24h（抓取+AI 打标+聚合+翻译），直接写 `DATABASE_URL`（云端）；含作者库爬取 |
| `make crawl-authors` | 单独跑作者库：爬实力榜 Top 作者历史帖（DeepSeek 粗筛→千问深析）。需 DeepSeek key |
| `make analyze-qwen` | 真实千问逐帖打标 + 重算聚合 |
| `make gr` | 全球散户五地区数据：日韩台爬精选跨区美股 + DeepSeek flash 打标 + 跨区滚动(US 读现有 Reddit)。CN(雪球)走 `gr-xueqiu`(收浏览器过 WAF 的导出 JSON) |
| `make toss` | Toss(토스증권) 종목 커뮤니티评论爬取 → `gr_post(source='toss',region='kr')` + `gr-tag` 打标。逆向 Web API `wts-cert-api.tossinvest.com/api/v4/comments`(subjectType=STOCK&subjectId={code}&commentSortType=RECENT，**无需登录**、游标 `lastCommentId` 翻页、每页 11 条)；标的映射 `platforms/toss/community.py` 的 `TOSS_STOCKS`(MU=US19890516001，PLTR=US20200930014)。`--days/--only/--resume/--max-pages/--sleep/--commit-pages`；`--resume` 会基于本地已有最新/最旧游标补新+补旧，达到页数上限但未触达截止日时会明确提示。**本地跑须 `DATABASE_URL='sqlite:///./data/dev.db'`**。落库后跑 `gr-tag`、`retail-sentiment`/`retail-volume`/`retail-newcomers`，以及需要观点抽取时的 `kol-refine`/`kol-relevance`/`kol-quality`/`kol-judgment`。出站 `make site` |
| `make youtube` | YouTube 观点：按标的搜近 24h、浏览量>1000 的全语种视频(`youtube-crawl`) + Gemini 混合分析(`youtube-tag`：top N 原生看视频，其余优先复用完整口播/字幕)→ 标的页观点流。需 `YOUTUBE_API_KEY`+`GEMINI_API_KEY`；`youtube-tag --since-days N --min-subscribers 2000 --min-duration-seconds 60 --workers 8` 可按产品门槛完整补跑，`--transcript-only` 只处理已有 `yt_fulltext` 且不回退原生视频；**无配额兜底**：`youtube-tag-text`(标题+简介→LOW 档双语，mode=text)，同样支持 `--only/--since-days/--min-subscribers/--min-duration-seconds` 精确补缺 |
| `make yt-channels` | YouTube 频道作者基础信息(粉丝数/视频数/个人简介/@handle) → 本地 `yt_channel`(供 YouTube 正文作者头像旁展示)。Data API `channels.list`(part=snippet,statistics)；需 `YOUTUBE_API_KEY`。整表刷新(~540 频道)。出站 `make site` |
| `make youtube-digest` | YouTube 完整口播 → 「投资者摘要」+「内容目录(章节)」→ 本地 `yt_digest`。读 `yt_fulltext` 口播文本跑 LOW 档(qwen-flash，不重看视频)；增量(`--force` 重跑、`--only` 指定 video_id)；需 `QWEN_API_KEY`。先跑 `youtube-fulltext`。出站 `make site` |
| `make youtube-judgment` | 作者页「① 标的判断」结构化参数：从 `yt_analysis` 观点/论据抽 时间周期/目标价/关键位置 → 本地 `yt_judgment`。LOW 档(qwen-flash，纯文本不重看视频)；增量(`--force` 重抽、`--only` 指定 ticker、`--workers`)；只抽明说不臆造、多为 null；需 `QWEN_API_KEY`。出站 `make site` |
| `make youtube-creator-view` | 作者页「① 标的判断」每标的综合：把同一博主对同一标的的多条视频判断综合成 整体立场+几点关键判断 → 本地 `yt_creator_view`。LOW 档(qwen-flash，读已蒸馏文本不重看视频)；增量(`--force`/`--only` ticker/`--workers`)；需 `QWEN_API_KEY`。出站 `make site` |
| `make kol-judgment` | KOL 目标价+操作周期：从 reddit/x/雪球/Toss/Yahoo JP **原帖**抽 买入/卖出/目标价(prompt 现价锚点剔噪)+周期 → 本地 `kol_judgment`。LOW(qwen-flash)；增量(`--only`/`--force`)；只抽明说、反臆造；先跑 `kol-refine`(复用其候选池)；需 `QWEN_API_KEY`。出站 `make site` |
| `make kol-refine` | KOL 个体观点提炼：reddit/x/雪球/Toss/Yahoo JP 每标的每源 top-N 按 Qwen LOW → DeepSeek low → Gemini 兜底（`KOL_REFINE_PROVIDERS` 可改顺序）→ `kol_refined`(为什么看多/看空 + 2-3 要点，zh/en)，并记录实际成功模型。标的页象限①「个体观点·KOL」展示提炼而非照搬原文。增量；`pipeline.manage kol-refine --per-source/--only/--source/--force`。需至少一个对应 provider key |
| `make kol-viewpoint` | KOL 观点视角分类：对已蒸馏观点(`kol_refined`+`yt_analysis`) 跑 LOW 档 → `kol_viewpoint`(7 视角 1-3 个)。供标的页 KOL 模块「按视角」视图。增量；先跑 `kol-refine`；支持 `--only/--source/--since-days/--force` 精确补跑 |
| `make tw-match` | X 推文 ↔ ticker/topic 硬匹配：重建云端 `tw_tweet_topic`，由 `pipeline.manage tw-match` 调用 X 平台适配器。整表重算，需 `DATABASE_URL` 指向 Supabase Postgres |
| `make tw-sentiment` | X 推文情绪打分：`tw_tweet_topic` 命中的 ~5.4 万推文 flash 批量打 -1..1 → **云端** `tw_tweet_sentiment`。⚠ 别加 sqlite 覆盖。增量。需 flash key。供 `kol-sentiment` |
| `make sv-price-history` | SV 结算所需日线价格回填：通过 `pipeline.manage sv-price-history` 写入 `price_daily`，默认从 `2025-06-01` 起，支持 `ONLY=MU,NVDA` 局部回填 |
| `make sv-v0 / sv-v0-prod` | Smart Voice v0：通过 `pipeline.manage sv-v0` 跑候选召回、LLM 结构化、价格结算、投资者评分和前端 JSON 导出；`sv-v0-prod` 使用作者均衡抽样。YouTube 候选、全文队列、抽取、结算和评分统一要求频道粉丝 `>=2000` 且视频时长 `>60s`，`--only`/`--youtube-since-days` 贯穿候选到抽取；Reddit 的 `--reddit-since-days` 同样贯穿候选与抽取，避免局部补跑吞入历史欠账；继续执行作者池、映射版本与完整口播证据门槛。结构化抽取默认 Qwen LOW → DeepSeek low → Gemini（`SV_EXTRACT_PROVIDERS` 可改顺序），记录实际成功模型 |
| `make sv-ticker-signals ONLY=MU,NVDA,MSTR` | 标的级 SV：历史时点作者百分位 → 7 日观点聚集 → 下一交易日开盘后的 1/5/20/60/90/180 日相对 SPY 回测；首批详情页只消费 MU/NVDA/MSTR |
| `make sv-indicator-backtest` | Smart Voice 发现页四指标：历史平台内正式 Top/Bottom 10% → 1/3/7/30/90D 加权净强度、作者净人数、人数突变和高低分歧 → 连续信号事件化 → 1/5/20/60/90D 胜率、盈亏比、利润因子及相对 SPY 超额；CSV 写 `data/reports/sv_indicator_backtest.csv` |
| `make sv-indicator-report` | 不重算信号，基于现有 `sv_indicator_*` 导出逐事件结果、逐 Call 原文/URL、紧凑证据、稳健性统计和四指标各 5 个成功/5 个失败的原帖证据案例集到 `data/reports/` |
| `pipeline.manage overall-signals --ticker MU` | 重算标的页整体数据的异常归因与聪明钱/散户分歧：归因优先读显式 JSONL、缺失时读本地 `x_opinion`；聪明钱线缺旧实验缓存时读取 `sv_call` 并按 call 当日 `sv_investor_score_asof` 前 10% 作者加权，避免前视；输出 `web/lib/data/overallData.json` |
| `make xueqiu-author-plan / xueqiu-author-auth / xueqiu-author-run / xueqiu-author-drain / xueqiu-author-status` | 雪球 SV 作者池：版本化候选池 → 用户登录授权 → 一年作者时间线断点回填（`drain` 为小批次冷却长跑）→ 状态统计；固定写本地 `data/dev.db` |
| `make xueqiu-sv-full` | 雪球 SV 完整长跑：自适应退避回填正式 300 人作者池 → 校验全部完成 → 扩展标的映射 → 候选召回 → 作者均衡 LLM 抽取 → 结算/评分/导出；作者池不完整则停止在评分前 |
| `make kol-sentiment` | KOL 每日净情绪 rollup：跨平台 情绪×ln(1+互动)×相关性 → 本地 `kol_sentiment_daily`(折线图下方绿/红面积)。⚠ **不加** sqlite 覆盖(脚本自 hardcode 本地+从 .env 读云端拿 X)。先跑 `tw-sentiment`。出站 `make site` |
| `make kol-volume` | KOL 每日讨论度 rollup：跨平台帖子/视频**计数** → 本地 `kol_volume_daily`(折线图下方条状图)。X 默认读本地 `x_opinion`；需要云端 `tw_tweet_ticker` 补充时设置 `KOL_VOLUME_CLOUD_X=1`，并按 `(tweet_id,ticker)` 去重。⚠ **不加** sqlite 覆盖。出站 `make site` |
| `make retail-sentiment` | 整体散户 每日净情绪 rollup → 本地 `retail_sentiment_daily`(KOL 模块切到「整体散户」时的绿/红面积)。全量散户+本土论坛(Naver/YahooJP/PTT/Toss)、不含 YouTube；X 走 `tw_tweet_ticker`⋈`tw_tweet_sentiment`。⚠ **不加** sqlite 覆盖。先跑 `tw-sentiment`。出站 `make site` |
| `make retail-volume` | 整体散户 每日讨论度 rollup → 本地 `retail_volume_daily`(「整体散户」视图的条状图)。同口径计数。⚠ **不加** sqlite 覆盖。出站 `make site` |
| `make retail-newcomers` | 整体散户 每日新增散户 rollup → 本地 `retail_newcomers_daily`(「整体散户」视图第三块条状图)。各平台首次参与该标的讨论的去重作者数(Reddit 发帖+评论 / 5 论坛；不含 X/YouTube)。**纯本地、无需云端**。出站 `make site` |
| `make kol-newcomers` | KOL 每日新增 KOL rollup → 本地 `kol_newcomers_daily`(「KOL」视图第三块条状图)。X(x_opinion)/YouTube(yt_video)/雪球(gr_post) 首次讨论该标的的去重作者数。**纯本地、无需云端**。出站 `make site` |
| `make overall-signals` | 整体数据『异动归因 + 聪明钱↔散户分歧』(仅 KOL，qwen-flash) → 构建期 JSON `web/lib/data/overallData.json`(异动金 ⚑ 标记+AI 归因 / 技能加权 KOL vs 散户分歧线)。读本地 daily + `retail_sentiment_daily` + `/tmp/<ticker>_x6m.jsonl` + `/tmp/mt_*` 技能缓存。`TICKER=XXX make overall-signals`(默认 PLTR)。需 `QWEN_API_KEY`。出站 `make site` |
| `make narrative-rotation` | 新叙事页数据：固定板块 taxonomy、跨社区内容归类 → 构建期 JSON `web/lib/data/narrativeRotation.json`；展示热度排名变化、讨论占比变化、情绪转向与叙事详情页来源/地区/标的分布。默认近 21 天，近 7 天作为当前窗口；不使用旧 `narratives` 表。出站 `make site` |
| `make kol-translate` | KOL 原帖**完整忠实翻译**(逐句、不压缩) → `kol_refined.trans_zh·en`。供观点浏览器卡片/阅读面板的「译」选项。只译已展示项、增量；同一 `source+item` 的翻译跨 ticker 复用，已有兄弟行直接回填，新内容只调用一次并写全部 ticker 行；与提炼解耦可独立重跑；`--source/--per-source/--since-days/--only/--force`。默认 provider 链为 Qwen LOW → DeepSeek low → Gemini，可用 `KOL_TRANSLATE_PROVIDERS=gemini` 等调整顺序；单一路失败会继续尝试后备，不会把原文伪装成译文。需对应 provider key。本地测试加 `DATABASE_URL=sqlite:///./data/dev.db` 直写 `dev.db` |
| `make kol-relevance` | KOL **相关性打分** 0-100(越高=越是在讲这只票，区分「深度分析」vs「顺带列入名单」) → 隔离表 `kol_relevance`(覆盖 reddit/x/雪球/Toss/Yahoo JP+youtube)。供观点浏览器默认『相关度降序』排序(不做筛选)。增量、可独立重跑；`--only/--force/--per-source/--no-youtube`。需 `QWEN_API_KEY`。本地测试同上 |
| `make kol-quality` | KOL **帖子质量打分** 0-100(内容含金量：实质分析/数据/逻辑 vs 口号/喊单/灌水；**与标的无关**，按 source+item 去重) → 隔离表 `kol_quality`。供观点浏览器『只看高质量』开关(≥65)。覆盖 reddit/x/雪球/Toss/Yahoo JP+youtube；增量；`--only/--force/--per-source/--no-youtube`。需 `QWEN_API_KEY` |
| `make rollup / mood / trending / narratives / brief` | 单独重算各聚合 |
| `make cloud-init` | 一次性迁移：建表 + 上传本地源数据 + 云端重算派生表 |
| `make cloud-push` | 把本地源数据增量上传到云端（redditalpha 用；Prismo 一般不需要） |
| `make cloud-pull` | ⛔ **默认拒绝**（会用「只有 Reddit 核心」的云端覆盖本地、抹掉 Prismo 独有的 gr_*/yt_*/kol_*）。确需重建：`make backup-db && FORCE=1 make cloud-pull` |
| `make backup-db` | 用 SQLite backup API 备份 `data/dev.db` 到项目外目录；默认只保留最近一份 |
| `make snapshot-db` | 校验并压缩本地真源，按 90MB 阈值生成单文件或 24MB 分片部署快照；不提交原始库 |
| `make restore-db FORCE=1` | 从仓库压缩快照还原本地 `data/dev.db` |
| `make data-clean` | 清项目内旧备份/抽帧缓存并 checkpoint WAL，不删除主库 |
| `make site` | 构建静态站 `web/out/`（读**本地 dev.db**；需 **Node 22**） |
| `make cf-deploy` | Cloudflare Pages Direct Upload：先 `make site`，再把 zh/en 产物复制到 `/tmp/prismo-out-cf` 并上传到 `prismo` 的 `main` production；可用 `PROJECT=xxx` 覆盖项目名 |
| `make site-cloud` | **现等同 `make site`**（Prismo 以本地为真源、不再 cloud-pull；保留名字防误清） |
| `make stats` | 打印库内统计 |
| `make demo` | 一键离线全流程（样本+mock，无需 key） |

---

## 8. 构建 & 部署

1. `nvm use 22`（**必须 Node 22**；Node 23 + 实验 SQLite 会让构建被系统 SIGKILL；仓库根目录有 `.node-version=22`）。
2. `make site`（读本地真源 `data/dev.db` + `next build` → `web/out/`，~6500 页、cpus:1 串行）。
3. 推荐发布到 Cloudflare Pages：首次 `npx wrangler login`，之后 `make cf-deploy`（可用 `PROJECT=xxx` 改 Pages 项目名）。
4. Railway/Dockerfile 仅作为旧路径保留；Cloudflare Pages 运行时只托管静态文件，不跑 `server.mjs`。

---

## 9. 重要约定 / 易踩坑

- **构建用 Node 22**（见上）。若构建报 `Cannot find module for page /_not-found`：先 `rm -rf web/.next web/out` 再构建（残留进程会锁住 .next）。
- **多语字典**：`dictionaries/zh.ts` 是源（`Dictionary = typeof zh`），`en.ts`/`ja.ts`/`ko.ts` 必须镜像完全相同的 key（`npx tsc --noEmit` 会强校验）。新增 locale 只需在 `i18n.ts` 的 `locales`/`isLocale`/`DICTS` 三处登记 + 加 `LanguageSwitcher` 选项；路由/sitemap 自动随 `locales` 扩展。帖子内容只有 `*_zh` 译文，故 ja/ko 渲染时回退英文原文。
- **密钥不入库**：`.env` / `web/.env.local` 已 gitignore；含 `QWEN_API_KEY`/`DEEPSEEK_API_KEY`/`DATABASE_URL`(含密码)/Supabase anon key 等，切勿提交或泄露。
- **回到纯本地**：`.env` 的 `DATABASE_URL` 改回 `sqlite:///./data/dev.db` 即可。
- **管线所有步骤必须走 SQLAlchemy（`common/db.py` 的 engine），不要裸 `sqlite3.connect`**：否则 `DATABASE_URL` 指向云端时会把结果写进本地文件、云端拿不到。`translate.py` 曾因此漏译，现已修复并继续作为 Reddit 中文补译链路使用。
- **待办（省 token）**：千问/DeepSeek 的系统提示词每次逐帖重发，未确认是否走缓存计费；可启用上下文缓存。
