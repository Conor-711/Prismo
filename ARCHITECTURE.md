# 项目架构与结构（ARCHITECTURE）

> **维护约定**：本文件是项目的「活地图」。**每次对项目结构或功能有实质改动后，必须同步更新本文件对应章节**
> （新增/删除模块、改数据流、改命令、改部署方式、改 schema 等）。详见根目录 `CLAUDE.md`。
> 最近更新：2026-09-12。

**真实交易面板样式恢复（2026-09-12）**：`LiveMarketOrderView` 恢复大金额、快捷金额、数字键盘/K 线切换和底部滑动确认；复用 `TradeLeveragePicker`/`TradeSlideToConfirm`，不重新接入 `PaperTradingEngine`。`LiveOrderAmountPanel/EntrySummary` 仅组装显示；真实账户余额、杠杆和费率来自 `HyperliquidMarketOrderStore.loadEntry` 的只读查询。输入金额仍是 USDC 名义仓位价值，MAX 只预填保守估值，提交仍重新验证完整订单。杠杆显示真实值且只读，未实现真实调整时不允许模拟滑动修改。行情图使用独立会话；钱包、入金路径和签名/日志不变。

**入金日志路径兼容修复（2026-09-12）**：`FundingJournalFiles.databasePath` 在 SQLite 打开前使用 POSIX `realpath` 规范化父目录，解决系统 `/var` 别名与 `SQLITE_OPEN_NOFOLLOW` 冲突导致日志无法创建的问题；数据库文件本身仍拒绝符号链接，Keychain 锚点、防回滚、签名和提交门槛不变。不删除或重置已有记录，不修改钱包密钥、地址或注册信息。

**内测钱包免强制备份（2026-09-12）**：`DeviceWalletBackupPolicy` 统一控制入金、交易、出金和签名的备份门槛；当前 1.0(6) 在 `ios/project.yml` 显式设置 `BSMART_INTERNAL_OPTIONAL_WALLET_BACKUP=YES`，包含内测使用的 Release 归档。钱包页备份入口折叠为可选，不改 `recoveryVerified`、密钥、地址或注册绑定；Google 登录、设备解锁、确认、资金开关与预检仍保留。密钥仍仅本机保存，Google 不能恢复遗失密钥；缺失已有钱包的本机密钥仍阻止资金操作，不能创建新地址覆盖。缺失/非 YES 开关恢复备份要求，公开发布前必须设 NO；本次不接入第三方钱包服务。见 `docs/contracts/native_perpetual_mvp.md`。

**保守代码清理（2026-09-12）**：移除 `TodayEditorialSections.swift` 中五个无调用的旧首页组件及其专用辅助代码，保留当前 `TodayEvidenceTimeline` 和共享图表类型；不改交易、钱包、账户、算法或数据契约。通过既有 `make clean` 清除可重建的网页导出，保留主库、部署快照、依赖和 iOS 发布归档。清理范围及保护边界见 `docs/operations/repository-cleanup-2026-09-12.md`。

**Google 登录后基础交易路径（2026-09-12）**：用户已在真机确认 Google 登录成功；`TradingAccountView` 仍只管登录，“继续”进入独立 `TradingWalletView`，个人主页和下单缺钱包时也进入此处。面板复用设备钱包备份、Arbitrum USDC 收款、CCTP 转入、出金；`TradingMarketsView` 展示真实合约目录，`TradingPositionsStore/View` 有界读取全部 perpetual DEX 持仓并进入 reduce-only 平仓，不使用研究持仓或 demo 余额。`UnifiedAccountSetupStore/Codec` 在用户明确确认且无持仓/挂单时签名固定 `userSetAbstraction(unifiedAccount)`，与订单/出金共用持久化 nonce，读回协议状态才显示启用；统一账户出金仅在全部仓位/挂单清空且 USDC hold 为零时从 spot 余额进行，不支持 portfolio margin。已接受出金不代表到账，但允许基于新余额另行确认；未知请求仍禁止重发。合约交易不带未配置的 builder；高级历史/报表继续后置。契约见 `docs/contracts/native_perpetual_mvp.md`，真实资金验收需由用户在 App 中执行。

**iOS 直连 Supabase 账号（2026-09-12）**：`Core/Data/SupabaseAccountAuthClient` + `SupabaseAccountTransport` 独立于研究 API/安装会话，直接处理 provider ID token、nonce、用户验证、刷新与退出；`auth.users.id` 是新账户 ID，项目独立的 device-only Keychain 保存会话。`AccountIdentityAuthorizer` 使用哈希 nonce；旧 `HTTPAccountAuthClient` / backend `accounts/supabase_identity` 只保留兼容，不再是 iOS 登录依赖，不需 Vultr。公开 publishable key 位于 gitignored `ios/Config/Supabase.xcconfig.local`。`supabase/ios-account` 是新账号项目的独立部署根，包含公开钱包地址 RLS、一次性签名挑战及 `bsmart-wallet` Edge Function；EIP-191 使用 viem 验证，私钥/助记词继续只在设备端，不上传、不从登录信息派生。用户报告钱包 SQL 已执行，Edge Function 已部署；未认证访问实测 401。注册响应以独立 capabilities 控制入金、交易、出金，缺字段/缺地址/验证失败关闭，不因 Google 登录而自动开放。旧钱包不覆盖、不按 email 自动迁移；缺失函数/表显示错误而非未绑定。Apple 和账号删除仍后置，公开发布前须完成。操作步骤见 `supabase/ios-account/README.md`，契约见 `docs/contracts/supabase_account.md`。

当前内测开关：`BSMART_DEPOSITS_ENABLED`、`BSMART_TRADING_ENABLED`、`BSMART_WITHDRAWALS_ENABLED` 已设为 `true`，仍要求当次注册身份、本机已核验钱包、明确确认及签名前后预检；备份门槛见上方内测策略。上阶段 197 项 iOS 回归通过，含 4 项主网只读检查；另 4 项界面回归、11 项 Edge Function 测试及架构/术语检查通过。未执行真实资金操作、未上传 TestFlight，不代表公开发布就绪。

Google 上阶段自动验收：43 项账号逻辑测试、3 项 UI 测试通过（模拟器 ad-hoc 签名），SDK 测试停在官方邮箱/手机号输入页，不代填凭据；随后用户提供真机登录成功截图。早期后端路径验证不作为当前直连登录的验收结论。

**观点交易人数 Demo（2026-09-11）**：观点详情无已核验人数时直接展示带「演示数据」标记的本地预览；`Core/Data/OpinionTraderDemoData` 提供六位虚构昵称、不同本地头像、方向、开仓价、仓位金额、杠杆和时间，两位模拟匿名用户仅计示例总数。`OpinionTradersDemoView` 支持展开与加载更多；真实接口成功后切回正式列表，真实零人数亦不替换成示例。演示模型与成交 API 隔离，不改真实账户、订单、公开同意或统计账本，无需 Debug 参数，未上传 TestFlight。

**Feed 显式 Demo（2026-09-11）**：Feed 右上角增加 Demo/实时动态切换，无需测试启动参数；`TradeFeedDemoData` 从独立 `trade-feed-demo.json` 加载六条虚构交易，引用既有真实观点。Feed、卡片和示例用户页标记 Demo，分页及用户跳转均本地完成；快捷块只进入 `FeedDemoTradePreview`，不调用订单、签名或余额逻辑。实时接口失败保持原错误态，用户主动切换后才显示示例，不发布虚构成交。

**iOS 构建依赖恢复（2026-09-11）**：新增 `make ios-resolve`，从 `ios/project.yml` 重新生成工程后，在 Xcode 默认工作区解析固定的 Swift Package 依赖。`WalletCore/WalletCoreSwiftProtobuf` 缺失需先检查依赖图最早的下载错误；本次日志根因为 GoogleSignIn 的 GitHub 连接超时，不是钱包模块被删除。保留官方二进制版本、校验和、已有缓存及钱包数据，恢复流程见 `ios/README.md`。

**基础交易收敛（2026-09-11，预生产）**：按用户最新要求，只推进 Arbitrum USDC 入金、合约市价单和出金。`HyperliquidMarketOrderStore` 提交后直接返回订单回执，不再等待逐笔成交查询；`LiveMarketOrderView` 暂不展示历史及逐笔费用。既有查询代码、持久化防重复提交及不确定状态保护保留，不继续扩展历史功能。

**原生出金确认（2026-09-11，预生产）**：钱包新增 `Features/Account/HyperliquidWithdrawalView`；`Core/Trading/Funding/HyperliquidWithdrawalPreview/Store/Permits` 接入默认合约 USDC 可提余额、CCTP 费用检查、显式地址确认、受保护设备签名与一次性提交，复用原订单 HTTP 传输与加密日志。`Core/Wallet/HyperliquidWithdrawalSigner` 固定 Arbitrum 自动转发，不引入私钥上传。首版不从统一/组合保证金的 spot 总额推算可提余额；API 接受只显示处理中，未知请求不重发。完整协议费用、目的链到账确认、真实登录和小额资金验收仍未完成，生产开关不变；不能把这次界面及编译完成视为已开放真实出金。

基础路径验证：模拟器构建通过；`CCTPTransferTests`、`HyperliquidMarketOrderStoreTests`、出金 codec/journal/store 共 55 项测试通过。测试使用临时日志、公开测试密钥与模拟传输，未执行真实资金操作。

**仅合约交易与减仓入口（2026-09-11，预生产）**：用户确认仅支持永续合约，不做现货交易。`HyperliquidExecutionMarket/OrderIntent` 校验合约资产命名空间，资金链路仍保留共享/spot USDC 读取及回退核验，不把它们当现货交易功能。`HyperliquidMarketOrderPlan/Store` 与 `LiveMarketOrderView` 加入按真实仓位比例减仓/平仓，自动决定方向、固定 reduce-only，确认及签名后仓位变化需重新预览；保留完整费用、真实成交与出入金验收边界，生产开关不变。决策见 `docs/product/hyperliquid-trading-pivot-2026-09.md`。

**出金持久记录与共享序号（2026-09-11，预生产）**：`Core/Trading/Funding/HyperliquidWithdrawalRecord/Journal` 将出金阶段写入既有加密、Keychain 防回滚日志；`HyperliquidOwnerNonce` 统一订单与出金的 owner nonce 高水位，预约在同一文件锁内检查。只有未签名审核可取消/本地过期；签名开始后不因超时或重启释放，未知回执不可重发，API 接受不等于到账。记录层不直接发放设备签名或广播许可，新接入的独立许可层见上方「原生出金确认」，生产开关不变。

**基本资金与交易优先（2026-09-11，预生产）**：先完成 Arbitrum USDC 入金、出金与真实 IOC 市价交易；builder 地址/费率未定，首阶段订单明确不携带 builder。`Core/Trading/Execution/HyperliquidMarketOrderStore` 接入真实确认、设备签名、前后重检、一次性提交与持久化订单记录，复用加密 SQLite 及 Keychain 防回滚锚点；`HyperliquidOrderStatus` 按 cloid 校验终态，不虚构成交价/费用，未知结果不重试。`Features/Trading/LiveMarketOrderView` 替代普通下单及 Feed 快捷入口的模拟执行，个人主页应用账户不再显示虚拟余额/仓位。`Core/Trading/Funding/HyperliquidWithdrawalIntent/CCTPWithdrawalFeeReader` 与 `Core/Wallet/HyperliquidWithdrawalCodec` 准备出金协议和只读 CCTP 费用检查，尚无出金签名入口；完整费用、可提额、共用 nonce 日志和目的链到账仍须接入。生产开关、版本和真实资金验收边界不变，见 `docs/contracts/hyperliquid_execution.md`。

**Builder code 产品边界（2026-09-11）**：bSmart 仅作为 Hyperliquid 交易前端，不部署交易所或 HIP-3 市场。现有市场费用与 bSmart builder fee 分开；`HyperliquidBuilderFee` 固定订单收款地址/费率并参与订单签名编码，预览通过 `maxBuilderFee` 检查当前用户授权上限。未配置真实收款地址或费率，未授权、未收费、未下单；授权确认、签名提交与生产资格核验仍待完成。详见交易协议契约。

**真实委托深度预览（2026-09-11，预生产）**：`Core/Trading/Execution` 使用现有账户检查、原始市场费率及真实 `l2Book/userFees`，按 IOC 限价遍历深度，输出预计成交数量、未覆盖数量、均价、价格冲击和预计手续费。计算使用 BigInt 精确值，订单簿额外限制双时钟 5 秒。不代表足额保证金、签名授权或实际成交，交易开关不变。

**真实交易账户检查（2026-09-11，预生产）**：`Core/Trading/Execution/HyperliquidExecutionReader` 只查询固定主网 info 接口；`HyperliquidTradingSnapshotProvider/Snapshot` 保存原始市场、保证金限制、真实杠杆、仓位和逐方向容量，双时钟限制 15 秒，仓位服务端时间可进一步缩短有效期；读取前后核对模式、杠杆与仓位。订单约束检查不代替完整资金预检、用户许可、订单日志或成交对账，不启用真实下单。

**Feed 与个人主页 AI 入口（2026-09-11）**：根导航为「今日 / Smart / Feed / 个人主页」；`ProfileAssistantLauncher` 在个人主页右下角展开现有 AI 页，全屏期间用独立令牌隐藏 Tab，退出后释放。`Features/Feed` 展示按成交时间倒序的用户、作者、原观点及标的跳转；`TradeFeedStore` 管理分页与失效。`opinion_trades/feed` 从已核验订单聚合部分成交，新增 `/v1/trade-feed` 与公开用户页，只展示 Top 25% 作者和单独同意公开金额的账户。四个快捷块按红 100/500、绿 500/100 排列，只预填真实确认页，不自动成交或写真实 Feed。真实核验及公开金额同意服务未启用时返回 503；`feed_migration.sql` 仅准备，未执行或部署。契约见 `docs/contracts/trade_feed.md`。

**Hyperliquid 真实订单协议层（2026-09-11，预生产）**：`Core/Trading/Execution` 保存原始 DEX/资产索引、抵押币和精确十进制 IOC 委托；`Core/Wallet/HyperliquidOrderCodec` 用固定 MessagePack 依赖及既有 Wallet Core 编码 L1 action、校验签名。回执区分拒单、完整/部分成交与未知状态。协议编码本身不构成下单许可；设备签名及提交只能经上述日志许可进入。实际成交费用/fills 对账、真实仓位展示和完整退出链路仍须验收。契约见 `docs/contracts/hyperliquid_execution.md`。

**CCTP 原生转入确认（2026-09-11，预生产）**：钱包面板的 `CCTPTransferView/Content` 接入现有报价、设备签名、日志及一次性广播；`CCTPTransferStore` 编排金额审核，`CCTPTransferDisplay` 只投影金额、地址、费用、期限与公开哈希。授权、网络费签名、提交逐步确认，过期/不确定结果进入原入金记录；核心操作默认禁止，使用实时开关和当前钱包检查。账户维护不因暂时 inactive（系统认证提示）重新恢复，真正退后台仍作废权限。未开放生产资金，未改变记账/真实交易的验收边界。

**Arbitrum 原生收款页（2026-09-11，预生产）**：`Features/Account/ArbitrumReceiveView/Content` 从钱包面板进入；`ArbitrumReceiveStore` 核验当前账户、已备份设备钱包与最新注册地址，并要求网络确认。`WalletReceiveAddress` 用既有 Wallet Core 生成校验地址，二维码由本机 Core Image 生成；复制限定本机、五分钟过期。地址检查受双时钟 60 秒限制，切账户/退后台/取消确认清除，迟到响应不恢复旧地址。不新建密钥、不转账、不将钱包收款计为 HyperCore 入账。生产开关仍关闭，完整入金、真实订单与退出链路仍待验收；契约见 `docs/contracts/trading_account.md`。

**账户删除与授权撤回（2026-09-11，预生产）**：`accounts/deletion_routes/repository/work/service` 先持久化请求、撤销全部会话，再以固定 Apple 端点撤权和事务清理账户数据。iOS `AccountDeletionRecord/Storage/Coordinator` 以独立 device-only Keychain 保存进度；`Features/Account/AccountDeletionView` 提供钱包风险确认、原账户重新认证、状态恢复及 Google 撤权。`GoogleAccountDisconnect` 隔离超时与迟到回调，`DeviceAccountDeletionCleanup` 清理个人资料并阻止旧编辑器写回，不碰私钥/入金日志。删除用 `/sessions.expectedAccountId` 只认证现有匹配账户、不重建已删除账户；存储异常和重新认证废止旧签名许可。后台 worker 只在开发/测试显式开启，不自动迁移。真实 provider、过期/遗失查询凭据恢复、真机、完整资金链路和生产运维仍须验收；契约见 `docs/contracts/account_deletion.md`。

**Apple 原生凭据检查（2026-09-11，预生产）**：`Core/Data/AppleCredentialStateClient` 以 10 秒超时、取消及迟到回调隔离封装系统检查；`AppleCredentialMonitor` 合并进行中的请求。`AccountAccessStore` 在恢复、钱包访问与前台维护时校验，原生撤销通知经主队列废止检查与签名许可；错误保留凭据但禁止资金操作，明确失效清除应用会话并尽力撤销会话族，不删除钱包。版本 3 Keychain envelope 原子保存本地 Apple 标识、精确时间与续期状态，不新增 HTTP 身份字段。检查和 `FundingSigningLease` 同时受系统日期与 `ContinuousClock` 最多 60 秒约束，续期/延迟签发/设备调时不能延长旧许可。契约及 iOS 专题已同步；真实 provider/真机验收、账户删除与完整资金链路仍未完成，生产开关不变。

**身份安全事件（2026-09-11，预生产）**：`accounts/security_event_routes/verifier/repository` 接收 Apple JWS 与 Google RISC SET，以固定来源公钥验证签名、audience、issuer 和事件时间；`provider_http` 隔离继承认证并限制 JSON 大小。哈希回执、subject 撤销时间屏障、受影响会话和 Apple grant 撤销原子提交；保留初次 provider 认证时间，迟到事件不撤销更新的交互登录，禁用身份阻止新登录。iOS `AccountAccessStore` 收到当前账户/钱包请求的 401 后清除应用会话、取消续期和签名许可，不删除钱包；旧响应不能退出新账户。`security_event_migration.sql` 仅供人工审核，本次未执行；真实通知流注册/验收、应用账户删除和生产运维仍待完成，原生检查见上。契约见 `docs/contracts/account_security_events.md`，生产资金开关不变。

**账户会话续期（2026-09-11，预生产）**：`accounts/session_renewal` 增加安装绑定的一次性凭据轮换，访问会话 30 分钟、闲置 24 小时和会话族绝对 7 天上限；重放先提交整族撤销再返回 401。同账户同安装重新登录替换旧族，其他设备不受影响。iOS `AccountSessionRenewal` 合并并发请求，`AccountSessionStore` 在 Keychain 先持久化续期中状态；丢失响应/重启不重放旧凭据，退出用整族撤销且不删除钱包。前台恢复和钱包读取前续期，恢复/续期期间禁止资金授权并废止旧签名许可。`session_renewal_migration.sql` 仅供人工审核，本次未执行；provider 撤销/删除、生产数据库并发和真机验收仍待完成，真实资金开关不变。契约与 iOS 专题已同步。

