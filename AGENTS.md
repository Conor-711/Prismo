# AGENTS.md — 给 AI 助手的项目须知

本文件每次会话自动加载。动手前先读 **`ARCHITECTURE.md`**（项目结构/数据流/命令的活地图）。开发新功能前还必须读 `docs/architecture/08-development-rules.md`，按其中的落点规则扩展。

## 最重要的规则：保持 ARCHITECTURE.md 最新
**每次对项目做了实质改动后，必须同步更新 `ARCHITECTURE.md` 对应章节**，并把顶部的「最近更新」日期改为当天。需要更新的改动包括但不限于：
- 新增/删除/重命名模块、目录、关键文件；
- 改数据流、数据库 schema（`pipeline/common/models.py`）、大模型档位（`pipeline/common/llm.py`）；
- 改 Makefile 命令、构建/部署方式、环境变量；
- 改云端架构（Supabase）或网站路由结构。

小改动（改文案、修 bug、调样式）不必更新；**结构性/流程性改动必须更新**。更新要简洁，跟随既有格式。

## 项目速记
- **bSmart**：多语（zh 默认 / en 为主）多社区美股舆情与 Smart Voice 看板。核心系统：① Python 管线 `pipeline/` ② 本地内容真源 `data/dev.db` ③ Next.js 静态站 `web/` ④ Supabase web 后端/Auth/收藏/埋点和部分外部 `tw_*` 读取。
- 线上：bSmart 静态站由本地完整 sqlite 快照构建后部署；旧 `redditalpha.xyz` 属 Reddit-only 历史站，不能代表 bSmart 当前内容架构。
- 架构专题文档：`docs/architecture/`；跨平台数据契约：`docs/contracts/`。新增复杂功能前先确认 `docs/architecture/08-development-rules.md` 和对应 contract。

## 硬性约定
- **构建必须用 Node 22**（`nvm use 22`）。Node 23 + 实验 SQLite 会让 `next build` 被系统 SIGKILL。构建报 `Cannot find module for page /_not-found` 时先 `rm -rf web/.next web/out`。
- **不要提交/泄露密钥**：`.env`、`web/.env.local` 已 gitignore（含 `QWEN_API_KEY`/`DEEPSEEK_API_KEY`/含密码的 `DATABASE_URL`/Supabase key）。不要把密码写进代码或文档。
- **双语字典**：`web/lib/dictionaries/zh.ts` 为源，`en.ts` 必须镜像完全相同的 key。
- **禁止解释性小字**：后续界面开发不得在标题下新增用于解释功能或提示操作方式的 subtitle、caption、helper copy。优先通过结构、图标、状态和数据本身表达含义；仅合规、风险、数据口径、错误状态必须说明时例外。
- **不要替用户输入密码 / 建账号 / 跑改库的 DDL**：这些让用户自己做；助手只准备代码与迁移脚本。
- 改完代码做验证：Python 侧无类型检查则跑相关命令；Web 侧 `npx tsc --noEmit`，必要时构建或用 curl 验证（用户不喜欢截图式自测）。

## 数据/构建工作流
- bSmart 内容默认写本地：`DATABASE_URL='sqlite:///./data/dev.db'`。
- 出网站：`make site` 读取本地 `data/dev.db` 并生成 `web/out/`。
- 推荐部署：Cloudflare Pages Direct Upload 上传本地 `web/out/`。
- 不要用旧云端快照覆盖本地 `data/dev.db`；这会抹掉 `gr_*`、`yt_*`、`kol_*` 等 bSmart 独有层。
- 详见 `ARCHITECTURE.md`、`docs/architecture/06-deployment.md`、`CLOUD_DB.md`。
