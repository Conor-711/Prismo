# Architecture Overview

bSmart 是一个面向个人美股投资者的持仓智能事件助手。系统被拆成七个长期边界：

产品范围和优先级以 `docs/product/product-direction-mvp.md` 为准；本文只定义实现边界。

1. **iOS 产品系统**：`ios/`，是 MVP 主客户端，负责持仓事件、手动持仓、研究和 Smart 跟踪。
2. **Web 保留系统**：`web/`，负责公开页面、内部研究工具和迁移期回归，不再作为 MVP 主客户端扩张。
3. **数据管线系统**：`pipeline/`，负责抓取、标准化、AI 分析、聚合和导出。
4. **领域与客户端契约系统**：`docs/contracts/` + `contracts/openapi/`，定义跨平台对象与版本化 API。
5. **数据存储系统**：本地 `data/dev.db` 是当前 bSmart 内容真源；Supabase 承担账号能力和部分外部数据源读取。
6. **运行与部署系统**：`Makefile`、Xcode/TestFlight、`Dockerfile`、Cloudflare Pages 和数据快照。
7. **生产客户端 API 系统**：版本化 `/v1` Read Model、匿名安装会话、用户状态 mutation、设备注册和通知调度；
   它遵循 `contracts/openapi/bsmart-v1.yaml`，不得由 iOS Feature、Web 页面查询或管线 CLI 临时代替。

Client API 的用户状态与物化 Read Model 都通过 SQLAlchemy 持久化，但职责不同：用户状态由 `/v1` mutation 写入；
Read Model 只接受独立发布任务生成的已验证契约文档。API 服务不得在请求路径内调用抓取、AI 或 Score 计算。

## 当前真源

- bSmart 内容真源：`data/dev.db`。
- 静态站构建：`web/` 在 build/export 阶段通过 `node:sqlite` 读取 `data/dev.db`。
- 运行时：前端页面本身不依赖服务端数据库查询；账号、收藏、埋点等走 Supabase。
- X/Twitter 数据：部分 `tw_*` 表来自云端或外部管线，不能被本地 cloud-pull 覆盖策略替代。
- iOS 开发阶段通过 `contracts/fixtures` 消费与 `/v1` 相同的数据形态；生产阶段只访问 bSmart API，不直接读数据库。

## 迁移策略

本次架构整理采用增量迁移，不做一次性重写：

1. 先建立文档和目录边界。
2. 新需求必须进入新的目标边界。
3. 旧的大文件只在相关需求触达时逐步拆分。
4. 每次迁移必须保持页面输出和数据口径不变，除非需求明确要求改变。

## 判断一个改动属于哪里

- 新 UI、筛选、交互：`web/features/<domain>/`。
- iOS MVP 页面和交互：`ios/BSmart/Features/<domain>/`。
- iOS API、状态与持久化：`ios/BSmart/Core/Data/`。
- 通用 UI、布局、图表基础件：`web/shared/`。
- 新平台接入：`pipeline/platforms/<platform>/`。
- 跨平台业务分析：`pipeline/domain/<domain>/`。
- 完整任务编排：`pipeline/jobs/<job>/`。
- 新 CLI 命令：`pipeline/cli/commands/`。
- 新跨平台数据对象：先补 `docs/contracts/` 和必要的 `contracts/openapi/` schema。
- 新客户端读取、状态同步或设备接口：先补 `contracts/openapi/`，实现进入生产客户端 API 系统，客户端只通过
  `Core/Data` 消费。
