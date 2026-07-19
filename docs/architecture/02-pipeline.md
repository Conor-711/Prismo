# Pipeline Architecture

Python 管线的目标边界是：平台接入、领域分析、任务编排、CLI 注册互相分离。

## 目标目录

```text
pipeline/
  cli/
    manage.py
    registry.py
    commands/
  platforms/
    reddit/
    x/
    youtube/
    xueqiu/
    toss/
    yahoojp/
    naver/
    ptt/
    market_data/
    author_assets/
  domain/
    opinions/
    authors/
    tickers/
    narratives/
    smart_voice/
    target_prices/
    translations/
  jobs/
    global_retail/
    ticker_detail/
    narrative_rotation/
    youtube_fulltext/
    smart_voice/
  common/
    config.py
    db.py
    llm.py
    logging.py
    models.py
    ticker_extraction.py
```

现有 `pipeline/ingest` 和 `pipeline/analyze` 只保留历史导入/命令路径兼容 wrapper。
新增功能优先落到目标目录；平台抓取、平台作者资产、市场数据采集的新实现必须落到 `pipeline/platforms`。

## 平台层

`pipeline/platforms/<platform>/` 只负责平台本身：

- 抓取、分页、鉴权、限速、重试。
- raw payload 保存。
- 平台字段到标准字段的基础映射。
- 平台作者元信息采集。

平台层不应该写 Smart Voice 排名、观点推荐、叙事归类等跨平台业务逻辑。

## 领域层

`pipeline/domain/<domain>/` 处理平台无关逻辑：

- `opinions`：观点清洗、翻译、质量、相关性、视角、摘要。
- `authors`：作者标准化、KOL 池、作者画像。
- `tickers`：标的目录、种子、价格、region/market 归属；基础 ticker 抽取在 `pipeline/common/ticker_extraction.py`，供 platform 和 domain 共用。
- `narratives`：固定叙事 taxonomy、内容归类、mindshare。
- `smart_voice`：SV 候选、结算、评分、导出。
- `target_prices`：目标价、操作周期、买卖点抽取。
- `translations`：内容翻译工作流。

## Job 层

`pipeline/jobs/<job>/` 是完整工作流编排：

- 读取配置。
- 调用一个或多个 platform/domain 模块。
- 负责断点续跑、批处理窗口、输出报告。
- 不直接写复杂平台解析或模型 prompt。

## CLI 层

CLI 只负责命令注册和参数解析。长期目标是把当前 `pipeline/manage.py` 拆成：

- `pipeline/cli/registry.py`
- `pipeline/cli/commands/global_retail.py`
- `pipeline/cli/commands/youtube.py`
- `pipeline/cli/commands/kol.py`
- `pipeline/cli/commands/smart_voice.py`
- `pipeline/cli/commands/narratives.py`

新增命令必须有对应 job/domain/platform 落点，不能把业务实现写在 CLI 函数里。

## 当前迁移状态