**Apple 授权码交换（2026-09-11，预生产）**：iOS `AccountIdentityAssertion` 将系统 ID token 与一次性授权码传到独立账户 API；Google 请求仍只带 ID token。`accounts/apple_oauth` 固定 Apple HTTPS 端点、短时 ES256 客户端凭据、不重试；`apple_repository` 在外部请求前原子消费 challenge，二次校验返回身份后把会话与加密授权凭据一起提交。`credential_cipher` 使用 AES-256-GCM 与账户/subject/client/key 上下文绑定，密钥由运维通过受保护文件提供；不接收钱包私钥。新增 `apple_grant_migration.sql` 仅供人工审核执行，本次未迁移。退出原生账户页取消登录，晚返回不发布身份。授权撤销/删除、真机与生产凭据仍待完成；应用会话续期见上，真实资金开关不变。部署要求见 `services/client_api/accounts/README.md`，契约与 iOS 专题已同步。

**HyperCore 真实余额查询（2026-09-11，预生产）**：`Core/Trading/Funding/HyperCoreBalanceClient/Provider/Snapshot/Store` 仅向固定主网 `/info` 查询已注册 owner 的账户模式、USDC 和默认永续余额；统一账户与组合保证金读取 spot，其他模式分项展示，不相加、不推导下单额度。钱包页 `Features/Account/HyperCoreBalanceView` 提供显式刷新，30 秒失效并隔离过期会话、账户切换与迟到响应。金额精确处理至 8 位，失败显示未核实而非零；不写模拟资金、不签名/转账。原生公开地址只读检查已通过；余额不是单笔入金凭据，HyperCore 系统 nonce 与目标 EVM 交易映射、真实订单和生产验收仍待闭环。详见入金研究与 iOS 专题。

**观点交易人数（2026-09-11，未开放真实成交）**：`Features/Smart/OpinionTradersSection` 在观点详情展示去重人数及可展开、分页的公开交易者；`TradeAccessView` 仅向该观点自身的交易 sheet 传递 `OpinionTradeSource`，关闭后重读统计，不本地加数。`services/client_api/opinion_trades` 提供已核验成交只读接口、去重账本与公开资料/撤回边界，同账户同观点计一次，按最近成交排序。默认服务返回 503，不以模拟成交或历史 fixture 冒充真实人数。真实执行核验、公开资料/同意服务和人工迁移尚待接入，未部署、未执行 DDL；契约、上线闸门见 `docs/contracts/opinion_trades.md`。

**iOS 个人主页（2026-09-11）**：根导航调整为「今日 / Smart / Feed / 个人主页」，保留 `portfolio` 内部路由与原有资产、持仓、关注及全部标的内容。`Features/Portfolio/UserProfileHeader/UserProfileEditor` 提供头像、昵称、简介和地址展示；`Core/Data/LocalUserProfileStore` 按账户 UUID/访客隔离本地资料，头像缩略存储。地址仅取当前账户匹配的已验证设备钱包；否则明确展示不可复制的示例地址与禁止转账提示，不自动创建钱包、不修改身份认证及资金链路。详见 iOS 专题。

**入金目标链转发回执（2026-09-11，预生产）**：`Core/Wallet/CCTPForwardEventCodec` 核对固定合约的消息、USDC 转移、HyperCore 路由和金额事件；`Core/Trading/Funding/CCTPForwardReceipt/Observer` 在批量转发中按认证 nonce 隔离单笔证据，复查 HyperEVM canonical block、receipt 和 nonce。`CCTPForwardObservation` 写入原加密日志，关联当前源链及认证观察；已接纳回执不能被空响应或另一笔交易替换。历史页显示永续转发、现货回退、实际转发请求金额及合约开户扣费，不记入可用余额。CCTP 净额预览不再承诺最低 HyperCore 到账；开户费文档差异、实际逐笔 HyperCore 记账和真实交易仍须验收。无实际广播、转账、生产入口开放或私钥上传。

**浅色模式可读性（2026-09-11）**：`BSmartTokens` 区分页面/卡片/内凹背景、深色文字强调色、实心控件 `onAccent` 和浅色编辑卡片专用底色；页面不得再把固定 `pulseInk` 放到会变深的品牌/涨跌背景上。共识、阿尔法、Smart Money、导航与统一价格图消费对应角色，仅调整显示，不改布局、数据或交易逻辑。`BSmartAppearanceContrastTests` 回归浅色文字、徽章、图表和深色原配色，详见 iOS 专题。

**入金 CCTP 认证核对（2026-09-11，预生产）**：`Core/Wallet/CCTPAttestedMessage` 将 Circle 签名消息与已验证的源链消息逐字节比对；`Core/Trading/Funding/CCTPMessageClient` 只查询固定源链交易哈希，`HyperEVMAttesterReader` 按 HyperEVM 合约的实际签名门槛与启用账户校验。默认 RPC 仅支持 latest 状态，前后链头必须一致且新鲜。`CCTPAttestationObservation` 独立加密留档并关联本次源链证据，保留上次有效认证以拒绝回退；迟到结果不得覆盖新证据。历史页增加显式跨链查询及认证/过期/暂停状态，不把签名、转发哈希或 nonce 已使用当作 HyperCore 到账。生产入口仍关闭，目标链转发回执、逐笔到账、真实交易及完整安全验收尚未完成。

**入金源链回执与查询（2026-09-11，预生产）**：`Core/Trading/Funding/ArbitrumSourceObserver` 只按日志中的已签名哈希查询固定 Arbitrum RPC；`FundingReceiptCodec` 核对完整交易、回执与日志，`Core/Wallet/CCTPSourceMessage` 验证固定金额/路径/owner hook 的源链消息。`FundingSourceObservation` 关联 canonical/finalized 区块、nonce 与授权状态，以独立事件写入原加密日志；迟到查询不能覆盖新记录，失败或重组不释放原交易。`FundingHistoryStore` 显式查询前复核注册账户，返回的已验证证据先归档再处理旧 UI；历史页展示源链执行、实际网络费和 RPC 最终性，均不表示 HyperCore 到账。无自动查询/重发、不接入模拟余额；逐笔跨链到账、终态释放、生产确认/提现/交易与真机安全验收仍待完成。离线回归与协议来源见 `docs/product/arbitrum-usdc-funding.md`。

**原生 K 线统一（2026-09-10）**：`Core/DesignSystem/BSmartPriceChart` / `BSmartCandlestick` 统一交易页、下单面板、观点证据、作者代表作、Smart Money 开仓图及 Today 历史时间线；`BSmartPriceChartData` 管理只读绘制数据与有界视窗，`BSmartChartGestures` 管理缩放、平移与查价，标记布局也归设计系统。业务页面只适配原有数据和证据跳转，不再自行绘制蜡烛或复制坐标轴；市场/股票数据源、原始观点和 Score 均不变。扩展规则与回归口径见 `docs/operations/ios-market-charts.md`。

**设备入金授权、提交与恢复（2026-09-10，预生产）**：`Core/Trading/Funding/FundingTransactionJournal` 在独立加密 SQLite 中保存前置确认、USDC 授权、源交易与提交状态；`FundingConsentRecord/JournalEvent` 保留旧事件并以同一 ID 原子关联授权和交易。`Core/Wallet/FundingDeviceSigner` 只签固定授权与源交易；`CCTPDepositPreparation` 先核对账户/源链余额，再分别确认授权和网络费，签名产生后先留档再处理取消。最多 60 秒的权限在退出/重载账户、退后台或设备锁定时撤销。新增 `ArbitrumSourceSubmissionCheck` 以原签名、gas/费用上限再次核对源链状态；10 秒检查不延长原确认。日志提交后的一次性引用许可才能启动 `ArbitrumFundingBroadcaster` 的固定 `eth_sendRawTransaction` 请求，无自动重试；超时/错误保留不确定记录，取消后的已观察响应也先归档。`FundingHistoryEntry/Store` 向钱包面板提供不含签名和可广播字节的投影；未签名确认可经日志复核后取消，已签名/提交记录不因超时释放。仅离线提交测试通过，尚未真实广播；真机文件保护、receipt/重组/跨链对账、资金确认页接入、退出路径及生产审核仍待完成，不代表已到账或可交易。契约和证据见 `docs/contracts/trading_account.md`、`docs/product/arbitrum-usdc-funding.md`。

**X 数据包日更（2026-09-10）**：`pipeline/jobs/x_daily` / `x-daily` 将用户上传的 JSONL/ZIP 串成检查、幂等导入、限定本包抽取、行情补充、既有结算/Score、完整翻译和 read-model 导出，保留按内容哈希的续跑记录；不执行 DDL、不改算法或正式 Top 25% 观点范围。`services/client_api/publish_daily_x` 校验 manifest、客户端必需字段和版本，备份后原子替换三个 Smart Account 集合及既有事件投影的 X 分区，保留其他平台和用户状态。通用 X 事件投影迁入 `client_api/smart_account_signals`，实时服务保留兼容导出。iOS 前台刷新补上作者榜单及代表作更新，条件请求支持鉴权后的 304，网络失败保留缓存。操作与首次上线闸门见 `docs/operations/x-daily-package.md`；本轮未上传真实新包、未完成 Vultr 发布，不将本地准备视为已上线。

导出链路中的 Reddit 已验证头像目录读取器收敛到 `pipeline/common/reddit_profile_avatars.py`；平台目录保留兼容导出与原 JSON 目录，避免 domain 反向导入 platform。头像、作者关联和排序不变。

**Arbitrum 源交易编码（2026-09-10，预生产）**：`Core/Wallet/CCTPSourceTransaction` 将新鲜预检固定为 EIP-1559 type-2 交易，重验完整 USDC 授权/calldata、账户、nonce、金额与费用；`FundingEthereumSignature` 区分 EIP-3009 与交易恢复位并拒绝高 S。`Core/Trading/Funding/CCTPSourceGasBudget` 统一模拟和编码的 gas 上限算法。固定 Wallet Core 编译经恢复验证的签名，生成不可变交易字节与本地哈希；独立 Python 向量核对，不读设备私钥、不广播。设备日志已补充（见上），实际提交恢复、跨链记账、真实交易及生产审核仍待完成，正式资金入口不因此开放。

**Arbitrum 入金预检（2026-09-10，预生产）**：`Core/Trading/Funding/ArbitrumSourcePreflight` 通过固定只读 RPC，在同一个 canonical block hash 检查真实 USDC/ETH 余额、EOA、Circle 合约配置/限制/额度；`CCTPSourceReadCodec` 负责静态 ABI，`FundingQuantity` 使用固定 BigInt 5.7.0 精确处理 uint256。已验证的单笔授权才能进入模拟执行和 gas 预估，费用/nonce/区块/账户/时效任一检查失败即作废。`Features/Account/ArbitrumWalletBalanceView` 提供手动查询，仅显示设备钱包余额，不记入 HyperCore 或练习账户，退后台/切账户清空。正式资金签名、持久日志、跨链对账、提现及真实交易尚未开放；公开 RPC 和合约 getters 不替代生产 SLA、实现字节码审计或独立安全审核。详见 `docs/contracts/trading_account.md` 和入金调研。

**CCTP 入金准备（2026-09-10，预生产）**：核对官方最新 USDC 文档后，新计划不再使用已弃用的 Bridge2 / 固定 5 USDC 最低额。`Core/Trading/Funding` 固定 Arbitrum 原生 USDC → Circle CctpExtension → HyperEVM forwarder → 当前 owner 的 HyperCore 默认永续账户，提供官方费用查询、精确整数报价、60 秒失效与不可变计划；`Core/Wallet/CCTPDepositCodec` 用固定 Wallet Core 编码 EIP-3009/ABI 并校验签名，不读取私钥或广播。入金准备页可查询费用和净额，仍不开放收款；后续余额/gas 预检见上条，持久交易日志、逐笔签名/提交与跨链对账、提现及真实执行待完成。契约见 `docs/contracts/trading_account.md`，协议更新和证据见 `docs/product/arbitrum-usdc-funding.md`。

**账户与 Arbitrum USDC 准备（2026-09-10，预生产）**：`services/client_api/accounts` 提供 Google/Apple 令牌校验、一次性 challenge、独立短时会话及钱包地址绑定；不保存钱包私钥、不自动跑迁移，也不替代研究安装会话。`Core/Data/Account*` 与 `Features/Account` 提供原生登录和入金准备，入口为设置“账户与钱包”；Google SDK 固定 9.2.0，外部登录配置未完成。新增 `Core/Wallet` 以 OS 熵和固定 Wallet Core 4.8.1 发布包实现设备钱包、标准 24 词恢复、Keychain 保护和固定 EIP-191 绑定签名；`wallet_repository/proof/routes` 验证签名并原子绑定唯一账户/地址，已有地址不替换。恢复词不上传，备份需完整重输，切换账户/退后台清理 UI；并发初始化遗留密钥保留不覆盖。`ArbitrumDepositPolicy` 只校验链/原生 USDC/整数金额。生产入口与资金能力仍关闭：真机恢复、真实 OAuth、链上对账、入金/提现/交易签名、账户生命周期、独立安全审核待完成。契约见 `docs/contracts/trading_account.md`，发布闸门见 `docs/product/arbitrum-usdc-funding.md`。练习余额保持隔离。

**代表作补全与早期判断（2026-09-09）**：Client Read Model 作者列表新增可选 `representativeWork` 轻量摘要，首页/目录不再逐人等待全文和 K 线；`domain/smart_voice/client_read_model.py` 保持累计加分最高的三个标的排序，每个标的改用最早有效加分 Call 作为主观点，保留该点与最多九个高分点。`representative_intro.py` 投影同一条观点的日期、方向、结算涨幅和发帖前已完成日线参考价，不重算 Score，不倒填未来成交价。iOS `TodayInvestorDiscoveryWork` 在原简介高度内展示 Logo+ticker、日期/参考价及可追溯明细，详情默认也选择该早期观点。AppModel 网络错误不再永久缓存空证据。`jobs/smart_voice/representative_intro.py` 支持只读真源、dry-run 和本地快照补全；旧证据正文/译文保留。当前首页 87/87 候选齐全，全体 342/353 有代表作、341 位有历史参考价；其余不伪造，不等于生产发布。规则见 `docs/contracts/smart_account.md` 和 `docs/product/investor-discovery-home.md`。

观点详情的阅读层位于 `Features/Smart/OpinionReaderView.swift`：现有 bSmart 摘要与作者正文分层，原文/完整译文点选切换，不再连续重复展示；正文无外框、支持动态字号和逐字复制。`OpinionReadingDocument` 只按原段落及系统句子边界组织长文，保留标题、列表、数字、条件与链接；仅将能在原文逐字或空白等价匹配的证据片段在原文内突出，不把译文或摘要伪装成引用。无翻译时回退原文，资料依据、历史结算、行情及交易入口保持原有功能；不改接口、采集、Score 或正文数据。

---

## 0. 架构文档导航与模块边界

首页投资者发现评审位于 `docs/product/prototypes/investor-discovery/index.html`：A 头像池与焦点人物、B 逐人发现、C 按赛道选人、D 从观点识人。使用本地作者/观点快照，支持并排/单屏、追踪、目录与证据；仅 HTML 评审，不替换当前 SwiftUI 首页，不更改 Score、API 或生产数据。

融合版原型位于 `docs/product/prototypes/investor-discovery-unified/bsmart-discovery-unified.html`，其交互已落地 SwiftUI 首页 `Features/Today/TodayInvestorDiscovery*`。当前上半屏只保留人物池、作者赛道筛选、可搜索目录和连续人物档案，不再重复提供“看观点”入口。原生只消费 AppModel 的显式平台 Top 25% 排名，不引入 HTML 快照、示例仓位或新的 Score；追踪写入原有持久化状态，详情复用 `SmartAccountDetailView` 及代表作。规则见 `docs/product/investor-discovery-home.md`。

高表现力评审版位于 `docs/product/prototypes/investor-discovery-expressive/bsmart-discovery-expressive.html`：头像群像、人物卡、赛道与观点共用只读作者快照，追踪形成个人研究阵容，可导出人物/阵容/观点 PNG 卡片。单文件离线可用，分享保留日期、排名口径与摘要边界；仅设计评审，不替换原生实现、不修改 Score/API 或生产数据。

**观点相关依据（2026-09-09）**：`Features/Smart/OpinionSupportingSourcesView.swift` 在原文/译文之后展示有对应事实的资料，点击卡片沿用共享元素转场进入独立详情，保留摘要、对应表述、短摘录与原文链接。支持公司披露、监管文件、媒体、研究、数据等可归属来源；不提供官方渠道追踪/通知，没有有效依据时整块不渲染且不影响作者信任分。`SmartAccountUpdate.supportingSources` 为可选契约；`pipeline/domain/opinions/supporting_sources.py` 从逐帖审核目录匹配平台、作者、原帖、标的及逐字表述，由批量导出和 X realtime job 在发布前投影，Client API 只保存/返回结果，不执行检索或算法。首批关联现有两条历史观点，尚未建设自动全网检索服务；更正/撤回在重新导出发布后生效，Score 与观点算法不变。现行方案见 `docs/product/opinion-supporting-sources.md`，契约见 `docs/contracts/opinion_supporting_sources.md`。原 `official-context` HTML 是历史研究原型，官方频道及缺失提示已明确不采纳。

**本地资料抓取样本（2026-09-09）**：`pipeline/platforms/source_documents/web.py` 负责公开 HTML、robots、限速、公共 IP 固定连接与缓存；`domain/opinions/crawled_sources.py` 校验具体表述、文章标题、事实摘录及时间；`jobs/opinion_source_crawl.py` 仅运行 `local_crawl_samples.json` 指定的少量观点。默认 dry-run，`--apply` 更新独立 `crawled_sources.json` 并与人工目录合并导出本地 fixtures。新增 4 条观点的 5 条资料，旧历史样本保留。来源可选 `updatedAt` 保留修订时间；发布或修订晚于观点的版本标为后续资料，不倒填当时依据。这是人工选题和摘要、规则驱动抓取验证的本地实验，不是通用语义搜索，不启动常驻任务、不部署、不修改数据库或排名。

Today 顶部由 `TodayInvestorDiscoveryModule` 替换价格观点图，无持仓用户也能发现投资者；下方 `TodayHomePager` 继续提供“持仓与追踪 / 市场情况 / 聪明动态”三个文字标签页。发现区只有一个实例，不参与横向分页；三个原生垂直滚动页独立保存位置，标签栏在发现区滚出后吸顶。`BSmartCollapsingScrollState` 只协调 UI 滚动，不接管 ScrollView delegate、不改图表数据或排序。方案落点见 `docs/product/today-home-navigation.md`。

