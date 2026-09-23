# Telegram X 数据包自动接收

状态：2026-09-23 已完成一份真实频道 ZIP 的接收、筛选、模型翻译、Supabase 发布和数据库回读校验；App 前台刷新与后续定时运行仍需观察。

## 来源与授权

来源为 Telegram 频道 `https://web.telegram.org/k/#-4310606552`。由频道管理员创建一个专用 Bot 并加入频道管理员列表；Bot 只接收加入后产生的 `channel_post`。不需要发帖或删除频道消息的权限。Telegram Bot API 待处理 updates 最多保留 24 小时，现有 Bot 接口不能回填频道历史；缺口需要人工提供原包，不能假装无缺口。

Bot Token 只写入 Git 忽略的根 `.env` 的 `TELEGRAM_BOT_TOKEN`，绝不写入日志、文档、提交或聊天。频道 ID 默认为 `-1004310606552`。已经在聊天中披露的 Token 应先通过 BotFather 轮换，再配置新 Token；不要把新值发到聊天。普通 Bot API 不需要 Telegram API ID/Hash。

## 接收配置

Telegram 公共 Bot API 的 `getFile` 下载上限为 20 MB。频道截图中可见 ZIP 为 1.8 MB、2.1 MB、8.9 MB，因此默认直接使用 `https://api.telegram.org`，只需 Bot Token，不需要 Docker 或 API ID/Hash。配置后运行：

```sh
make telegram-x-sync
```

未来若某个文件超过 20 MB，接收任务会明确返回 `telegram_local_api_required`，不会尝试调用远端 `getFile`。此时才需在本机 `.env` 配置 `TELEGRAM_API_ID`、`TELEGRAM_API_HASH`、`TELEGRAM_BOT_API_URL=http://127.0.0.1:8081` 和 `TELEGRAM_LOCAL_FILES_DIR=./data/runtime/telegram-bot-api`，启动 Docker Desktop 并运行 `make telegram-bot-api-up`、`make telegram-bot-api-cutover`。`cutover` 调用官方远端 `logOut`，之后该 Bot 由本机服务接收更新。不要同时设置 webhook 或在别的机器上消费相同 Bot 的 updates。

## 工作流

现有三小时 `make content-delivery` 先同步一份频道 ZIP/JSONL，接着处理 X 队列中最早的待办包。只识别目标频道文档，不处理聊天文本或其他频道。`data/inbox/telegram/state.json` 保存 Telegram update offset；接收、筛选、入队成功后才前进，避免下载失败导致漏包。内容哈希在 X 队列去重，故重复同步不重复发布。

交付 ZIP 可包含 `tweets.jsonl` 或 `tweets_*.jsonl`；清单、README 和 roster 是旁车文件，不作为观点输入。每条推文仍需通过既有字段和时间校验。只读 Telegram 请求有有限重试，超过重试次数仍保持失败可见。

2026-09-23 验收：频道文件 `bsmart_Xtweets_ExT_f3000_r2897_260922_23Z_p1of1_260923v3.zip`（662,653 字节）含 237 条推文，前 25% 排名筛出 4 条，其中 1 条形成通过完整翻译校验的观点。发布 revision `a30354a54712f7af8970307283980ec56ffd06d83ee3a5c6cbee74c4b2feb759` 的 `databaseVerified=true`；自动下载的 ZIP 与筛选文件随即清理，频道原件未动。`publicAPIVerified=false`，尚不代表 App 前台已验收。首次发布被历史标的 ATAI 的过期行情阻断；[Nasdaq 公司行动公告](https://www.nasdaqtrader.com/TraderNews.aspx?id=ECA2026-633)证实它于 2026-09-10 最后交易，本地 `ticker_meta.is_active` 已设为 0，不补造价格。

在任何新帖提炼前，先检查 `data/inbox/x/ranking-snapshot.json`：存在时只使用其中固定的旧版 Top 25% 作者 ID，不重新评分；尚未建立快照时才按本机正式 `sv_investor_score` 的 X 合格作者排序取前 `ceil(25%)`。只把入选作者原帖写入衍生包，不改源包。每包保留源哈希、原帖数、选中帖数、排名时间及作者 ID 集合。之后沿用 `x-daily` 的 Qwen 观点抽取、完整原文翻译、摘要、评分、质量检查和 Supabase 发布；`skipTranslation=false`。固定名单不代表新作者会自动进入前 25%；需要更新排名口径时，应单独评审，不能暗中放宽。

手动补齐机器人加入前的历史 ZIP，先用已验收的接收回执冻结名单，再为每份原包生成最多 900 行的工作包：

```sh
pipeline/.venv/bin/python -m pipeline.jobs.x_delivery.prepare_ranked \
  --freeze-from data/inbox/telegram/759681548.json --package '/absolute/path/to/archive.zip'
```

后续包省略 `--freeze-from`；命令对同一原包/名单幂等，输出在 `data/inbox/x/manual/<sourceHash>/`，不删除或覆盖用户原包。逐个使用 `make x-delivery-enqueue PACKAGE='<part path>'` 入队；X 队列按包截止时间串行处理，三小时入口每轮最多处理一包。工作包超过每包调用预算时不得自动扩大预算。

`TELEGRAM_X_MAX_CALLS` 默认 1000，是本包模型候选数量上限，不是人民币预算。超限、老包超过现有 96 小时鲜度门禁、翻译失败或其他处理错误都会保持队列待处理或 `needs_attention`，不能当作已发布。实际模型费用取决于候选帖数及 Qwen 计价，需要上线后按调用量监控。

**仅当 X 队列回执为 `verified` 且 `databaseVerified=true` 后**，清理此任务记录的本地原 ZIP/JSONL、筛选包及可选的 Local Bot API 下载缓存；清理前核对路径、设备、inode 和文件大小。不会删除 Telegram 频道里的文件、用户另存的原件、其他任务数据、数据库或已发布内容。无入选帖的包完成筛选后可立即清理本地副本。失败最多自动尝试 3 次，随后需排障并运行 `make telegram-x-retry`。运行日志与状态在 `data/inbox/telegram` 和 `data/inbox/x`。

## 验收

1. 确认 Bot 已加入正确频道，轮换后的 Token 可在本机 `.env` 加载；仅超过 20 MB 时才需验证 Docker 服务。
2. 在频道发送一份含已排名作者帖子的小型测试 JSONL，运行 `make telegram-x-sync`；核对 `selectedRows` 和 X 队列 `skipTranslation=false`。
3. 运行 `make content-delivery`，查验真实 Qwen 处理、全文翻译、发布回执及数据库校验。发布失败时本地原件必须保留。
4. 数据库 `verified` 后确认本地原件及可选 Bot 缓存仅按本任务记录被清理，App 同一安装版本能在前台刷新到新内容。

只做了单元测试时，第 2–4 步不可标记通过。
