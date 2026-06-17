<div align="center">
  <img src="web/public/logo.png" alt="Prismo" width="96" />
  <h1>Prismo</h1>
  <p>Reddit 美股舆情情报 Dashboard</p>
</div>

> **品牌 / 命名（正式确定）**
> - **名称**：`Prismo`（小写 wordmark，呼应 Reddit 自身的小写风格）。即原“Reddit 版 Kaito Pro”。
> - **Logo**：深藏青字母「A」+ 橙色波浪（波浪 = 舆情信号）。文件 `web/public/logo.png`，并作为站点 favicon（`web/app/icon.png`）。
> - **主题色（取自 logo）**：品牌橙 `#FC3E02`（主色 / CTA / 热度 / upvote）、藏青 `#13212C`（界面底色家族），辅以 bull 绿 `#24B47E` / bear 红 `#F0556E` 作多空语义色。

把 [Kaito Pro](https://pro.kaito.ai/portal) 的「注意力份额(mindshare) + 叙事 + 情绪 + KOL 榜」打法，从 Twitter/crypto 迁到 **Reddit / 美股**。以专业方式分析 Reddit 财经板块的帖子数据，输出**真实数据 + 多角度 AI 结论**。

## 三大系统
1. **数据系统**（Python / PRAW）— 从 Reddit 主流财经板块合规拉取帖子/评论，抽取股票 ticker，写入数据库。
2. **AI 分析系统**（Python / Claude）— 逐帖打标（情绪/多空/质量/主题/TL;DR/多空论点），聚合出 mindshare、市场情绪、异动，AI 叙事聚类与每日简报。
3. **UI 展示系统**（Next.js）— 看板、趋势异动、叙事、智能帖子流、作者榜、Ticker 详情页、每日简报。

## 架构
```
Python ingest (PRAW) ──► DB (SQLite 开发 / Postgres 生产) ◄── Python analyze (Claude Batch)
   posts/comments            raw + 分析 + rollup 表           item_analysis / narratives / briefs
   ticker 抽取 → mentions          ▲
                                   │ Prisma
                          Next.js (App Router, RSC 直读)
```
- **数据层抽象**：SQLAlchemy + `DATABASE_URL`。开发默认 **SQLite 零配置**；生产切 **Postgres**（`docker compose up -d`，改 `DATABASE_URL`）。同一套 models 两边通用。

## 快速开始（离线，无需任何凭证）
最快感受整套系统：用内置样本帖 + mock AI 跑通全流程。
```bash
make install          # 建 venv 装 Python 依赖
cp .env.example .env  # 默认 DATABASE_URL=sqlite，无需改
make demo             # 建库→seed ticker→载样本→AI(mock)打标→mindshare/情绪/异动→叙事→简报→统计
```
`make demo` 结束会打印库内统计与 top mindshare。随后启动前端：
```bash
make web-install && make web-dev   # http://localhost:3000
```

## 接真实数据（在你本机，带凭证）
> ⚠️ 本仓库的沙箱环境出口 IP 被 Reddit/SEC 屏蔽；真实拉取请在你自己的机器上跑。

1. **Reddit**：`https://www.reddit.com/prefs/apps` 建一个 **script** app（2025-11 起需先申请审批，含个人项目）。把 client id/secret/UA 填进 `.env`。
2. **Anthropic**：`.env` 填 `ANTHROPIC_API_KEY`。
3. 运行：
```bash
make seed       # 从 SEC 拉全量 ticker 字典
make ingest     # PRAW 拉取 + ticker 抽取
make analyze    # Claude 逐帖打标（Batch + 缓存）
make rollup     # mindshare / 市场情绪 / 异动
make narratives # AI 叙事聚类
make brief      # 每日 AI 简报
make worker     # 或：一键启动调度器，按节奏自动跑以上全部
```

## 目录结构
```
legacy/        归档的旧科普原型
pipeline/      Python：数据 + AI
  common/      config / db(SQLAlchemy) / models / reddit(PRAW) / claude
  ingest/      reddit_ingest / ticker_extract / seed_tickers / sample_loader / refresh
  analyze/     item_analyze / rollups / market_mood / trending / narratives / brief
  data/        ticker 字典 / 停用表 / subreddits.yml / sample_posts.json
  manage.py    CLI 入口（被 Makefile 调用）
  worker.py    APScheduler 调度
web/           Next.js（App Router + TS + Tailwind + Prisma + ECharts）
db/            SQL 备注（schema 真源在 SQLAlchemy models）
data/          dev.db 等本地数据（git 忽略）
```

## 验证（端到端）
- `make demo` 后 `make stats`：应看到 posts / mentions / item_analysis 行数，且各 ticker mindshare 占比之和 ≈ 100%。
- 抽样核对 ticker 抽取：`$AAPL` 这类 cashtag 命中应近 100%，常用词（A/IT/DD）被停用表过滤。
- 前端看板能展示 treemap、市场情绪、热度榜、叙事、帖子流；Ticker 详情页的多空论点可点回真实原帖链接。

## 合规
仅用官方 Reddit Data API、遵守 100 QPM 限额与 User-Agent 规范、非商用、内容回链 Reddit。AI 结论为「信号」非投资建议。

## 模型
逐帖打标 `claude-haiku-4-5`（高并发低成本，Batch −50% + prompt caching）；叙事/综合 `claude-sonnet-4-6`；简报可选 `claude-opus-4-8`。见 `.env` 可配。
