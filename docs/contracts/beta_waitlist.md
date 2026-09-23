# bSmart 内测等候名单

这是官网独立的收集接口，不创建 App 账户，不触发邮件发送，不接入交易数据。

## 请求

`POST /api/waitlist`，JSON，最大 2048 字节。字段：

- `email`：有效 ASCII 邮箱，去除首尾空白并转小写，最长 254 字符。
- `lang`：`zh` 或 `en`。
- 新版：`intent` 必须为 `"beta-access"`，表示用户主动点击申请按钮。不显示或自动勾选隐私同意框。
- 旧版意图字段兼容：未带 `intent` 时仍接受 `consent: true`，但也必须提供完整问卷；旧的仅邮箱请求返回 `400 invalid_survey`，需刷新网页。
- `website`：反机器人隐藏字段，只允许空字符串或省略。
- `survey`（必填）：`channels` 为 `accounts` / `politicians` / `institutions` / `onchain` / `insiders` / `other` 的数组，至少 1 项、最多 6 项，去重后按固定顺序保存；`otherChannel` 为最多 200 字符的文本，选择 `other` 时必须填写，否则必须为空；`contact` 必须为 `{ platform: "telegram" | "wechat" | "twitter", handle: string }`，账号/主页链接去首尾空白后非空、最长 120 字符。不接受控制字符。邮箱、渠道和联系方式均须填写，缺少任何一项不落库。

Origin 限制为同源及 bsmart.today / www.bsmart.today；`WAITLIST_LOCAL_DEV=true` 才允许本地 3100 代理。无 Origin 的服务器提交仍校验字段和限流。

## 返回

- `200 {"ok":true}`：新记录已写入，或已存在对应 Email；两者返回一致。
- `400`：字段、申请意图、JSON 或 honeypot 无效。
- 问卷无效时 `400` 使用 `code: "invalid_survey"`，前端显示问卷错误而非邮箱错误。
- `403`：来源不允许。
- `405`：非 POST，公开读取不受支持。
- `413`：请求过大。
- `415`：非 JSON。
- `429`：粗粒度限流，附 Retry-After。
- `503`：未绑定存储或存储失败。不得显示已加入名单。

错误 JSON 为 `{"ok":false,"code":"..."}`，无 Email/名单/内部错误回显。

## 存储

Cloudflare KV binding：`WAITLIST`。

`entry:<sha256(normalized-email)>` 存储 email、lang、createdAt、source。新申请附带 `requestVersion: "beta-application-2026-09-13"`、`requestMethod: "application-button"`，不记录已同意隐私声明。旧版请求继续附带 `consentVersion: "beta-invitation-2026-09-13"`。source 为 `bsmart.today`。重复请求不覆盖原创建时间或授权版本。KV 最终一致性下跨地域并发可能最后写入覆盖同邮箱，但不会产生多个不同的名单键。

`rate:<sha256(hour:CF-Connecting-IP)>` 存储本小时计数，TTL 为 3600 秒，不保存原始 IP。每小时约 5 个新 Email，KV 最终一致性意味着这只是粗粒度防滥用，不是严格原子配额。生产应视流量在 Cloudflare 添加 WAF/Turnstile；不要把此接口作为任意公开邮件营销订阅源。

不记录请求正文、邮箱或原始 IP 的日志。名单仅由管理员通过 Cloudflare 读取。删除联系邮箱为 `zfy3712z@gmail.com`（极简首页不再展示）；管理员据规范化邮箱计算 key 后删除对应记录。仅收集名单，发送邀请需单独安排。

## 问卷补充（2026-09-15）

提交完整回答时记录 `survey`、`surveyVersion: "investment-interests-required-2026-09-15"` 和 `surveySubmittedAt`。此前只留邮箱的申请可补充第一次问卷，原始创建时间、语言和申请/同意字段保持不变；补充问卷同样计入每小时限流。已有问卷的匿名重复请求不改写联系方式或回答，也不对外透露是否已登记。历史选填写入的记录保留，不批量改写。KV 仍是最终一致性存储，不保证跨地域并发原子性。

新增联系方式仅供内测联系，渠道偏好用于产品调研，与邮箱一起保存在现有私有 KV；没有新增公开查询接口、邮件发送或 App 账户。
