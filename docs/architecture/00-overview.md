# Architecture Overview

Prismo 是一个多平台美股舆情与 Smart Voice 看板。系统被拆成五个长期边界：

1. **前端产品系统**：`web/`，负责页面、布局、筛选、阅读器、图表、账号和收藏。
2. **数据管线系统**：`pipeline/`，负责抓取、标准化、AI 分析、聚合和构建期 JSON 导出。
3. **领域契约系统**：`docs/contracts/`，定义跨平台复用的数据对象，例如 Opinion、Author、Judgment、Smart Voice。
4. **数据存储系统**：本地 `data/dev.db` 是 Prismo 内容真源；Supabase 主要承担 web 后端能力和部分外部数据源读取。
5. **运行与部署系统**：`Makefile`、`Dockerfile`、`railway.json`、`data/dev.db.xz.part-*`、Cloudflare Pages 静态部署。

## 当前真源

- Prismo 内容真源：`data/dev.db`。
- 静态站构建：`web/` 在 build/export 阶段通过 `node:sqlite` 读取 `data/dev.db`。
- 运行时：前端页面本身不依赖服务端数据库查询；账号、收藏、埋点等走 Supabase。
- X/Twitter 数据：部分 `tw_*` 表来自云端或外部管线，不能被本地 cloud-pull 覆盖策略替代。

## 迁移策略

本次架构整理采用增量迁移，不做一次性重写：

1. 先建立文档和目录边界。
2. 新需求必须进入新的目标边界。
3. 旧的大文件只在相关需求触达时逐步拆分。
4. 每次迁移必须保持页面输出和数据口径不变，除非需求明确要求改变。

## 判断一个改动属于哪里

- 新 UI、筛选、交互：`web/features/<domain>/`。
- 通用 UI、布局、图表基础件：`web/shared/`。
- 新平台接入：`pipeline/platforms/<platform>/`。
- 跨平台业务分析：`pipeline/domain/<domain>/`。
- 完整任务编排：`pipeline/jobs/<job>/`。
- 新 CLI 命令：`pipeline/cli/commands/`。
- 新跨平台数据对象：先补 `docs/contracts/`。
