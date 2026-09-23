# iOS 账号与钱包配置

当前架构：iOS 直接连接 Supabase Auth；钱包密钥仅保存在设备；Supabase
只保存公开钱包地址并验证绑定签名。无需 Vultr，也不依赖研究数据 API。

此目录只对应 bSmart 账号项目 `dzyitinagewdfkzjkuiz`。
不要在仓库根目录运行 `supabase db push`：根目录指向另一套历史内容项目。

## 固定 Relay 充值地址（2026-09-23 已部署）

`bsmart-funding/address` 首次获取 Relay 开放式地址后，按账号、绑定钱包及
USDC 来源网络写入 `bsmart_funding_addresses`；刷新页面只读回已经登记的地址。
并发首次请求使用数据库唯一键和 `ON CONFLICT DO NOTHING`，只向 App 返回
持久化成功的地址。数据库不可用时不展示未登记的新地址。不同网络仍有各自的
地址；Relay 仅保证开放式地址在同一路由内可复用，不能将其宣传为跨链统一地址。

上线顺序（仅账号项目；本次迁移已由负责人执行，函数版本 8、ACTIVE）：

1. 在 SQL Editor 审核并执行单条迁移
   `supabase/migrations/202609230004_funding_addresses.sql`。不要全量 `db push`，
   旧迁移曾手动执行，CLI 记录未统一。
2. 确认 `public.bsmart_funding_addresses` 存在且 RLS 已开启，再从本目录执行
   `supabase functions deploy bsmart-funding --project-ref dzyitinagewdfkzjkuiz --use-api`。
3. 使用已有测试账号，在同一网络两次打开充值页，应得到相同地址；切换网络
   应显示该网络独立地址。只检查展示和数据库登记，不需要真实转账。

旧版已经显示过、但尚未登记的 Relay 地址不会因本次上线被删除；旧版充值记录
仍由原有 `/deposits` 查询。首次上线后新展示的地址才开始固定。
本机直连 Functions 域名被重置，尚未完成登录态下的线上地址复用验收；
发布成功不等于真实资金路径已验证。

## 热门观点与热门投资者榜单

2026-09-22：用户已确认执行统计迁移；`bsmart-feed` 已部署，管理 API 确认
版本 14、状态 ACTIVE（09:48:35 UTC）。部署后的无登录 HTTP 探测因本地连接
重置未取得响应；尚需在新版 App 登录后验收榜单和筛选，不视为线上功能验收通过。

同日 10:06:19 UTC 已部署兼容修复，管理 API 确认版本 15、ACTIVE：
`includeTheses=true` 的公开动态请求遇到 `PGRST202`（新增 RPC 尚未可用）时，
使用原有 `bsmart_feed_page`，保留分页和公开资料筛选。个人动态不会回退至公开
动态，其他数据库错误仍按失败返回。成交理论/点赞仍需手动执行
`202609220004_trade_theses.sql`；本次未执行生产 DDL，未确认生产迁移状态。
本地通过 91 项 Deno 测试、3 项榜单单测和 1 项自定义筛选面板 UI 测试。
线上登录态动态仍需复验，部署成功不等于用户遇到的错误已被线上确认解决。

先在本账号项目单独执行
`supabase/migrations/202609220003_discovery_rankings.sql`，再从本目录部署：

```sh
supabase functions deploy bsmart-feed --project-ref dzyitinagewdfkzjkuiz --use-api
```

新 `/rankings` 支持交易人数/成交额、24h/7d/30d/全部周期；旧 `/popular`
保持兼容。不要全量 `db push`。iOS 界面需新版构建；之后榜单随已核验成交更新，
无需重新发布数据包。未部署时客户端显示统计不可用，不用演示数据填充。

## 关注与私信（2026-09-22）

### 站内内容分享（2026-09-24 函数已部署）

