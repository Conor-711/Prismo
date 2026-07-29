PY := pipeline/.venv/bin/python
SYS_PY := python3
PIP := pipeline/.venv/bin/pip
MANAGE := $(PY) -m pipeline.manage
SV_INDICATOR_WINDOWS := 1,3,7,30,90
SV_INDICATOR_SOURCES := all,x,youtube,reddit,xueqiu
SV_SEGMENT_WINDOWS := 3,7,14,30
SV_SEGMENT_TYPES := horizon,narrative,investor_type
SV_SEGMENT_BANDS := top10,top25

.PHONY: install venv db-init migrate seed seed-cn sample ingest refresh extract analyze analyze-mock \
        rollup narratives narrative-rotation brief worker daily daily-build cn-backfill demo stats test web-install web-dev clean help \
        arch-check sv-price-history sv-v0-candidates sv-v0 sv-v0-prod private-sv-telegram sv-ticker-signals sv-indicator-backtest sv-indicator-report sv-segment-backtest sv-portfolio-backtest sv-rank-event-research reddit-sv-authors sv-v0-reddit-candidates sv-v0-reddit-prod tw-match cf-deploy \
        backup-db snapshot-db restore-db data-clean data-status xueqiu-author-auth xueqiu-author-plan xueqiu-author-run xueqiu-author-drain xueqiu-author-status xueqiu-sv-full

help:
	@echo "Reddit 版 Kaito Pro — 常用命令"
	@echo "  make install       建 venv 并装 Python 依赖"
	@echo "  make demo          一键离线全流程（样本数据 + mock AI），最快体验"
	@echo "  make stats         打印库内统计 / top mindshare"
	@echo "  --- 真实数据（需 .env 凭证，在你本机跑）---"
	@echo "  make seed          从 SEC 拉取并 seed ticker 字典"
	@echo "  make ingest        用 PRAW 拉取 Reddit 帖子并抽取 ticker"
	@echo "  make analyze       用 Claude 逐帖打标"
	@echo "  make rollup        计算 mindshare / 情绪 / 异动"
	@echo "  make narratives    AI 叙事聚类     make brief  每日 AI 简报"
	@echo "  make narrative-rotation  跨社区固定叙事轮动 JSON（新叙事页）"
	@echo "  make daily         分析过去 24 小时（一天一次；UTC+8 08:00 跑）"
	@echo "  make daily-build   分析过去 24h 并重建静态站点（web/out）"
	@echo "  make migrate       已有库迁移到带 market 维度（幂等）"
	@echo "  make seed-cn       seed 中概/港股/A 股字典"
	@echo "  make cn-backfill   回填中概·港股语料（爬30天+AI打标+双market聚合+翻译）"
	@echo "  make worker        启动调度：每天 UTC+8 08:00 自动跑 daily-build"
	@echo "  make sv-price-history     补齐 SV 所需日线价格"
	@echo "  make sv-v0                运行 Smart Voice v0：候选召回 → LLM 结构化 → 结算 → 导出"
	@echo "  make sv-v0-prod           生产级 SV：更大候选池 + 作者均衡 LLM 抽样"
	@echo "  make private-sv-telegram  单个公开 Telegram 频道的隔离 Private SV 报告"
	@echo "  make sv-ticker-signals    标的 SV 分层、聚集事件与无泄漏历史回测"
	@echo "  make sv-indicator-backtest  回测 SV 发现页指标的胜率、盈亏比和超额收益"
	@echo "  make sv-indicator-report    导出逐事件、逐原文证据和稳健性细分数据"
	@echo "  make sv-segment-backtest    按周期、赛道和投资类型子 SV 做垂直集中回测"
	@echo "  make sv-portfolio-backtest  计算 X SV 集体信号及逐作者组合年化"
	@echo "  make sv-rank-event-research 扩展 X SV 头尾事件参数并做前后半段验证"
	@echo "  make xueqiu-author-plan   导入雪球候选池并创建一年作者时间线任务"
	@echo "  make xueqiu-author-auth   由用户登录雪球并保存本地会话（不保存密码）"
	@echo "  make xueqiu-author-run    断点运行雪球作者时间线任务"
	@echo "  make xueqiu-author-drain  低频冷却长跑正式 300 人作者池"
	@echo "  make xueqiu-sv-full       回填完整作者池后自动召回、抽取、结算并导出雪球 SV"
	@echo "  make reddit-sv-authors    补 Reddit SV 作者历史和作者资料"
	@echo "  make sv-v0-reddit-prod    运行 Reddit 帖子版 Smart Voice"
	@echo "  --- Web ---"
	@echo "  make web-install   安装前端依赖    make web-dev  启动 Next.js"
	@echo "  make cf-deploy     构建并上传 web/out 到 Cloudflare Pages（PROJECT=prismo 可改项目名）"
	@echo "  make arch-check    检查前端/管线架构边界"
	@echo "  make backup-db     备份本地真源到项目外（默认只保留最近一份）"
	@echo "  make snapshot-db   生成可提交的压缩部署快照（不提交原始 dev.db）"
	@echo "  make data-status   查看主库、部署快照和外部备份大小"

