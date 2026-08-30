<div align="center">
  <img src="web/public/logo.png" alt="bSmart" width="96" />
  <h1>bSmart</h1>
  <p>面向个人美股投资者的持仓智能事件助手</p>
</div>

bSmart 聚合 Reddit、X、YouTube、雪球、Toss、Yahoo Finance Japan、Naver、PTT 等平台的美股讨论，并结合 Hyperliquid 代币化美股公开资金行为，为用户提供与实际持仓相关的事件、研究证据、Smart Account 和 Smart Money 信号。

**iOS SwiftUI App 是第一版 MVP 的主客户端**。现有 Next.js 看板保留为公开榜单、内部研究和迁移期回归基线，不再承担移动端产品逻辑。后端、数据库、算法和版本化 API 契约由 iOS 与 Web 共用。**本地 `data/dev.db` 仍是当前 bSmart 内容真源**。

## 架构入口

先读：
roster_tweets_20260626_20260711
- `ARCHITECTURE.md`：项目活地图，记录当前系统事实、数据真源、主要目录和关键命令。
- `docs/product/product-direction-mvp.md`：第一阶段产品决策真源；产品、iOS 和用户功能开发前必读。
- `docs/product/`：iOS-first 迁移、市场需求和竞品研究。
- `docs/architecture/`：专题架构文档，包含前端、管线、数据模型、平台适配器、Smart Account、部署和工程约定。
- `docs/architecture/09-ios.md`：iOS 主客户端边界、SwiftUI 目录和发布规则。
- `docs/contracts/`：跨平台产品契约，包含 Opinion、Author、Ticker、Judgment、Smart Account、Narrative。
- `contracts/openapi/bsmart-v1.yaml`：iOS/Web 共用的版本化客户端 API 契约。
- `DESIGN_LANGUAGE.md`：视觉系统和 UI token。
- `CLOUD_DB.md` / `DEPLOY.md`：云端、快照和部署说明。

## 当前系统

```text
ios/                       iOS 17+ 原生 SwiftUI MVP 主客户端
  bSmart/App/              App 生命周期与根导航
  bSmart/Core/             API 模型、数据客户端、设计系统
  bSmart/Features/         Today / Portfolio / Tickers / Smart / AI 场景

contracts/                 客户端 API、开发 fixture 与跨端机器可读契约
design/tokens/             Web/iOS 共用视觉 token 真源

services/client_api/       iOS 使用的版本化 /v1 API、匿名会话与用户状态同步

pipeline/                  Python 数据管线：抓取、标准化、AI 分析、聚合、导出
  ingest/                  迁移期抓取模块
  analyze/                 迁移期分析模块
  platforms/               目标边界：平台适配器
  domain/                  目标边界：跨平台业务逻辑
  jobs/                    目标边界：完整任务编排
  cli/                     目标边界：CLI 注册与参数解析

web/                       Next.js 14 保留站点（公开页/内部研究/迁移回归）
  app/                     路由层
  features/                目标边界：按业务域组织页面能力
  shared/                  目标边界：跨业务 UI/layout/charts
  server/                  目标边界：构建期 DB/query
  components/              迁移期旧组件
  lib/                     迁移期旧查询和工具

docs/architecture/         架构专题文档
docs/contracts/            跨平台数据契约
data/dev.db                bSmart 内容真源
```

## 快速运行

生成并打开 iOS 工程：

```bash
make ios-generate
open ios/bSmart.xcodeproj
```

验证 iOS：

```bash
make ios-build
make ios-test
```

启动并验证本地 Client API：

```bash
make client-api-install
make client-api-test
make client-api-seed-mock
make client-api-dev
```

Web 与数据管线的维护命令仍然可用：

安装依赖：

```bash
make install
make web-install
```

启动前端开发服务器：

```bash
make web-dev
```

构建静态站点：

```bash
make site
```

常用数据任务见：

```bash
make help
```

## 数据与部署原则

- bSmart 内容默认写入本地 `data/dev.db`。
- 静态站构建读取本地 `data/dev.db`，输出 `web/out/`。
- 不要用只含旧 Reddit 核心表的云端快照覆盖本地 bSmart 真源。
- 部署推荐 Cloudflare Pages Direct Upload，上传本地构建好的 `web/out/`。
- Railway/Docker 路径必须确保完整 sqlite 快照能在构建期还原。

## 开发约定

- 新的用户端 MVP 功能优先放入 `ios/BSmart/Features/<domain>`。
- iOS 只消费 `contracts/openapi/bsmart-v1.yaml` 对应的 API，不读取 SQLite，不在客户端重算 Score。
- 跨端稳定字段先更新机器契约与 `docs/contracts`，再修改 iOS/Web 消费端。
- 新 UI/页面能力优先放入 `web/features/<domain>`。
- 通用 UI、布局和图表基础件放入 `web/shared`。
- 新平台接入放入 `pipeline/platforms/<platform>`。
- 跨平台分析逻辑放入 `pipeline/domain/<domain>`。
- 完整任务编排放入 `pipeline/jobs/<job>`。
- 新跨平台对象先补 `docs/contracts`。
- 结构性改动必须同步更新 `ARCHITECTURE.md` 和对应 `docs/architecture` 专题文档。

## 验证

文档/目录调整：

```bash
git diff --check
python3 scripts/check_architecture.py
```

前端逻辑调整：

```bash
cd web && npx tsc --noEmit
```

管线逻辑调整应使用小范围 smoke test，例如 `--only MU` 或较短时间窗口。