首页主模块以“发现聪明投资者 / 他们怎么看市场”区分人物与观点，复用 `TodayHomeSectionHeading` 的 20pt 标题和小图标；第二标题在共享头部中只出现一次并随头部滚出。下方三个标签继续左对齐，字号 16pt；`TodayEditorialSectionTitle` 统一下级模块为 15pt，追踪动态同步使用，支持 Dynamic Type，不加解释性小字。持仓观点行通过独立浅底色、细边框和间距区分，分组不重复套卡；排序、来源及详情路由不变。

首页顶栏保留“今日”、帮助和设置。`TodayInvestorPool` 只编排发现展示：头像沿单条水平线排列，不采用环绕；中央大头像显示真实平台 Top 比例，两侧头像依距离递减，各带来源标识。默认聚焦 X 账号 `@aleabitoreddit`，仅在其仍符合当前筛选条件时采用，首屏两侧优先展示 3 位有头像的合格 YouTube 作者及 1 位有头像优先的 Reddit 作者（含已核实的内置头像映射）；剩余候选同样将有头像者前置，同组保留原顺序，无头像者不删除。排名、资格和完整候选覆盖不变。`SmartPlatformMark` 使用 Asset Catalog 的 `PlatformReddit` 内置橙白 Snoo 图片，不再用 `r/` 文字替代；资源复用仓库已有平台 Logo，无运行时网络依赖。`TodayInvestorDiscoveryPeople` 使用原生横滑居中吸附，仅由用户横滑或点击头像切换，移除定时横移、播放/暂停按钮及人数/进度行。简介卡取消裸 Score 和重复平台文字，固定高度内显示风格与首个既有贡献排名代表作的方向、结算窗口及标的股价变化；无代表作回退真实覆盖领域/标的，不把股价涨幅包装成账户收益。`TodayInvestorDiscoveryHighlight` 优先消费作者列表内置代表作摘要，旧数据缺失时才在焦点稳定 650ms 后复用 AppModel 按需证据缓存，目录不批量请求。下方三标签内容与详情图不变。

**Reddit 作者头像（2026-09-10）**：`platforms/author_assets/reddit_profile_avatars.json` 记录按公开主页核实的身份与完整头像 URL（含平台默认头像，不等同自定义头像，部分为搜索索引快照）。Client Read Model 仅在 Reddit 头像缺失时按作者 ID 补齐；`scripts/sync_reddit_profile_avatars.py --apply` 投影本地作者、观点/代表作及 iOS 身份映射，`sync_ios_author_avatars.py --reddit-only` 沿用精确 URL 哈希打包。共享头像控件在源 URL 缺失且展示名明确为 u/账号时才使用同一映射，不覆盖在线有效头像、不按相似姓名猜图。首批 13/31 位作者、11 张不同源图片已核实打包；18 位仍待核实（公开访问验证/资源不可获取），不伪造其头像。无数据库写入、无评分变更、未发布生产。

作者头像由共享 `BSmartAvatar` 统一读取：优先匹配完整源 URL 的内置 `AuthorAvatar_*` 小图，未内置的图片通过 `Core/Data/AvatarImageStore` 请求合并、最多 4 并发、后台解码和有界内存/磁盘缓存加载；回到前台可重试，失败不缓存成头像。`scripts/sync_ios_author_avatars.py` 只读现有模型的公开头像地址，维护 `ios/asset-sources/author-avatars.json` 与 URL 哈希注册表；可显式允许构建期公共图片中转，App 不依赖该中转服务。没有头像地址的作者继续显示占位，不按姓名猜测身份，不改变 API、作者池或 Score。

三标签阅读节奏评审原型位于 `docs/product/prototypes/today-reading-rhythm/index.html`，可直接本地打开，支持并排与单屏预览。其布局已落地到原生 iOS；HTML 中的示意行情、样例仓位与追踪状态不进入 App。

原 `TodayPortfolioNowModule` 行情组件保留兼容，但首页不再装载其行情 session。标的详情和下单页仍共用 Hyperliquid 公开 Info API 与市场选择规则（优先 xyz，缺失或失败才查其他 venue），现价与 24h 涨跌来自同一 coin 的 markPx/prevDayPx，不从持仓快照或观点证据推导行情。行情请求按版本、coin、interval 隔离，过滤无效 OHLC/重复时间。`Core/DesignSystem/BSmartCandlestick` 继续统一详情及下单页蜡烛绘制；交易仍为既有本地模拟边界。

“持仓相关”位于第一个标签页。`TodayHoldingsActivity` 只匹配声明为持仓的股票（含仅填占比的持仓，不含自选与本地模拟交易仓位），从已有 Smart Account / Smart Money 中选取近 30 天最新来源动态；同一新鲜度档内按已知仓位占比排序，不重算 Smart 评分。首页先按来源筛选再沿用 3 条分散标的预览，全量页另支持标的筛选。`TodayHoldingGroupHeader` 每组只展示一次标的/仓位，`TodayHoldingsActivityRow` 使用独立底色和细边框区分摘要与来源卡片；组间按首次出现顺序排列，组内保持原顺序。追踪动态采用轻量行；观点进入原始证据页，资金操作直接进入对应 `SmartMoneyMovementDetailView`，不回退到同标的其他钱包。设计依据及边界见 `docs/product/holdings-related-activity.md`。

Today 的“单独观点”已替换为第三个标签页的“聪明动态”；追踪动态留在第一个标签页并改为纵向列表。`TodayInvestorActivity` 按平台 + 作者 ID / 钱包账户 ID 聚合真实近 30 天的现有动态，跨标的保留原始事件，按最新时间排序；不受持仓筛选限制、不重新评分、不合并未知身份。`TodayInvestorActivityModule` 首页展示 3 位投资者，每人最近 2 条；完整列表按来源和投资者/标的搜索叠加筛选。`TodayInvestorActivityCard` 保留兼容名称，实际以无外框作者时间线展示：日期分隔、一次头像/平台/名称/排名、缩进观点序列与追踪按钮；单条动态进入原始证据，“全部动态”进入该投资者的时间线。无持仓或无数据时仍保留模块与明确空态。

持仓页为统一资产工作区：顶部 `外部持仓 / bSmart 账户` 与估值图随整页纵向滚动收起，仅保留吸顶的文字下划线标签按 `自选 / 持仓 / 全部标的` 排列，支持点选和原生左右分页，不显示系统分段控件。三个列表保留独立滚动位置，切换不重建顶部曲线；持仓列表随资产账户切换，自选和全部目录不受影响。`PortfolioValueChart.swift` 提供 1D/1W/1M/全部、稀疏日期刻度和拖动估值点。`Core/Data/PortfolioValuationHistory.swift` 整理有效快照、去重与限量保留；AppModel 仅导入与当前持仓构成一致的服务端历史，并本地持续保存完整估值，数量/组合变化开启新记录段，不用现价倒推历史。交易账户在成交及盯市时记录现金+保证金+未实现盈亏，不把杠杆名义规模计入权益；旧账户无历史时仅显示已知单点，不制造走势。`PortfolioHoldingSnapshot.swift` 与 `PortfolioHoldingRow.swift` 保留成本、现价、价值和持仓回报；`PortfolioAppAccountView.swift` 保留现金/仓位权益。行情列表名称/价格维持紧凑字号并隐藏平台名称，底层 coin/venue 标识不变。

Today 与 Portfolio 复用 `Core/DesignSystem/BSmartCollapsingPager.swift` 及 `BSmartCollapsingScrollState.swift`（原 Today 专属协调器），整页滚动和吸顶只处理 UI，不接管 ScrollView delegate、不改变行情和评分。Portfolio 三个内容模块不再内嵌第二层垂直 ScrollView；目录搜索聚焦时将头部滚出，取消搜索后保持用户阅读位置，可下拉恢复估值图。`Features/Research/TickerDirectorySections.swift` 沿用首页现有热门标的选取结果置顶最多 10 个，复用完整目录中的同一报价/标识；下方按原顺序展示其余标的，不重复、不减少覆盖。搜索同时覆盖热门与普通标的，进入搜索后统一展示匹配结果，不硬编码热门股票池。

持仓、关注与全部标的复用 `Core/DesignSystem/BSmartMarketRow.swift`，展示单价、24h 涨跌及同一市场的名义成交量，缺失不填零；金额统一使用 `BSmartMoneyFormat` 的美元符号格式。标的图标随 Asset Catalog 内置，`scripts/sync_ios_ticker_logos.py` 维护资源与 `ios/asset-sources/ticker-logos.json` 来源/哈希审计，`TickerLogoRegistry` 用于完整性测试。

Today 的市场标签页由 `TodayMarketActivityView` 展示两张热门卡片和两条轻量 `TodayAlphaDiscoveryRow`，更多进入完整列表；取消首页卡片内层横滑和穿插轮播，避免与切页手势冲突。首页与热门标的列表复用 `TodayViewpointPackageCard`，采用浅绿/浅蓝底和深色文字，预览采用容器宽度、232pt 基准等高和 12pt 上下间距，完整列表仍用 264pt 基准等高。顶部展示最近三位作者；正文先展示单条摘要，底部展示该作者头像、平台标识、名称、Top 比例和发布时间；摘要取 Top 25% 作者中最新的一条（无符合者回退到包内排名最高的作者）。Alpha 条目只预览第一条来源摘要及该来源的身份/排名，完整详情仍保留所有证据。热门和 Alpha 均独立进入详情并保留共享元素转场；平台标识复用 `Core/DesignSystem/SmartPlatformMark.swift`。原 Rail 组件保留兼容，不用于新首页。市场与聪明动态不再以是否有持仓作为可见性条件。

iOS 标的导航统一使用 `Features/Research/TickerDestinationView.swift`，每个详情独立行情 session；`Core/Data/AppTickerCatalog.swift` 合并持仓、Smart 覆盖、摘要与 Hyperliquid 目录，缺少报价不填 0。下单页由 `TradeLeveragePicker` 提供横滑杠杆刻度，复用行情图切换键盘/K 线，方向只在底部确认操作中体现。

所有标的复用 `TickerIntelligenceView(symbol:)`，不再按是否存在 NVDA 式研究快照分成正式页与简化页。价格图下展示用户持仓、概览/Smart Activity/交易；市场选择器同时切换简介、动态、持仓和交易目标。`TickerDetailSections` 复用两类持仓口径；`Core/Data/TickerProfile` 保存带公司官网来源的双语简介，缺失明确留空，不定义新的股票池。`HyperliquidMarketChart` 独立为共享行情图，详情可开启观点头像；`TickerChartOpinions` 按 1H/4H/1D/1W/1M 最多选 3/4/5/6/7 个主体，头像 38/36/34/30/28pt，完整触控区域与排名标签参与碰撞检测。同主体取最新，分来源按既有排名/分数排序，不重算 Score；时间窗外观点不贴到边缘，不把股票原始证据价格混入永续合约坐标。点头像直接进入证据，窗口全量动态仍可查看。切换行情周期的异步结果按请求版本与 coin/range 校验，防止旧响应覆盖。

标的页概览只展示资产简介与市场事实，Smart Activity 独立展示动态。`Supporting/ticker-profiles.json` 扩充离线双语资料，连同 `TickerProfile` 共覆盖 47 个主要标的，保存官方来源，ETF 与公司分开描述；未知标的不编造简介。顶部星标直接写入既有关注列表，已有持仓保持追踪且不被关注操作覆盖。`Features/Smart/SmartSubjectDestination.swift` 统一观点、动态、共识及 Alpha 身份区域的共享元素主页入口；图表气泡和观点正文仍打开证据。观点详情不再展示结构化 Call 与审计模块，原文、译文、历史结果及后台证据字段保留。

作者详情仅保留概览与历史表现两个分区，概览内可展开全部最新观点。`Features/Smart/SmartAccountRepresentativeWorks.swift` 在单一图表区域切换最多三个既有排名代表标的；图表支持 K 线/折线、点击编号观点与下方证据联动。`RepresentativeWorkChartModel` 仅整理有效 OHLC 与既有贡献排名前三的窗口内观点，标记不跨时间窗夹到边缘，44pt 点击区避让；切换标的重置所选观点，单条观点贡献与标的累计贡献不混用。原有 Score、代表作筛选及 Smart Money 图表不变。

根目录 `ARCHITECTURE.md` 保持为项目活地图，记录当前系统事实、数据真源、主要目录和关键命令。长期设计边界已拆到专题文档：

- `docs/product/product-direction-mvp.md`：第一阶段产品决策真源，定义持仓事件、Smart Account / Smart Money、覆盖策略和 iOS/Web 分工。
- `docs/product/hyperliquid-trading-pivot-2026-09.md`：交易前端转向、模拟交易边界、Builder Code 路线和竞品取舍。
- `docs/product/prototypes/today-home-tabs/index.html`：首页三子页的 A/B/C 历史交互评审原型及竞品研究；当前 SwiftUI 布局以 `docs/product/today-home-navigation.md` 为准，不改评分、接口或生产数据。
- `docs/architecture/00-overview.md`：系统总览、当前真源和迁移策略。
- `docs/architecture/01-frontend.md`：Next.js 前端 feature/shared/server 边界。
- `docs/architecture/02-pipeline.md`：Python 管线 platforms/domain/jobs/cli 边界。
- `docs/architecture/03-data-model.md`：raw/normalized/analysis/rollup/export 数据层级。
- `docs/architecture/04-platform-adapters.md`：新增平台适配器规范。
- `docs/architecture/05-smart-account.md`：Smart Account 工程边界。
- `docs/architecture/06-deployment.md`：静态构建、数据快照与部署。
- `docs/architecture/07-conventions.md`：命名、文件大小、验证和文档同步规则。
- `docs/architecture/08-development-rules.md`：后续新功能开发落点、禁止落点、常见场景和验证清单。
- `docs/architecture/09-ios.md`：iOS 主客户端、SwiftUI 模块、API 消费和发布规则。
- `docs/architecture/10-congress-score.md`：美国国会两院公开交易评分的来源、结算、输出和隔离边界。
- `docs/operations/smart-money-live.md`：Hyperdash 主源、Hyperliquid 降级、原子发布、健康阈值与事故处置。
- `docs/operations/ios-market-charts.md`：iOS 首页/详情/交易图的 Hyperliquid 行情口径、刷新、OHLC 验证和原生回归记录。

跨平台产品契约位于 `docs/contracts/`：`opinion`、`author`、`ticker`、`judgment`、`smart_account`、`narrative`、`congress_score`。新增平台、观点筛选、Score、目标价、叙事等功能前，先确认 `docs/architecture/08-development-rules.md` 和对应 contract。

**iOS-first MVP（2026-08-03）**：`ios/` 是第一版产品的主客户端，使用 iOS 17+ 原生 SwiftUI；`contracts/openapi/bsmart-v1.yaml` 和 `contracts/fixtures/` 是客户端接口与开发数据入口。iOS 不读 `data/dev.db`、不直接调用平台 API、也不重算 Score。现有 `web/` 保留为公开页、内部研究工具和迁移回归基线，停止承接面向 MVP 的 Web-only 复杂看板；删除旧 Web 功能必须等 iOS 替代、API 契约和下游依赖都完成核验。

**持仓信号首个纵向切片（2026-08-04）**：`PortfolioSignal` 契约显式包含 `smartMoneyCoverage`、`dataStatus`、`limitations` 与 `nextStep`；iOS `AppModel.portfolioSignals` 只保留当前本地持仓或关注标的信号，并按严重度、仓位权重和时间排序。Today 提供空持仓入口、日报、观点/资金/关系/未读筛选和相关信号空态；详情展示持仓影响、覆盖解释、下一步研究和原始证据。Smart Account / Smart Money 关注状态、信号阅读状态与通知策略均本地持久化；通知策略由 `Core/Notifications/NotificationPreferencesStore` 统一管理每日摘要时间、安静时段和逐标的开关，生产 APNs 仍由后端执行。关注对象在持仓外产生的新信号只进入 Today 次级区域。次级 Opportunity Radar 仅展示覆盖股票池内、达到重要级别且尚未持有或观察的服务端信号，并允许从证据详情一键加入观察；生产候选资格仍由后端 Signal Engine 决定，iOS 不从原始平台数据自行发现机会。`contracts/fixtures` 以 MSTR 验证 Smart Account-only 场景，必须显示“暂无资金验证”，不能把缺失资金数据解释为中性；旧 `InvestmentEvent` 仅作为 1.0 兼容层。

**品牌标识（2026-08-10）**：产品公开名称统一为 `bSmart`；Swift 类型和 target 使用 `BSmart` 前缀，环境变量使用 `BSMART_` 前缀，URL scheme、存储键、数据库和机器标识使用小写 `bsmart`。旧品牌名不得重新出现在页面、接口说明、文档、资源文件名或新代码中；外部域名、部署配置和应用商店标识必须与该映射保持一致。

**iOS Smart 双源产品边界（2026-09-04）**：iOS 主导航固定为 `Today / Portfolio / Smart / Mr Collie`，Smart Account 与 Smart Money 是平行、可独立审计的用户侧情报来源。`AppModel` 同时负责两类数据的装载、缓存、刷新、关注状态与证据按需加载；Today、Smart 榜单、标的价格证据图、持仓状态、提醒和 onboarding 均可展示两类来源，但不得把不同周期的来源强行推导成同向、背离或确认。`Mr Collie` 是最后一个 Tab，只解释既有持仓、信号和证据，不成为新的市场事实来源。`Signal Pulse` 视觉层继续有效：荧光绿色只承担选中、实时、主要动作和最高优先级边线，不代表底层看多判断。共享组件必须落在 `ios/BSmart/Core/DesignSystem`，Feature 不得复制局部设计系统；完整规则见 `docs/architecture/09-ios.md`。

**iOS Mr Collie 研究入口（2026-09-04 恢复）**：界面位于 `ios/BSmart/Features/AI`；Live/Release 构建通过经过安装会话认证的 `POST /v1/mr-collie/query` 请求 Client API，受控内部构建可通过 `ios/Config/Secrets.xcconfig` 临时直连 DeepSeek。所有远程回答必须保留真实证据 ID、数据时间和上下文版本；不可在客户端生成市场事实、重算 Score、把缺失证据解释为中性或给出个性化买卖/杠杆/仓位指令。远程服务不可用时，iOS 降级到 `AIResearchAssistant` 的本地确定性证据回答。

