# CLAUDE.md — 给 AI 助手的项目须知

本文件每次会话自动加载。动手前先读 **`ARCHITECTURE.md`**（项目结构/数据流/命令的活地图）。

## 最重要的规则：保持 ARCHITECTURE.md 最新
**每次对项目做了实质改动后，必须同步更新 `ARCHITECTURE.md` 对应章节**，并把顶部的「最近更新」日期改为当天。需要更新的改动包括但不限于：
- 新增/删除/重命名模块、目录、关键文件；
- 改数据流、数据库 schema（`pipeline/common/models.py`）、大模型档位（`pipeline/common/llm.py`）；
- 改 Makefile 命令、构建/部署方式、环境变量；
- 改云端架构（Supabase）或网站路由结构。

小改动（改文案、修 bug、调样式）不必更新；**结构性/流程性改动必须更新**。更新要简洁，跟随既有格式。

## 项目速记
- **redditalpha**：双语（zh 默认 / en）Reddit 美股 + 中概股舆情看板。三系统：① Python 管线 `pipeline/` ② Supabase 云端 Postgres（数据的家）③ Next.js 静态站 `web/`。
- 线上：https://www.redditalpha.xyz（纯静态，根域名）。

## 硬性约定
- **构建必须用 Node 22**（`nvm use 22`）。Node 23 + 实验 SQLite 会让 `next build` 被系统 SIGKILL。构建报 `Cannot find module for page /_not-found` 时先 `rm -rf web/.next web/out`。
- **不要提交/泄露密钥**：`.env`、`web/.env.local` 已 gitignore（含 `QWEN_API_KEY`/`DEEPSEEK_API_KEY`/含密码的 `DATABASE_URL`/Supabase key）。不要把密码写进代码或文档。
- **双语字典**：`web/lib/dictionaries/zh.ts` 为源，`en.ts` 必须镜像完全相同的 key。
- **不要替用户输入密码 / 建账号 / 跑改库的 DDL**：这些让用户自己做；助手只准备代码与迁移脚本。
- 改完代码做验证：Python 侧无类型检查则跑相关命令；Web 侧 `npx tsc --noEmit`，必要时构建或用 curl 验证（用户不喜欢截图式自测）。

## 数据/构建工作流
- 管线写云端：`.env` 的 `DATABASE_URL` 指向 Supabase → `make daily` 等直接写云端。
- 出网站：`make site-cloud`（= 从云端拉快照到 `data/dev.db` + 构建），再部署 `web/out/`。
- 详见 `CLOUD_DB.md`。
