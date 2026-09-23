# 三小时内容发布

2026-09-23：周期入口 `make content-delivery` 包含 YouTube、Reddit、Telegram 新频道文件同步及 X 已登记包。Telegram Bot Token 未配置前只处理原有来源；小于 20 MB 的文件默认使用公共 Bot API，无需本机 Bot API，详见 [Telegram X 数据包自动接收](telegram-x-delivery.md)。
来源流程见 [YouTube / Reddit 管道](social-content-delivery.md)，以下 X 单独命令仍可用。

本机接收并处理包，Supabase 提供内容，App 在前台约每 60 秒检查版本。
Codex 当前任务已配置每 3 小时唤醒；本机及 Codex 必须可运行。此机制不承诺
电脑睡眠/关机时仍准点处理，也不是服务器每 3 小时自动采集新帖子。

## 接收与登记

收到完整 ZIP/JSONL 后登记；记录保存在忽略 Git 的 `data/inbox/x`，不额外复制原包。
未完成上传的文件不要登记。提供文件给助手时，由助手执行：

```sh
make x-delivery-enqueue PACKAGE='/absolute/path/package.zip' WORKERS=2 MAX_CALLS=1000
```

默认生成全文翻译；用户指定跳过时使用 `SKIP_TRANSLATION=1`。`MAX_CALLS` 是候选上限，
不会自动扩大。队列沿用原 x-daily 处理逻辑，只处理本包阅读内容；已有旧运行若选项不同，
会要求人工核对，不静默改为别的处理范围。

```sh
make x-delivery
```

每次唤醒只处理时间最早的一个待办包；没有包为 idle，重叠执行为 busy。
按包内容哈希去重，已验证的包不重复发布。正常增量包需在下一轮前完成；首次补历史
可能耗时更久，不能把调度频率当作处理耗时保证。

## 保护与故障恢复

- 全队列及原日更库分别加锁；相同数据库不会并行处理。
- 原包重验哈希；超过 96 小时的包自动任务拒绝，不冒充新内容。
- 启动处理前至少 4 GiB 空闲；主数据库及用户提供的原包不自动删除。Telegram 自动同步的本地原包仅在数据库发布校验成功后删除，频道原件不删除。
- 模型处理整组进程上限 150 分钟；发布和数据库复核各上限 10 分钟。
- 数据库连接上限 10 秒、单 SQL 30 秒、发布锁等待 10 秒。
- 临时故障下次唤醒续跑，最多三次；永久输入错误或重试耗尽标为 needs_attention。
- 统一命令把任何来源的 `retry`、`needs_attention` 或锁冲突汇总为失败退出码；未解决的 X 队列阻断不再显示为 `idle`，供三小时任务告警。无新内容的正常 `unchanged`/`idle` 仍成功退出。
- 只有发布完成且八个集合集合数量/哈希及数据库页内容一致，才记 verified/databaseVerified。
- 回执的 publicAPIVerified 仍为 false；不能替代真实 App 的用户鉴权与解码验收。
- 原 x-daily 临时目录正常退出时自动清理；队列日志完成后各限制为最近 1 MiB。
- 云端当前指针只在原子发布完成后切换；失败保留原版本，不自动回滚别人的更新。

`needs_attention` 需处理原因后通过 `python -m pipeline.manage x-delivery --retry-package <sha256> --retry-reason <说明>`
显式重新入队；队列保留累计尝试次数及重试原因，不自动无限重试。
不要无上限自动反复调用模型。云端版本在三来源统一周期中按 48 小时宽限期及最近 4 版、当前版、基线保护规则清理；
仅删除重复的不可变快照，不删除当前集合中的旧观点。

## 真实设备验收

1.0 (9) 的默认内容后端为 Supabase；Supabase 构建在从桌面图标启动时也保持 live；普通 bSmart scheme 同样启用 live，
bSmart Local 显式保留 legacy 供本地 API 开发，测试指定 fixture 的行为不变。
设备在真实登录后成功解码全部主集合，会原子写入
`Library/Application Support/ContentVerification.json`，仅含内容版本、时间和数量，无账号、令牌或正文。
此文件可用于核对同一设备发布前后版本，不代表读取了全部按需历史证据。

用户已明确授权使用旧包测试。仅本次人工操作可传 `--historical-test`，保留原始 asOf/sourceThrough，
跳过鲜度限制但保留排序、引用、哈希、25% 缩减保护，不派发推送；自动队列绝不启用此选项。

```sh
services/client_api/.venv/bin/python -m services.client_api.content_release --input-dir /reviewed/release --historical-test
# 人工审查校验输出后再加 --apply
```

发布器只保留 `data/runtime/content-cache/current.json` 一份可重建快照。使用前与线上
manifest 的每个集合哈希/数量核对；缓存损坏或版本不同会回退数据库分块读取。
数据库验证会将每一页和预期 JSONB 比较并检查总页数，因此不是只相信本地缓存。
日更导出缺少旧代表作不代表已删除：仍在新作者集合中的历史 X 证据按 ID 合并，新内容覆盖同 ID，
移出作者集合的孤立证据不保留。25% 缩减闸门继续生效，正式删除需单独治理流程。

## 本次验收

1.0 (9) 已安装到连接 iPhone。真实登录前后两个内容版本在同一安装构建中切换成功：
267 → 737 条观点，353 → 349 位作者。旧包测试不代表获得今日新帖子。
验证回执位于 data/runtime/content-delivery-acceptance/，不含用户令牌。
本次本地回归：26 项队列/日包测试、27 项内容发布/配置/校验测试、22 项原生内容/工厂测试通过。
