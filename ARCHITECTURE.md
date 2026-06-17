# 项目架构与结构（ARCHITECTURE）

> **维护约定**：本文件是项目的「活地图」。**每次对项目结构或功能有实质改动后，必须同步更新本文件对应章节**
> （新增/删除模块、改数据流、改命令、改部署方式、改 schema 等）。详见根目录 `CLAUDE.md`。
> 最近更新：2026-06-16。

---

## 1. 这是什么

**redditalpha** —— 一个多语（中文默认 / English / 日本語 / 한국어）的 **Reddit 美股 + 中概股舆情情报看板**。
抓取 Reddit 财经社区的真实帖子，用大模型逐帖做投资打标（情绪 / 多空 / 质量 / 主题 / 双语摘要 /
按标的归属的多空论据），再聚合成声量榜、情绪、异动、主导叙事、每日简报，最终渲染成一个**纯静态网站**。

- 线上地址：**https://www.redditalpha.xyz**（根域名，静态托管）
- 两个市场（market）：`us`（美股）、`cn`（中概股 + 港股 + A 股），互不污染，各出一套聚合。

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
- **网站后端**（独立小表，RLS 保护）：`app_events`（埋点）、`ticker_searches`（搜索榜）、`user_collections`（账户收藏/追踪，仅本人可读写）、Auth（登录）。
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
CLI `gr-crawl/gr-tag/gr-rollup/gr-xueqiu`，`make gr`；web `lib/globalQueries.ts` + `app/[lang]/lab/global-retail/`（复用 AsiaCharts；noindex/不进 sitemap/无导航）。隔离表 `gr_*`。

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
│   │   └── seed_tickers.py    #   seed ticker 字典 → ticker_meta（含中概/港股 cn_hk_tickers.json）
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
│   │   └── translate.py       #   翻译成中文 *_zh 列（增量、幂等；走 SQLAlchemy/DATABASE_URL，云端本地通用）
│   └── data/                  #   随仓库的字典/样本（ticker_stoplist.txt, cn_hk_tickers.json, subreddits.yml, asia_targets.yml, global_targets.yml…）
│
├── web/                       # ③ Next.js 14 静态站
│   ├── app/
│   │   ├── layout.tsx         #   根布局（主题防闪烁 + 默认 OG/metadataBase）
│   │   ├── [lang]/            #   语言段（zh|en|ja|ko）：generateStaticParams（页面数 = locales × 各内页）
│   │   │   ├── page.tsx       #     落地页（股神轮播）
│   │   │   ├── dashboard/     #     美股看板    cn/ 中概看板
│   │   │   ├── ticker/[symbol]/  个股页   cn/ticker/[symbol]/
│   │   │   ├── post/[id]/     #     帖子详情（AI 摘要 + 多空 + 评论 + 翻译切换）
│   │   │   ├── author/[name]/  作者聚合页（代表作/看好看空标的/基础数据；全站作者名头像可点入）
│   │   │   ├── search/ leaderboard/ insights(管理员看板) account/ me(个人主页·私密) login/ signup/ …
│   │   │   ├── lab/asia-pulse/ #   ★隐藏页：亚洲散户脉搏（无导航入口/不进 sitemap/noindex，仅 URL 直达）
│   │   │   ├── lab/global-retail/ # ★隐藏页：全球散户四地区脉搏（美日韩台跨区对比；同样 noindex/无导航）
│   │   ├── sitemap.ts / robots.ts / not-found.tsx   # SEO + 404
│   │   └── icon.png           #   favicon
│   ├── lib/
│   │   ├── db.ts              #   ★构建期用 node:sqlite 读 ../data/dev.db
│   │   ├── queries.ts         #   ★所有取数 SQL（getMindshare/getTrending/getPostDetail…）
│   │   ├── asiaQueries.ts      #   亚洲实验隐藏页取数（读 asia_* 表，try/catch 包裹：表缺失返回空不崩）
│   │   ├── globalQueries.ts    #   全球散户隐藏页取数（读 gr_* 表 + US 代表帖读现有 Reddit；try/catch 兜底）
│   │   ├── i18n.ts + dictionaries/{zh,en,ja,ko}.ts # 多语（zh 为源，en/ja/ko 必须镜像同样的 key；UI 译，帖子内容 ja/ko 回退英文原文）
│   │   ├── supabase.ts / auth.ts / admin.ts    # Supabase 客户端 + 登录 + 管理员判定
│   │   ├── analytics.ts / searchCounts.ts      # 埋点 + 搜索榜（写 Supabase）
│   │   ├── favorites.ts                         # ★账户收藏/追踪：客户端读写 user_collections（RLS）
│   │   └── site.ts            #   SITE_URL（https://www.redditalpha.xyz）+ OG
│   ├── components/            #   UI 组件（Sidebar/Topbar/FeedCard/MarkdownLite… + auth/ favorites/ profile/）
│   ├── next.config.mjs        #   output:export(仅生产) + cpus:1 串行导出 + images:unoptimized
│   └── public/               #   logo/og/avatars/communities（图片已压缩）
│
├── supabase/migrations/       # ② Supabase SQL 迁移（ticker_searches / analytics / user_collections 的表+RLS+RPC）
├── data/dev.db                # 本地 SQLite 快照（gitignore；由 cloud-pull 从云端拉取）
├── Makefile                   # ★所有常用命令入口
├── .env / .env.example        # 凭据与配置（.env gitignore：QWEN/DEEPSEEK/DATABASE_URL…）
└── 文档：README / DEPLOY / CLOUD_DB / SUPABASE_AUTH / STRATEGY / ARCHITECTURE(本文)
```

---

## 5. 数据库 schema（14 张主表 + 4 张亚洲实验 + 3 张全球散户隔离表，`pipeline/common/models.py` 为单一真源）

| 类别 | 表 | 说明 |
|---|---|---|
| 原始 | `subreddits` `authors` `posts` `comments` | 抓来的原始内容（含 `*_zh` 译文列、`market`；`posts.source` scan/author 区分实时舆情/作者库，`authors.crawled_at` 作者库增量标记） |
| 字典/抽取 | `ticker_meta` `mentions` | ticker 字典 + 帖子↔ticker 提及（含 confidence/method） |
| AI 分析 | `item_analysis` | ★逐帖打标结果（情绪/多空/质量/主题/双语摘要/per-ticker 论据），按 item_id 持久化 |
| 派生聚合 | `ticker_rollup` `market_mood` `trending` | 声量榜 / 市场情绪 / 异动（每次全量重算，可弃） |
| 叙事/简报 | `narratives` `narrative_tickers` `narrative_posts` `daily_briefs` | 主导叙事 + 每日简报 |
| 亚洲实验(隔离) | `asia_posts` `asia_analysis` `asia_ticker_summary` `asia_price` | 日韩本土散户帖(含 `sentiment`=flash 全量打分 + views/comments/images/verified) + 千问深析 + 每格汇总 + 日K价格（market `jp`/`kr`；与 us/cn 完全隔离，实时聚合/feed 一律不读，仅供隐藏看板） |
| 全球散户(隔离) | `gr_post` `gr_ticker_region` `gr_ticker` | 日韩台+中国大陆(雪球)爬精选跨区美股的散户帖(flash 打标 sentiment+stance) + 每 region×ticker 滚动(region `us`/`cn`/`jp`/`kr`/`tw`；**US 不入 gr_post，rollup 只读现有 Reddit**；CN 经浏览器过 WAF 导入) + 每 ticker 跨区派生(共识/分歧)。与 us/cn 主表 及 asia_* 均隔离，仅供隐藏页 /lab/global-retail |

> 迁移只搬「原始+字典+AI 分析」这 7 张源表（贵、需长期保存）；派生表在云端用 `make rollup` 等重算。
> 亚洲实验 4 表 + 全球散户 3 表都在 `ALL_TABLES`（`cloud-pull` 会快照），但**不在** `sync.SOURCE_TABLES`；`make asia` / `make gr` 写当前 `DATABASE_URL`（本地验证用 `DATABASE_URL='sqlite:///./data/dev.db'` 覆盖，勿对云端跑建表 DDL）。

---

## 6. 大模型档位（`pipeline/common/llm.py` 为路由真源）

| 档位 | 用途 | 当前 provider |
|---|---|---|
| **HIGH** | 逐帖投资打标（思考模式，全站分析大脑，token 大头） | 通义千问 `qwen3.7-plus` |
| **MID** | 叙事聚类 / 每日简报 / 正文重排版 | DeepSeek `deepseek-v4-pro` |
| **LOW** | 翻译（标题/正文/摘要/评论） | DeepSeek `deepseek-v4-flash` |

改模型只动 `llm.py` 路由表。缺 key 时各环节回退 mock 启发式，不崩。

---

## 7. 常用命令（Makefile）

| 命令 | 作用 |
|---|---|
| `make daily` | 分析过去 24h（抓取+AI 打标+聚合+翻译），直接写 `DATABASE_URL`（云端）；含作者库爬取 |
| `make crawl-authors` | 单独跑作者库：爬实力榜 Top 作者历史帖（DeepSeek 粗筛→千问深析）。需 DeepSeek key |
| `make analyze-qwen` | 真实千问逐帖打标 + 重算聚合 |
| `make asia` | 亚洲散户舆情实验：爬日(Yahoo)/韩(Naver)本土板 + 真实 AI 分析（千问逐帖 + DeepSeek 汇总）。`make asia-mock` 为零成本版 |
| `make gr` | 全球散户五地区看板：日韩台爬精选跨区美股 + DeepSeek flash 打标 + 跨区滚动(US 读现有 Reddit)。隐藏页 /lab/global-retail。CN(雪球)走 `gr-xueqiu`(收浏览器过 WAF 的导出 JSON) |
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