- `pipeline/manage.py` 已变成兼容入口，只转发到 `pipeline.cli.registry`。
- CLI 顶层 parser 已迁到 `pipeline/cli/registry.py`。
- CLI 命令适配与 argparse 子命令注册已按业务组拆到 `pipeline/cli/commands/`。
- YouTube 命令已迁到 `pipeline/jobs/youtube/workflows.py`，CLI 不再直接依赖 `pipeline/ingest/youtube_*` 或 `pipeline/analyze/youtube_*`。
- YouTube 抓取/频道刷新实现已迁入 `pipeline/platforms/youtube`，旧 `pipeline/ingest/youtube_*` 仅保留兼容 wrapper。
- X 推文与 ticker/topic 硬匹配、云端 X 拉取、完整 X ticker universe 已迁到 `pipeline/platforms/x`。
- YouTube 观点分析、完整口播、摘要、目标价判断、创作者综合观点实现已迁到 `pipeline/domain`。
- `youtube-tag` 支持按发布日期、频道订阅数和视频时长限制候选；非头部视频优先复用 `yt_fulltext` 完整口播或在线字幕，再回退原生视频理解。
- `pipeline/common/llm.py` 保留 LOW/MID/HIGH 默认路由，并支持通过 `LLM_PROVIDER=qwen|deepseek|gemini` 为一次任务显式切换 provider；Reddit 逐帖分析另按 `ITEM_ANALYSIS_PROVIDERS` 做真实 provider 回退。
- YouTube 进入观点流、目标价、相关性/质量和 KOL 日序列的展示门槛集中在 `pipeline/common/youtube_filters.py` 与 `web/server/queries/kol/shared.ts`：频道粉丝 `>=2000` 且视频时长 `>60` 秒。
- KOL 命令已有 `pipeline/jobs/kol` 工作流，CLI 不再直接调用 domain。
- KOL 观点提炼、视角分类、论点综合、完整翻译、相关性、质量评分实现已迁到 `pipeline/domain/opinions`。
- KOL 目标价/操作周期抽取实现已迁到 `pipeline/domain/target_prices`。
- Smart Voice 的 X 情绪打分、KOL/散户情绪/讨论度/新增参与者 rollup、整体信号导出、SV v0、价格历史回填已有 `pipeline/jobs/smart_voice` 工作流。
- 叙事轮动导出已有 `pipeline/jobs/narrative_rotation` 工作流。
- 全球散户多区抓取、打标、聚合、报价、Toss、雪球长期管道已有 `pipeline/jobs/global_retail` 工作流。
- 雪球 SV 作者池通过 `domain/authors/xueqiu_pool.py` 版本化筛选，`platforms/xueqiu/author_timeline.py` 负责已登录作者时间线分页与断点任务，`jobs/global_retail` 只做导入、规划、运行和关联标的扩展编排；长时间回填由 `gr-xueqiu-author-drain` 按小批次、正常冷却、失败指数退避和重试上限持续消耗正式池，并对 SQLite 写锁及中断后遗留的 `running` 游标任务自动恢复。
- Toss 社区抓取、全球散户多区抓取/浏览器雪球导入/报价、雪球 direct crawler 和雪球长期任务管道实现已迁入 `pipeline/platforms`，对应旧 `pipeline/ingest/*` 文件仅保留兼容 wrapper。
- 全球散户打标和聚合实现已迁到 `pipeline/domain/global_retail`。
- 核心历史命令已有 `pipeline/jobs/core` 工作流，覆盖数据库初始化、样本数据、Reddit 抓取、ticker 提取、市场聚合、每日任务、统计和云同步。
- Reddit / Arctic Shift 抓取、Reddit 近期刷新、作者池抓取实现已迁入 `pipeline/platforms/reddit`，旧 `pipeline/ingest/reddit_*` / `arctic_scrape.py` / `author_crawl.py` / `refresh.py` 仅保留兼容 wrapper。
- 本地样本数据实现已迁入 `pipeline/platforms/local`，旧 `pipeline/ingest/sample_loader.py` 仅保留兼容 wrapper。
- SV 价格历史回填与短窗口 `price_daily` 加载实现已迁入 `pipeline/platforms/market_data`，旧 `pipeline/ingest/sv_price_history.py` / `price_daily.py` 仅保留兼容 wrapper。
- 作者头像等跨平台作者资产刷新实现已迁入 `pipeline/platforms/author_assets`，旧 `pipeline/ingest/author_avatars.py` 仅保留兼容 wrapper。
- ticker 种子实现已迁到 `pipeline/domain/tickers`；基础 ticker 抽取实现已下沉到 `pipeline/common/ticker_extraction.py`，旧 `pipeline/domain/tickers/extraction.py` 与 `pipeline/ingest/ticker_extract.py` 仅保留兼容 wrapper。
- 通用帖文分析、内容翻译、市场信号、叙事聚类、叙事轮动、Smart Voice 信号与 SV v0 实现已迁到 `pipeline/domain`。
- `scripts/check_architecture.py` 已加入边界检查，`make arch-check` 可直接运行。
- 旧 `pipeline/analyze` 仅作为兼容 wrapper 保留；domain 禁止重新依赖 `pipeline.analyze`。
- 旧 `pipeline/ingest` 仅作为兼容区保留；新增平台实现不得回写旧目录。

## 迁移优先级

1. Compatibility cleanup：确认无人直接执行 `pipeline.analyze.*` 或旧 `pipeline.ingest.*` 后，再删除对应 wrapper。
2. Contract tests：为已迁入 domain 的 Smart Voice、KOL、YouTube、narrative 输出补充小样本回归测试。
3. Platform/domain coverage：持续补齐平台 wrapper 与 domain contract 的回归测试，避免后续重构破坏旧命令路径。