**Hyperliquid 交易前端转向（2026-09-01）**：标的详情页以价格图和持仓为首层，图下默认概览并保留 `Trade` 上下文，直接消费 Hyperliquid 官方公开 Info API 的 HIP-3 市场元数据、标记价、盘口影响价和 K 线；Smart Account 概览与观点流仍由 bSmart Client API 提供并保留为交易判断证据。当前执行层是设备本地、初始资金固定为 US$10,000 的内测沙盒，支持多空、逐仓杠杆、资金费近似、未实现/已实现盈亏和维护保证金强平；封闭 TestFlight 使用正式账户与订单术语，不在每个控件重复展示模拟提示，但不得作为真实执行对外发布。卡片不再提供交易按钮；标的页以价格与大图表为主体、图下选择周期，账户与市场指标移入次级区域。共识、阿尔法、单条观点和各类证据详情统一复用 `Features/Trading` 的底部做空/做多栏和交易弹窗，金额页由 `TradeOrderComposer` 提供数字键盘、比例预设、杠杆和滑动确认，保留费用/敞口/强平价；弹窗行情独立 session，执行引擎共用。交易成功页的“完成”通过呈现方回调关闭整张交易弹窗，保留原页面状态；按钮整块背景均可点击。沙盒不得发送钱包签名或伪造 Hyperliquid 成交；未来真实执行必须放入独立签名适配器，逐单附加用户已批准的 Builder Code；Score、观点排序和行情展示不得受 Builder 返佣影响。完整决策见 `docs/product/hyperliquid-trading-pivot-2026-09.md`。

**iOS 持仓估值与标的目录（2026-08-12）**：Portfolio 的 `持仓` 场景顶部优先展示当前持仓总价值；历史变动曲线只能读取独立的持仓估值快照，缺失时显示不可用，禁止从成本价或当前收益生成伪历史。独立 `Tickers` Tab 已取消，Portfolio 的 `全部标的` 场景必须完整列出服务端 `TickerIntelligence` 支持范围并在其上搜索，客户端不得维护第二份静态股票池。

**iOS 生产数据边界（2026-08-04）**：`BSmartClientFactory` 是客户端数据源的唯一组合入口。未带 `--use-live-api` 的 Debug 构建使用 `BundleBSmartAPIClient`；Release 构建无条件使用 `HTTPBSmartAPIClient`，且 Archive 不包含 `contracts/fixtures`。未登录用户通过持久化安装 UUID 创建匿名安装会话，Opaque Bearer Token 仅存 Keychain；除 `/v1/installations` 外的 `/v1` 接口均要求安装会话。任何 Feature 不得自行选择 Fixture、读取 Token 或绕过该组合根。

**iOS 本地优先同步边界（2026-08-04）**：持仓、信号阅读/保存/忽略/反馈、通知偏好和 APNs 设备 Token 通过 `BSmartSyncCoordinator` 写入生产 API。用户操作先落本地，再进入 `UserDefaults` 持久化 outbox；同一实体只保留最新待同步状态，失败操作在下次启动或下一次变更时重放。持仓使用客户端生成 UUID 的幂等 `PUT /v1/portfolio/{id}`。Feature 不直接发 mutation，也不得因网络失败回滚用户已经完成的本地操作。

**生产客户端 API 边界（2026-08-04）**：`services/client_api` 实现 `contracts/openapi/bsmart-v1.yaml` 的 `/v1` HTTP 边界，负责匿名安装会话、安装级用户状态、设备注册与 Read Model 读取。开发环境可用 `contracts/fixtures` 联调，生产环境拒绝 Fixture Read Model。该服务不得导入或编排 `pipeline` 抓取、AI 分析和 Score 任务；真实信号必须由管线生成并写入独立物化 Read Model 后再由服务读取。

**MVP 数据覆盖闸门（2026-08-04）**：`scripts/audit_mvp_coverage.py` 从只读 SQLite 真源审计首发标的的 Smart Account 新鲜度、近 30 天合格独立作者、YouTube 证据/口播版本绑定，以及 Smart Money 市场流动性、成交新鲜度、7 日当前合格账户和派生信号。入口为 `make mvp-coverage-audit`，当前基准报告为 `docs/product/mvp-data-coverage-audit-2026-08-04.md`。历史观点数、历史合格账户或历史成交量不能代替当前覆盖；未达到双侧门槛时不得生成确认或背离，Smart Account 单侧通过时必须标注“暂无资金验证”。

**Smart Account 术语约定**：产品和页面统一称 `Smart Account`，具体数值统一称 `Score`；iOS 中间主 Tab 固定称 `Smart`。`Smart`、`Smart Account`、`Smart Money` 是所有语言环境中的英文保留术语，不得翻译为中文或其他语言。`smart_voice` 包、`sv_*` 表/字段、`smartVoice.json` 和 `smartVoice*` adapter 是历史兼容标识，不得直接显示在 UI；没有 schema 与构建产物双读迁移前不得贸然改名。公开正式入口为 `/smart-account`，旧入口仅保留兼容。

**X 增量归档重跑（2026-09-05）**：`x-import-archive --tweet-dir <目录>` 由 `pipeline/jobs/x_archive` 编排、`pipeline/platforms/x/archive.py` 解析，沿用本地已有价格覆盖池，按 `(ticker, tweet_id)` 只补缺失原文，支持多目录、dry-run 和导入报告；不删历史、不执行 DDL。随后 `sv-v0 --stage candidates --candidate-limit 0 --tweet-dir <目录>` 召回增量，`--stage extract --created-since YYYY-MM-DD` 可限定新资料时间范围；结算与 Score 仍使用完整历史证据。 当备用 DeepSeek V4 用于短输出批处理时，可设 `DEEPSEEK_THINKING=disabled`，避免默认思考耗尽 JSON 输出预算；不设置时保持提供商默认行为。

**热门/阿尔法标的来源标题（2026-09-06）**：`Features/Today/TodaySourceHeadlines.swift` 统一展示来源观点与仓位变化；热门标的并列两条独立来源摘要（优先最近观点及不同方向来源），不生成共同论点；阿尔法按来源分别展示观点或仓位前后值，保留姓名与时间归属。`pipeline/common/smart_account_titles.py` 保留完整摘要及后续条件句，禁止持久化字符截断；现有本地 267 条动态已从本地真源刷新双语标题，无新增模型调用。

**本地 Smart 快照预览（2026-09-06）**：9 月 5 日重跑结果已复制到 `contracts/fixtures/smart-accounts.json`、`smart-account-updates.json`、`smart-account-evidence.json`，用于显式 `--use-fixture-data` 的本地 Debug 预览。近 30 日动态 266 条，另保留 1 条已有持仓信号引用的历史观点以保证证据链接完整；账户 353 个、代表证据 916 条。原文件备份和运行记录位于 `data/runtime/x-refresh-20260905/`。本地快照不等于线上 API 发布，模型候选仍有未处理部分。

**Kimi 限额续跑（2026-09-05）**：`common/kimi.py` 通过 `LLM_PROVIDER=kimi` 或显式 Kimi provider 接入现有抽取、提炼与翻译；沿用 `kimi-k2.6` 非思考模式。密钥仅从本地 `KIMI_API_KEY` 读取，调用必须同时设置 `KIMI_BUDGET_CNY` 和 `KIMI_BUDGET_FILE`。`common/kimi_budget.py` 用文件锁共享请求预留、实际 token 用量的公开价费用估算和不确定请求上界，跨进程共用同一额度，不自动充值或修改其他 provider 默认值。剩余原文未处理时，下游结算/Score/导出仅反映已有有效 Calls，运行报告必须保留覆盖缺口，不能宣称全量重跑完成。

**迁移期规则**：现有 `web/lib/*Queries.ts`、`web/components/bsmart/*`、`pipeline/manage.py`、`pipeline/ingest`、`pipeline/analyze` 继续可用；新增复杂功能优先落到目标边界 `web/features`、`web/shared`、`web/server`、`pipeline/platforms`、`pipeline/domain`、`pipeline/jobs`、`pipeline/cli`。`pipeline/ingest` 和 `pipeline/analyze` 现在只作为历史导入/命令路径兼容层保留，新增平台或分析实现不得继续写入旧目录。前端 Tailwind content 必须覆盖 `web/features` 和 `web/shared`，否则迁移后的组件样式不会被生成。

**边界检查**：结构性改动后运行 `python3 scripts/check_architecture.py`。该脚本目前强制检查：`pipeline/cli` 只能调用 `pipeline/jobs`，`pipeline/jobs` 不得直连旧 `pipeline/ingest`/`pipeline/analyze`，平台/domain 层不反向依赖上层；`services/client_api` 不得导入管线实现；前端禁止迁移后的 feature/shared/server 回流到旧 bSmart 组件或旧 query 文件。

---

## 1. 这是什么

**bSmart** 是面向个人美股投资者的**持仓智能事件助手**。第一版以原生 iOS App 为主，围绕用户手动添加的持仓、成本价和仓位占比，组合 Smart Account 链下观点证据与 Hyperliquid 代币化美股 Smart Money 公开仓位行为，主动发现和解释值得关注的持仓变化。Web 保留为公开页、获客、内部研究和迁移回归工具。
（注：早期作为 Reddit 单站「redditalpha」起步——抓 Reddit 财经社区帖、逐帖大模型打标、聚合声量/情绪/异动/叙事/简报；该 Reddit 管线仍是后端基础，新增 4 区由 `gr_*` 表承载。）

- 线上地址：**https://www.redditalpha.xyz**（根域名，静态托管）
- 两个市场（market）：`us`（美股）、`cn`（中概股 + 港股 + A 股），互不污染，各出一套聚合。

> **⚠ 价值判断 / 护城河（别被「海外散户视角」叙事带偏）**：
> 1. **最有价值的内容并非「非英语散户对美股的个体看法」本身。** 韩国 Naver、日本 Yahoo 掲示板等本土股吧**单帖信息质量普遍很差**——多数是水帖、情绪宣泄、无意义 shitpost；这类内容**只有靠「量」做聚合分析才有价值**（情绪分布 / 声量异动 / 跨区分歧），逐条看几乎没有信息量。
> 2. **抓取这些股吧本身不构成技术护城河。** 爬取门槛很低（人人有个 crawling agent 都能爬），技术不是壁垒。

> **🎨 UI 已按 QuiverQuant 风重建（2026-06）**：品牌 = **bSmart**（仓库 `Conor-711/bSmart`）。**设计系统（复刻 QuiverQuant）**：字体 Figtree(UI/标题)+Roboto(数据/数字 tabular)；默认深色底 `#121212`（卡片 `#161616`，靠 `#2a2d2f` 发丝边区分；图表底才用 `#202630`；**仅深色**、已彻底移除白天模式 CSS 回退与主题切换）+ 青绿强调 `#57D7BA`（Tailwind `reddit`/`amber`/`brand`/`bull` token 同值；看跌珊瑚 `#FF5C6C` 全站统一、不随地区红绿翻转；品牌渐变青绿→深松绿、去紫）+ 小圆角(2–4px) + 数据密集卡片/表格 + 等宽数字；侧边栏导航（`globals.css` CSS 变量 + `tailwind.config.ts`）。**完整设计语言宪法见 `DESIGN_LANGUAGE.md`（改 token 前后都要同步）**。
> **主要页面**（数据多走 `gr_*` → `lib/globalQueries.ts`；投资者/作者页另走 `investorQueries`/`creatorQueries`；Smart Account 作者详情读 `smartVoice.json` + `smartVoiceInvestorQueries`；叙事页走构建期 JSON）：**落地页**(`/`，无侧栏 chrome) · **总览看板**(`/dashboard`，单视窗三栏工作台：市场信号、跨社区热力/全球热度榜、Smart Account 精简榜；长列表模块内滚动) · **叙事轮动**(`/narratives` + `/narratives/[slug]`，固定板块叙事的跨社区热度排名/讨论占比/情绪转向；入口在桌面侧栏，移动底栏暂不扩容；只做 zh/en 内容，ja/ko 回退英文) · 标的总览(`/tickers`) · 标的详情(`/tickers/[symbol]`；`MU/NVDA/MSTR` 首批展示历史时点 Top/Bottom Score 聚集、无泄漏回测、Score 加权目标价、观点变化雷达、预期差/拥挤风险、投资逻辑生命周期、作者能力矩阵、三标的组合叙事风险、可解释提醒和个性化仓位匹配，其余标的保留旧 Score 投资者模块；详情页不展示有效广度、平台确认、`n_eff` 和跨平台扩散等低解释度指标) · 投资者榜单(`/investors`) · YouTube 作者页(`/investors/youtube/[channelId]`) · Smart Account 工作台(`/smart-account`，借鉴 Nansen Smart Money 的信息架构，单视窗展示高 Score 标的集中方向、高低 Score 分歧、X/YouTube/Reddit/雪球完整平台排名、明确分层的全部已评分作者观察池和近 60 天最新 actionable call；投资者榜可叠加平台、正式/观察/前后分位、优势周期（短/中/长）、赛道、主投资风格、精确周期分数和作者/标的搜索，周期与赛道同时选中时按两类子 Score 的均值形成明确标注的能力分排序，不改写综合 Score 或平台正式名次；标的聚合使用各来源正式平台 rank 成员，支持四平台任意非空组合及 24H/3D/7D/30D/90D 窗口，集中方向至少需要 2 条同向 call 和 2 位独立 Top 10% 作者，右侧按同口径展示净强度、原文证据及原始链接，并独立展示按每位作者最新 call 去重的一人一票净人数/共识度，以及与前一等长窗口比较的作者净人数突变幅度、状态和排名；投资者榜右栏使用更宽但仍窄于左榜单的响应式宽度，前后分位作者以真实收盘价折线 + 历史观点气泡展示主要加分/扣分代表标的；观察池不参与正式分位信号，实时流按来源限额且不声称真实持仓或资金流) · Score 作者详情(`/investors/smart-account/[investorId]`，正式平台排名作者的分数解释、风格分类与代表性 call) · 追踪/自选(`/tracking`) · 搜索(`/search`) · Profile(`/me`) · 设置(`/account`)。**叙事轮动页**不再使用旧 Reddit-only `narratives` 表，也不把财报/政策/估值等事件或驱动因素作为叙事板块；离线 `make narrative-rotation` 从 `gr_post`、Reddit `posts+item_analysis`、`x_opinion+kol_refined`、`yt_video+yt_analysis` 读取内容，先按最新源日期把时间窗口下推到各平台 SQL，再按固定板块 taxonomy 归入一个主叙事，输出 `web/lib/data/narrativeRotation.json`；Web 端 `lib/narrativeRotation.ts` + `components/bsmart/NarrativeRotationCharts.tsx` 渲染顶部三张轮动图、轮动榜与详情页来源/地区/标的分布，暂不展示代表原帖。
> **Smart Account 公开投资者榜（2026-07-31）**：`/[lang]/smart-account/leaderboard` 位于独立 `(public)` 路由壳，不渲染应用侧边栏且无需登录；应用内 `/smart-account` 只保留标的发现与实时观点，通过明确入口进入公开榜。公开页复用同一份构建期 Score 数据和作者证据，支持来源、正式/观察/前后分位、精确周期、优势周期、赛道、风格和作者/标的搜索的叠加筛选；右侧作者证据栏采用 `360/400/440px` 响应式宽度。榜单状态与列表编排归 `SmartVoiceLeaderboardView.tsx`，作者侧栏归 `SmartVoiceLeaderboardProfile.tsx`，纯筛选与能力分派生归 `leaderboardModel.ts`，不得把 Score 派生逻辑重新写回视图组件。
> **Smart Account 高 Score 新关注（2026-07-31）**：应用内 `/smart-account` 的标的发现默认展示最近 7D 新覆盖。平台正式 Top 10% 作者在当前窗口首次发布某 ticker 的 actionable call，且该作者此前 180 天未覆盖该 ticker 时计为新增作者；历史期无任何当前 Top 10% 作者覆盖才标记“全新进入”，否则标记“新作者加入”。查询层读取最长 90D 当前窗口加 180D 历史基线，按作者/标的去重，并附原始观点证据；该信号不修改作者 Score，也不在历史时点回测完成前声称有交易收益。查询兼容入口 `smartVoiceQueries.ts` 仅重导出稳定 API，类型、SQL、聚合基础件、榜单构建和概览查询分别落在 `smartVoiceTypes.ts`、`smartVoiceMarketQueries.ts`、`smartVoiceMarketAggregation.ts`、`smartVoiceMarketBuilder.ts`、`smartVoiceOverviewQueries.ts`。
> **Smart Account 作者证据与组合回测（2026-07-30）**：`/[lang]/investors/smart-account/[investorId]` 在分数解释和风格画像下提供“观点证据 / 组合回测”双视图；观点证据继续展示真实价格路径、原帖链接和全部已结算战绩，组合回测由该作者真实 `sv_call` / `sv_call_settlement` 与 `price_daily` 在构建期生成，口径为下一交易日复权开盘入场、同标的最新观点覆盖、活跃标的等权、空仓期持有现金、10 bps 往返成本并以 SPY 对照。回测是信号跟随模型，不代表作者真实账户。
> **Smart Account 逐账户跟单回测（2026-09-02）**：`make smart-account-follow-backtest` 对当前正式 X、YouTube、Reddit 作者逐一计算总收益和年化。主结果只从 Call 发布日前最后一个历史平台合格快照开始；按下一交易日复权开盘执行，同标的同向判断延长周期、反向判断翻仓、平仓/失效判断退出，活跃标的等权并计 10bps 往返成本。任务同时输出只做多对照、当前作者池完整历史描述和逐笔证据到 `data/reports/smart_account_follow_backtest/`；完整历史带幸存者偏差，所有结果均不回写 Score。
> **标的页『目标价 × 操作周期』(2026-06-29 新增)**：① **观点检索/正文提炼**——每条观点抽到时在 reader 多显一行「作者明确给出 买入/卖出/目标价 + 周期(原话+档)」(`OpinionExplorer` 的 `JudgmentLine`)；`getKolOpinions` 汇总 Reddit/YouTube/雪球/Toss/Yahoo JP/X。浏览器端观点池是有界展示层，不是原始数据真源：Reddit 按近 370 天时间倒序取最近 350 条，X 仅纳入已进入 `kol_refined` 的观点并按质量、相关性、互动排序取前 120 条，雪球/Toss/Yahoo JP 各取 100 条；全量原帖仍保留在 SQLite 并用于离线日指标，避免 mega-cap 单页把数万条 X 帖文序列化成百 MB HTML。② **整体数据**——`KolModule` 底部通过 `web/features/ticker/components/TargetPricePanel.tsx` 渲染目标价时间线/价格分布/筛选入口，旧 `web/components/bsmart/TargetPricePanel.tsx` 只保留兼容导出。抽取层=独立表 `kol_judgment`(reddit/x/雪球/Toss/Yahoo JP，见 §5)+ YouTube 复用 `yt_judgment`；**只抽作者明说、反臆造**，价格在 `kolQueries.judgmentMap` 按**现价 0.2–5× band 剔噪**(penny-pump/假设估值/$1225 这类数量级离谱者置空)。取数 `getKolTargetPrices`(复用 `getKolOpinions` 池，judgment 挂到 `KolOpinion.judgment`)。`make kol-judgment`。
> Reddit 单站旧页（dashboard/ticker/post/author/leaderboard/cn/onboarding）已删；**后端 pipeline 全保留**。线上 redditalpha.xyz 仍由旧 `reddit_alpha` 仓库部署、不受影响（bSmart 部署需快照含 `gr_*`，否则相关页为空）。

