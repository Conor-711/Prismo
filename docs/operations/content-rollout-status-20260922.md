# 内容免发版更新核查 — 2026-09-22

已实现主要链路，但尚未完成默认客户端切换与真实用户端到端验收。

| 环节 | 本次核实状态 |
| --- | --- |
| 日包处理 | `make x-daily` 已有校验、抽取、排名、阅读内容和导出；本地 9 月 16 日运行记录为 ready，未见该包发布回执 |
| Supabase 发布 | 数据库结构、版本发布器、bsmart-content 已准备；只读线上 active 返回 200，仍为 f862986a1e0907ba4a3bb433962f8a60fdb90271c4b60fa869a924acd85e6a06 |
| 线上内容 | 上述版本是 9 月 16 日准备的历史基线，不是 9 月 16 日新日包；回执 publicAPIVerified=false |
| iOS 数据源 | ios/project.yml 与生成工程均默认 BSMART_CONTENT_BACKEND=legacy；SupabaseContentClient 已实现，尚未默认启用 |
| 自动拉取 | BSmartApp 启动加载，前台约每 60 秒刷新；进入前台可检查。挂起或关闭时无准点刷新保证 |
| 自动上传触发 | 当前是提供文件后运行命令的工作流，没有“上传完成即触发全部处理发布”的常驻任务或上传后台 |

剩余步骤：

1. 使用真实 Google/Apple 登录测试账户，验收 Supabase 内容 manifest、分页、哈希及代表作；服务角色只读检查不能替代用户鉴权验收。
2. 准备一个新日包，经现有质量闸门发布到 Supabase；配置 BSMART_CONTENT_PUBLISH_TARGET=supabase，并确认旧 X 写入任务停用。旧包不能伪装成今日数据。
3. 将 App 内容后端切为 supabase，首次发布/安装这个版本。在同一个已安装版本上记录旧数据 → 发布新内容 → 回前台验证新数据，核对离线保留、失败回退与回滚。

这次接通可能需要一次 App 升级；之后兼容现有 schema 的观点、排名、代表作等内容发布不需要每次升级。新增页面或不兼容字段仍可能需要发版。
如果目标是完全无人值守，还需上传入口/文件到达触发、处理任务调度和失败通知；不能把当前命令行工作流称为已自动运行。

本次没有新日包，没有发布内容、修改默认数据源或上传 TestFlight。
详见 [Supabase 内容操作](supabase-content.md) 和 [日包工作流](x-daily-package.md)。

## 本日二次核查：工程、归档与线上服务

- 当前工程的 Debug 默认 fixture；仅显式 use-live-api/BSMART_USE_LIVE_API 才进入网络模式。启用 live 不等于选择 Supabase，后端开关仍独立。
- 检查本机 2026-09-22 19:13 归档 Info.plist：版本 1.0 (8)，内容后端 legacy，API 为 https://api.bsmart.today，环境 production。这是归档证据，不等于已确认用户设备安装的是该归档。
- Supabase bsmart-content 为 ACTIVE，部署 version 3；未登录 manifest 请求返回 401 unauthorized，符合函数内鉴权设计。
- 发布器保护配置可读取，使用其真实连接完成 SELECT 1；三张内容表存在且 RLS 开启，当前存有两个历史版本。没有执行生产写入或 DDL。
- 线上 active 仍为上述 f862986a... 版本，激活时间 UTC 2026-09-15 17:20:43（北京时间 9 月 16 日 01:20）。八个集合 manifest 可读，观点最新时间为 9 月 5 日、Smart Money 为 8 月 14 日。
- 旧 Release 域名健康检查从本机遇到 TLS EOF，InternalAlpha 地址 TLS 握手超时；这只能证明本机本次未连通，不能断言服务器停机，也未完成 Vultr 主机内部审计。
- 真实 Google/Apple 用户登录后的 Supabase manifest/page，以及同一 App 发布前后刷新，仍未验收。未获取或伪造用户令牌。
- 本次重跑内容配置、版本发布、API 校验器 Python 测试与 Edge 内容测试；不重建刚清理缓存的 App，也未发布新内容或更改数据源。

结论：服务器内容版本读写基础可用；App 远程刷新代码已有，但当前归档连接旧 API，不消费 Supabase 内容发布。启用这条发布链路仍需一次客户端配置切换发版和真实用户端到端验收。

## 接通进展（本日后续）

用户授权旧包测试后，默认后端已切到 Supabase，build 9 编译并安装到连接 iPhone。
真实登录后的设备回执确认读取线上 f862986a... 基线：353 位作者、267 条观点、54 个资金账户、220 条动态。
回执不含用户令牌；这证明真实用户鉴权与全部主集合解码通过，不代表按需证据全部浏览通过。
21 项 iOS 内容/工厂回归通过。三小时 Codex heartbeat 已建立（id bsmart），处理逻辑见 content-delivery.md。
旧包待完成下一版本发布与同设备前后版本验收；此前“默认 legacy”描述是切换前的核查记录。

## 真机发布前后验收完成

北京时间 2026-09-22 22:18，连接 iPhone 的同一 build 9 自动读到新版本 cbcc995f...：
349 位作者、737 条观点、54 个 Smart Money 账户、220 条动态。对照发布前回执
f862986a...（353 位作者、267 条观点），未在两个回执之间重装 App。主集合真实用户鉴权与
免发版更新已验证；通过 App 解码验收，不宣称运行了需要用户令牌的外部 API 验证器。
历史包原始日期保留，本次未发送推送。

私有证据保存在 data/runtime/content-delivery-acceptance/；当前任务每 3 小时运行已登记
队列，无包保持静默。调度依赖 Mac/Codex 可运行，挂起/关机不保证准点；TestFlight 未上传。

新版本八个集合的数据库逐页内容比较、总页数、集合哈希/数量及最终 active 指针复核通过（database-after.json）。