# ---------- 环境 ----------
venv:
	python3 -m venv pipeline/.venv

install: venv
	$(PIP) install -U pip
	$(PIP) install -r pipeline/requirements.txt

# ---------- 数据库 / 数据 ----------
db-init:
	$(MANAGE) db-init

# 把已有库迁移到带 market 维度的新 schema（幂等；源表加列、派生表重建）
migrate:
	$(MANAGE) migrate

seed:
	$(MANAGE) seed-tickers

# seed 中概股 / 港股 / A 股字典（cn_hk_tickers.json → ticker_meta，market=cn）
seed-cn:
	$(MANAGE) seed-cn-hk

sample:
	$(MANAGE) load-sample

# ---------- 数据系统（真实）----------
ingest:
	$(MANAGE) ingest --once

refresh:
	$(MANAGE) refresh

extract:
	$(MANAGE) extract --reextract

scrape:
	$(MANAGE) scrape --days 3 --limit 300

# 作者库：爬「实力榜」Top 作者历史帖（两级漏斗：DeepSeek 粗筛 → 千问深析）。需 DeepSeek key。
crawl-authors:
	$(MANAGE) crawl-authors --limit 50

reddit-sv-authors:
	$(MANAGE) crawl-authors --limit $(or $(AUTHORS),1000) --per-author $(or $(PER_AUTHOR),40) --max-fetch-per $(or $(MAX_FETCH),1000) --since-days $(or $(DAYS),365)

# ---------- 每日一次（不再实时；以 UTC+8 24h 为界，08:00 跑一次）----------
# 分析过去 24 小时：拉取 1 天的帖子/评论 + AI 打标 + 聚合。需要真实 Claude 则设 ANTHROPIC_API_KEY。
daily:
	$(MANAGE) daily

# 同上，并重建静态站点（web/out），让部署页面反映最新一天
daily-build:
	$(MANAGE) daily --rebuild
	@echo "" && echo "✅ 每日分析 + 站点重建完成。本地部署见 make serve 或 server.mjs"

# 一次性回填「中概·港股」语料：迁移 + seed cn 字典 + 爬 30 天 cn 社区 + 抽取 + AI 打标 + 双 market 聚合 + 翻译。
# 需要 .env 里 QWEN_API_KEY（AI 打标/翻译走通义千问）。完成后 make site 重建即可看到 /cn 页。
cn-backfill:
	$(MANAGE) migrate
	$(MANAGE) seed-cn-hk
	$(MANAGE) scrape --days 30 --limit 400 --markets cn
	$(MANAGE) scrape-china --days 45 --limit 300
	$(MANAGE) scrape-comments --top 400 --per-post 12 --min-comments 4
	$(MANAGE) analyze --qwen --workers 10
	$(MANAGE) rollup --market all
	$(MANAGE) mood --market all
	$(MANAGE) trending --market all
	$(MANAGE) narratives --mock --market all
	-$(MANAGE) translate
	@echo "" && echo "==== 中概·港股回填完成 ====" && $(MANAGE) stats

# 真实数据全流程（Arctic Shift 实时 Reddit 数据 + mock AI；真实 Claude 需 ANTHROPIC_API_KEY）
real:
	rm -f data/dev.db data/dev.db-wal data/dev.db-shm
	$(MANAGE) db-init
	$(MANAGE) seed-tickers
	$(MANAGE) seed-cn-hk
	$(MANAGE) scrape --days 3 --limit 300
	$(MANAGE) analyze --mock
	$(MANAGE) rollup
	$(MANAGE) mood
	$(MANAGE) trending
	$(MANAGE) narratives --mock
	$(MANAGE) brief --mock
	@echo "" && echo "==== 真实数据导入完成 ====" && $(MANAGE) stats

# ---------- AI 分析 ----------
analyze:
	$(MANAGE) analyze

analyze-mock:
	$(MANAGE) analyze --mock

# 真实 AI 打标（通义千问 qwen3.7-plus，双语英文+中文，并发、可断点续跑，需 .env 里 QWEN_API_KEY）。
# 跑完建议接 rollup/mood/trending/narratives 让聚合对齐新情绪。
analyze-qwen:
	$(MANAGE) analyze --qwen --workers 10
	$(MANAGE) rollup
	$(MANAGE) mood
	$(MANAGE) trending
	$(MANAGE) narratives --mock