---

## 2. 三大系统

> **⚠ 两站两套数据、互不干扰（2026-06）**：本仓库 = **bsmart.today**（完整多社区），数据真源 = **本地 `data/dev.db`**（含 gr_*/yt_*/kol_* 等云端没有的独有层）；旧站 **redditalpha.xyz** = `Conor-711/reddit_alpha` 仓库（只 Reddit），数据 = 下面的 Supabase 云端。**bSmart 不再 `cloud-pull`**（它会用「只有 Reddit 核心」的云端快照覆盖本地、抹掉独有层 = 之前『数据消失』元凶；已在 Makefile 锁死：`site-cloud`=`make site`、`cloud-pull` 默认拒绝、`clean` 不删 db）。出站 `make site` 读本地 dev.db。

```
┌─────────────────┐  写本地   ┌──────────────────────┐   读本地   ┌─────────────────────┐
│ ① Python 数据管线 │ ───────▶ │ ② 本地 data/dev.db       │ ───────▶ │ ③ Next.js 静态网站   │
│  抓取 + AI 分析   │  (默认)   │  bSmart 唯一真源(gr/yt/kol)│  构建期    │  读 dev.db → 出 HTML │
└─────────────────┘          └──────────────────────┘          └─────────────────────┘
        │  只读拉 tw_*(X)            ▲ Supabase 云端 = redditalpha 的 Reddit 核心
        └──────────────────────────┘   + bSmart 的 web 后端(Auth/app_events/收藏)，ref wimipsiwtrqhizgmbxas
```

### ① Python 数据管线（`pipeline/`）
抓 Reddit → 抽取 ticker → 大模型逐帖打标 → 聚合（榜单/情绪/异动/叙事/简报）→ 翻译；+ 5 社区 `gr_*`、YouTube `yt_*`、KOL `kol_*` 等扩展层。
**bSmart 内容写本地 `data/dev.db`**（`DATABASE_URL='sqlite:///./data/dev.db'`）。**X 数据 `tw_*` 从云端只读拉**（`kol_sentiment.py`/`kol_volume.py` 的 `_cloud_url()` 直接读 `.env` 拿云端串）。

### ② 数据真源 = 本地 `data/dev.db`（bSmart）
- Reddit 核心（14 表）+ **bSmart 独有层** `gr_*`(5 社区)/`yt_*`(YouTube)/`kol_*`/`x_opinion`/`price_daily`/`author_avatar` 等（这些云端**没有**）。
- **推荐部署路径：Cloudflare Pages Direct Upload**。本地用 Node 22 + `node:sqlite` 读取 `data/dev.db` 构建 `web/out/`，再 `make cf-deploy` 上传 zh/en 静态产物；Cloudflare 运行时不需要 Node 服务，也不重新构建。
- Railway/Dockerfile 仍可作为备用部署路径：用**提交进仓库的压缩数据快照**构建（线上=本地）。原始 `data/dev.db` 被 Git 和 Docker context 忽略，不再走 Git LFS。更新数据后运行 `make snapshot-db`：压缩结果不超过 90MB 时只提交 `data/dev.db.xz`，超过时只提交普通 Git 分片 `data/dev.db.xz.part-*` 和 manifest `data/dev.db.xz.parts`。Docker 按 manifest/单文件顺序还原。改数据前用 `make backup-db` 写项目外轮换备份。
- **Supabase 云端**（`wimipsiwtrqhizgmbxas`，**不是 bSmart 的内容家**）：① redditalpha.xyz 的 Reddit 核心；② bSmart 的 **web 后端**（`app_events`/`ticker_searches`/`user_collections`/`user_profiles`/Auth，走 `NEXT_PUBLIC_*`；`user_collections` 只承接帖子/评论账户收藏，标的/作者/叙事/社区追踪保存在设备 `localStorage`）；③ bSmart 只读的 `tw_*`(X)。见 `CLOUD_DB.md`。

### ③ Next.js 静态网站（`web/`）
Next 14 App Router，**静态导出**（`output:"export"` 仅生产）。构建期用 `node:sqlite` 读**本地 `data/dev.db`**
（bSmart 真源，**不再 cloud-pull**），生成 ~6500 个静态页面到 `web/out/`，可部署到任意静态托管。
**网站运行时不连数据库**（纯静态，无服务端攻击面）。

---

## 3. 端到端数据流

```
平台 API / 浏览器导出 / 外部快照
        │
        ▼
pipeline ingest / platforms(目标边界) ──▶ raw / normalized tables
        │                                      │
        ▼                                      ▼
pipeline analyze / domain / jobs ──────▶ analysis / rollup tables
        │                                      │
        └────────────── 写入本地 data/dev.db ◀─┘
                                               │
                    构建期 JSON(web/lib/data/*.json) + node:sqlite 查询
                                               │
                                               ▼
                                      Next.js export → web/out/
```

**关键：bSmart 内容默认写本地 `data/dev.db`，出站 `make site` 读取本地真源。** Supabase 不再是 bSmart 内容家，只承担 redditalpha 旧站核心、bSmart web 后端、以及部分 `tw_*` 外部数据读取。分析层保持增量：逐帖打标按稳定内容 ID 持久化，只分析新内容；rollup/export 层应可重算。

**国会议员公开交易评分（2026-08-04）**：`make congress-score` 读取 House Clerk / Senate eFD 官方披露的开源归一化快照，保留每笔官方 PDF 链接；`pipeline/platforms/congress` 负责来源规范化，`pipeline/domain/congress_score` 按议员+日期+标的+方向去重、用下一交易日复权收盘和 20D/60D 相对 SPY 超额结算，`pipeline/jobs/congress_score` 编排本地 `price_daily` 与 Yahoo 缺口回补并导出完整榜单、逐事件证据和 manifest 到 `data/exports/congress_score/`。该评分与 Smart Account 作者 Score 隔离，不写 `dev.db`；少于 5 个已结算买入决策日的议员只进入观察/无评分清单。

**本地大体量原始推文归档（2026-08-01）**：已导入的 `roster_tweets_*` 与 `equity_trader_kol_tweets_2025h2` 不再物理存放于仓库目录，统一归档到 `/Users/windz7z/Documents/bsmart-data-archive/twitter/`；仓库根目录保留同名符号链接，因此现有 X/Score 管线默认路径无需修改。归档不是 Git 或部署输入，删除符号链接不会影响 `data/dev.db` 中已经落库的数据，但重新抽取历史 Call 前必须保证归档可访问。

**作者库（优质作者聚合页）** —— `make daily` 内（主分析之后）爬「实力榜」Top 50 作者的 Reddit 历史帖，
两级模型漏斗控成本：**DeepSeek(LOW) 粗筛质量 → 仅过线帖送千问(HIGH) 深析并入库**。这些帖标记
`posts.source='author'`，**被所有实时舆情聚合/feed 排除**（`source='scan'` 过滤），只出现在作者页与其自身帖详情页。
入口：全站作者名/头像 → `/[lang]/author/[name]/`。详见 `pipeline/platforms/reddit/authors.py`（旧 `pipeline/ingest/author_crawl.py` 为 wrapper）。

**全球散户 · 五地区数据层** —— 这是 ticker 中心、
**精选 ~40 支跨区高共识美股**、对比 **5 个地区**散户情绪的另一套。区 = **美国(Reddit) + 中国大陆(雪球) + 日(Yahoo) + 韩(Naver) + 台(PTT)**。
近 **14 天**。**US 区不重爬**——rollup 直接**只读**现有 Reddit `mentions×item_analysis×posts`(market=us) 算 stance/情绪（不污染主管线）；
日韩台复用 `platforms/global_retail/asia_sources.py` 的共享 fetch 函数（JP 板 `/quote/{SYMBOL}/forum` 美股代码直连；KR `naver_code` 由 autoComplete 解析的 reutersCode 如 NVDA.O；
TW PTT 综合板抓一遍，用繁中/英文别名从标题+正文**抽取**精选标的）。**CN(雪球)** 讨论接口在阿里云 WAF 后面、requests 直连过不去 →
用 **Claude-in-Chrome 真实浏览器**（自然过 WAF）在页面内 XHR 拉 `/query/v1/symbol/search/status.json` 导出 JSON，再由 `platforms/global_retail/xueqiu_export.py` 收进 gr_post(region=cn)。
**打标 = DeepSeek flash 全量（不用千问）**：每帖 sentiment + 派生 stance。
跨区滚动 → `gr_ticker_region`(每 region×ticker 帖数/多空/情绪)；跨区派生 → `gr_ticker`(共识 all_bull/all_bear、分歧 divergent=某区与其余相反、情绪极差 spread)。
正式页面消费：总览、标的与区域页读取地区相关 `gr_*`，展示五地区情绪、跨区热力、共识/分歧、全球热度榜与代表帖；追踪页仅消费 `gr_ticker` 聚合，不读取或展示地区维度数据。
管线：`pipeline/data/global_targets.yml`(40 标的+别名+naver码) → `platforms/global_retail`/legacy ingest 抓取 → `domain/global_retail` 打标与聚合；
CLI `gr-crawl/gr-tag/gr-rollup/gr-xueqiu/gr-quote`（`gr-quote`=抓各标的最新价(Nasdaq api 主 + Yahoo 兜底) → `gr_quote` 表，实际实现 `platforms/global_retail/quotes.py`，旧 `ingest/gr_quote.py` 为 wrapper），`make gr`（含 gr-quote）/`make gr-quote`；web `lib/globalQueries.ts`。隔离表 `gr_*`（含 `gr_quote`；迁移 `supabase/migrations/…_gr_quote.sql`）。

**雪球 Score 作者池（2026-07-10）**：作者发现样本先写 `xueqiu_author_snapshot`，`domain/authors/xueqiu_pool.py` 按版本把候选写入 `xueqiu_author_pool`；首版门槛为粉丝 ≥500（或认证）且平台历史发帖 ≥300，明显媒体/机构发布者单独标记，正式池取 Top 300 位创作者，其余为 warm reserve。`platforms/xueqiu/author_timeline.py` 为每位候选建立 `xueqiu_author_crawl_job`，通过已登录 Playwright 会话按作者回填一年时间线，正文继续写 `xueqiu_raw_post`，随后统一扩展 `xueqiu_post_ticker`。雪球未登录会话只能读取作者首屏；首次运行 `make xueqiu-author-auth` 由用户本人完成登录，会话仅保存到 gitignore 的 `.xueqiu_storage_state.json`，不保存密码。常用入口：`make xueqiu-author-plan/auth/run/drain/status`；`drain` 以小批次和自适应冷却持续消耗正式作者池：部分成功固定退避 30 分钟，仅整批零成功才指数退避且最长 1 小时；SQLite 写锁、连接重置和浏览器导航超时会自动重试，超过 10 分钟未更新的 `running` 任务会保留游标恢复为 `pending`。`domain/smart_voice/v0_impl.py` 的 `xueqiu` 候选适配器只消费该版本中 `selected=1` 且回填完成的作者，并默认要求正式池全部完成后才放行候选召回；转发内容被排除，粉丝/认证/发现排名不进入 Score 得分。

**Hyperdash Smart Money 主源（2026-08-06）**：`platforms/hyperdash` 直接读取 Hyperdash Web 使用的公开 GraphQL `Equities Focused` 系统组、Copy Score、30 天绩效曲线、主要资产和账户仓位快照；bSmart 不再重算默认生产链上评分，只负责标准化、相邻仓位快照差分、30 天裁剪和原子发布。`jobs/smart_voice/hyperdash_live.py` 默认每 10 分钟刷新，失败时先保留最后成功 Hyperdash 快照，超过新鲜度阈值后才允许使用保存的 Hyperliquid 降级快照。`services/smart_money_ingest` 将来源、更新时间和健康状态连同 Read Model 发布到 PostgreSQL；iOS/Web 只经 Client API 消费，不直连第三方。`platforms/hyperliquid` 与原有 `hl_*` 评分管线保留为官方数据审计、诊断及显式应急模式，不是默认生产榜单。正式商业发布前必须确认 Hyperdash API 使用许可。运行见 `docs/operations/smart-money-live.md`。

**Hyperliquid 候选完整性边界（2026-08-06）**：持续成交会发现大量一次性对手方，不能把所有地址作为正式 Smart Money 补数分母。历史补齐限定为达到 5 笔观察成交或 10,000 美元观察成交额后、按观察成交额排序的最近 30 天 top-500 候选账户；活跃 fills、历史候选和画像使用独立后台通道。候选只决定补数优先级，只有可用历史已完整补齐且满足账户资格的地址才能正式评分；未补齐账户标记 `incomplete`。首轮补齐达到 2,000 fills 时已满足算法型排除条件并停止继续下载，`fills_limit_reason` 将该产品策略上限与交易所最近 10,000 fills 来源上限分开记录；受限账户不得进入正式排名和标的方向信号。健康文件同时报告候选池覆盖率、限制原因与全体观察地址审计覆盖率。

**X Smart Account 15 分钟更新（2026-08-06）**：`services/x_ingest` 是独立 webhook/worker 服务。`pipeline/platforms/x/realtime` 只负责 TwitterAPI.io 规则、标准化、补偿查询和实时事实持久化；`pipeline/domain/smart_voice/realtime_x.py` 复用现有 X Call 门禁，从完整原文提取方向、周期、目标价和逐字证据，并生成与摘要严格分离的完整中英文译文；`pipeline/jobs/smart_voice/x_realtime.py` 编排作者池、蓝绿规则、补偿、处理、删除检查和发布。作者池每日从 X 正式榜单动态取 Top 25%，以数字 X user ID 为稳定身份；`BSMART_X_POOL_LIMIT=10` 仅用于首日灰度，`0` 表示完整 Top 25%。Webhook 为主、15 分钟高级搜索补偿为辅；补偿查询在单页结果饱和时由 bSmart 主动二分时间窗口，以有限请求预算换取可审计的完整性。只有 `ready` Call 才进入 `smart-account-updates`，并投影为明确标注“暂无链上资金验证”的 `account_leads` 持仓事件。Client Read Model 使用数据库内 producer 分区事务发布，X、Hyperliquid 和不可变基础快照不能互相覆盖。生产必须使用 PostgreSQL，部署和验收见 `docs/operations/x-smart-account-realtime.md`。

**Smart Account 作者证据读取（2026-08-10）**：`smart-account-updates` 仍只承担 Top 25% 作者的低延迟提醒，不作为作者详情的数据源。离线 Client Read Model 另从 `sv_call`、`sv_call_candidate`、`sv_call_settlement` 与 `price_daily` 生成 `smart-account-evidence`，为所有正式榜单作者按人保留有界的近期、代表性命中和代表性失误 Call。iOS 进入作者详情后通过 `GET /v1/smart-accounts/{accountId}/evidence` 懒加载；页面严格分开结构化解释、原始证据、完整原文/已有完整译文、相对 SPY 与行业 ETF 的历史结算和算法审计信息，不得用摘要伪装译文，也不得把历史结果表述为真实持仓或未来保证。

**iOS Smart Account 代表标的（2026-08-13）**：作者详情的“代表作”不是单条最高收益观点。Client Read Model 只使用已结算且 `contribution > 0` 的 Call，按作者和 ticker 累计 Score 正贡献并选择加分最高的 3 个标的；每个标的保留最多 10 条加分观点及真实日线 OHLC。iOS 以 K 线叠加观点落点，颜色表示原始多空方向、大小表示单条 Score 贡献，并展示标的累计加分和观点数。客户端不得用价格涨跌、命中次数或当前作者排名重算代表标的。

**iOS Smart Money 代表性开仓（2026-08-13）**：Smart Money 详情通过独立 `smart-money-evidence` Read Model 和 `GET /v1/smart-money/{accountId}/evidence` 按需加载代表性开仓，不扩大榜单主载荷。服务端只统计 `opened / increased / flipped`，按账户和实际 Hyperliquid market 累计可观察新增敞口，选出最多 3 个市场并保留最多 10 个开仓点；图表必须使用同一合约的 Hyperliquid `candleSnapshot` 4h OHLC。旧快照缺少价格时只能明确标记为最接近观察时刻的 4 小时收盘价，客户端不得重排市场、替换成股票/ETF 价格或把仓位快照变化称为可保证成交。

---

## 4. 目录结构（带注释）

