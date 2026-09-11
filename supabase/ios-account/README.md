# iOS 账号与钱包配置

当前架构：iOS 直接连接 Supabase Auth；钱包密钥仅保存在设备；Supabase
只保存公开钱包地址并验证绑定签名。无需 Vultr，也不依赖研究数据 API。

此目录只对应 bSmart 账号项目 `dzyitinagewdfkzjkuiz`。
不要在仓库根目录运行 `supabase db push`：根目录指向另一套历史内容项目。

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

函数的三个独立资金开关默认关闭，只有值精确为 `true` 才开放：
`BSMART_DEPOSITS_ENABLED`、`BSMART_TRADING_ENABLED`、`BSMART_WITHDRAWALS_ENABLED`。
修改使用 `supabase secrets set <NAME>=true --project-ref dzyitinagewdfkzjkuiz`。
返回能力仍要求已认证、已绑定钱包；Google 登录设置不开放资金操作。

本轮内测配置：上述三个开关已通过 CLI 设置为 `true`。这只是开放用户自行
确认的入口，不会自动入金或下单，也不是已完成真实资金验收/公开发布审核。

### App 基本路径

1. Google 登录后的「继续」进入「交易钱包」。
2. 本机生成或解锁钱包；当前内测版备份可选，无需抄写助记词即可继续。Google 不能恢复丢失的本机密钥；已有绑定缺少本机密钥时仍须恢复原钱包，不能另建地址覆盖。
3. 「接收 USDC」仅用于 Arbitrum 原生 USDC；需要同一网络少量 ETH 支付转入 gas。
4. 「转入 Hyperliquid」依次核对金额、授权、网络费和提交，回到钱包刷新到账余额。
5. 明确确认「启用 USDC 统一余额」，协议读回成功后再进入合约交易。
6. 选择合约，确认市价单；已开仓位通过「当前合约持仓 → 减仓 / 平仓」退出。
7. 「提取 USDC」确认 Arbitrum 地址及金额。统一余额首版要求全部仓位及挂单清空；
   不支持组合保证金出金。API 接受显示处理中，不冒充到账。

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