# 全球散户多区数据：日韩台爬精选跨区美股 + DeepSeek flash 打标 + 跨区滚动(US 读现有 Reddit)。
# 隔离表 gr_*，供总览、标的、叙事、追踪等正式页面读取。本地跑：DATABASE_URL='sqlite:///./data/dev.db' make gr
gr:
	$(MANAGE) gr-crawl --per-board 120 --since-days 14
	$(MANAGE) gr-tag
	$(MANAGE) gr-rollup
	$(MANAGE) gr-quote
	@echo "" && echo "✅ 全球散户数据完成。出站：make site（正式页面读取 dev.db 渲染）。"

# 仅刷新各标的最新价（Yahoo 15m chart → gr_quote），供标的页展示最新价/涨跌幅。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make gr-quote
gr-quote:
	$(MANAGE) gr-quote

# 雪球 SV 作者池：候选池导入 → 一年作者时间线任务 → 断点回填。
# 首次运行需 `make xueqiu-author-auth`，用户在弹出的 Chrome 中自行登录。
xueqiu-author-auth:
	DATABASE_URL='sqlite:///./data/dev.db' $(MANAGE) gr-xueqiu-author-auth

xueqiu-author-plan:
	DATABASE_URL='sqlite:///./data/dev.db' $(MANAGE) gr-xueqiu-author-plan --pool-csv $(or $(POOL_CSV),reports/xueqiu_author_pool_discovery_2026-07-10.csv) --pool-version $(or $(POOL_VERSION),xueqiu-sv-pool-20260710-v2) --min-followers $(or $(MIN_FOLLOWERS),500) --min-statuses $(or $(MIN_STATUSES),300) --days $(or $(DAYS),365) $(if $(ONLY_USERS),--only-users $(ONLY_USERS),) $(if $(SELECTED_ONLY),--selected-only,) $(if $(FORCE),--force,)

xueqiu-author-run:
	DATABASE_URL='sqlite:///./data/dev.db' $(MANAGE) gr-xueqiu-author-run --pool-version $(or $(POOL_VERSION),xueqiu-sv-pool-20260710-v2) --max-jobs $(or $(MAX_JOBS),4) --sleep $(or $(SLEEP),2.0) --headless --selected-only --order activity --expand-tickers $(if $(ONLY_USERS),--only-users $(ONLY_USERS),) $(if $(RETRY_FAILED),--retry-failed,) $(if $(RETRY_BLOCKED),--retry-blocked,)

xueqiu-author-drain:
	DATABASE_URL='sqlite:///./data/dev.db' $(MANAGE) gr-xueqiu-author-drain --pool-version $(or $(POOL_VERSION),xueqiu-sv-pool-20260710-v2) --batch-size $(or $(BATCH_SIZE),3) --cooldown $(or $(COOLDOWN),300) --failure-cooldown $(or $(FAILURE_COOLDOWN),1800) --max-failure-cooldown $(or $(MAX_FAILURE_COOLDOWN),3600) --max-cycles $(or $(MAX_CYCLES),0) --sleep $(or $(SLEEP),2.0) --max-attempts $(or $(MAX_ATTEMPTS),5) --headless --expand-tickers

xueqiu-author-status:
	DATABASE_URL='sqlite:///./data/dev.db' $(MANAGE) gr-xueqiu-author-status --pool-version $(or $(POOL_VERSION),xueqiu-sv-pool-20260710-v2)

xueqiu-sv-full:
	POOL_VERSION=$(or $(POOL_VERSION),xueqiu-sv-pool-20260710-v2) bash scripts/run_xueqiu_sv_full.sh

# SV scoring price history: backfill Nasdaq daily OHLC into local price_daily.
# 可局部补齐：make sv-price-history ONLY=MU,NVDA
sv-price-history:
	$(MANAGE) sv-price-history --start $(or $(START),2025-06-01) --top-n $(or $(TOP_N),1000) --min-count $(or $(MIN_COUNT),25) --workers $(or $(WORKERS),8) --sleep $(or $(SLEEP),0.02) $(if $(ONLY),--only $(ONLY),)

# Toss(토스증권) 종목 커뮤니티评论 → gr_post(source='toss', region='kr')。逆向 Web API、游标翻页 RECENT，无需登录。
# 标的映射在 pipeline/platforms/toss/community.py 的 TOSS_STOCKS；大体量标的可调 --resume/--max-pages/--sleep/--commit-pages。
# 落库后跑 gr-tag(打情绪)→retail-sentiment/-volume/-newcomers(进散户图)。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make toss
toss:
	$(MANAGE) toss --days 14
	$(MANAGE) gr-tag
	@echo "" && echo "✅ Toss 爬取 + 打标完成。下一步：make retail-sentiment && make retail-volume，再 make site。"

