# YouTube / Reddit 三小时增量更新

`make content-delivery` 是三来源周期入口：先运行 YouTube、Reddit，再检查已登记的 X 包。
现有 `bsmart` heartbeat 每三小时运行，依赖 Mac 和 Codex 可运行；并非云端独立 cron。
单独运行：`make social-delivery SOURCE=youtube` 或 `SOURCE=reddit`。

## 来源和覆盖

- YouTube：现有版本化作者池（目前 500 频道）；官方 channels + uploads playlistItems + videos API，
  不使用全站 search。频道查询确认不可用的 ID 单列在 raw 回执，保留其旧内容；可用频道低于 90%
  阻断发布。分页上限、视频详情缺失、网络/配额错误均失败，不把截断当作完整。
- Reddit：用户选择公开爬虫；直连公开 JSON 实测 403，使用项目已有 Arctic Shift 公开镜像。
  采集配置中的美股板块及既有评分作者。镜像不等于 Reddit 实时接口，运行前检查活跃板块
  最近三小时是否有帖子；这只是可观察的新鲜度门禁，不能证明镜像完整收录全部帖子。
  HTTP 429/5xx，以及实测偶发的 422 最多三次退避；分页重叠边界秒、按 ID 去重，停滞或超限阻断。

首次只取最近六小时；成功后从上次截止时间向前重叠三小时补迟到数据。
错过多个周期时每轮最多向前追六小时；离线超过七天要求人工补历史，避免静默跳过缺口。镜像迟到超过重叠窗口仍可能漏收，
长期稳定性需要持续监测来源延迟与多轮结果，不宣称零遗漏。

## 分层与处理

平台模块 `pipeline/platforms/{youtube,reddit}/incremental.py` 负责真实采集、标准化和原始事实写入。
任务位于 `pipeline/jobs/social_delivery`，CLI 仅注册参数。
共用 `data/.x-daily.lock`，子进程继承锁；同一本地 SQLite 真源串行更新，不执行 DDL。

已有 Score 模块复用完整正文提取、真实日线、结算与平台评分，不修改评分公式。
YouTube 观点抽取按既有正式榜单的 Top 25% 作者进行；全部选中频道仍做元数据增量收集。
只分析本次观察到的 ID，单次最多 300 个待处理候选；超过预算失败，不自动扩大。
YouTube 最多 30 个待补视频，沿用配置中的每天 420 分钟原生视频预算，优先字幕，无截图、无抽帧。
缺少完整口播文本、双语观点或有效行情时不得发布。原文与模型观点分开，缺失译文保持为空。

处理阶段写断点：crawl → ingest → analysis → prices → settle → score → export。Reddit crawl 还在
`crawl-checkpoint.json` 中按板块/作者保存已完成查询，同一窗口四小时内重试时从断点继续；
镜像健康检查每次仍重新执行。跨窗口或过期检查点不能复用。
失败下一轮续跑原窗口；三次失败后 `needs_attention`。先修复原因、审阅日志，再人工登记重试，
自动任务不得无限重置。成功发布但回读失败时沿用同一发布哈希复核，不重复生成内容。

## 发布与客户端

`platform-manifest.json` 包含来源、采集窗口、实际最新帖子时间、完整性和三个集合的哈希/数量。
`services/client_api/content_release/partition.py` 校验契约和平台身份；发布器在既有 Supabase
事务锁中合并对应平台，保留其他平台、旧观点和历史证据。交易、理论、点赞及用户表不在此链路中。
组合信号使用实际平台名称和独立稳定 ID，不再把 YouTube / Reddit 标成 X。

指针只在完整校验和提交后切换；随后回读全部集合校验。`databaseVerified` 不是设备验收。
App 沿用已接通的 Supabase 内容源，前台刷新，无需重新发版。

## 时间、磁盘与状态

- 每平台处理子进程最多 25 分钟，发布/复核各最多 10 分钟；X 周期内处理 35 分钟、发布/复核各 10 分钟。
  总预算约 145 分钟，预留三小时周期余量。超时保留断点，不能将调度频率当作新内容完成时间保证。
- 至少 6 GiB 空闲才启动；固定 `data/runtime/social-delivery/<source>/` 保存当前状态、原始抓取、导出和回执，
  下一成功周期复用，不复制本地大数据库、不持久化视频文件。日志保留上限 1 MiB。
- 云端完整版本在统一周期的新发布完成数据库校验后执行保留清理：当前版本、最初基线、最近 4 个版本及 48 小时内的版本受保护；只删除更旧的重复快照页与版本记录，不涉及用户、交易或观点真源表。清理失败单独报告，不把已验证发布误判为失败。操作前可运行 `services/client_api/.venv/bin/python -m services.client_api.content_release.retention` 预览。实际数据库文件空间回收由 PostgreSQL 自动清理机制决定。
- `retry` / `needs_attention` 保留线上最后成功内容。没有新帖与采集失败必须区分。

接口参考：[YouTube 上传列表](https://developers.google.com/youtube/v3/docs/playlistItems/list)、
[Arctic Shift 项目](https://github.com/ArthurHeitmann/arctic_shift)。

## 2026-09-23 实际验收

统一入口连续接续到下一三小时窗口：YouTube 和 Reddit 均在一次任务尝试内完成采集、处理、发布与
Supabase 全量回读，X 队列空闲；最新合并版本为
`bcbc1835c760683e4dcf876105659b40634fc908647748e8459f54bca2119046`。
连接的 iPhone 在真实登录状态下自动加载到该版本，回执记录 411 位作者、761 条观点，
位于 `data/runtime/content-delivery-acceptance/social-20260923.json`。
云端清理检查本轮保留 9 个受保护版本、删除 0 个；本机运行目录约 10 MiB。
以上证明连续实际周期及设备读取成功，不构成镜像长期可用率或离线 Mac 仍可自动执行的保证。