本次 iOS 更新增加观点、投资者及标的卡片，可发送到公共聊天室或私聊。先在**账号项目**
的 SQL Editor 审核并单独执行 `supabase/migrations/202609240001_chat_shares.sql`，确认
`bsmart_social_messages.shared_content` 和新版 `bsmart_chat_send` 存在，再从本目录执行
`supabase functions deploy bsmart-social --project-ref dzyitinagewdfkzjkuiz --use-api`。
最后发布新版 iOS；旧版文字/图片消息仍通过原参数调用。切勿全量 `db push`：历史迁移记录
未统一，CLI 会尝试重放旧迁移。发布后用两个测试账号验证公共聊天室、私聊、卡片打开、
普通文字消息和失败重试；未完成这套线上验收前不要将分享视作已上线。

用户已确认执行本次 SQL；`bsmart-social` 已部署，管理 API 确认版本 12、状态 ACTIVE。
本机直连 Functions URL 仍被连接重置，未完成登录态下的收发验收；函数部署成功不等于
TestFlight 已更新或站内分享已由真机验证。

第四个 iOS Tab 使用 `bsmart-social`：用户可直接关注/取消关注，也可不关注就发送
私信；没有好友申请或同意步骤。动态页展示新关注者和未读消息。表与 RPC 在
`supabase/migrations/202609210001_social.sql`，函数在
`supabase/functions/bsmart-social/`。两者已部署到本项目；匿名请求实测返回 401。
私信与关注只保存 Supabase 账号 ID，客户端只得到公开资料 ID；消息内容不会出现在
研究数据或交易 Feed 中。每个账户每小时最多发送 60 条私信。

此前 SQL 是手动执行，CLI 迁移历史未登记旧版本。本次仅通过隔离的迁移目录部署
`202609210001_social.sql`；不要在此目录直接对远端执行完整 `supabase db push`，
否则 CLI 会尝试重放旧迁移。后续先核对线上历史，再决定是否修复迁移记录。

观点详情页的累计成交额使用独立迁移
`supabase/migrations/202609220001_opinion_trade_volume.sql`。上线时仅在本账号
项目执行这一条 SQL，确认 `bsmart_opinion_traders` 返回 `totalNotionalUSD`；
无需重新部署 `bsmart-feed` 函数，也不要用本目录的完整 `db push` 重放历史迁移。

## 统一平台资料（005，已部署）

手动执行 `supabase/migrations/202609120005_account_profiles.sql` 后，历史
`bsmart_feed_profiles` 即为平台资料真源：nickname（用户名，可重复）、handle
（唯一）、bio 和 avatar_url。不迁移公开 ID，不覆盖已有隐私同意。
新注册自动建档，旧账号补齐默认资料；所有表仍禁止客户端直接读取或写入。

创建私有 Storage bucket `bsmart-profile-avatars`，仅允许 `image/jpeg`、最大
200000 字节，不添加客户端写入策略。服务对头像解码、去元数据、重新编码，
Feed 返回有效期 300 秒的签名链接；旧头像由现有分钟任务从清理队列删除。
保存超时需先重载资料，避免把一次已成功的保存当作失败重复覆盖。

从此目录部署 `bsmart-profile` 和更新后的 `bsmart-feed`（使用 `--use-api`）；
不能先部署依赖 handle 列的新 Feed 再执行迁移。iOS 更新无需改钱包功能开关。
完整契约：`../../docs/contracts/account_profiles.md`。

2026-09-12 已只读确认线上 handle/bio/revision、ensure RPC、头像清理队列存在；
保留的 1 个账户资料 handle 唯一。私有 bucket 已建立，profile/feed 函数已部署；
线上 Feed 和观点名单已返回 handle，匿名访问两接口均为 401，worker 心跳正常。
未代替用户修改头像或用户名，需在新版真机 App 中完成编辑/上传验收。

## Google 登录已验收

不需要 Vultr、不需要执行 SQL、不需要部署钱包 Edge Function，也不用先配置
Apple。账户页只提供 Google 登录，成功后显示「已登录」，不会自动初始化钱包。

1. Xcode 运行最新 App，进入「设置 → 账户 → Google」。
2. 用户本人完成 Google 授权，返回 App 确认「已登录」。
3. 关闭并重开 App，确认登录仍在；再退出，确认恢复 Google 登录按钮。

2026-09-12 只读核对：Supabase Google provider 已启用，授权重定向返回 302，
Web Client ID 与工程一致，回调为该项目 `/auth/v1/callback`。
随后用户提供了真机 Google「已登录」截图，真人登录已确认成功。