# YouTube 观点：按标的搜近 24h、浏览量>1000 的视频（全语种）→ Gemini 混合分析 → 标的页模块。
# 需 YOUTUBE_API_KEY + GEMINI_API_KEY。无 key 验证：make youtube-mock
youtube:
	$(MANAGE) youtube-crawl --since-hours 24
	$(MANAGE) youtube-tag --top-native 2
	@echo "" && echo "✅ YouTube 观点完成。出站：make site（标的页「YouTube 观点」模块）。"

# YouTube 频道作者基础信息（粉丝数/视频数/个人简介）→ 本地 yt_channel（供 YouTube 正文作者头像旁展示）。
# Data API channels.list（1 配额/50频道）；需 YOUTUBE_API_KEY。整表刷新。出站 make site。
yt-channels:
	$(MANAGE) yt-channels
	@echo "" && echo "✅ YouTube 频道信息完成。出站：make site。"

# 零成本版（多语种样本，无需 YouTube/Gemini key）——验证 schema 与看板渲染
youtube-mock:
	$(MANAGE) youtube-crawl --mock
	$(MANAGE) youtube-tag --mock

# YouTube 完整口播 → 「投资者摘要」+「内容目录(章节)」→ 本地 yt_digest（供正文上方摘要 + 右侧目录跳转）。
# 读 yt_fulltext 的口播文本跑 LOW 档(qwen-flash，不重看视频)；增量。先跑 youtube-fulltext。出站 make site。
youtube-digest:
	$(MANAGE) youtube-digest
	@echo "" && echo "✅ YouTube 投资者摘要+目录完成。出站：make site。"

# 作者页「① 标的判断」结构化参数：从已有 yt_analysis 观点/论据抽 时间周期/目标价/关键位置 → 本地 yt_judgment。
# LOW 档(qwen-flash，纯文本不重看视频)；增量(只补未抽)；多数视频无明确周期/关键位→大量 null 属正常。出站 make site。
youtube-judgment:
	$(MANAGE) youtube-judgment
	@echo "" && echo "✅ YouTube 标的判断参数完成。出站：make site。"

# 作者页「① 标的判断」每标的综合：同一博主对同一标的多条视频判断 → 整体立场+几点关键判断 → 本地 yt_creator_view。
# LOW 档(qwen-flash，读已蒸馏文本不重看视频)；增量(只补未做)；让作者页每标的只显示一段综合而非铺开每条视频。出站 make site。
youtube-creator-view:
	$(MANAGE) youtube-creator-view
	@echo "" && echo "✅ YouTube 作者×标的综合完成。出站：make site。"

# KOL 个体观点 AI 提炼+双语：把 reddit/x/雪球/Toss 照搬的原文 → 「为什么看多/看空 + 2-3 要点」(zh/en) → kol_refined。
# 只提炼每标的每源 top-N(默认 20)；增量(只补未提炼)。YouTube 复用 yt_analysis 无需在此。
# 默认 Qwen→DeepSeek→Gemini，可用 KOL_REFINE_PROVIDERS 改顺序；需至少一个对应 provider key。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make kol-refine
kol-refine:
	$(MANAGE) kol-refine --per-source 20
	@echo "" && echo "✅ KOL 观点提炼完成。出站：make site（标的页象限①「个体观点·KOL」展示 reason+要点）。"

# KOL 个体观点 视角分类：把已蒸馏观点(kol_refined + yt_analysis) → 7 视角标签(1-3 个) → kol_viewpoint。
# 增量(只补未分类)；无明确观点的直接记 other 省调用。需 DEEPSEEK_API_KEY。先跑 kol-refine 再跑本目标。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make kol-viewpoint
kol-viewpoint:
	$(MANAGE) kol-viewpoint
	@echo "" && echo "✅ KOL 视角分类完成。出站：make site（标的页 KOL 模块『按视角』视图）。"

# KOL 目标价+操作周期 抽取：从 reddit/x/雪球/Toss 原帖**只抽作者明说**的 买入/卖出/目标价 + 周期 → kol_judgment。
# 反臆造(没明说=空)；增量(只补未抽)。YouTube 复用 yt_judgment 无需在此。需 QWEN_API_KEY(LOW档)。先跑 kol-refine。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make kol-judgment（单标的调试 $(MANAGE) kol-judgment --only NFLX）
kol-judgment:
	$(MANAGE) kol-judgment --per-source 40
	@echo "" && echo "✅ KOL 目标价+周期抽取完成。出站：make site（正文提炼显示买卖价/周期 + 整体数据目标价散点图）。"

