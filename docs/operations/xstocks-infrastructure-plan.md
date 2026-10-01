# xStocks Infrastructure Development Plan

更新：2026-10-01。目标是沿用 bSmart 用户现有非托管 EVM 钱包，HL 有
同标的活跃永续市场时仍走 HL；只有确认 HL 缺失时才使用 xStocks 现货。
卖出后默认将 USDC 回流到该用户的 HL 合约账户。第一版覆盖 50 个研究候选，
无需直接接入发行方 xChange；公共 API 仍可能存在服务商权限或使用限制。

本文是按依赖顺序实施的开发与验收计划，不代表资金链路已经可用。
当前已完成候选研究、P1/P2/P4 只读实现、P3 账本/快照基座、P5a CoW 证据、P5b 私有准备/预留、P5c 签名暴露保护与原生 codec；用户已执行 005/006/007 迁移，云端权限/共享锁及两连接回滚写事务验收通过。生产 Storage/HTTP、真实钱包/授权/执行验收仍待完成。旧 `bsmart-markets` 是 Solana/Jupiter 只读接口。
新 EVM 路径使用独立 `bsmart-equities`，不替换 HL 交易执行器或旧接口。

## 成熟服务优先

我们只做服务融合，不自建 DEX、跨链桥、求解器、交易广播网或通用 paymaster。
市场深度与混合成交交给 CoW solvers，跨链与退款交给 Across/Relay；钱包与
支持的 gas sponsorship 优先沿用 Privy。用官方 CoW SDK 与成熟 ABI/EIP-712
库，只有服务提供的数据不能直接表达产品安全边界时才增加薄校验层。

| 能力 | 优先复用 | bSmart 必须保留 |
| --- | --- | --- |
| 钱包/用户签名 | 现有 Privy 与设备钱包 | owner 绑定、同意范围、签名前校验 |
| 多 DEX 报价/成交 | CoW Trading SDK、Order Book API、solvers | 净到账、费用边界、UID 对账 |
| 跨链/HL 资金路由 | Across 与已有 Relay 服务 | leg 授权、到账证据、不双算余额 |
| gas 代付 | Privy 或 provider 已支持的 sponsored flow | 当前钱包/链兼容性与平台预算 |
| 元数据 | xStocks 官方资产 API、HL info API | 完整性、身份唯一、HL 优先 |
| 持久化/定时对账 | 现有 Supabase Postgres/RPC/cron | 订单意图、owner 隔离、未知结果处理 |