本轮自动验证：43 项账号逻辑测试、3 项 UI 测试通过。真实 Google SDK
已经打开官方邮箱/手机号输入页；测试不输入凭据或代替用户同意。
`GoogleSignInLiveUITests` 默认跳过，显式设置
`TEST_RUNNER_BSMART_TEST_GOOGLE_OAUTH=1` 后运行对应 Xcode UI 测试才访问 Google。

### Google 后台配置

已有两个公开 Client ID 和 reversed iOS 回调 scheme 已配置进工程。
Supabase 的 Google Client IDs 应包含 Web ID 和 iOS ID（Web ID 放首位），
Web Client Secret 只保存在 Supabase 后台，保持 nonce 检查开启。
若 Google Cloud Audience 仍为 Testing，将内测 Google 账号加入 Test users。

## 后续基础钱包

### Apple 登录（暂停）

1. Apple Developer → Identifiers → `today.bsmart.ios`，开启 Sign in with Apple。
2. Supabase → Authentication → Sign In / Providers → Apple，启用并在允许的
   Client IDs 中加入 `today.bsmart.ios`。保持 nonce 检查开启。
3. 再做 Apple 时，恢复 `BSMART_APPLE_SIGN_IN_ENABLED`、Sign in with Apple
   entitlement 和按钮，再更新 provisioning profile；本轮三者都暂停。

2026-09-12 公共设置检查结果：Google 已启用，Apple 未启用。
本次只读检查，没有代为更改后台配置或创建用户。

### 钱包地址登记

在该项目的 SQL Editor 中，由项目负责人审核并运行一次：

`supabase/migrations/202609120001_wallet_registry.sql`

然后部署本目录 `supabase/functions/bsmart-wallet/` 内的 Edge Function。
它只做认证、签名验证和公开地址绑定，不代管资产、不执行交易。

推荐从此 README 所在目录执行：

```sh
supabase login
supabase functions deploy bsmart-wallet --project-ref dzyitinagewdfkzjkuiz --use-api
```

也可以在 Supabase 的 Edge Functions 编辑器创建 `bsmart-wallet`，上传
`index.ts`、`handler.ts`、`proof.ts` 三个文件。关闭旧网关的 JWT 验证开关，
但必须保留代码内 `auth.getUser(token)` 验证；不要删除该校验。
函数使用 Supabase 自动注入的 `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`。
不要将 service-role key、Google secret、Apple 私钥写入 iOS。

2026-09-12：用户报告 SQL 已执行成功；函数已通过 CLI 部署，未认证 GET
实测返回 401。没有使用用户令牌代建钱包，线上建钱包与绑定仍由本人在 App 内完成。

资金开关只有值精确为 `true` 才开放。出金仅支持 Across，使用
`BSMART_ACROSS_WITHDRAWALS_ENABLED`；旧版 `withdrawalsEnabled` 响应固定为
`false`，旧提交接口返回 `426`。旧版数据库记录保留，用于阻止未解决的历史
出金与 Across 出金重叠，不得重新启用旧版直接出金。
部署和异常恢复顺序见 `../../docs/operations/across-withdrawals.md`。
修改使用 `supabase secrets set <NAME>=true --project-ref dzyitinagewdfkzjkuiz`。
返回能力仍要求已认证、已绑定钱包；Google 登录设置不开放资金操作。

截至 2026-09-23，用户要求 Across 开关保持开启，旧版开关关闭；尚未确认小额
真实出金到账。不要只依赖此文档推断线上开关现值，发布前应核对实际配置。

### App 基本路径