# X 推文情绪打分（写**云端** tw_tweet_sentiment）：给 tw_tweet_topic 命中的 ~5.4 万推文 flash 批量打 -1..1。
# ⚠ 别加 sqlite 覆盖（tw_* 在云端）。需 DEEPSEEK_API_KEY。增量(只打未打分的)。
tw-match:
	$(MANAGE) tw-match

tw-sentiment:
	$(MANAGE) tw-sentiment
	@echo "" && echo "✅ X 推文情绪打分完成（云端 tw_tweet_sentiment）。下一步：make kol-sentiment。"

# KOL 每日净情绪 rollup → 本地 kol_sentiment_daily（标的页折线图下方绿/红面积子面板）。
# 跨平台 情绪×ln(1+互动)×相关性 加权净值。⚠ **不要**加 sqlite 覆盖——脚本自 hardcode 本地 dev.db +
# 从 .env 读云端拿 X；先跑 tw-sentiment。出站 make site。
kol-sentiment:
	$(MANAGE) kol-sentiment
	@echo "" && echo "✅ KOL 每日净情绪完成。出站：make site。"

# KOL 每日讨论度 rollup → 本地 kol_volume_daily（标的页折线图下方条状子面板）。
# 跨平台帖子/视频**计数**（X 直接数 tw_tweet_ticker、不 join tw_tweet）。⚠ **不要**加 sqlite 覆盖——
# 脚本自 hardcode 本地 dev.db + 从 .env 读云端拿 X。出站 make site。
kol-volume:
	$(MANAGE) kol-volume
	@echo "" && echo "✅ KOL 每日讨论度完成。出站：make site。"

# 整体散户 每日净情绪 rollup → 本地 retail_sentiment_daily（标的页『整体散户』视图的绿/红面积子面板）。
# 全量散户 + 本土论坛(Naver/YahooJP/PTT)、不含 YouTube。⚠ **不要**加 sqlite 覆盖——脚本自 hardcode 本地 +
# 从 .env 读云端拿 X；先跑 tw-sentiment。出站 make site。
retail-sentiment:
	$(MANAGE) retail-sentiment
	@echo "" && echo "✅ 整体散户 每日净情绪完成。出站：make site。"

# 整体散户 每日讨论度 rollup → 本地 retail_volume_daily（标的页『整体散户』视图的条状子面板）。
# 全量散户帖子计数 + 本土论坛、不含 YouTube（X 直接数 tw_tweet_ticker）。⚠ **不要**加 sqlite 覆盖。出站 make site。
retail-volume:
	$(MANAGE) retail-volume
	@echo "" && echo "✅ 整体散户 每日讨论度完成。出站：make site。"

# 整体散户 每日『新增散户』rollup → 本地 retail_newcomers_daily（标的页『整体数据』视图的第三块条状子面板）。
# 各平台首次参与该标的讨论的去重作者数(Reddit 发帖+评论 / 五论坛)，不含 X(无作者)/YouTube。纯本地、无需云端。出站 make site。
retail-newcomers:
	$(MANAGE) retail-newcomers
	@echo "" && echo "✅ 整体散户 每日新增散户完成。出站：make site。"

# KOL 每日『新增 KOL』rollup → 本地 kol_newcomers_daily（标的页『整体数据』KOL 视图的第三块条状子面板）。
# X/YouTube/雪球(有身份/粉丝象征)首次参与该标的讨论的去重作者数。纯本地、无需云端（X 用本地 x_opinion）。出站 make site。
kol-newcomers:
	$(MANAGE) kol-newcomers
	@echo "" && echo "✅ KOL 每日新增 KOL 完成。出站：make site。"

# 整体数据『异动归因 + 讨论方面』（仅 KOL）→ web/lib/data/overallData.json（构建期静态读）。
# ① 情绪/讨论度异常日 + AI 一句话归因（标在当天折线/条状上，hover 出原因）；② 近 14 天 KOL 最密集讨论的 3 个方面。
# 读本地 dev.db 的 daily 序列 + KOL 推文抽取(/tmp/<ticker>_x6m.jsonl)；用 qwen-flash 归因/提炼。需 QWEN_API_KEY。
# 当前 PLTR 测试：make overall-signals（或 TICKER=XXX make overall-signals）。出站 make site。
overall-signals:
	$(MANAGE) overall-signals --ticker $(or $(TICKER),PLTR)
	@echo "" && echo "✅ 整体数据 异动归因+讨论方面 完成。出站：make site。"

# 新叙事页：跨社区固定板块的叙事轮动（排名变化 / 讨论占比 / 情绪变化）→ 构建期 JSON。
# 不使用旧 Reddit-only narratives 表；默认近 21 天，近 7 天作为当前窗口。
narrative-rotation:
	$(MANAGE) narrative-rotation --window-days 21 --recent-days 7
	@echo "" && echo "✅ 叙事轮动数据完成。出站：make site。"