```
crypto_us/
├── services/                  # ② 对外/常驻服务；不在客户端进程内执行抓取
│   ├── client_api/            #   iOS / Web 的 /v1 API 与物化 Read Model 读取
│   ├── smart_money_ingest/    #   Hyperdash 主源、Hyperliquid 降级与 PostgreSQL 发布
│   └── x_ingest/              #   X webhook、补偿抓取与实时观点发布
├── pipeline/                  # ① Python 数据管线
│   ├── manage.py              #   统一 CLI 入口（被 Makefile 调用的所有子命令）
│   ├── daily.py               #   每日一次的全量编排（抓取→分析→聚合→翻译）
│   ├── sync.py                #   ★本地 SQLite ⇄ 云端 Supabase 同步（cloud-push / cloud-pull）
│   ├── worker.py              #   调度器（APScheduler，定时跑 daily）
│   ├── cli/                   #   目标边界：CLI 注册与参数解析（迁移期 README，manage.py 后续拆入）
│   ├── platforms/             #   目标边界：Reddit/X/YouTube/雪球/Toss 等平台适配器
│   │   ├── reddit/            #   Reddit PRAW/Arctic/作者池抓取（旧 ingest/reddit_* 为 wrapper）
│   │   ├── local/             #   本地样本数据加载（旧 ingest/sample_loader.py 为 wrapper）
│   │   ├── youtube/           #   YouTube 视频发现、频道刷新（旧 ingest/youtube_* 为 wrapper）
│   │   ├── toss/              #   Toss 社区抓取（旧 ingest/toss.py 为 wrapper）
│   │   ├── x/                 #   X 推文↔标的硬匹配、云端 X 拉取、完整 X ticker universe（旧 ingest/twitter_match.py/x_pull.py/load_complete_x_ticker_universe.py 为 wrapper）
│   │   ├── hyperliquid/       #   Hyperliquid HIP-3 TradFi 只读 Info API、标准化、SQLite 持久化
│   │   ├── hyperdash/         #   Hyperdash Equities Focused / Copy Score / 仓位 GraphQL 适配器
│   │   ├── congress/          #   House/Senate STOCK Act 公开披露快照下载与官方证据 URL 规范化
│   │   ├── market_data/       #   Score 价格历史回填、短窗口 price_daily 加载（旧 ingest/sv_price_history.py/price_daily.py 为 wrapper）
│   │   ├── author_assets/     #   作者头像等跨平台作者资产刷新（旧 ingest/author_avatars.py 为 wrapper）
│   │   ├── global_retail/     #   全球散户多区抓取、雪球导入与报价
│   │   └── xueqiu/            #   雪球 direct crawler 与长期任务管道
│   ├── domain/                #   目标边界：opinions/authors/tickers/narratives/Score/target_prices 跨平台逻辑；congress_score 独立处理议员公开交易评分
│   ├── jobs/                  #   目标边界：完整任务编排（global_retail/ticker_detail/youtube_fulltext/Score/Hyperliquid/Congress Score）
│   ├── common/
│   │   ├── congress.py        #   House/Senate 议员与披露的 platform-neutral 数据契约
│   │   ├── config.py          #   配置/环境变量（含 normalize_db_url：Supabase 串自动转 psycopg+SSL）
│   │   ├── db.py              #   SQLAlchemy 引擎/会话（sqlite 开发 / postgres 生产通用）
│   │   ├── models.py          #   ★数据模型 = schema 单一真源（14 张表）
│   │   ├── ticker_extraction.py #  基础 ticker 抽取（platform/domain 共用）
│   │   ├── llm.py             #   ★大模型「档位路由」：LOW/MID/HIGH → 具体 provider
│   │   ├── qwen.py            #   通义千问（HIGH：逐帖打标，思考模式）
│   │   ├── deepseek.py        #   DeepSeek（MID：叙事/简报；LOW：翻译）
│   │   └── claude.py / reddit.py
│   ├── ingest/                #   旧抓取兼容区；只保留 wrapper，新增实现不要继续放这里
│   │   ├── arctic_scrape.py   #   兼容 wrapper；实际实现见 platforms/reddit/arctic.py
│   │   ├── reddit_ingest.py   #   兼容 wrapper；实际实现见 platforms/reddit/realtime.py
│   │   ├── author_crawl.py    #   兼容 wrapper；实际实现见 platforms/reddit/authors.py
│   │   ├── asia_crawl.py      #   兼容 wrapper；实际实现见 platforms/global_retail/asia_sources.py
│   │   ├── global_retail_crawl.py # 兼容 wrapper；实际实现见 platforms/global_retail/regional.py
│   │   ├── global_retail_xueqiu.py # 兼容 wrapper；实际实现见 platforms/global_retail/xueqiu_export.py
│   │   ├── toss.py             # 兼容 wrapper；实际实现见 platforms/toss/community.py
│   │   ├── ticker_extract.py  #   兼容 wrapper；实际实现见 common/ticker_extraction.py
│   │   ├── seed_tickers.py    #   兼容 wrapper；实际实现见 domain/tickers/seeding.py
│   │   ├── price_daily.py     #   兼容 wrapper；实际实现见 platforms/market_data/short_window_prices.py
│   │   ├── x_pull.py          #   兼容 wrapper；实际实现见 platforms/x/cloud_pull.py
│   │   ├── load_complete_x_ticker_universe.py # 兼容 wrapper；实际实现见 platforms/x/complete_universe.py
│   │   ├── author_avatars.py  #   兼容 wrapper；实际实现见 platforms/author_assets/avatars.py
│   │   └── twitter_match.py   #   兼容 wrapper；实际实现见 platforms/x/ticker_match.py
│   ├── analyze/              #   分析 + 聚合
│   │   ├── item_analyze.py    #   ★逐帖 AI 打标（analyze_qwen 是全站分析大脑；增量，跳过已分析）
│   │   ├── rollups.py         #   声量/情绪聚合（mindshare 归一化）
│   │   ├── market_mood.py     #   市场情绪（恐惧贪婪）
│   │   ├── trending.py        #   异动（z-score / spike）
│   │   ├── narratives.py      #   叙事聚类（deepseek 语义聚类，失败回退主题分组）
│   │   ├── brief.py           #   每日简报（deepseek 润色）
│   │   ├── global_retail_tag.py    # ★全球散户：DeepSeek flash 全量打标 gr_post(sentiment+派生 stance，不用千问)
│   │   ├── global_retail_rollup.py # ★全球散户：跨区滚动 gr_ticker_region(US 读现有 Reddit) + 派生共识/分歧 gr_ticker
│   │   ├── kol_refine.py       #   ★KOL 个体观点 AI 提炼+双语：reddit/x/雪球/Toss/Yahoo JP 每标的每源 top-N → DeepSeek flash → kol_refined(stance+reason+points, zh/en；提炼与翻译合一)
│   │   ├── kol_viewpoint.py    #   ★KOL 观点 视角分类：对已蒸馏观点(kol_refined+yt_analysis) → DeepSeek flash 打 7 视角(1-3 个,首个为主) → kol_viewpoint
│   │   ├── kol_judgment.py     #   ★KOL 目标价+操作周期 抽取：reddit/x/雪球/Toss/Yahoo JP 原帖**只抽明说**的 买入/卖出/目标价(现价锚点剔噪)+周期 → kol_judgment(独立表，复用 kol_refine._load 候选池)；YouTube 复用 yt_judgment
│   │   ├── tweet_sentiment.py  #   ★X 推文情绪打分：tw_tweet_topic 命中推文 flash 批量 -1..1 → **云端** tw_tweet_sentiment（供每日净情绪）
│   │   ├── kol_sentiment.py    #   ★KOL 每日净情绪 rollup：跨平台 情绪×ln(1+互动)×相关性 加权净值 → 本地 kol_sentiment_daily（混合读本地三源+云端 X）
│   │   ├── retail_sentiment.py #   ★整体散户 每日净情绪 rollup：全量散户+本土论坛(Naver/YahooJP/PTT/Toss)、不含 YouTube → 本地 retail_sentiment_daily（X 走 tw_tweet_ticker⋈tw_tweet_sentiment）
│   │   ├── retail_volume.py    #   ★整体散户 每日讨论度 rollup：同口径计数 → 本地 retail_volume_daily
│   │   ├── retail_newcomers.py #   ★整体散户 每日新增散户 rollup：各平台首次参与该标的讨论的去重作者数(Reddit 发帖+评论 / 5 论坛；不含 X/YouTube) → 本地 retail_newcomers_daily
│   │   ├── kol_newcomers.py    #   ★KOL 每日新增 KOL rollup：X(x_opinion)/YouTube(yt_video)/雪球(gr_post) 首次讨论该标的的去重作者数 → 本地 kol_newcomers_daily
│   │   ├── overall_signals.py  #   ★整体数据『异动归因 + 聪明钱↔散户分歧』(仅 KOL，qwen-flash) → 构建期 JSON web/lib/data/overallData.json（读本地 daily 序列 + retail_sentiment_daily + /tmp/<ticker>_x6m.jsonl + /tmp/mt_* 技能缓存；_skill_map 复刻 gen_topinvestors 的 z。讨论方面/新叙事 2026-06-28 已下线）
│   │   ├── narrative_rotation.py # ★叙事轮动：固定板块 taxonomy、跨社区内容归类 → 构建期 JSON web/lib/data/narrativeRotation.json（排名变化/讨论占比/情绪变化；不读旧 narratives 表）
│   │   └── translate.py       #   翻译成中文 *_zh 列（增量、幂等；走 SQLAlchemy/DATABASE_URL，云端本地通用）
│   └── data/                  #   随仓库的字典/样本（ticker_stoplist.txt, cn_hk_tickers.json, subreddits.yml, global_targets.yml…）
│
├── web/                       # ③ Next.js 14 静态站
│   ├── app/
│   │   ├── layout.tsx         #   根布局（主题防闪烁 + 默认 OG/metadataBase）
│   │   ├── [lang]/            #   语言段（zh|en|ja|ko）：generateStaticParams（页面数 = locales × 各内页）
│   │   │   #   layout.tsx 仅 LocaleProvider；(app)/ = 侧栏壳；(marketing)/ = 落地页壳；(public)/ = 无登录门槛、无侧栏的公开数据页壳
│   │   │   ├── dashboard/     #     ★总览看板路由（取数后交给 features/dashboard；单视窗三栏、模块内滚动、专用骨架屏）
│   │   │   ├── narratives/ + narratives/[slug]/ # ★叙事轮动总览 + 详情（构建期 narrativeRotation.json；固定板块、跨社区、暂不展示原帖）
│   │   │   ├── tickers/ + tickers/[symbol]/   # 标的总览(可排序表 + 上方 **三个 KOL 排行榜** `KolRankBoards`：看多/看空=`getKolBullBearBoards`(kol_sentiment_daily 近14天 net 跨标的聚合、scope gr_ticker、top/bottom 5)、**情绪变化最大**=`getKolSentimentSwings`(同窗口劈前7/后7天，比**看多占比** n_bull/(bull+bear) 的 pp 变化、按 |Δ| top5；用占比非 net 以免被大票声量主导)) + 标的详情(★模块看板:个体观点·KOL[真实] + 异动/跨区视角/独有叙事/多空共识/风险温度/大家在等什么 — mock,多图表；海外信息差/最强反方/独立 YouTube 观点 模块已删)
│   │   │   ├── search/        #     搜索（客户端 ticker/公司名模糊匹配）
│   │   │   ├── me(Profile) account(设置) login/ signup/ forgot-password/ reset-password/ auth/callback/  # 账号系统
│   │   │   ├── onboarding/    #     ★首登引导向导（沉浸式全屏；采集投资画像→写 user_profiles+自动追踪持仓；?edit=1 从设置复用）
│   │   │   ├── status(routine 运维)
│   │   ├── sitemap.ts / robots.ts / not-found.tsx   # SEO + 404
│   │   └── icon.png           #   favicon
│   ├── lib/
│   │   ├── db.ts              #   ★构建期用 node:sqlite 读 ../data/dev.db；库缺失/查询失败→降级空（不崩 output:export）
│   │   ├── queries.ts         #   ★所有取数 SQL（getMindshare/getTrending/getPostDetail…）
│   │   ├── globalQueries.ts    #   全球散户正式页面取数（读 gr_* 表 + US 代表帖读现有 Reddit；try/catch 兜底）
│   │   ├── investorQueries.ts   #   投资者榜单取数（getInvestorBoard：X/YouTube/Reddit/雪球 各按作者聚合互动·播放→排名；缺表返回空）
│   │   ├── creatorQueries.ts    #   YouTube 作者页取数（getYoutubeCreator：单频道 ①标的判断 tickerJudgments[yt_analysis 立场/观点/论据/目标价 ⋈ price_daily 当时价→现在价+命中,含中性,按标的归组]/②代表性标的/③互动最高视频；getYoutubeChannelIds 供 generateStaticParams）
│   │   ├── smartVoiceInvestorQueries.ts # Score 作者证据兼容入口；实现拆到 smartVoiceInvestorTypes / smartVoiceInvestorEvidenceQueries / smartVoiceRepresentativeQueries
│   │   ├── smartVoicePortfolioQueries.ts # Score 作者构建期组合回测（真实已结算 call + 复权价格 + SPY；下一交易日入场/同标的最新观点覆盖/活跃标的等权）
│   │   ├── i18n.ts + dictionaries/{zh,en,ja,ko}.ts # 多语（zh 为源，en/ja/ko 必须镜像同样的 key；UI 译，帖子内容 ja/ko 回退英文原文）
│   │   ├── supabase.ts / auth.ts / admin.ts    # Supabase 客户端 + 登录 + 管理员判定
│   │   ├── analytics.ts        # 埋点（写 Supabase）
│   │   ├── favorites.ts                         # ★帖子/评论账户收藏走 user_collections；标的/作者/叙事/社区追踪走 localStorage
│   │   ├── profile.ts                           # ★用户投资画像：客户端读写 user_profiles（RLS）+ markOnboarded/isOnboarded（门禁标志走 user_metadata）
│   │   ├── instruments.ts                       # onboarding 持仓选择器的「广义标的」补集（ETF/杠杆反向/商品/加密/债券；个股来自 gr_ticker）
│   │   └── site.ts            #   SITE_URL（https://www.redditalpha.xyz）+ OG
│   ├── features/              #   目标边界：按业务域组织 dashboard/ticker/narrative/investor/region/search/tracking/smart-account/onboarding；dashboard 承接总览视图模型与工作台；ticker 将目标价编排、分布图和纯模型分离；smart-account 承接跨页 Score 展示与作者详情；onboarding 承接纯步骤 UI
│   ├── shared/                #   目标边界：跨业务 UI/layout/charts/icons/formatting/i18n/market；已承接 KOL 平台/立场/头像/原文译文、TickerLogo、PriceSparkline、ViewportWorkspace、Bits/DetailBits 展示基础件
│   ├── server/                #   目标边界：构建期 DB/query 边界（迁移期 lib/db.ts 与 *Queries.ts 继续可用）
│   ├── components/            #   迁移期旧 UI 组件（Sidebar/FeedCard/MarkdownLite…；复杂新逻辑不要继续堆入）
│   ├── next.config.mjs        #   output:export(仅生产) + cpus:1 串行导出 + images:unoptimized
│   └── public/               #   logo/og/avatars/communities（图片已压缩）
│
├── supabase/migrations/       # ② Supabase SQL 迁移（ticker_searches / analytics / user_collections / user_profiles 的表+RLS+RPC）
├── data/dev.db                # 本地 SQLite —— **bSmart 唯一真源**（gitignore，不进入 Git/Docker context）
├── data/dev.db.xz             # 小于等于 90MB 时的单文件部署快照（二选一）
├── data/dev.db.xz.part-*      # 大于 90MB 时的普通 Git 分片快照（二选一）
├── data/dev.db.xz.parts       # 分片 manifest；存在时 Docker 启用分片还原
├── data/dev.db.snapshot.json  # 快照时间、体积、SHA-256 与文件清单
├── Makefile                   # ★所有常用命令入口
├── .env / .env.example        # 凭据与配置（.env gitignore：QWEN/DEEPSEEK/DATABASE_URL…）
├── docs/architecture/         # 架构专题文档（前端、管线、数据、平台、Score、部署、约定）
├── docs/contracts/            # 跨平台产品契约（Opinion/Author/Ticker/Judgment/Score/Narrative）
└── 文档：README / DEPLOY / CLOUD_DB / SUPABASE_AUTH / STRATEGY / ARCHITECTURE(本文)
```

---

## 5. 数据库 schema（14 主表 + 4 亚洲 + 3 全球散户 + 3 YouTube + 1 KOL 提炼 隔离表，`pipeline/common/models.py` 为单一真源；另有**仓库外加载**的 X `tw_*`，见表末行）

