# bsmart.today 内测单页官网

## 当前状态

- 最新连续必填版已发布 `https://8b1ebaa5.bsmart-501.pages.dev`。发布脚本已将财经背景加入资源清单，共 93 个文件，源图与发布图 SHA-256 一致。TypeScript、完整 1,198 路由构建、13 项接口测试和架构/术语检查通过；中英文各 320/390/1440/1920 宽度、图片加载、表单首屏可见、邮箱/渠道/联系方式/其他必填校验以及本地 KV 提交通过。下面两步版部署为历史记录，现已替换。

- 2026-09-15 两步申请版已发布至 `https://11fd1b38.bsmart-501.pages.dev`（生产分支 main）。完整构建 1,198 路由、TypeScript、13 项名单接口测试和架构/术语检查通过；浏览器覆盖中英文 320/390/1440 宽度、返回/前进、草稿保留、“其他”校验、错误重试和本地 KV 实际提交。正式域名新问卷校验返回 `400 invalid_survey`，该检查没有创建生产测试名单。

- 已实现 `/`、`/zh/`、`/en/` 连续长页面：顶部居中 Logo 与品牌句，背景为财经报刊摄影；下方表单默认展示，首屏可见邮箱栏，没有前置 Request Access。`#apply` 为表单锚点。三项全部必填，渠道可多选；按浏览器首选语言自动选择中文/英文。
- 2026-09-13 已通过 Node 22 完整 `make site`（1,198 个页面）、SQLite `quick_check`、TypeScript、架构边界、产品术语和 7 组名单接口测试。
- 已通过浏览器与本地 Wrangler/KV 的表单提交，并读回持久化记录。测试使用 `example.com` 测试地址，没有发送邮件。
- 已创建 Cloudflare Pages 项目 `bsmart`，生产分支 `main`，默认地址 `https://bsmart-501.pages.dev`。生产 KV `bsmart-waitlist-production`（`2e618e7da8fa422f8f94947507059810`）已绑定为 `WAITLIST`，兼容日期 `2026-07-01`；预览环境未绑定生产名单库。
- 官网和 Functions 已发布：`https://bsmart-501.pages.dev`，最新一屏部署 `https://2c1f6b82.bsmart-501.pages.dev`。根页/中英文 HTTP 200，生产 `POST /api/waitlist` 返回 200 且已通过 API 读回 KV；只清理了本次 `example.com` 测试记录，未发送邮件。
- 域名已激活：bsmart.today / www.bsmart.today 均通过 HTTPS 检查，根页、中英文、新 Logo / favicon / Service Worker 均为最新版；正式域名 Email 提交及生产 KV 读回通过，测试记录已清理。Cloudflare zone `03ef1219bce38a6f26565270add83813` 使用 `amy.ns.cloudflare.com` / `lynn.ns.cloudflare.com`，根域名和 www 指向 `bsmart-501.pages.dev`，保留原 `_domainconnect` / `_dmarc`。

## 本地运行

2026-09-15 问卷版沿用现有 `WAITLIST` KV，不需要额外配置、SQL 迁移或第三方表单服务。平台字段支持 Telegram、微信、Twitter/X，填写账号或主页链接。邮箱、渠道、联系方式均必填，“其他”被选中时需要说明。旧页面仅邮箱提交也会被接口拒绝，需要刷新。已登记邮箱可补充首次问卷，但已有问卷不允许匿名覆盖。接口字段与边界见 `docs/contracts/beta_waitlist.md`。