# KOL 论点综合：把已分类观点(kol_refined+kol_viewpoint+yt_analysis) → 每 标的×视角×立场 聚成 1-3 个论点 → kol_argument。
# 增量(只补未综合的组)；单条观点的组不花 LLM。需 DEEPSEEK_API_KEY。先跑 kol-refine + kol-viewpoint 再跑本目标。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make kol-argument
kol-argument:
	$(MANAGE) kol-argument
	@echo "" && echo "✅ KOL 论点综合完成。出站：make site（标的页 KOL 模块『按视角』下的论点）。"

# KOL 原帖完整忠实翻译（逐句直译、不压缩）→ kol_refined.trans_zh/en。供『按视角·原帖流』的「译」选项。
# 与提炼解耦、可独立重跑；只译已展示(已提炼)的原帖。增量(只补未译)，同一 source+item 跨 ticker 只调用一次并复用；默认 Qwen→DeepSeek→Gemini，可用 KOL_TRANSLATE_PROVIDERS 改顺序。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make kol-translate
kol-translate:
	$(MANAGE) kol-translate --per-source 200 --since-days 30
	@echo "" && echo "✅ KOL 原帖翻译完成。出站：make site（标的页『按视角』原帖卡的「译」选项）。"

# KOL 相关性打分：给每条帖文/视频 与标的的相关度打 0-100(越高越相关) → kol_relevance。供『按相关性』筛选/排序。
# 覆盖 reddit/x/xueqiu(已展示项)+youtube；增量(只补未打分)；需 QWEN_API_KEY。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make kol-relevance
kol-relevance:
	$(MANAGE) kol-relevance --per-source 200 --since-days 30
	@echo "" && echo "✅ KOL 相关性打分完成。出站：make site（标的页『按相关性』排序）。"

# KOL 帖子质量打分：给每条帖文/视频本身的含金量打 0-100(与标的无关、按 source+item 去重) → kol_quality。
# 供观点浏览器『只看高质量』开关。覆盖 reddit/x/xueqiu+youtube；增量；需 QWEN_API_KEY。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make kol-quality
kol-quality:
	$(MANAGE) kol-quality --per-source 800 --since-days 35
	@echo "" && echo "✅ KOL 帖子质量打分完成。出站：make site（标的页『只看高质量』开关）。"

rollup:
	$(MANAGE) rollup
	$(MANAGE) mood
	$(MANAGE) trending

narratives:
	$(MANAGE) narratives

brief:
	$(MANAGE) brief

# 把帖子/AI 摘要/评论翻译成中文 → *_zh 列（增量、幂等，需 ANTHROPIC_API_KEY）。
translate:
	$(MANAGE) translate

worker:
	$(PY) -m pipeline.worker

# ---------- 一键离线全流程（无需凭证）----------
demo:
	rm -f data/dev.db data/dev.db-wal data/dev.db-shm
	$(MANAGE) db-init
	$(MANAGE) seed-tickers --fallback
	$(MANAGE) seed-cn-hk
	$(MANAGE) load-sample
	$(MANAGE) analyze --mock
	$(MANAGE) rollup
	$(MANAGE) mood
	$(MANAGE) trending
	$(MANAGE) narratives --mock
	$(MANAGE) brief --mock
	@echo "" && echo "==== DEMO 完成，库内统计： ====" && $(MANAGE) stats

stats:
	$(MANAGE) stats

test:
	$(PY) -m pytest -q
	$(SYS_PY) scripts/check_architecture.py

arch-check:
	$(SYS_PY) scripts/check_architecture.py

# ---------- Smart Voice v0 ----------
# 只做规则候选召回，不调用 LLM，便于先检查覆盖范围。
sv-v0-candidates:
	$(MANAGE) sv-v0 --stage candidates --candidate-limit $(or $(LIMIT),50000)

sv-v0-reddit-candidates:
	$(MANAGE) sv-v0 --source reddit --stage candidates --candidate-limit $(or $(LIMIT),50000) --reddit-author-limit $(or $(AUTHORS),1000) --reddit-since-days $(or $(DAYS),365) --reddit-min-author-posts $(or $(MIN_POSTS),8)

# 混合版：规则召回 + LLM 结构化 + 价格结算 + SV 打分 + 前端 JSON 导出。
# 可覆盖参数：make sv-v0 LIMIT=50000 EXTRACT=2000 WORKERS=4
sv-v0:
	$(MANAGE) sv-v0 --stage all --candidate-limit $(or $(LIMIT),50000) --extract-limit $(or $(EXTRACT),1000) --workers $(or $(WORKERS),4)