| 类别 | 表 | 说明 |
|---|---|---|
| 原始 | `subreddits` `authors` `posts` `comments` | 抓来的原始内容（含 `*_zh` 译文列、`market`；`posts.source` scan/author 区分实时舆情/作者库，`authors.crawled_at` 作者库增量标记） |
| 字典/抽取 | `ticker_meta` `mentions` | ticker 字典 + 帖子↔ticker 提及（含 confidence/method） |
| AI 分析 | `item_analysis` | ★逐帖打标结果（情绪/多空/质量/主题/双语摘要/per-ticker 论据），按 item_id 持久化；真实分析按 `ITEM_ANALYSIS_PROVIDERS` 在 Claude/Qwen/Gemini 间回退并记录实际成功模型，全部失败时保留待处理，不写 mock 冒充真实结果 |
| 派生聚合 | `ticker_rollup` `market_mood` `trending` | 声量榜 / 市场情绪 / 异动（每次全量重算，可弃） |
| 叙事/简报 | `narratives` `narrative_tickers` `narrative_posts` `daily_briefs` | 主导叙事 + 每日简报 |
| 叙事轮动(构建期 JSON) | `web/lib/data/narrativeRotation.json` | **新 `/narratives` 页面数据源**：固定板块 taxonomy 的跨社区叙事轮动；由 `make narrative-rotation` 从 `gr_post`、Reddit、X、YouTube 聚合生成，记录每日 rank/share/sentiment 与详情来源/地区/标的分布；**不使用旧 Reddit-only `narratives` 表**，不把财报/政策/估值等事件项作为板块 |
| Smart Account 指标回测(本地派生) | `sv_investor_score_asof` `sv_indicator_signal_daily` `sv_indicator_event` `sv_indicator_outcome` `sv_indicator_stat` | 历史时点平台正式池 Score/排名 → 发现页四类指标的 1/3/7/30/90D 滚动信号 → 连续同向事件 → 下一交易日开盘后的 1/5/20/60/90D 调整价方向收益、相对 SPY 超额、胜率、Wilson 区间、盈亏比和利润因子；`make sv-indicator-backtest` 全量重建，`make sv-indicator-report` 另导出逐事件、逐原文证据、成本/时间/标的/强度/质量/不重叠持仓细分 CSV 及 40 例原帖证据案例集；`make sv-portfolio-backtest` 在 X 历史时点事件和作者 Call 上构建不重叠等权组合，输出 0/10/25bps 成本下的 CAGR、夏普和回撤，不新增主库日净值表 |
| Smart Account 逐账户跟单回测(本地报告) | `sv_investor_score` `sv_investor_score_asof` `sv_call` `price_daily` | 当前正式 X/YouTube/Reddit 作者 → 发布日前历史资格 → 生命周期覆盖的单标的持仓 → 下一交易日开盘执行、活跃标的等权、10bps 成本 → 每个账户总收益、CAGR、SPY 超额、回撤、只做多对照和逐笔证据；输出 `data/reports/smart_account_follow_backtest/`，不写数据库或 Score |
| Smart Account 子 Score 垂直回测(本地派生) | `sv_segment_score_asof` `sv_segment_signal_daily` `sv_segment_event` `sv_segment_outcome` `sv_segment_stat` | 仅用每个历史时点之前已结算的 Call 重建周期、赛道和投资类型子 Score，按子类内部 Top 10%/25% 作者生成 3/7/14/30D 集中方向事件，再从下一交易日开盘计算 1/5/20/60/90/180D 调整价方向收益和相对 SPY 超额；默认至少 3 位作者、65% 同向度和 2.5 有效声音，结果与原文证据写入 `data/reports/sv_segment_backtest/`，不修改当前作者分数或页面榜单 |
| Smart Money（Hyperdash 主源） | `hyperdash-last-good.json`、原子 client manifest；`hl_*` 仅作降级审计 | Hyperdash Equities Focused → Copy Score/30 天绩效/仓位快照 → 快照差分 movement → iOS Read Model；来源和更新时间必须显式，客户端不重算 |
| X Smart Account 实时事实与观点 | `x_realtime_subscription` `x_realtime_rule` `x_realtime_post` `x_realtime_call` `x_realtime_event_candidate` `x_realtime_run` | 正式 X Top 25% 作者池与规则版本 → webhook/15 分钟补偿幂等原帖 → 完整 Call/翻译门禁 → `smart-account-updates` 和持仓事件；生产只写 PostgreSQL，原始、译文、摘要严格分层，删除检查会撤下对应 Read Model 文档 |
| 全球散户(隔离) | `gr_post` `gr_ticker_region` `gr_ticker` | 日韩台+中国大陆(雪球)爬精选跨区美股的散户帖(flash 打标 sentiment+stance) + 每 region×ticker 滚动(region `us`/`cn`/`jp`/`kr`/`tw`；**US 不入 gr_post，rollup 只读现有 Reddit**；CN 经浏览器过 WAF 导入) + 每 ticker 跨区派生(共识/分歧)。与 us/cn 主表隔离，供正式页面读取 |
| YouTube 观点(隔离) | `yt_video` `yt_analysis` `yt_ticker_summary` | 按标的近 24h、浏览量>1000 的**全语种**财经视频(YouTube Data API)→ Gemini **混合分析**(top N 原生看视频[画面+音频] + 其余优先读取 `yt_fulltext` 完整口播/在线字幕，再回退低清原生视频)出 stance/sentiment/双语摘要 → 每标的浏览量加权汇总。**两条分析路径**：① `youtube-tag` Gemini 视频/口播分析，支持 `--since-days`、`--min-subscribers`、`--min-duration-seconds` 精确限制产品候选，`--workers>1` 走并发付费模式；幂等判定同时校验 `yt_analysis.ticker == yt_video.ticker`，同一视频被新 ticker 搜索命中后会自动重分析；② `youtube-tag-text` **无配额兜底**：用**标题+简介**跑 LOW 档出双语观点(mode=`text`)，覆盖 Gemini 没看的长尾、**不占 `analyzed` 旗标**→ 日后 Gemini 仍能升级覆盖。**纳入站外当地分析者**(韩 슈퍼개미/日 testa/美 FinTube)。YouTube 数据经 `kolQueries.youtubeOps` 并入标的页**观点浏览器**(`OpinionExplorer`)；展示口径要求频道 `yt_channel.subscriber_count >= 2000` 且视频 `duration_s > 60`，目标价时间线、YouTube 相关性/质量候选、KOL 情绪/讨论度/新增 KOL 日序列都使用同一口径；详情阅读器按 channel_id 匹配 YouTube 作者 Score 并显示具体 Score 分数。**原独立『YouTube 观点』模块已移除**(与浏览器重复，删 `YouTubeOpinions.tsx`+`youtubeQueries.ts`)；缺 key 回退 mock |
| YouTube 完整口播(隔离) | `yt_fulltext` | 视频「完整口播」：Gemini 真看视频→**只还原口播**(不描述画面)成有序段落 `{type:speech, speaker, text}`：**按语义分段**(3-6 句/段) + **行内 Markdown 划重点**(`**加粗**`关键结论/数据/标的、`*斜体*`转折，克制)；**多人(访谈/播客)每段标 `speaker`、独白留空**；剔赞助订阅VIP二维码宣传。列 content_zh(扁平**纯文本**,去 Markdown)+segments(JSON 有序带 Markdown)。前端 `YtFullContent.tsx`(被 `YtReader.tsx` 包裹，见 `yt_digest` 行)：行内 Markdown 渲染(`inline`/`RichText`)；单人→限行宽分段长文、多人→按说话人分回合对话排版；传入 chapters 时在对应 speech 段前插**章节标题+锚点 `data-ch`**。`youtube-fulltext --only/--per-ticker/--force/--no-frames`。⚠ 旧档 `visual` 段(关键帧)代码休眠、新提示不产出(下载/OCR 配方备查见 memory `project-youtube-fulltext`) |
| YouTube 投资者摘要+目录(本地派生) | `yt_digest` | YouTube 正文阅读容器 `YtReader.tsx` 的两个新模块：① **投资者摘要**(`summary_zh/en`：整段口播精华/话题 AI 提成 4-7 分点，放正文上方)；② **内容目录**(`chapters`=有序章节 `{t_zh,t_en,seg}`，seg=起始 **speech 段下标**→`YtFullContent` 据此埋 `data-ch` 锚点 + 章节标题；右侧目录点击→正文平滑滚到该段、折叠时先自动展开)。③ **正文默认折叠到 ~72vh(约一屏)**、`展开更多`/`收起`。`youtube_digest.py`/`make youtube-digest` 读 `yt_fulltext` 口播文本跑 **LOW 档(qwen-flash，不重看视频)**，校验 seg 单调/夹紧；增量、原生 DDL 不入 models.py、写本地；web `ytDigestMap`(kolQueries)→YtReader。需 `QWEN_API_KEY` |
| YouTube 判断参数(本地派生) | `yt_judgment` | 作者页「① 标的判断」每条判断的结构化 chip：从**已有** `yt_analysis`(summary+key_points+price_target)抽 `horizon_zh/en`(时间周期)·`target`(目标价，规整成 `$X`/`$X–Y`)·`key_levels_zh/en`(关键位置=支撑/阻力/突破位/形态/均线)。`youtube_judgment.py`/`make youtube-judgment` 跑 **LOW 档(qwen-flash，纯文本不重看视频)**，**只抽明说、缺则 null**(776 条 ~105 有值、target 69>price_target 60)；增量、裸 sqlite3 写本地、不入 models.py(同 `yt_digest` 范式)；web creatorQueries `safe` LEFT JOIN(表缺失不影响)、目标价结构化优先于原始 `price_target`。需 `QWEN_API_KEY` |
| YouTube 作者×标的综合(本地派生) | `yt_creator_view` | 作者页「① 标的判断」**每标的综合**：把**同一博主对同一标的**的多条视频判断(已蒸馏 summary+key_points+stance)综合成 `stance`(整体立场)+`points_zh/en`(**3-5 条关键判断**，合并去重)。PK=(channel_id,ticker)。`youtube_creator_view.py`/`make youtube-creator-view` 跑 **LOW 档(qwen-flash，读已蒸馏文本不重看视频)**，**忠实综合不臆造**；增量、裸 sqlite3 写本地、不入 models.py(同 `yt_digest`/`yt_judgment` 范式)；web creatorQueries `safe` 按 channel 查、缺则回退最新一条判断的 key_points。让作者页每标的只显示一段综合而非铺开每条视频(原太繁杂)。635 对 0 失败。需 `QWEN_API_KEY` |
| KOL 提炼(隔离) | `kol_refined` | ★个体观点「AI 提炼+双语」：对 reddit/x/雪球/Toss/Yahoo JP 每标的每源 top-N 按 Qwen LOW → DeepSeek low → Gemini 兜底（`KOL_REFINE_PROVIDERS` 可改顺序）→ stance + **reason_zh·en**(为什么看多/看空) + **points_zh·en**(2-3 要点)，**提炼与翻译合一**(只 zh/en，ja/ko 前端回退 en)。PK source+item_id；实现 `pipeline/domain/opinions/kol_refine.py`，命令 `make kol-refine`(增量、`--per-source`/`--only`/`--force`)。**标的页象限①「个体观点·KOL」** 用之替换照搬原文；YouTube 不入此表(复用 `yt_analysis`) |
| KOL 目标价+周期(隔离) | `kol_judgment` | ★个体观点的『目标价 + 操作周期』结构化抽取：对 reddit/x/雪球/Toss/Yahoo JP 每标的每源 top-N 跑 **LOW(qwen-flash)** 从**原帖**抽 `buy_price`/`sell_price`/`target_price`(各 nullable、区间取中点、原文留 `price_raw`) + `horizon_zh/en`(原话) + `horizon_bucket`(short/mid/long)。**只抽明说、反臆造**：prompt 喂**当前价锚点**(`_price_map`)剔数量级离谱者 + 拒 penny-pump/假设估值/相对幅度；模型返回后再以最新收盘价 **0.2–5× band** 做确定性校验，单侧区间任一端越界则整侧清空。PK 同 kol_refined (source,item_id,ticker)；实现 `pipeline/domain/target_prices/kol_judgment.py`(复用 `kol_refine._load`)，命令 `make kol-judgment`(增量、`--only`/`--force`)。**标的页『整体数据』散点(`TargetPricePanel`) + 『观点检索』正文提炼行** 用之；YouTube 不入此表(复用 `yt_judgment`)；web `kolQueries.judgmentMap` 再按现价 **0.2–5× band 二次剔噪**($1225 这类砍掉)。需 `QWEN_API_KEY` |
| KOL 视角分类(隔离) | `kol_viewpoint` | ★把已蒸馏观点(kol_refined + yt_analysis)用 DeepSeek(flash) 分到 **7 视角**(估值/业务成长/竞争/管理层/宏观/催化剂/资金盘面，1-3 个、首个为主、纯方向性/情绪→other)。PK 同 kol_refined (source,item_id,ticker)；实现 `pipeline/domain/opinions/kol_viewpoint.py`，命令 `make kol-viewpoint`(增量、无明确观点预判 other 省调用)。供**标的页观点流的「视角」分类**，web 经 `kolQueries.viewpointMap` 挂到观点上 |
| KOL 每日净情绪(本地派生) | `kol_sentiment_daily` | ★折线图下方绿/红面积子面板的数据。每 (ticker,day) 跨平台把『提到该标的的帖子』按 **情绪 × ln(1+互动) × 相关性** 加权求和 = **无界净情绪 net**(>0 偏多/绿，<0 偏空/红，量纲随声量×情绪放大，Kaito 风)。源：本地 Reddit(`item_analysis.sentiment_score`)/雪球(`gr_post.sentiment`)/YouTube(`yt_analysis.sentiment`) + **云端 X**(`tw_tweet_topic`⋈`tw_tweet`⋈`tw_tweet_sentiment`，relevance 用关键词命中 `strong` 代理)；YouTube 只计入频道粉丝 ≥2000 且时长 >60 秒的视频。`kol_sentiment.py`/`make kol-sentiment`(整表重算；**原生 DDL 自建、不入 models.py**；混合读本地+云端、勿加 sqlite 覆盖)。⚠ `vertical_topic_metadata.json` 漏掉 NVDA/TSLA/AAPL/MSFT → 这些大票暂无 X 贡献。**⚠ `tw_tweet` 现已空 0 行** → `tw_tweet_topic⋈tw_tweet` 现返 0、net_x 是陈旧快照；散户版 `retail_sentiment` 已改走稳定的 `tw_tweet_ticker⋈tw_tweet_sentiment`，KOL 版待同样迁移 |
| KOL 每日讨论度(本地派生) | `kol_volume_daily` | ★『每日讨论度』堆叠条状子面板的数据。每 (ticker,day) 跨平台**计数**当天讨论该标的的帖子+视频：n_reddit(mentions⋈posts 去重)/n_xueqiu(gr_post)/n_youtube(yt_video，频道粉丝 ≥2000 且时长 >60 秒) + **n_x = 本地 `x_opinion`**；可选用云端 `tw_tweet_ticker` 补充（设置 `KOL_VOLUME_CLOUD_X=1`，按 `(tweet_id,ticker)` 去重，云端侧仍**不 join `tw_tweet`**）。n_total=四者和。`kol_volume.py`/`make kol-volume`(整表重算；原生 DDL、不入 models.py；默认本地、勿加 sqlite 覆盖) |
| 整体散户 每日净情绪(本地派生) | `retail_sentiment_daily` | ★KOL 模块切到「整体散户」时的绿/红面积数据。与 KOL 同形状(net + net_<平台>)，**人群口径=全量散户**、平台=X/Reddit/雪球/**Naver/YahooJP/PTT/Toss**(本土论坛)、**不含 YouTube**。加权 net += 情绪×相关性×**(1+ln(1+互动))**——`(1+…)` 基座让无互动数据的源(Yahoo JP 引擎不给赞/评)仍按「一帖一票」计入。**X 走稳定的 `tw_tweet_ticker`⋈`tw_tweet_sentiment`**（⚠ `tw_tweet` 现已空 0 行→KOL 版 net_x 已陈旧；散户版改用稳定链接表、代价是无逐帖互动→权重退化为基座 1.0）。`retail_sentiment.py`/`make retail-sentiment`(整表重算；原生 DDL、不入 models.py；混合本地+云端、勿加 sqlite 覆盖) |
| 整体散户 每日讨论度(本地派生) | `retail_volume_daily` | ★「整体散户」视图的堆叠条状数据。每 (ticker,day) 同口径**计数**：n_reddit/n_xueqiu/n_naver/n_yahoojp/n_ptt/n_toss(gr_post 按 source) + **n_x = 直接数 `tw_tweet_ticker`**，n_total=各平台和。`retail_volume.py`/`make retail-volume`(整表重算；原生 DDL、不入 models.py) |
| 整体散户 每日新增散户(本地派生) | `retail_newcomers_daily` | ★「整体散户」视图第三块『每日新增散户』堆叠条状。每 (ticker,day) 计**首次参与该标的讨论的去重作者数**(用户对该平台×标的最早出现日计 1)：n_reddit(posts⋈mentions + comments⋈父帖 mentions)/n_xueqiu/n_naver/n_yahoojp/n_ptt/n_toss(gr_post 按 source)，n_total=各平台和。**不含 X**(云端 `tw_tweet_ticker` 无作者列)/**YouTube**(创作者非散户)。`retail_newcomers.py`/`make retail-newcomers`(纯本地、整表重算；原生 DDL、不入 models.py)。⚠ "数据集内首次"在数据窗起点偏高(Toss 仅 06-14 起) |
| KOL 每日新增 KOL(本地派生) | `kol_newcomers_daily` | ★「KOL」视图第三块『每日新增 KOL』堆叠条状。每 (ticker,day) 计**首次讨论该标的的去重作者数**，平台=**有身份/粉丝象征的 X / YouTube / 雪球**(不含 Reddit/匿名源)：n_x(`x_opinion` 按 handle)/n_youtube(`yt_video` 按 channel_id，频道粉丝 ≥2000 且时长 >60 秒的视频首次出现)/n_xueqiu(`gr_post` 按 author)，n_total=三者和。**X 用本地 `x_opinion`**(含作者)而非散户版云端 tw_tweet_ticker。`kol_newcomers.py`/`make kol-newcomers`(纯本地、整表重算；原生 DDL、不入 models.py) |
| YouTube 频道作者(本地) | `yt_channel` | YouTube 正文(OpinionExplorer 阅读面板)作者头像旁的**基础信息**：`subscriber_count`(粉丝)/`video_count`(视频)/`description`(简介)/`handle`(@)。`platforms/youtube/channels.py`/`make yt-channels` 用 **Data API `channels.list`**(part=snippet,statistics) 按 `yt_video.channel_id` 全集刷新(~540 频道/11 次调用、1 配额/次)；直接写本地(同 author_avatar)、不入 models.py；web `ytChannelMap`(kolQueries)→Reader。需 `YOUTUBE_API_KEY` |
| **X/Twitter(隔离·外部加载)** | `tw_tweet`(58万) `tw_kol` `tw_tweet_ticker` `tw_crawl_state` `tw_tweet_sentiment`(空) `tw_ticker_rollup`(空) + `tw_tweet_topic` | KOL 推文由**仓库外工具**灌入云端(14 天 bootstrap，**尚未打情绪/未聚合**)，**均不在 `models.py`**。`tw_tweet_topic` = `platforms/x/ticker_match.py` 的**关键词硬匹配**派生(无 AI；按 `vertical_topic_metadata.json` 每 topic 的 keyword_list 混合匹配 $cashtag/@handle/短语/单词，sigil 敏感+Unicode 分词)→ 仅留 **Stocks** vertical 并清掉「普通词」误报(Bullish→BLSH 等)；约 8.6 万 (推文,标的) 对 |

> 迁移只搬「原始+字典+AI 分析」这 7 张源表（贵、需长期保存）；派生表在云端用 `make rollup` 等重算。
> 全球散户 3 表 + YouTube 3 表都在 `ALL_TABLES`（`cloud-pull` 会快照），但**不在** `sync.SOURCE_TABLES`；`make gr` / `make youtube` 写当前 `DATABASE_URL`（本地验证用 `DATABASE_URL='sqlite:///./data/dev.db'` 覆盖，勿对云端跑建表 DDL）。
> **X 的 `tw_*` 不同**：由仓库外工具直接写云端，**不在 `models.py`/`ALL_TABLES`**（故 `cloud-pull` 不快照、网站构建也不读）；`tw_tweet_topic` 由 X 平台适配器用原生 DDL 自建。重跑匹配：`make tw-match` 或 `pipeline/.venv/bin/python -m pipeline.manage tw-match`（整表重算，幂等）。

---

## 6. 大模型档位（`pipeline/common/llm.py` 为路由真源）

| 档位 | 用途 | 当前 provider |
|---|---|---|
| **HIGH** | 逐帖投资打标（思考模式，全站分析大脑，token 大头） | 通义千问 `qwen3.7-plus` |
| **MID** | 叙事聚类 / 每日简报 / 正文重排版 | DeepSeek `deepseek-v4-pro` |
| **LOW** | 翻译 + KOL 提炼/视角/论点综合（走量） | 通义千问 `qwen-flash`（原 DeepSeek flash；2026-06 DeepSeek 余额耗尽 → 切千问，`QWEN_MODEL_LOW` 可改回）。**故 KOL 三步现需 `QWEN_API_KEY`，非 DeepSeek** |
| **GEMINI** | YouTube 视频理解(画面+音频) + 字幕文本总结；KOL/逐帖分析 fallback；也可承接统一档位文本任务 | Gemini（`common/gemini.py`；设置 `LLM_PROVIDER=gemini` 时 LOW/MID/HIGH 显式切到 `GEMINI_MODEL`） |

默认 LOW/MID/HIGH 仍按 `llm.py` 路由表运行；可用 `LLM_PROVIDER=qwen|deepseek|gemini` 对一次任务显式切换 provider，`model` 字段记录实际选择。YouTube 视频理解及带独立 fallback 的批任务仍可直接调用 `common/gemini.py`。真实逐帖分析全部 provider 失败时保留待处理，不静默写 mock。

---

## 7. 常用命令（Makefile）

| 命令 | 作用 |
|---|---|
| `make daily` | 分析过去 24h（抓取+AI 打标+聚合+翻译），直接写 `DATABASE_URL`（云端）；含作者库爬取 |
| `make crawl-authors` | 单独跑作者库：爬实力榜 Top 作者历史帖（DeepSeek 粗筛→千问深析）。需 DeepSeek key |
| `make analyze-qwen` | 真实千问逐帖打标 + 重算聚合 |
| `make gr` | 全球散户五地区数据：日韩台爬精选跨区美股 + DeepSeek flash 打标 + 跨区滚动(US 读现有 Reddit)。CN(雪球)走 `gr-xueqiu`(收浏览器过 WAF 的导出 JSON) |
| `make toss` | Toss(토스증권) 종목 커뮤니티评论爬取 → `gr_post(source='toss',region='kr')` + `gr-tag` 打标。逆向 Web API `wts-cert-api.tossinvest.com/api/v4/comments`(subjectType=STOCK&subjectId={code}&commentSortType=RECENT，**无需登录**、游标 `lastCommentId` 翻页、每页 11 条)；标的映射 `platforms/toss/community.py` 的 `TOSS_STOCKS`(MU=US19890516001，PLTR=US20200930014)。`--days/--only/--resume/--max-pages/--sleep/--commit-pages`；`--resume` 会基于本地已有最新/最旧游标补新+补旧，达到页数上限但未触达截止日时会明确提示。**本地跑须 `DATABASE_URL='sqlite:///./data/dev.db'`**。落库后跑 `gr-tag`、`retail-sentiment`/`retail-volume`/`retail-newcomers`，以及需要观点抽取时的 `kol-refine`/`kol-relevance`/`kol-quality`/`kol-judgment`。出站 `make site` |
| `make youtube` | YouTube 观点：按标的搜近 24h、浏览量>1000 的全语种视频(`youtube-crawl`) + Gemini 混合分析(`youtube-tag`：top N 原生看视频，其余优先复用完整口播/字幕)→ 标的页观点流。需 `YOUTUBE_API_KEY`+`GEMINI_API_KEY`；`youtube-tag --since-days N --min-subscribers 2000 --min-duration-seconds 60 --workers 8` 可按产品门槛完整补跑，`--transcript-only` 只处理已有 `yt_fulltext` 且不回退原生视频；**无配额兜底**：`youtube-tag-text`(标题+简介→LOW 档双语，mode=text)，同样支持 `--only/--since-days/--min-subscribers/--min-duration-seconds` 精确补缺 |
| `make yt-channels` | YouTube 频道作者基础信息(粉丝数/视频数/个人简介/@handle) → 本地 `yt_channel`(供 YouTube 正文作者头像旁展示)。Data API `channels.list`(part=snippet,statistics)；需 `YOUTUBE_API_KEY`。整表刷新(~540 频道)。出站 `make site` |
| `make youtube-digest` | YouTube 完整口播 → 「投资者摘要」+「内容目录(章节)」→ 本地 `yt_digest`。读 `yt_fulltext` 口播文本跑 LOW 档(qwen-flash，不重看视频)；增量(`--force` 重跑、`--only` 指定 video_id)；需 `QWEN_API_KEY`。先跑 `youtube-fulltext`。出站 `make site` |
| `make youtube-judgment` | 作者页「① 标的判断」结构化参数：从 `yt_analysis` 观点/论据抽 时间周期/目标价/关键位置 → 本地 `yt_judgment`。LOW 档(qwen-flash，纯文本不重看视频)；增量(`--force` 重抽、`--only` 指定 ticker、`--workers`)；只抽明说不臆造、多为 null；需 `QWEN_API_KEY`。出站 `make site` |
| `make youtube-creator-view` | 作者页「① 标的判断」每标的综合：把同一博主对同一标的的多条视频判断综合成 整体立场+几点关键判断 → 本地 `yt_creator_view`。LOW 档(qwen-flash，读已蒸馏文本不重看视频)；增量(`--force`/`--only` ticker/`--workers`)；需 `QWEN_API_KEY`。出站 `make site` |
| `make kol-judgment` | KOL 目标价+操作周期：从 reddit/x/雪球/Toss/Yahoo JP **原帖**抽 买入/卖出/目标价(prompt 现价锚点剔噪)+周期 → 本地 `kol_judgment`。LOW(qwen-flash)；增量(`--only`/`--force`)；只抽明说、反臆造；先跑 `kol-refine`(复用其候选池)；需 `QWEN_API_KEY`。出站 `make site` |
| `make kol-refine` | KOL 个体观点提炼：reddit/x/雪球/Toss/Yahoo JP 每标的每源 top-N 按 Qwen LOW → DeepSeek low → Gemini 兜底（`KOL_REFINE_PROVIDERS` 可改顺序）→ `kol_refined`(为什么看多/看空 + 2-3 要点，zh/en)，并记录实际成功模型。标的页象限①「个体观点·KOL」展示提炼而非照搬原文。增量；`pipeline.manage kol-refine --per-source/--only/--source/--force`。需至少一个对应 provider key |
| `make kol-viewpoint` | KOL 观点视角分类：对已蒸馏观点(`kol_refined`+`yt_analysis`) 跑 LOW 档 → `kol_viewpoint`(7 视角 1-3 个)。供标的页 KOL 模块「按视角」视图。增量；先跑 `kol-refine`；支持 `--only/--source/--since-days/--force` 精确补跑 |
| `make tw-match` | X 推文 ↔ ticker/topic 硬匹配：重建云端 `tw_tweet_topic`，由 `pipeline.manage tw-match` 调用 X 平台适配器。整表重算，需 `DATABASE_URL` 指向 Supabase Postgres |
| `make tw-sentiment` | X 推文情绪打分：`tw_tweet_topic` 命中的 ~5.4 万推文 flash 批量打 -1..1 → **云端** `tw_tweet_sentiment`。⚠ 别加 sqlite 覆盖。增量。需 flash key。供 `kol-sentiment` |
| `make sv-price-history` | Score 结算所需日线价格回填：通过 `pipeline.manage sv-price-history` 写入 `price_daily`，默认从 `2025-06-01` 起，支持 `ONLY=MU,NVDA` 局部回填 |
| `make sv-v0 / sv-v0-prod` | Smart Account v0：通过 `pipeline.manage sv-v0` 跑候选召回、LLM 结构化、价格结算、投资者评分和前端 JSON 导出；`sv-v0-prod` 使用作者均衡抽样。YouTube 候选、全文队列、抽取、结算和评分统一要求频道粉丝 `>=2000` 且视频时长 `>60s`，`--only`/`--youtube-since-days` 贯穿候选到抽取；Reddit 的 `--reddit-since-days` 同样贯穿候选与抽取，避免局部补跑吞入历史欠账；继续执行作者池、映射版本与完整口播证据门槛。结构化抽取默认 Qwen LOW → DeepSeek low → Gemini（`SV_EXTRACT_PROVIDERS` 可改顺序），记录实际成功模型 |
| `make hyperliquid-smart-money` | Hyperliquid HIP-3 TradFi Smart Money：同步 TradFi 合约、主动成交候选地址、fills、账户状态、当前仓位、绩效曲线和资金台账，计算 Onchain Score、Smart/Qualified 分层及标的 1D/3D/7D 仓位/资金流，导出 Web/iOS 数据；支持 `STAGE=markets/wallets/profiles/score/all`、`MARKETS`、`WALLETS` |
| `make hyperliquid-smart-money-live` | 持续订阅全部活跃 TradFi 成交，后台补 fills/账户画像，默认 30 秒评分、60 秒原子发布并写 `data/runtime/smart-money-live-health.json`；支持 `CANDIDATES`、`WALLETS`、`PROFILES` 和各刷新周期调优 |
| `make congress-score` | 美国国会两院一年公开交易评分：下载保留 House/Senate 官方 PDF 链接的归一化快照，按同日同标的同方向去重，以次一交易日收盘入场并结算 20D/60D 相对 SPY 超额；至少 5 个已结算买入决策日才进入正式排名，完整 CSV、逐事件证据、Markdown 报告和 manifest 输出到 `data/exports/congress_score/` |
| `make sv-ticker-signals ONLY=MU,NVDA,MSTR` | 标的级 Score：历史时点作者百分位 → 7 日观点聚集 → 下一交易日开盘后的 1/5/20/60/90/180 日相对 SPY 回测；首批详情页只消费 MU/NVDA/MSTR |
| `make sv-indicator-backtest` | Smart Account 发现页四指标：历史平台内正式 Top/Bottom 10% → 1/3/7/30/90D 加权净强度、作者净人数、人数突变和高低分歧 → 连续信号事件化 → 1/5/20/60/90D 胜率、盈亏比、利润因子及相对 SPY 超额；CSV 写 `data/reports/sv_indicator_backtest.csv` |
| `make sv-indicator-report` | 不重算信号，基于现有 `sv_indicator_*` 导出逐事件结果、逐 Call 原文/URL、紧凑证据、稳健性统计和四指标各 5 个成功/5 个失败的原帖证据案例集到 `data/reports/` |
| `make sv-segment-backtest` | X 作者周期/赛道/投资类型子 Score 垂直回测：历史时点子类排名 → Top 10%/25% 的 3/7/14/30D 集中事件 → 1/5/20/60/90/180D 方向收益、相对 SPY 超额和原帖证据；报告写 `data/reports/sv_segment_backtest/` |
| `make sv-portfolio-backtest` | 只使用 X：将历史时点 Score 集体信号和逐作者已结算 Call 转成真实资金占用的组合净值，按下一交易日调整开盘、同标的不重叠、活跃持仓等权、空窗持有现金计算多空/只多/只空及 1/5/20/60/90/180D 的总收益、CAGR、年化波动、夏普、最大回撤和成本敏感性；输出 `data/reports/sv_portfolio_backtest/` |
| `make smart-account-follow-backtest` | 当前正式 X/YouTube/Reddit 作者逐账户跟单：只从发布日前历史合格快照开始，按下一交易日复权开盘、同标的最新生命周期判断覆盖、活跃标的等权和 10bps 往返成本计算总收益、CAGR、SPY 超额、回撤及只做多对照；另导出带幸存者偏差的完整历史描述与逐笔证据到 `data/reports/smart_account_follow_backtest/` |
| `make sv-rank-event-research` | 只使用 X 历史时点排名事件：强度阈值只读信号日前历史，宽参数搜索头部跟随、底部反向和头尾背离，并以前半段 50bps 净收益选参、后半段固定验证，同时做流动性、成本、延迟成交和剔除主要贡献标的压力测试；输出 `data/reports/sv_portfolio_backtest/x_sv_rank_event_*` |
| `pipeline.manage overall-signals --ticker MU` | 重算标的页整体数据的异常归因与聪明钱/散户分歧：归因优先读显式 JSONL、缺失时读本地 `x_opinion`；聪明钱线缺旧实验缓存时读取 `sv_call` 并按 call 当日 `sv_investor_score_asof` 前 10% 作者加权，避免前视；输出 `web/lib/data/overallData.json` |
| `make xueqiu-author-plan / xueqiu-author-auth / xueqiu-author-run / xueqiu-author-drain / xueqiu-author-status` | 雪球 Score 作者池：版本化候选池 → 用户登录授权 → 一年作者时间线断点回填（`drain` 为小批次冷却长跑）→ 状态统计；固定写本地 `data/dev.db` |
| `make xueqiu-sv-full` | 雪球 Score 完整长跑：自适应退避回填正式 300 人作者池 → 校验全部完成 → 扩展标的映射 → 候选召回 → 作者均衡 LLM 抽取 → 结算/评分/导出；作者池不完整则停止在评分前 |
| `make kol-sentiment` | KOL 每日净情绪 rollup：跨平台 情绪×ln(1+互动)×相关性 → 本地 `kol_sentiment_daily`(折线图下方绿/红面积)。⚠ **不加** sqlite 覆盖(脚本自 hardcode 本地+从 .env 读云端拿 X)。先跑 `tw-sentiment`。出站 `make site` |
| `make kol-volume` | KOL 每日讨论度 rollup：跨平台帖子/视频**计数** → 本地 `kol_volume_daily`(折线图下方条状图)。X 默认读本地 `x_opinion`；需要云端 `tw_tweet_ticker` 补充时设置 `KOL_VOLUME_CLOUD_X=1`，并按 `(tweet_id,ticker)` 去重。⚠ **不加** sqlite 覆盖。出站 `make site` |
| `make retail-sentiment` | 整体散户 每日净情绪 rollup → 本地 `retail_sentiment_daily`(KOL 模块切到「整体散户」时的绿/红面积)。全量散户+本土论坛(Naver/YahooJP/PTT/Toss)、不含 YouTube；X 走 `tw_tweet_ticker`⋈`tw_tweet_sentiment`。⚠ **不加** sqlite 覆盖。先跑 `tw-sentiment`。出站 `make site` |
| `make retail-volume` | 整体散户 每日讨论度 rollup → 本地 `retail_volume_daily`(「整体散户」视图的条状图)。同口径计数。⚠ **不加** sqlite 覆盖。出站 `make site` |
| `make retail-newcomers` | 整体散户 每日新增散户 rollup → 本地 `retail_newcomers_daily`(「整体散户」视图第三块条状图)。各平台首次参与该标的讨论的去重作者数(Reddit 发帖+评论 / 5 论坛；不含 X/YouTube)。**纯本地、无需云端**。出站 `make site` |
| `make kol-newcomers` | KOL 每日新增 KOL rollup → 本地 `kol_newcomers_daily`(「KOL」视图第三块条状图)。X(x_opinion)/YouTube(yt_video)/雪球(gr_post) 首次讨论该标的的去重作者数。**纯本地、无需云端**。出站 `make site` |
| `make overall-signals` | 整体数据『异动归因 + 聪明钱↔散户分歧』(仅 KOL，qwen-flash) → 构建期 JSON `web/lib/data/overallData.json`(异动金 ⚑ 标记+AI 归因 / 技能加权 KOL vs 散户分歧线)。读本地 daily + `retail_sentiment_daily` + `/tmp/<ticker>_x6m.jsonl` + `/tmp/mt_*` 技能缓存。`TICKER=XXX make overall-signals`(默认 PLTR)。需 `QWEN_API_KEY`。出站 `make site` |
| `make narrative-rotation` | 新叙事页数据：固定板块 taxonomy、跨社区内容归类 → 构建期 JSON `web/lib/data/narrativeRotation.json`；展示热度排名变化、讨论占比变化、情绪转向与叙事详情页来源/地区/标的分布。默认近 21 天，近 7 天作为当前窗口；不使用旧 `narratives` 表。出站 `make site` |
| `make kol-translate` | KOL 原帖**完整忠实翻译**(逐句、不压缩) → `kol_refined.trans_zh·en`。供观点浏览器卡片/阅读面板的「译」选项。只译已展示项、增量；同一 `source+item` 的翻译跨 ticker 复用，已有兄弟行直接回填，新内容只调用一次并写全部 ticker 行；与提炼解耦可独立重跑；`--source/--per-source/--since-days/--only/--force`。默认 provider 链为 Qwen LOW → DeepSeek low → Gemini，可用 `KOL_TRANSLATE_PROVIDERS=gemini` 等调整顺序；单一路失败会继续尝试后备，不会把原文伪装成译文。需对应 provider key。本地测试加 `DATABASE_URL=sqlite:///./data/dev.db` 直写 `dev.db` |
| `make kol-relevance` | KOL **相关性打分** 0-100(越高=越是在讲这只票，区分「深度分析」vs「顺带列入名单」) → 隔离表 `kol_relevance`(覆盖 reddit/x/雪球/Toss/Yahoo JP+youtube)。供观点浏览器默认『相关度降序』排序(不做筛选)。增量、可独立重跑；`--only/--force/--per-source/--no-youtube`。需 `QWEN_API_KEY`。本地测试同上 |
| `make kol-quality` | KOL **帖子质量打分** 0-100(内容含金量：实质分析/数据/逻辑 vs 口号/喊单/灌水；**与标的无关**，按 source+item 去重) → 隔离表 `kol_quality`。供观点浏览器『只看高质量』开关(≥65)。覆盖 reddit/x/雪球/Toss/Yahoo JP+youtube；增量；`--only/--force/--per-source/--no-youtube`。需 `QWEN_API_KEY` |
| `make rollup / mood / trending / narratives / brief` | 单独重算各聚合 |
| `make cloud-init` | 一次性迁移：建表 + 上传本地源数据 + 云端重算派生表 |
| `make cloud-push` | 把本地源数据增量上传到云端（redditalpha 用；bSmart 一般不需要） |
| `make cloud-pull` | ⛔ **默认拒绝**（会用「只有 Reddit 核心」的云端覆盖本地、抹掉 bSmart 独有的 gr_*/yt_*/kol_*）。确需重建：`make backup-db && FORCE=1 make cloud-pull` |
| `make backup-db` | 用 SQLite backup API 备份 `data/dev.db` 到项目外目录；默认只保留最近一份 |
| `make snapshot-db` | 校验并压缩本地真源（系统 `xz` 多线程优先、Python `lzma` 回退），按 90MB 阈值生成单文件或 24MB 分片部署快照；不提交原始库 |
| `make restore-db FORCE=1` | 从仓库压缩快照还原本地 `data/dev.db` |
| `make data-clean` | 清项目内旧备份/抽帧缓存并 checkpoint WAL，不删除主库 |
| `make site` | 构建静态站 `web/out/`（读**本地 dev.db**；需 **Node 22**） |
| `make cf-deploy` | Cloudflare Pages Direct Upload：先 `make site`，再把 zh/en 产物复制到 `/tmp/bsmart-out-cf` 并上传到 `bsmart` 的 `main` production；可用 `PROJECT=xxx` 覆盖项目名 |
| `make site-cloud` | **现等同 `make site`**（bSmart 以本地为真源、不再 cloud-pull；保留名字防误清） |
| `make clean` | 只清 `web/.next-dev`、`web/.next`、`web/out` 构建缓存；用于修复开发热更新或生产构建残留 chunk，不触碰 `data/dev.db` |
| `make stats` | 打印库内统计 |
| `make demo` | 一键离线全流程（样本+mock，无需 key） |

