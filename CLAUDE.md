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
- **Prismo**：多语（zh 默认 / en / ja / ko）多社区美股 + 中概股舆情看板。三系统：① Python 管线 `pipeline/` ② **本地 `data/dev.db`**（Prismo 的唯一真源，含 gr_*/yt_*/kol_* 等独有层）③ Next.js 静态站 `web/`。
- **两个站、两套数据、互不干扰**（2026-06）：① **prismo.today** = 本仓库（`Conor-711/Prismo`），完整多社区，数据 = **本地 `data/dev.db`**（Railway/Dockerfile 用提交进去的 dev.db 构建，线上=本地）；② **redditalpha.xyz** = 旧仓库（`Conor-711/reddit_alpha`，只读保留），只含 Reddit，数据 = **Supabase 云端**（`wimipsiwtrqhizgmbxas` 的 Reddit 核心）。

## 硬性约定
- **构建必须用 Node 22**（`nvm use 22`）。Node 23 + 实验 SQLite 会让 `next build` 被系统 SIGKILL。构建报 `Cannot find module for page /_not-found` 时先 `rm -rf web/.next web/out`。
- **不要提交/泄露密钥**：`.env`、`web/.env.local` 已 gitignore（含 `QWEN_API_KEY`/`DEEPSEEK_API_KEY`/含密码的 `DATABASE_URL`/Supabase key）。不要把密码写进代码或文档。
- **双语字典**：`web/lib/dictionaries/zh.ts` 为源，`en.ts` 必须镜像完全相同的 key。
- **不要替用户输入密码 / 建账号 / 跑改库的 DDL**：这些让用户自己做；助手只准备代码与迁移脚本。
- 改完代码做验证：Python 侧无类型检查则跑相关命令；Web 侧 `npx tsc --noEmit`，必要时构建或用 curl 验证（用户不喜欢截图式自测）。

## 数据/构建工作流（⚠ 2026-06 改：Prismo = 本地真源，别 cloud-pull）
- **Prismo 的数据真源 = 本地 `data/dev.db`**（gr_*/yt_*/kol_* 只在本地、云端没有）。出网站 = **`make site`**（读本地 dev.db 构建 → `web/out/`）。
- **绝对别 `make site-cloud` / `make cloud-pull`**：会用「只有 Reddit 核心」的云端快照覆盖本地、**抹掉 Prismo 独有层**（『数据消失』的元凶）。已加保护：`site-cloud` 现等同 `make site`、`cloud-pull` 默认拒绝（需 `make backup-db && FORCE=1`）、`clean` 不再删 dev.db。
- 刷新本地数据：跑相应管线（`DATABASE_URL='sqlite:///./data/dev.db' make gr` / `make youtube` / `make kol-*` 等，都写本地）。**X 数据 `tw_*` 仍从云端只读拉**（`kol_sentiment.py`/`kol_volume.py` 的 `_cloud_url()` 直接读 .env 拿云端串，不受 sqlite 默认影响）。
- 改数据前先 `make backup-db`。云端 Supabase 留给 redditalpha.xyz（+ Prismo 只读 tw_*）。详见 `CLOUD_DB.md`。