# 生产级 v0：扩大候选池后，按作者均衡分配 LLM 额度，避免少数高互动/多 ticker 作者吃掉样本。
# 可覆盖参数：make sv-v0-prod LIMIT=50000 EXTRACT=10000 MIN=20 MAX=80 WORKERS=4
sv-v0-prod:
	$(MANAGE) sv-v0 --stage all --candidate-limit $(or $(LIMIT),50000) --extract-limit $(or $(EXTRACT),10000) --extract-mode author-balanced --per-author-min $(or $(MIN),20) --per-author-max $(or $(MAX),80) --workers $(or $(WORKERS),4)

private-sv-telegram:
	$(MANAGE) private-sv-telegram --handle $(or $(HANDLE),ruiminginvest) --stage $(or $(STAGE),all) --workers $(or $(WORKERS),4) $(if $(PROXY),--proxy $(PROXY),)

sv-v0-reddit-prod:
	$(MANAGE) sv-v0 --source reddit --stage all --candidate-limit $(or $(LIMIT),50000) --extract-limit $(or $(EXTRACT),10000) --extract-mode author-balanced --per-author-min $(or $(MIN),10) --per-author-max $(or $(MAX),50) --workers $(or $(WORKERS),4) --reddit-author-limit $(or $(AUTHORS),1000) --reddit-since-days $(or $(DAYS),365) --reddit-min-author-posts $(or $(MIN_POSTS),8)

# 标的级 SV 信号：历史时点作者百分位 → 7 天观点聚集 → 下一交易日开盘后的多周期回测。
# 可局部重建：make sv-ticker-signals ONLY=MU,NVDA
sv-ticker-signals:
	$(MANAGE) sv-ticker-signals $(if $(ONLY),--only $(ONLY),) --window-days $(or $(WINDOW),7) --min-authors $(or $(MIN_AUTHORS),3) --consensus-threshold $(or $(CONSENSUS),0.65) --effective-voices $(or $(EFFECTIVE),2.5)

# SV 发现页四类指标：历史平台内 Top/Bottom 10% → 事件化 → 下一交易日开盘多周期回测。
sv-indicator-backtest:
	$(MANAGE) sv-indicator-backtest $(if $(ONLY),--only $(ONLY),) --windows $(or $(WINDOWS),$(SV_INDICATOR_WINDOWS)) --source-scopes $(or $(SOURCES),$(SV_INDICATOR_SOURCES)) --report $(or $(REPORT),data/reports/sv_indicator_backtest.csv)

sv-indicator-report:
	$(MANAGE) sv-indicator-report --report-dir $(or $(REPORT_DIR),data/reports)

# 子 SV 垂直集中回测：历史周期/赛道/投资类型排名 → 滚动事件 → 匹配周期超额。
sv-segment-backtest:
	$(MANAGE) sv-segment-backtest $(if $(ONLY),--only $(ONLY),) --windows $(or $(WINDOWS),$(SV_SEGMENT_WINDOWS)) --sources $(or $(SOURCES),x) --segment-types $(or $(SEGMENTS),$(SV_SEGMENT_TYPES)) --rank-bands $(or $(BANDS),$(SV_SEGMENT_BANDS)) --report $(or $(REPORT),data/reports/sv_segment_backtest/sv_segment_backtest.csv)

# X-only SV portfolio CAGR: collective point-in-time signals and per-author portfolios.
sv-portfolio-backtest:
	$(MANAGE) sv-portfolio-backtest --windows $(or $(WINDOWS),1,3,7,14,30) --holding-days $(or $(HOLDING),1,5,20,60,90,180) --position-modes $(or $(MODES),long_short,long_only,short_only) --report-dir $(or $(REPORT_DIR),data/reports/sv_portfolio_backtest)

sv-rank-event-research:
	$(MANAGE) sv-rank-event-research --report-dir $(or $(REPORT_DIR),data/reports/sv_portfolio_backtest)

# ---------- Web ----------
web-install:
	cd web && npm install

web-dev:
	cd web && npm run dev

# 构建静态产物（web/out/），可部署到任意静态托管。见 DEPLOY.md
site:
	cd web && npm run build
	@echo "" && echo "✅ 静态产物已生成：web/out/  —— 见 DEPLOY.md"

# 本地部署：把静态产物跑在 http://localhost:8080（如无产物会先构建）
serve:
	@[ -d web/out ] || $(MAKE) site
	@echo "🌐 本地部署： http://localhost:8080   (Ctrl+C 退出)"
	@python3 -m http.server 8080 --bind 0.0.0.0 --directory web/out