先做服务能力 spike，再选择最少的 provider 组合；能由一个服务直接完成的
资金 leg 不人为拆成两段。没有成熟服务支持的能力先阻断上线，不立即自建替代。
Privy 有 EVM sponsorship 文档，但当前 Swift SDK、实际 wallet 类型及 Ink 支持
必须单独确认，不从 React API 推断原生可用。详见
[CoW SDK](https://docs.cow.fi/cow-protocol/integrate/sdk) 与
[Privy transaction sponsorship](https://docs.privy.io/guide/react/wallets/embedded/prompts/transact)。

## 固定约束

- HL 完整目录读取失败、不完整、过期或非 USDC 抵押不等于 HL 无市场。
- 现有仓位始终绑定原来的场所、链和代币；HL 新上市不阻止卖出旧 xStocks。
- xStocks 第一版只做 1x 多头现货；卖出必须使用已核实的用户持仓，不做空。
- Ethereum/Ink 都是执行候选链；Arbitrum 是既有资金链。执行链要按实时
  净到账、资金成本和 sponsor 能力决策，不按过去一次报价固定选择。
- 首次授权、跨链和卖出回流不是原子操作；不得声称一次失败能撤销已成交部分。
- “无需用户额外 gas”意味着平台或已验证的服务商承担 gas，不能假定 gas 不存在。
- 不保存用户私钥、不由服务端替用户签资金授权、不复用 HL agent 的受限权限
  签钱包订单。买卖必须绑定 Supabase 身份和既有不可变 owner 地址。
- 24/7 保留交易入口，只有实时有效报价才能成交；没有周末样本不能证明流动性。
- 用户无需新增 KYC 是产品目标，不是公共协议自动提供的保证；不绕过地区或
  服务商限制。无直接 issuer KYB 依赖，不等于所有 API 无申请门槛。

## 架构与边界

`bsmart-equities` 提供目录、报价、订单意图与对账 API。纯资产解析、HL 路由
和订单规则与 HTTP handler 分开，provider adapter 只访问固定域名。
与 HL 共用 `bsmart-markets` 的完整目录读取、缓存和基础校验。

CoW adapter 负责报价/订单 UID/状态；Across adapter 负责明确授权的资金 leg。
现有 withdrawal/funding 服务与本地受保护交易日志只复用已验证能力，不把旧出金
请求当作可任意组合的新执行器。执行数据库及 RPC 独立迁移，由用户执行 DDL。

iOS 新代码进入 `Core/Trading/Equities`、`Core/Wallet` 与 `Core/Data`；Features
只消费 store/model，不拥有网络或签名逻辑。现有 HL 弹窗与执行流程保持不变。

## 阶段与验收

| 阶段 | 当前状态 | 交付 | 验收条件 |
| --- | --- | --- | --- |
| P0 设计 | 已完成 | 本计划、EVM 发现契约 | 确定依赖、资金安全约束和上线门槛 |
| P1 目录路由 | 本地及公开元数据 smoke 完成；未部署 | 50 名单、发行方 EVM 解析、完整分页目录、认证只读 API | HL 优先、身份唯一、失败阻断、名单不等于执行许可 |
| P2 报价校验 | 本地只读实现及公开双链探针完成；真实用户 funded 验收未完成 | 买/卖 CoW 预览、链上余额/allowance/rebase 读取、规范化订单边界 | 精确整数、服务端 owner、净到账/时效/费用边界；上线前仍需真实用户验收 |
| P3 账本状态 | 用户已迁移；云端执行前幂等/CAS/RLS 角色验证通过；生产快照/HTTP 与执行步骤待验收 | SQL 迁移、RLS、service RPC、CAS、幂等、完整目录快照 | owner 隔离、崩溃恢复、并发去重、未知结果不得重发 |
| P4 资金编排 | 本地只读资金预览已实现；真实资金/到账/回流与生产验收待完成 | 资金来源/到账/回流 adapters 与编排器 | 不挪用保证金、不重复记账、退款可定位、费用有界 |
| P5 签名成交 | P5a/b/c 本地完成，005/006/007 已迁移，云端双连接回滚写事务及暴露保护通过；原生 codec 已构建，实际钱包接线、提交及 HL 对账待完成 | 私有准备、钱包互斥、iOS 解码校验器、CoW 提交与对账 | 签名前后重新验证、单次提交、成交终态可证明 |
| P6 gas 代付 | 未开始 | provider 代付配置、预算和健康检查 | 用户不补原生币、不能无限领 gas、平台成本可追踪 |
| P7 App 灰度 | 未开始 | 统一交易入口、原生状态展示、受控发布 | 失败/取消/部分成交/回流不确定全链路验收 |

### P1 目录与路由

1. 将研究脚本中的 EVM 地址、原生 USDC、发行方身份/停牌解析移至 runtime
   模块；研究脚本继续消费同一解析器，避免两份地址配置漂移。
2. 固定当前 50 个候选 ticker，只允许完整官方名册解析出唯一 USD underlying；
   禁止从 ticker 拼资产 ID/链上地址，禁止根据研究报价决定实时可交易状态。
3. 完整分页名册缓存最多 10 分钟；实时单资产详情与 HL 观察最多 30 秒。
   详情必须匹配名册的 asset ID、symbol 和部署地址；链上持仓验证留到 P2/P5。
4. 新 `GET bsmart-equities/route?ticker=...` 验证 Apple/Google Supabase 身份。
   所有路由 `executionEnabled=false`，不返回 calldata、签名或 secret。
5. 单元测试覆盖完整目录、名单、停牌、过期、HL 新上市、身份变化、认证及
   query 攻击。只读现场 smoke 验证不使用用户钱包或资金。

生产发现还需一个独立性能门槛：官方完整目录冷读取不能在用户操作时逐页
等待。第一次 smoke 出现一次 8 秒 provider 超时，随后冷加载约 38 秒；已有
warm cache 只读约 338ms。这不是 App 的可接受首单时延。优先用现有 Supabase
Storage/cron 分发完整验证过的不可变身份快照，再同步重读单资产/HL 活状态；
快照过期或校验失败仍阻断，不用过期快照授权。准备快照契约和发布脚本时
复用现有基础设施，不再建设新缓存服务；此性能优化是 P3/P7 上线前依赖。

首次交易耗时须分解为目录、quote、funding、签名、fill 和 return，不能把
warm metadata 耗时或 provider 的桥填单估计作为端到端交易承诺。

本轮验证：46 项目录/路由/认证/旧接口/研究工具回归测试通过；完整历史目录
1,169 条解析为 995 个 USD 身份，50 个候选全部匹配。两次初始现场读取出现
网络超时，未产生错误回退；增加最多两次固定域名元数据 GET 重试后，第三轮
NVDA/ASTS/SPY/JPM/OUST 五个探针全部通过。ASTS 冷目录约 28.1 秒，后续
SPY/JPM warm 读取约 330/697ms。证据 `data/reports/xstocks/20261001/infra-smoke-bounded.json`。
这些不是部署后的认证 HTTP、funded quote 或真实成交验收。

### P2 报价与订单边界

1. 确认 CoW 对每个执行链、raw token、真实 owner 的 funded quote 能力；
   未验证的 quote 仅预览，不能因 HTTP 200 升级为可执行。
2. 规范化 buy-USDC / sell-owned-token，金额全程使用原始整数；读取链上
   decimals、当前资产 multiplier 与 corporate actions；EVM balanceOf 已调整，
   不二次乘 multiplier，不把内部 sharesOf 记账量当 ERC20 转账量。
3. 校验 input/output token、chain、receiver、sellAmount、feeAmount、minBuyAmount、
   validTo、kind、balance mode、partial-fill policy、appData 与 EIP-712 domain。
4. 最低到账和费用 cap 由用户订单授权决定，研究用 3% 筛选线不是交易费用上限。
   初始策略采用不可部分成交订单；仍要处理供应商及链上异常部分执行。
5. `GET/POST preview`、quote fingerprint 和 signing preparation 契约先于客户端。
   用官方 SDK 的固定版本处理 ABI/EIP-712/UID，不手写密码学实现。

本地已实现 `POST /preview`，server wallet binding 锁定 owner/receiver；买入仍
复核 HL 优先，卖出单独核实官方旧仓余额，不因后来上市或买入名单变化而迁移
用户原仓。Viem 固定 block 读取 ERC20/relayer allowance 和当前/待生效 multiplier，
报价后重读并拒绝 rebase 变化、切换窗口、超余额卖出。两条候选链独立记录失败，
不将某一链失败伪装为另一链已交易。整数/时效/appData/不可部分成交等均校验。

复用固定版本的 CoW SDK 费用/slippage 数学、订单 domain 和 relayer 配置，
保留已有限时 JSON REST 传输（SDK HTTP 不支持注入 AbortSignal）。现代订单
费用按 SDK 纳入 sellAmount，待签规范对象 feeAmount=0，不原样签报价对象。
仅返回业务 fingerprint 和预览，不返回签名载荷/UID、不生成真实订单。用户
`maxNetworkFeeBps` 只约束报价网络成本，不把动态协议费或未来桥费说成全部包含。
fingerprint 不是授权凭证；持久化授权与签名前重读仍依赖 P3/P5。

公开现场 ASTS 两条链报价均通过边界校验；其 providerVerified=false，使用
无 signer 的公共测试地址，不属于真实用户 funded quote 或出售持仓验收。
该测试地址在 Ethereum 有既有 USDC，不能据此声称我们给测试账户入过金。
60 项相关回归通过，type-check 与公开响应的 OpenAPI schema 校验通过。
全仓检查仍有九项既有 iOS 架构问题及一项既有资源术语问题，不在本次修改范围。
Ink 第一个公共 RPC 超时，另一个官方端点成功；已用成熟 viem fallback 做
只读查询备用，生产仍需配置稳定 RPC。冷探针约 67 秒，绝非交易时延承诺。
证据 `data/reports/xstocks/20261001/preview-smoke-recheck.json`。只读 flag 默认关，
未部署、未写 DDL、未下单/签名/批准/转账，未开启 gas 代付或默认回流。

进入 P3 前的交接：保留真实用户 funded quote、双向小额成交与链上对账作为
交易开启前必需的验收，不用公共地址报价代替；P3 同时准备完整目录快照分发，
并评估现有 withdrawal/funding 账本的幂等和恢复机制。最小迁移只准备文件，
由用户按项目规则执行，不在开发工具中自动执行数据库 DDL。

### P3 持久化意图与状态机

先评估现有资金/订单日志能否安全复用，再按必要字段准备最小
`equity_intents`、`equity_legs` 迁移与 RLS，不先建完整事件总线或交易账务系统。
CoW/桥服务保留执行、成交和退款状态真源；bSmart 保存用户授权、provider ID
与最后对账证据。owner 只能读本人记录，服务 RPC 在事务中推进状态。
数据库存规范化对象/hash、UID/tx hash 与安全错误码，不存钱包密钥，
不向客户端泄露 provider 原文。

`clientIntentId` 唯一绑定 owner/内容 hash；不同内容重用同 ID 必须拒绝。资金
leg 和订单 submit 各自有一次性租约/attempt，未知结果只查链或按确定 UID 查订单。
不能通过超时把未知变失败再重发。服务事件与客户端受保护日志互相校验。

预期状态：`draft -> quoted -> authorized -> funding_pending -> funded ->
order_pending -> filled -> return_pending -> completed`。已在执行链持有 USDC
可跳过 funding；买单成交后结束，卖单确认后默认进 return。另有明确的
`expired / rejected / cancelled / refund_pending / needs_reconciliation`。
尚未签名可取消；资金或订单已提交后只允许真实协议取消，不假装资金已返回。

### P3 本轮交付与交接

P3 本轮落地（2026-10-01，API 未部署）：用户已在 iOS 项目执行单文件迁移
`202610010005_equity_intent_ledger.sql`，助手没有执行 DDL，不重复运行。`bsmart_equity_intents`
按账号/clientIntentId 去重，绑定 owner、完整请求和内容 hash；同 ID 改金额/
约束/钱包返回冲突。认证 API 可以创建、恢复读取、版本 CAS 刷新预览、仅在
执行前取消；取消不依赖钱包当前可用。新账本 flag 默认关闭，只有 draft/quoted/
cancelled 可由 API 到达，不提供 authorize/submit/transfer。

`bsmart_equity_legs` 保留 provider ID、原链/目标链及 request hash，区分两个
funding/return 分段，前段确认后才可 claim 后段。RLS 只读本人，直接列权限及
API 均不泄露租约；写入只允许 service RPC。claim 永久限制一次 attempt，
租约过期/崩溃/丢响应只可对账，不重发。observe 以 CAS 记录证据 hash，不能
把 hash 本身当成交/到账证明。授权安装 legs、父状态执行推进及 provider/链
证据验证仍归 P4/P5，当前无实际执行 worker；不要因迁移成功提前启用资金。

完整发行方目录可用私有 Supabase Storage 预加载：原始全目录先校验，再压缩
为完整身份快照，并校验 SHA256、数量、原采集时间和十分钟 TTL。发布为不可变
hash 文件，读回后才改 active 指针；单 publisher，每五分钟刷新为后续运维要求，
尚未安装 cron。runtime 合并读取并短缓存指针，失败/过期不回退慢分页；HL/
单资产详情仍实时复核，不能用快照授权交易。公开采集 1,169 个身份/995 个 USD
资产，全部 50 个候选匹配，约 972 KB、采集约 23 秒；本地文件冷读约 33 ms、
warm 约 3 ms，绝非生产 Storage/App 时延。证据在 `catalog-preload/` 和
`catalog-preload-check.json`，历史文件不能日后冒充新快照上线。

79 项 Deno 回归（含三项仅 SQL 源码保护测试）、五项 Python probe 回归、项目
type-check 和契约校验通过。`probe_equity_ledger.py` 默认只读；显式 `--apply`
对既有测试账号创建一条 $1 草稿，用三条独立事务验证并发去重、输入/owner/
账号冲突、CAS 和取消重试，最终只保留已取消审计记录。模拟 SQL 预览仅在回滚
savepoint 内测试保存/时效/重试，不是供应商报价；RLS 为数据库角色模拟，
不是 App JWT/HTTP。云端检查通过，证据为 `ledger-database-probe.json`。
授权/执行 legs、生产 Storage/HTTP 仍未验收，无签名、资金或订单。全仓检查
的九项既有 iOS 和一项既有资源术语问题未改。下一步开始 P4 成熟 Across/Relay
资金路线能力验证，并完成私有目录快照上线依赖；不自动签资金。

### P4 资金调度与卖出回流

1. 精确区分 HL 可提现额、现货、已锁定保证金、执行链 USDC 与在途资金。
2. 买入优先花已到账执行链 USDC，不足再请求独立授权的资金 leg。金额不足或
   资金来源故障不能改 venue；报价过期后重报，不能隐瞒新成本。
3. HL -> EVM 验证 Relay 直接 v2 路由和现有 Across HyperCore gasless 权限/费用；
   若使用 HL -> Arbitrum -> 执行链，必须记录两段确认，不能假定原子性。
4. EVM -> HL 需实际验证 USDC-PERPS 的支持路由和 token identity；已有 Relay
   充值能力仅作为候选复用，不能因充值地址可用就认为卖出回流已成功。
5. 卖出所得归用户所有，默认全额扣除已授权有界回流费用后返 HL。成交与
   回流分开确认；失败时展示可定位的 execution-chain USDC，不假增 HL 权益。
6. 注入 quote expiry、bridge outage、慢确认、退款至 HyperEVM、用户退出、
   worker 重启等场景。保留余额不等于没有回流策略，而是回流失败的恢复状态。

### P4 本轮资金预览与交接

本地新增默认关闭的 `/intents/{id}/funding-preview`，仅消费已保存且新鲜的报价，
前后复核版本/owner/HL 优先和余额。买入先用执行链已到账 USDC，不足才基于
HL 可提现额计算 exact-input 资金补充；输入不超过缺口加剩余费用预算，最低
到账必须足额。统一账户需完整所有 perp 场所无仓位/订单、spot 无 hold；不双算
shared balance、不把净值当可提现额。Portfolio margin 暂时阻断 HL 资金来源。
旧出金/Across/其他执行中意图按 wallet-wide 查在途；这是只读阻断，不是资金锁。

Relay 薄 adapter 使用固定域名 quote-only、限时/限大小、无重试提交，校验同 owner
资金/退款、两边 USDC、协议 amount/minimum/deadline 和签名步骤类型。买入合并
CoW 网络费与桥最坏磨损，卖出单独约束回流桥费，不把股票单位的 CoW 费用虚算
成 USDC。费用总项和子项不重复相加。卖出只预估成交最低 USDC 的默认回流；
实际成交后必须取得新报价和用户有界同意，现有 USDC 不混入卖出所得。

官方 [Relay HC 文档](https://docs.relay.link/references/api/api_guides/hyperliquid-support)
已提供直接双向路径，因此不预先强制拆为 Arbitrum 两段。公开探针不等于真实
钱包资金能力；实际响应若无路由或需原生 gas 仍阻断。Across 旧执行器未改，
其 HyperCore 退款可能至 HyperEVM；第二段、通用 Across 资金 adapter 及链上/
HL 到账证据尚未落地。不得因 provider 状态 success 就累计 HL 可用权益。

目前 `executionEnabled/returnTransferImplemented/reservationsImplemented=false`，
gas 未验证。下一批 P4/P5 工作是实际 provider 权限/funded 路由验证、原子
wallet reservation、经用户授权安装 legs、未知结果只对账，以及成交/HL credit
证据；P5 专用签名 codec 必须校验 Relay permit 执行合约（不一定是存款地址）
和完整 nonce mapping/typed data。P6 解决 Ink 普通交易及首次 CoW allowance
代付，再做单 owner 小额往返。没有启用交易、签名、迁仓或生产资金。

100 项相关 Deno 测试与项目 type-check 通过。公开只读重测中 HL-origin 两条
路线暂不可用；Ethereum 回流为 permit-shaped，$100 最低到账 $99.843955；
Ink 回流为普通 EVM 交易，$100 最低到账 $99.829999，需原生 gas，planner 阻断。
价格是当时无真实用户资金验证的报价，不代表长期费率、真实成功率或完整
交易磨损。证据 `funding-smoke-recheck.json`。Ethereum permit recipient 为
执行 router 而非 depository，已纠正预览假设；允许识别其类型不等于允许签名。
OpenAPI/fixture/现场安全摘要 schema 校验通过；全仓仍有九项既有 iOS 架构问题
和一项资源术语问题，未在本阶段改动。

### P5 用户签名与真实成交

现有 Privy/设备钱包可以签 typed data，但需要新增专用 CoW codec 与验证器，
不能将任意 provider JSON 交给通用签名函数。校验 chain/domain/settlement/owner、
recipient、固定 appData 和 quote fingerprint，签名后再次验证授权边界。

精确 ERC-20 allowance 需要用户授权及 sponsor；禁止无限批准任意 spender。
提交前写持久化 attempt，提交后以确定 order UID 查成交与链上 receipts；
CoW API 接受不等于 fill。钱包退出/账号切换立即停止未提交动作，已提交只对账。
真实资金测试由用户执行有限额授权，不在纯开发阶段自动签名或转账。

### P5a 本轮交付与下一批

本地实现服务端专用 CoW codec，而非直接将报价 fingerprint 当可签订单。
`validateQuoteArtifacts/previewEquityArtifacts` 同一套前后路由、余额和 rebase
校验产生私有规范材料；公开 API 只保留原 preview，不泄露 order/domain/quote ID。
fingerprint 固定字段顺序，未来 jsonb 重排不改变绑定。旧只读报价无需数据库
变更；本批没有把规范材料持久化或声称旧预览可以重新拼成原始订单。

复用 `sdk-order-signing@1.1.15`、`sdk-contracts-ts@3.7.2` 和官方
`sdk-viem-adapter@0.3.33` 生成 domain/types/digest/UID。adapter 无 signer，
其 offline transport 禁止网络。只接受现有 owner 的 EOA EIP-712 签名，拒绝
eth_sign/EIP-1271 推断、任意 typed data、额外 hooks、partial/internal balance、
地址/domain/金额替换。准备与签名返回均须传入新读出的服务器钱包绑定、意图
版本及链状态，再查余额/allowance/精度/rebase/时效；签名有效不等于授权完成。
调用方仍需即时复核 HL/发行方活状态、在途资金，并通过未来原子授权事务。
相同订单可能在不同意图产生同一 UID，安装步骤必须使用已有永久 provider-ID
唯一约束，不靠 HTTP 幂等 key 或租约过期重发。

`cow_status` 只做有界固定域名 GET；`cow_receipt` 复用成熟 viem 查询真实链、
finalized head 与 canonical receipt block。`cow_reconciliation` 还必须匹配 API
订单、唯一 trade、官方 settlement 的 Trade、UID/owner/两种代币/精确输入与
最低输出，并核对该笔交易 owner 的净 ERC20 收付。receipt 未最终确认保持
pending；404/断网/取消/过期不当成无成交证明；假链/重组/重复/移除日志/
部分成交/批次归因不清需继续对账，不释放资金或自动重发。API fulfilled
本身不提供 credit。该 conservative finalized 策略会增加确认等待，需在真实
小额验收中分别测量成交展示与可回流资金时延，不承诺 HL 等同耗时。

只在已确认卖出中提供 `saleProceedsUsdcRaw`，这是该 UID 实际净到账 USDC，
不是钱包总余额或当前仍未花费的余额。回流前仍需读当前余额、重新报价并绑定
有界同意；`returnReady/resubmitAllowed=false`。OpenAPI v0.4.1 的 preparation/
observation schemas 是内部契约，无新签名、提交或对账 HTTP 入口；fixture 是
确定性合成测试，不是现场交易。当前 observation 不写 legs/推进父状态。

本轮最终验证：128 项相关 Deno 回归通过（28 项新增），项目及新模块
type-check 通过；OpenAPI 两个内部 schema 的 16 个正负例检查通过，
`git diff --check` 通过。全仓仍有九项既有 iOS 架构问题及一项既有资源
文案问题。本轮未部署、执行 DDL 或产生用户签名/订单/批准/资金操作。

下一批顺序：

1. 准备私有规范订单持久化与原子 owner 钱包预留迁移，由用户执行；原有
   withdrawal/Across 创建与 claim 必须共同遵守锁，不能只阻挡 equity。
2. 以新鲜规范订单、经 owner 校验的签名、有界资金/回流授权，在单一服务
   事务中安装唯一 legs；未知提交不释放锁、不重发，未签准备可明确撤销。
3. 接通单次 CoW submit 和 observation CAS，加入 HL 实际 credit/退款证据；
   同步完成 Relay nonce/permit executor allowlist 与 iOS 专用 codec。
4. 验证成熟 sponsor 与 funded bridge 能力，再由用户做有金额上限的小额
   双向验收；全部 flag 保持独立关闭，不因 codec 单测成功启用真实交易。

### P5b 本轮交付与交接

`preparations.ts/preparation_ledger.ts` 接通默认关闭的认证 `POST /intents/{id}/prepare`。
仅接收 expectedVersion，实时更新报价，只在已到账/已 allowance/已验证候选中
按真实 output decimals 比较最低净到账；选择一个执行链，并在同一事务保存
public preview、private material/order/domain/hash 和钱包预留。重试恢复原记录，
不生成新报价；取消/换钱包/新 HL 市场/资金活动/失去余额或授权均阻断。
公开接口仍无 typed data/签名/提交，signingEnabled/executionEnabled 恒 false。

迁移 `202610010006_equity_preparations.sql` 已由用户在 iOS 项目执行，不重复执行。
新增私有表无客户端读写，service 只能直接读取，通过 RPC 写入。共享原有
owner 钱包 advisory key，给两种出金表的 insert/update 加 guard；跨表互斥
不依赖 handler 先读后写。try-lock 在争用时 fail closed，避免旧 reserve
钱包先锁、direct update 行先锁导致死锁。只保护已协调的服务，不能锁住
外部钱包行为、设备本地 HL 订单或未登记转账，不把数据库预留称为链上托管。

未授权准备可通过原有 cancel CAS 原子释放，过期不会自动释放。内部买单
授权复核 owner/意图/实时路由/余额/allowance/rebase 和 EIP-712，单一事务
保存私有 consent 并安装唯一 CoW order leg；原 UID 在跨意图永久唯一。
卖单授权等待有界回流 consent，当前阻断；已授权 leg 保持 attempts=0，
数据库 trigger 独立阻断 claim/执行，不能靠一个环境变量打开真实交易。
没有新的授权 HTTP、executor、批准/资金 leg 或真实用户签名。

本地内存 PostgreSQL 测试验证了 RPC/CAS/私有权限、两种旧出金双向互斥、
失败全事务回滚、过期保留、取消释放、UID 去重、授权幂等及执行阻断。
PGlite 是单 session，不能代替真实多连接并发与 App JWT 验收。只读生产
审计时两种出金表和 legs 均为空，仅两个已取消意图；没有修改生产数据库。
旧 accepted/core_debited 状态仍按 P4 保守持锁，需要明确对账释放策略。
`probe_equity_ledger --preparations` 是新迁移后的只读权限/trigger 验证，不读
原始材料/签名，也不允许与 --apply 混用。用户执行后云端私有权限和五个
trigger 验证通过；两条 READ ONLY 事务使用合成 owner 验证旧出金相同 key、
重入、争用拒绝和事务结束释放。没有写入用户记录、调用供应商或产生资金。
证据 `data/reports/xstocks/20261001/preparation-database-probe.json`，并发写入
RPC 的完整事务验收仍为 false，不冒充已验证真实并发下单。

本轮 146 项相关 Deno 回归（18 项新增）、七项 Python probe 回归、项目
type-check、OpenAPI 两个正例/九个负例与 diff 检查通过；全仓仍有九项既有
iOS 架构问题及一项既有资源术语问题。API 没有部署或开放执行。

当时剩余顺序：完成云端多连接写事务竞争验收；完成 iOS 专用签名 codec 以及
有界 funding/return consent。开放 typed payload 前必须先持久化签名开始/
暴露状态，不能继续把已交给钱包的签名对象当作可直接 cancel 的未签准备。
再接单次 CoW submit 和证据 CAS。
目录 Storage/HTTP 部署、sponsor、真实 funded bridge/小额双向验收仍独立阻断上线。

### P5c 本轮交付与交接

用户已执行 007，不重复迁移。`preparation_signing.ts` 仅提供内部固定 payload
边界：新鲜检查后先持久化 signing 暴露状态，才能返回 immutable 原订单。
signing 加入全部持锁/父状态保护，只能接受原签名推进 authorized，不能取消、
自动释放、重新报价或跳过暴露状态。丢响应/拒签/超时都不证明未签；卖单仍
等待有界回流 consent。API 无 sign/authorize/submit 入口，数据库执行 guard 保留。

`probe_equity_preparations --rollback-writes` 在两条真实 PG 连接中仅用回滚种子
验证 distinct-intent 钱包竞争、失败 nested quote 回滚、普通/Across reserve
同 key timeout、释放后预留与 immutable retry。007 增补 signing-start retry
与取消阻断，所有五表测试行回滚并核对不存在；不调用 provider，不创建真实
签名/授权/legs/订单/转账。证据为 `signing-exposure-concurrent-write-probe.json`。
它证明 SQL 边界，不冒充 App JWT、真实 funded 并发或外部钱包原子互斥。

iOS 专用模型/codec 复用现有 WalletCore、BigInt 与 signature recovery；拒绝
未知字段/任意 EIP-712、错误 owner/account/意图/资产、金额/domain/UID 替换。
官方 SDK/viem 生成 Ethereum/Ink/超 UInt64 三组公开 key-1 测试向量。
当前只有离线边界，没有调用用户钱包或 UI/store 接线；151 项相关 Deno、
20 项 Python 回归及 `make ios-build` 通过。原生测试结果单独记录，非真机资金验收。

后续顺序：完成有界 funding/return consent 和 Relay nonce/permit executor
校验；再接 CoW 单次提交、observation CAS 与 HL 实际 credit/退款对账。
原生钱包接线必须先记录本地/云端 signing/unknown 恢复状态，且不能因为签名
单测通过就开启真实交易。目录 Storage/HTTP、sponsor/资金路径与小额往返仍待验收。

### P6 gas 与平台预算

CoW solver 可结算订单不代表首次 allowance 或返程跨链自动 gasless。
先确定现有 EOA 钱包是否支持可验证的 permit / sponsored transaction，
不为追求 UX 迁移到尚未审计的钱包或使用公共无界 gas faucet。

优先验证 Privy/provider 已有的 sponsored transaction 或 permit 路径，不自建
gas top-up/faucet/paymaster。若当前钱包或链不兼容，先评估同一钱包下的成熟
服务替代或调整候选执行链；不要默默换 owner 或新建托管钱包。平台支付
gas 与用户承担 USDC 服务费分开核算。不能证实代付时不得开放执行。

### P7 原生 UX 与发布

HL 市场继续现有 perp UI；xStocks 复用金额确认与结果状态，1x/仅买卖现货
是资产能力差异，不能伪装成杠杆或短仓。用户不需手动选链或备 gas，但应
在授权时看见最低到账、总 USDC 成本及资金未回流状态。

只读 API -> preview -> 单一内部测试 owner -> 小额真实往返 -> 多资产覆盖
-> 灰度。身份/KYC/地区限制核验、服务商权限与 sponsor 预算是独立上线门槛。
执行 flag、资金 flag、sponsor flag 默认关闭，不能用一个 flag 绕过全部验收。

## 验证与操作

每阶段新增针对风险的离线 tests、type check 和 architecture check。provider
调用使用 mock 注入；现场 smoke 只做 GET/unsigned read，不创建订单。
RLS/RPC 在本地 Supabase 测试后提供用户执行迁移的操作步骤；不自动运行 DDL。
生产部署与真实成交必须分别报告，不把本地测试或一次报价称为上线。

## 官方依据与未解决依赖

CoW 的订单签名、settlement 和 vault relayer 机制见
[核心合约](https://docs.cow.fi/cow-protocol/reference/contracts/core)。发行方名册
完整分页与网络元数据见 [资产 API](https://docs.xstocks.fi/apis/openapi/assets/list_public_assets)。
Across 的 HyperCore 出金需要 gasless 权限；退款可能到 HyperEVM，而不是 HL
合约账户，见 [HyperCore 出金](https://docs.across.to/introduction/hypercore-withdrawals)
与 [HyperCore 说明](https://docs.across.to/introduction/hypercore)。

截至本计划：尚未验证当前账户的 CoW funded order、Across 返程权限/路线、
raw token corporate-action 对账和 EOA gas 代付。它们决定能否达到完整无缝 UX，
不影响先实现默认禁用执行的目录、报价校验与订单账本。