---

## 8. 构建 & 部署

1. `nvm use 22`（**必须 Node 22**；Node 23 + 实验 SQLite 会让构建被系统 SIGKILL；仓库根目录有 `.node-version=22`）。
2. `make site`（读本地真源 `data/dev.db` + `next build` → `web/out/`，~6500 页、cpus:1 串行）。
3. 推荐发布到 Cloudflare Pages：首次 `npx wrangler login`，之后 `make cf-deploy`（可用 `PROJECT=xxx` 改 Pages 项目名）。
4. Railway/Dockerfile 仅作为旧路径保留；Cloudflare Pages 运行时只托管静态文件，不跑 `server.mjs`。

---

## 9. 重要约定 / 易踩坑

- **构建用 Node 22**（见上）。若开发或构建报缺失 page/vendor chunk，先停止残留 Next 进程并执行 `make clean`，再重启开发服务或构建。
- **多语字典**：`dictionaries/zh.ts` 是源（`Dictionary = typeof zh`），`en.ts`/`ja.ts`/`ko.ts` 必须镜像完全相同的 key（`npx tsc --noEmit` 会强校验）。新增 locale 只需在 `i18n.ts` 的 `locales`/`isLocale`/`DICTS` 三处登记 + 加 `LanguageSwitcher` 选项；路由/sitemap 自动随 `locales` 扩展。帖子内容只有 `*_zh` 译文，故 ja/ko 渲染时回退英文原文。
- **密钥不入库**：`.env` / `web/.env.local` 已 gitignore；含 `QWEN_API_KEY`/`DEEPSEEK_API_KEY`/`DATABASE_URL`(含密码)/Supabase anon key 等，切勿提交或泄露。
- **回到纯本地**：`.env` 的 `DATABASE_URL` 改回 `sqlite:///./data/dev.db` 即可。
- **管线所有步骤必须走 SQLAlchemy（`common/db.py` 的 engine），不要裸 `sqlite3.connect`**：否则 `DATABASE_URL` 指向云端时会把结果写进本地文件、云端拿不到。`translate.py` 曾因此漏译，现已修复并继续作为 Reddit 中文补译链路使用。
- **待办（省 token）**：千问/DeepSeek 的系统提示词每次逐帖重发，未确认是否走缓存计费；可启用上下文缓存。