1. Google 登录后的「继续」进入「交易钱包」。
2. 本机生成或解锁钱包；当前内测版备份可选，无需抄写助记词即可继续。Google 不能恢复丢失的本机密钥；已有绑定缺少本机密钥时仍须恢复原钱包，不能另建地址覆盖。
3. 「接收 USDC」仅用于 Arbitrum 原生 USDC；需要同一网络少量 ETH 支付转入 gas。
4. 「转入 Hyperliquid」依次核对金额、授权、网络费和提交，回到钱包刷新到账余额。
5. 明确确认「启用 USDC 统一余额」，协议读回成功后再进入合约交易。
6. 选择合约，确认市价单；已开仓位通过「当前合约持仓 → 减仓 / 平仓」退出。
7. 「提取 USDC」经 Across 报价后确认 Arbitrum 地址、金额、最低到账和费用；
   统一余额首版要求全部仓位及挂单清空，不支持组合保证金出金。
   Across 接受提交只表示处理中，须等状态核验为 `filled` 才是到账。

只做永续合约；builder 地址/费率未配置，订单不附带 builder 收费。
没有完整资金费率/交易历史产品；订单不确定状态的防重复保护仍保留。

## iOS 构建

本机公开 publishable key 已保存到 gitignored
`ios/Config/Supabase.xcconfig.local`。新机器参考同目录 `.example` 文件，
或由 CI 注入 `BSMART_SUPABASE_PUBLISHABLE_KEY`，再执行 `make ios-generate`。
登录与研究数据来源独立，Debug 使用本地数据也能登录。

## 后续钱包与发布验收

- Google / Apple 真机登录，退出、重新打开 App、刷新过期会话。
- 钱包创建、免备份继续、可选查看与确认备份、锁屏解锁；退出不删除密钥。
- 同一账号在第二台设备登录，必须恢复绑定的原钱包，不能自动换地址。
- 助记词错误、跨账号证明、重复证明必须失败。
- 云端函数未部署时显示配置错误，不将缺失服务当成“没有钱包”。
- 不自动合并旧服务账户。原账户有资金时，先保留并验证助记词，完成专门迁移；
  新 Supabase 账户或新地址不表示原资产已迁移。

钱包后端已部署；SQL 成功由用户报告，未由助手执行或代用户创建测试账户。
真实入金、交易、出金仍有独立开关，不能因为登录成功就自动打开。
公开发布前还需补齐账号删除等生命周期要求；本次不扩大高级功能范围。

## 本地检查

```sh
deno task check
deno task test
```

测试使用公开测试向量、模拟网络和内存 PostgreSQL，不访问用户数据库或真实资金。

本轮基础链路验证：197 项 iOS 回归通过（其中 4 项为显式主网只读检查，
涵盖 Arbitrum 源链、CCTP 出金合约、HyperCore 余额与 NVDA 合约账户状态）；
11 项 Deno 测试通过，4 项界面回归通过，函数类型检查、架构和术语检查通过。
结果包：`/tmp/bsmart-basic-wallet-verified.xcresult`、`/tmp/bsmart-basic-wallet-ui.xcresult`。
未发送真实订单或转账，未上传 TestFlight，需重新运行最新 App。

上一阶段 2026-09-12 验证：iOS 模拟器签名构建通过；124 项账号/钱包/基础交易相关
测试通过；9 项 Edge Function/内存 PostgreSQL 权限与签名测试通过；架构及
术语检查通过。构建产物确认已注入正确项目 URL 与公开 key。当时函数未部署；
该状态已被本轮部署和用户的 Google 登录确认更新。未执行真实资金操作。

