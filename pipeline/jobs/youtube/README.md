# YouTube Jobs

`pipeline.jobs.youtube` 是 YouTube 工作流入口层。

当前它通过 platform/domain 适配层封装了旧实现：

- `pipeline.platforms.youtube`
- `pipeline.domain.opinions.youtube`
- `pipeline.domain.target_prices.youtube`
- `pipeline.domain.authors.youtube`

YouTube Score 作者池的正式流程由以下边界组成：

- `pipeline.domain.authors.youtube_pool`：构建版本化 500 人 creator pool，并隔离媒体号。
- `pipeline.platforms.youtube.uploads`：按 uploads playlist 回填一年视频、保存 checkpoint，并只补齐相关视频的互动指标。
- `pipeline.domain.tickers.youtube_uploads`：以版本化高精度规则建立视频到 ticker 的多对多映射。
- `pipeline.domain.smart_voice.youtube_transcript_calls`：完整口播分段、YouTube 专用 Call 标签和视频内冲突合并。
- `pipeline.domain.smart_voice.v0_impl`：按作者均衡建立口播队列，并把口播验证后的 Call 交给共享结算和评分内核。

常用命令：

```bash
python -m pipeline.manage youtube-author-pool --target-size 500 --since-days 365
python -m pipeline.manage youtube-author-backfill --since-days 365 --workers 8
python -m pipeline.manage youtube-author-map --force
python -m pipeline.manage youtube-author-hydrate --min-confidence 0.90
python -m pipeline.manage youtube-tag --only MU,MSTR,NVDA --since-days 31 \
  --min-subscribers 2000 --min-duration-seconds 60 --workers 8
python -m pipeline.manage youtube-tag --only MU,MSTR,NVDA --since-days 31 \
  --min-subscribers 2000 --min-duration-seconds 60 --transcript-only --workers 4
python -m pipeline.manage sv-v0 --source youtube --stage candidates --candidate-limit 0
python -m pipeline.manage sv-v0 --source youtube --stage transcripts \
  --extract-limit 10000 --extract-mode author-balanced \
  --per-author-min 20 --per-author-max 40 --workers 4
python -m pipeline.manage sv-v0 --source youtube --stage extract \
  --extract-limit 10000 --extract-mode author-balanced \
  --per-author-min 20 --per-author-max 40 --workers 4
```

观点分析会对非头部视频优先读取已有 `yt_fulltext` 完整口播，其次尝试在线字幕，均不可得时才提交
低清原生视频。标题/简介生成的 `mode=text` 记录不会设置 `yt_video.analyzed`，后续仍会被 Gemini
口播/视频理解升级。

`scripts/run_youtube_sv_transcript_migration.sh` 默认使用 Gemini 付费模式：
`TRANSCRIPT_DAILY_MINUTES=0` 会关闭迁移任务本地的每日视频分钟限制。需要控制成本时，
可为该变量设置正整数；这一设置仅作用于迁移进程，不改变其他 YouTube 任务的预算。
迁移按作者均衡分批执行，默认每批 250 个视频且每次执行一批。可通过
`TRANSCRIPT_BATCH_SIZE` 和 `MAX_TRANSCRIPT_BATCHES` 调整；每批都会重新抽取 Call 并检查
300 位合格作者门槛，达到门槛后不再提交新视频。
`TRANSCRIPT_REQUEST_INTERVAL` 默认设置为 3 秒，用于约束付费 API 的进程级请求启动频率；
遇到 429 时，所有工作线程会共享 Google 返回的冷却窗口，避免并发重试风暴。
Score 迁移默认使用 `gemini-3-flash-preview`，并优先获取完整 YouTube 字幕后交给 Gemini
逐段翻译和结构化；字幕不可得时才回退到原生视频理解。其他需要关键画面还原的 YouTube
任务仍保持原有的视频优先流程。
脚本使用 PID 锁保证同一时间只有一个 YouTube Score 迁移实例，避免重复请求 Gemini 和并发写入
SQLite；进程异常退出后，下次执行会自动清理失效锁。

交互式视频配额不足时，使用独立配额的 Gemini Batch API：

```bash
PYTHONPATH=. pipeline/.venv/bin/python scripts/run_youtube_sv_batch.py --limit 500
```

脚本会保存 Batch 资源名、轮询任务、幂等回写 `yt_fulltext`，随后继续 Call 抽取。进程中断后可用
输出的 `--name batches/...` 恢复收集；`--submit-only` 仅提交而不等待。

发布包含两道门槛：至少 300 位作者拥有 5 条口播验证的可操作 Call；正式结算后还必须至少
300 位作者同时满足 `n_eff >= 4` 和 `settled_calls >= 5`。第二道门槛未通过时禁止导出产品数据。

CLI 不应直接导入旧 `ingest/analyze` 实现。后续拆分时，抓取和作者元信息应继续沉淀到 `pipeline/platforms/youtube`，观点分析、摘要、判断参数应继续沉淀到 `pipeline/domain/opinions` 和 `pipeline/domain/target_prices`。