# Cloudflare Pages：本地用 Node 22 读 dev.db 构建静态产物，再用 Wrangler Direct Upload 发布。
# 当前产品只部署 zh/en；web/out 里若有 ja/ko 历史产物，会先排除到临时目录，避免上传体积过大。
# 首次使用前需要：npx wrangler login。项目名默认 prismo，可用 PROJECT=xxx 覆盖。
cf-deploy:
	NEXT_BUILD_CPUS=$(or $(CPUS),1) $(MAKE) site
	rm -rf /tmp/prismo-out-cf
	rsync -a --exclude='/ja/' --exclude='/ko/' web/out/ /tmp/prismo-out-cf/
	npx wrangler pages deploy /tmp/prismo-out-cf --project-name $(or $(PROJECT),prismo) --branch main --commit-dirty=true

# ---------- 云端数据库（Supabase = 数据的家）----------
# 前提：.env 里 DATABASE_URL 已设为 Supabase 的 Postgres 连接串（见 CLOUD_DB.md）。
# 一次性迁移：在云端建表 + 上传本地 dev.db 的源数据 + 在云端重算派生表（榜单/情绪/异动/叙事/简报）。
cloud-init:
	$(MANAGE) cloud-push
	$(MANAGE) rollup --market all
	$(MANAGE) mood --market all
	$(MANAGE) trending --market all
	$(MANAGE) narratives --mock --market all
	$(MANAGE) brief --mock
	@echo "" && echo "✅ 云端初始化完成：Supabase 已成为数据的家。日常用 make daily，出站用 make site-cloud。"

# 把本地 dev.db 的源数据（帖子/评论/作者/AI 分析/提及/字典）上传到云端（增量、可重复跑）。
cloud-push:
	$(MANAGE) cloud-push

# ⚠⚠ Prismo 现以**本地 data/dev.db 为唯一真源**（含 gr_*/yt_*/kol_* 等云端没有的独有层）。
# 云端 Supabase 是 redditalpha.xyz 的 Reddit 核心（+ 只读 tw_* X 数据）。两站互不干扰。
# cloud-pull 会用云端快照「全新覆盖」本地 → 抹掉 Prismo 独有层（这就是之前「数据消失」的元凶）。
# 故**默认拒绝执行**；万一确需从云端重建，先 backup-db 再 FORCE=1。
cloud-pull:
	@if [ -z "$(FORCE)" ]; then \
	  echo "⛔ cloud-pull 会用云端快照覆盖本地 dev.db、抹掉 Prismo 独有的 gr_*/yt_*/kol_*（云端没有它们）。"; \
	  echo "   Prismo 以本地 dev.db 为真源；redditalpha.xyz 才用云端。"; \
	  echo "   确需执行：make backup-db && FORCE=1 make cloud-pull"; \
	  exit 1; \
	fi
	@$(MAKE) backup-db
	PRISMO_ALLOW_CLOUD_PULL=1 $(MANAGE) cloud-pull

# 事务一致地备份本地 dev.db 到项目外；默认只保留最近一份。
backup-db:
	@$(SYS_PY) scripts/data_snapshot.py backup --keep $(or $(KEEP),1)

# 生成 Railway/Docker 部署快照。原始 dev.db 不入 Git；压缩后 <=90MB 用单文件，
# 否则自动生成 24MB 普通 Git 分片和 manifest，且不会同时保留两份压缩副本。
snapshot-db:
	@$(SYS_PY) scripts/data_snapshot.py snapshot

# 从仓库压缩快照还原本地库。会覆盖现有 dev.db，必须显式 FORCE=1。
restore-db:
	@if [ -z "$(FORCE)" ]; then \
	  echo "⛔ restore-db 会覆盖 data/dev.db；确认后执行 FORCE=1 make restore-db"; \
	  exit 1; \
	fi
	@$(SYS_PY) scripts/data_snapshot.py restore --force

# 清理项目内旧备份/抽帧缓存，并安全截断 SQLite WAL；不删除 dev.db。
data-clean:
	@$(SYS_PY) scripts/data_snapshot.py cleanup

data-status:
	@$(SYS_PY) scripts/data_snapshot.py status

# 出站构建：Prismo = 本地真源，**不再 cloud-pull**。保留 site-cloud 名字（防 muscle-memory 误清）= 等同 make site。
site-cloud:
	@echo "ℹ️  Prismo 以本地 dev.db 为真源 → site-cloud 不再从云端拉取（避免抹掉本地独有层），等同 make site。"
	@$(MAKE) site

# clean 只清构建缓存；**绝不删 data/dev.db**（它现在是不可再生的真源）。
clean:
	rm -rf web/.next web/out
	@echo "ℹ️  已清 web/.next + web/out。（dev.db 是真源，未动；要删请手动并先 make backup-db）"