背景素材：Annie Spratt 的 [财经报刊摄影](https://unsplash.com/photos/a-close-up-of-a-paper-with-numbers-on-it-tuJ3tXSayco)，本地文件 `web/public/brand/market-editorial-annie-spratt.jpg`，来自 Unsplash 免费图片，原始下载 URL 为 `https://images.unsplash.com/photo-1579532582937-16c108930bf6?auto=format&fit=crop&w=1800&q=85`。仅作品牌区背景，不代表实时行情或收益。用户明确不采用建筑摄影，本版无建筑素材。

使用 Node 22。终端一，在 `web/`：

```sh
nvm use 22
npx wrangler@4.131.1 pages dev public --kv WAITLIST --binding WAITLIST_LOCAL_DEV=true --port 8788 --ip 127.0.0.1 --compatibility-date 2026-07-01 --persist-to .wrangler/beta-local
```

终端二，在 `web/`：

```sh
nvm use 22
npm run dev -- --hostname 127.0.0.1 --port 3100
```

打开 `http://127.0.0.1:3100/`。Next dev 把 `/api/waitlist` 转发到本地 Wrangler。`.wrangler/beta-local` 是本地名单，不连接生产 KV；禁止把该目录提交或打包发布。更改 Next 端口时同步调整本地 Origin 白名单。

## 上线准备

1. Zone、Pages 绑定、Cloudflare DNS、GoDaddy Nameserver、正式域名 HTTPS 及 Email 提交均已完成验证；不要重复提交 Nameserver 或重复创建 DNS 记录。
2. 生产 KV 已创建并绑定，后续发布应保留 `WAITLIST` 绑定；不要重复创建。如需线上预览，应绑定独立的预览 namespace。
3. 生产不得设置 `WAITLIST_LOCAL_DEV=true`。本方案不需要公开 KV 凭据，也不需要 SQL 迁移。
4. 后续在 Node 22 下执行 `make cf-deploy`：完整构建，再运行 `web/scripts/stage-beta-site.mjs` 抽取三条官网路由及必要资源（约 8.7 MB / 92 个资源），并从 `web/` 使用 Wrangler 4.131.1 将 `web/functions` 一并打包。脚本同步生成官网专用 manifest、robots 和 sitemap；不上传研究页或 `/data`。仅拖放 HTML/PNG 不会部署名单接口。
5. 发布后验证根页、中英文切换、`POST /api/waitlist` 与生产 KV 写入；不要把开发测试名单迁入生产。

这是单页公开官网，既有研究页代码与数据仍留在项目中，完整 `make site` 仍生成已有研究页，但官网发布包不包含它们。研究路径在线上返回 404。

已有完整构建时，可避免重复构建：在根目录执行 `node web/scripts/stage-beta-site.mjs`，然后在 `web/` 执行 `npx wrangler@4.131.1 pages deploy /tmp/bsmart-beta-out-cf --project-name bsmart --branch main --commit-dirty=true`。

## 管理名单

通过 Cloudflare Dashboard 的对应 KV namespace 读取 `entry:` 前缀记录；`rate:` 为一小时自动过期的防滥用计数。邮箱未公开暴露在读取接口里。按删除申请查找对应邮件记录后删除即可；生产管理必须选择正确 namespace。邀请邮件不会自动发送。

## 验证命令

```sh
cd web
npm run test:waitlist
npx tsc --noEmit
npm run build -- --experimental-build-mode compile
```

在仓库根执行 `python3 scripts/check_architecture.py`、`make terminology-check`、`git diff --check`。

接口和存储口径见 `../contracts/beta_waitlist.md`。Cloudflare 实现依据：[Pages Functions bindings](https://developers.cloudflare.com/pages/functions/bindings/)、[local development](https://developers.cloudflare.com/pages/functions/local-development/)。

## 品牌更新

2026-09-13 用户确认原图为 `ios/Brand/bsmart-logo-20260913.png`。运行 `python3 scripts/sync_brand_assets.py` 重新生成透明字标、iOS AppIcon、favicon 与 PWA 图标；不重绘字母。App 内共用 `BSmartWordmark` 图片，页签用原字标里的箭头 r。重新构建/发布后网页更新，已安装 iOS App 必须安装新版才能更新品牌。

上一版构建为 1,193 路由；保留研究页生成曾出现 `gr_ticker` SQLite 锁警告。公开官网不读取该表，三条官网路由和全部引用资源已单独验证；研究页不在发布包中。

## 先前品牌版验证边界

官网 TypeScript/生产构建、三路由结构与资源检查、正式域名 HTTPS、新图标字节比对、7 组邮箱接口测试以及生产提交/KV 读回均通过。
iOS `make ios-build` 通过。`make ios-test` 中 964 个单元用例已运行（6 跳过、27 个失败断言，集中在账户 Keychain 存储）；无签名测试产物没有有效的 App Keychain entitlement，环境原因尚未通过对照运行最终确认。后续 UI 回归还出现首页导航/设置元素等断言失败，剩余大范围 UI 测试已中止，不能视为全量通过。日志：`/tmp/bsmart-brand-ios-build.log`、`/tmp/bsmart-brand-ios-test.log`。本次未扩展修改账号、交易或导航代码；已安装手机 App 仍需安装新版获取新 Logo。

极简申请版：删除标题、能力列表、内测提示、页脚及隐私勾选。按钮表示主动申请，记录 `requestVersion` / `requestMethod`；不伪造已同意隐私声明。旧版 `consent: true` 请求兼容，已有记录不会被改写。成功仅改变按钮状态；错误反馈保留。

极简版验证：Node 22 完整构建 1,198 路由，中文/非中文/首选语言优先级 14 用例通过；8 组邮箱接口测试通过。三条发布路由已检查只渲染 Logo、Email 输入和申请按钮，没有标题、页脚、内测状态或同意勾选框；全部引用资源存在。此次未改动 iOS，也未重复运行 iOS 回归。

品牌文案版：Logo 下唯一一行介绍为“The best way to follow the smartest investors” / “追踪最聪明投资者的最佳方式”，采用灰绿色常规字重；中英文随浏览器首选语言自动切换，其余提示和页脚保持移除。

品牌文案版已发布到 `https://2c1f6b82.bsmart-501.pages.dev`，正式域名根页/zh/en/www HTTPS 和最终文案已核对；标题/页脚/内测提示/隐私勾选保持移除。TypeScript 与完整构建通过，申请接口正常校验；本轮先前已通过无勾选框的生产申请及 KV 读回，测试记录已清理。

## 分享卡片

公开页的标准 description、Open Graph 和 Twitter Card 由 `web/features/landing/metadata.ts` 统一生成。标题为 `bSmart`，根页/zh 的描述为 `追踪最聪明投资者的最佳方式`，en 使用英文品牌句。保留 summary 卡片和原 Logo 图片。卡片显示的域名仍为 bsmart.today；浏览器语言只切换页面正文，X 抓取的是静态元数据。X 已发布卡片可能保留平台侧旧缓存，网站部署不能保证立即改写旧推文预览。

分享字段版已发布 `https://2c1f6b82.bsmart-501.pages.dev`。Node 22 构建/TypeScript 通过；根页/zh/en 的生成字段已检查无重复，并以 Twitterbot User-Agent 检查正式根域名/www/zh/en，title 均为 bSmart，description 为对应语言品牌句，summary 类型与 Logo 保留。此次只调整元数据，没有发推文或操作用户的 X 账号。
