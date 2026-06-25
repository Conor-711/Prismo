PY := pipeline/.venv/bin/python
PIP := pipeline/.venv/bin/pip
MANAGE := $(PY) -m pipeline.manage

.PHONY: install venv db-init migrate seed seed-cn sample ingest refresh extract analyze analyze-mock \
        rollup narratives brief worker daily daily-build cn-backfill demo stats test web-install web-dev clean help \
        asia asia-mock mindshare-dashboard

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
	@echo "  make daily         分析过去 24 小时（一天一次；UTC+8 08:00 跑）"
	@echo "  make daily-build   分析过去 24h 并重建静态站点（web/out）"
	@echo "  make migrate       已有库迁移到带 market 维度（幂等）"
	@echo "  make seed-cn       seed 中概/港股/A 股字典"
	@echo "  make cn-backfill   回填中概·港股语料（爬30天+AI打标+双market聚合+翻译）"
	@echo "  make worker        启动调度：每天 UTC+8 08:00 自动跑 daily-build"
	@echo "  make mindshare-dashboard  从 SQLite + 可选 forum_mindshare.json 生成纯 HTML 实验面板"
	@echo "  --- Web ---"
	@echo "  make web-install   安装前端依赖    make web-dev  启动 Next.js"

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
	-$(PY) -m pipeline.analyze.translate
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

# ---------- 亚洲散户舆情实验（日本 Yahoo + 韩国 Naver；隐藏页 /[lang]/lab/asia-pulse）----------
# 爬日韩本土散户板对 NVDA/美光/海力士的讨论，沿用现有架构做真实 AI 分析（千问逐帖 + DeepSeek 汇总）。
# 隔离表 asia_*，不污染 us/cn。KR 海外股(NVDA/MU)需先把 cbox objectId 填进 pipeline/data/asia_targets.yml。
asia:
	$(MANAGE) asia-crawl --per-board 200 --since-days 7
	$(MANAGE) asia-score
	$(MANAGE) asia-analyze --limit-per 12
	$(MANAGE) asia-summarize
	$(MANAGE) asia-price
	@echo "" && echo "✅ 亚洲看板完成。出站：make site（读 dev.db 渲染隐藏页 /lab/asia-pulse）。"

# 全球散户多区看板：日韩台爬精选跨区美股 + DeepSeek flash 打标 + 跨区滚动(US 读现有 Reddit)。
# 隔离表 gr_*，隐藏页 /lab/global-retail。本地跑：DATABASE_URL='sqlite:///./data/dev.db' make gr
gr:
	$(MANAGE) gr-crawl --per-board 120 --since-days 14
	$(MANAGE) gr-tag
	$(MANAGE) gr-rollup
	$(MANAGE) gr-quote
	@echo "" && echo "✅ 全球散户看板完成。出站：make site（读 dev.db 渲染隐藏页 /lab/global-retail）。"

# 仅刷新各标的最新价（Yahoo 15m chart → gr_quote），供标的页展示最新价/涨跌幅。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make gr-quote
gr-quote:
	$(MANAGE) gr-quote

# YouTube 观点：按标的搜近 24h、浏览量>1000 的视频（全语种）→ Gemini 混合分析 → 标的页模块。
# 需 YOUTUBE_API_KEY + GEMINI_API_KEY。无 key 验证：make youtube-mock
youtube:
	$(MANAGE) youtube-crawl --since-hours 24
	$(MANAGE) youtube-tag --top-native 2
	@echo "" && echo "✅ YouTube 观点完成。出站：make site（标的页「YouTube 观点」模块）。"

# 零成本版（多语种样本，无需 YouTube/Gemini key）——验证 schema 与看板渲染
youtube-mock:
	$(MANAGE) youtube-crawl --mock
	$(MANAGE) youtube-tag --mock

# KOL 个体观点 AI 提炼+双语：把 reddit/x/雪球 照搬的原文 → 「为什么看多/看空 + 2-3 要点」(zh/en) → kol_refined。
# 只提炼每标的每源 top-N(默认 20)；增量(只补未提炼)。YouTube 复用 yt_analysis 无需在此。需 DEEPSEEK_API_KEY。
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

# KOL 论点综合：把已分类观点(kol_refined+kol_viewpoint+yt_analysis) → 每 标的×视角×立场 聚成 1-3 个论点 → kol_argument。
# 增量(只补未综合的组)；单条观点的组不花 LLM。需 DEEPSEEK_API_KEY。先跑 kol-refine + kol-viewpoint 再跑本目标。
# 本地：DATABASE_URL='sqlite:///./data/dev.db' make kol-argument
kol-argument:
	$(MANAGE) kol-argument
	@echo "" && echo "✅ KOL 论点综合完成。出站：make site（标的页 KOL 模块『按视角』下的论点）。"

# KOL 原帖完整忠实翻译（逐句直译、不压缩）→ kol_refined.trans_zh/en。供『按视角·原帖流』的「译」选项。
# 与提炼解耦、可独立重跑；只译已展示(已提炼)的原帖。增量(只补未译)；需 QWEN_API_KEY。
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

# 零成本版（mock 启发式，无需 AI key）
asia-mock:
	$(MANAGE) asia-crawl --per-board 80 --since-days 7
	$(MANAGE) asia-analyze --limit-per 12 --mock
	$(MANAGE) asia-summarize --mock

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
	$(PY) -m pipeline.analyze.translate

# 仅给 demo 数据灌入一批中文译文（无需 API key，用于演示「看广告解锁翻译」）。
translate-demo:
	$(PY) -m pipeline.analyze.seed_demo_zh

# 让 AI 读懂帖子后重排版正文 → posts.selftext_fmt（提升可读性，需 ANTHROPIC_API_KEY）。
format:
	$(PY) -m pipeline.analyze.format_posts

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

# 从当前 SQLite 快照 + 可选 forum_mindshare.json 生成单文件实验看板：根目录 dashboard.html。
# 可用 python3 -m http.server 8787 --directory . 打开 /dashboard.html。
mindshare-dashboard:
	$(PY) experiments/build_mindshare_dashboard.py

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

# 从云端拉取最新数据，全新覆盖本地 data/dev.db 快照（供构建读取）。
cloud-pull:
	$(MANAGE) cloud-pull

# 从云端拉快照后再构建静态站点（web/out）。部署前用这个，保证页面是云端最新数据。
site-cloud: cloud-pull
	cd web && npm run build
	@echo "" && echo "✅ 已从云端拉取最新数据并构建 web/out/"

clean:
	rm -f data/dev.db