参考：[Google](https://supabase.com/docs/guides/auth/social-login/auth-google)、
[Apple](https://supabase.com/docs/guides/auth/social-login/auth-apple)、
[Edge Function 认证](https://supabase.com/docs/guides/functions/auth)。
# Real Trade Feed deployment (2026-09-12)

Subject aggregation extension (2026-09-13): manually apply
`supabase/migrations/202609130001_subject_trade_stats.sql` after 005. Then deploy
`bsmart-feed` as below and republish the reviewed catalog, which now also consumes
`smart-money.json` and `smart-money-movements.json`. Missing money files do not
invent sources. Existing registrations retain their immutable snapshots and
are never reattributed. A count of ten means ten distinct user/source pairs;
see `docs/contracts/subject_trade_stats.md`. The new SQL does not require 006 or
alter its separate public-activity policy.

2026-09-12: deployed to this account project, independently of Vultr. The operator
confirmed both migrations succeeded; live service-role reads verified the schema
and scheduler. Existing wallet secrets/capabilities were not changed. No actual
order, user account, signature or transfer was created by the deployment task.

1. Review and apply `supabase/migrations/202609120002_trade_feed.sql` in this
   account project's SQL editor. It creates isolated Feed tables/functions with
   RLS, service-role-only access and auth-user cascade deletion. It does not alter
   wallet registrations or funding records. No automatic startup migration.
2. Review and apply `supabase/migrations/202609120003_feed_reconciliation.sql`.
   It adds shared verification leases, a Vault-owned scheduler secret and a
   once-per-minute job. The worker verifies up to five orders per run; the native
   sync endpoint checks only the requesting user's orders. Failed reads retry;
   after seven days unresolved registrations remain uncounted and marked expired.
3. Publish the reviewed real Smart Account snapshot to private Storage from the
   repository root: `make feed-catalog-publish INPUT_DIR=contracts/fixtures
   SOURCE_VERSION=real-smart-account-20260912 APPLY=1` (one command line).
   The current files in this historical `fixtures` directory contain the project's
   real author/call export, not simulated trades. The publisher requires real public
   source provenance and valid author ranks, uses the logged-in operator's Supabase
   CLI authorization, and never prints or stores service keys. No DDL is executed.
   It uploads all immutable objects before switching `active.json`. Republish when
   adding opinions; new files on this computer alone do not update the service.
4. Opinion order registration resolves the exact HIP-3 DEX and coin from current
   Hyperliquid `perpDexs` and `meta`, including older and newly listed markets.
   The contract symbol must match the opinion ticker; delisted markets and
   non-USDC collateral are rejected. `BSMART_FEED_MARKETS` is no longer needed.
5. From this directory run `supabase functions deploy bsmart-feed --project-ref
   dzyitinagewdfkzjkuiz --use-api` (one command line). Its gateway
   setting is in `supabase/config.toml`; the handler independently uses Auth
   `getUser` for every request. It needs standard Supabase service-role runtime
   configuration but never receives private wallet keys or order signatures.
6. Install the iOS update, sign in, and open Feed's privacy settings. Identity and
   amount sharing default off; only explicitly consented accounts appear publicly.
   Original local profile images are not uploaded; Google avatar use is opt-in.
7. The user may perform a real trade through an eligible opinion, then
   refresh Feed. Verify the exchange order/fills, anonymous count, public list,
   amount, duplicate refresh and consent withdrawal. Operators must not fabricate
   fills to force a populated Feed. Automated tests do not move real funds.

Run `make feed-service-check` from the repository root to inspect live readiness:
unauthenticated requests must be rejected, catalog bucket must be private, database
RPCs must exist, cron must be active, and worker heartbeat must be under five minutes
old. The worker shares the same read-only Hyperliquid verifier as native sync.
No guarantee is made about exchange outages or queue throughput beyond this MVP
capacity. Historical unregistered trades cannot be imported as opinion-driven trades.

### Popular opinions and direction counts

Apply `202609120004_feed_discovery.sql` manually in the same account project, then
deploy `bsmart-feed`. It replaces the existing trader-count projection and adds
the service-role-only popular-opinion RPC; no orders or funds are modified.
The native Feed offers Latest trades / Popular opinions. Popular ranks unique
verified users in the last seven days; the detail breakdown is all-time. Anonymous
users contribute counts only. Their most recent eligible fill determines one side.
The runtime is entirely Supabase, without changes to signing or exchange submission.

### Trade theses rollout (prepared 2026-09-22)

1. Operator manually applies `supabase/migrations/202609220004_trade_theses.sql`
   after the existing Feed/profile migrations. No trading or wallet table data is rewritten.
2. Deploy `bsmart-feed` after migration; it now calls `bsmart_feed_social_page`.
3. Release iOS. Verify using an already authenticated owner with a real verified
   opinion trade: publish once, same-text retry, personal/discovery display; use a
   second account to like/unlike. Do not fabricate executions for production QA.
4. Confirm direct anon/authenticated table and RPC access remains denied.

Rollback Edge and App together if needed; retain thesis tables and content.
Contract and known scope: `docs/contracts/trade_thesis.md`.
