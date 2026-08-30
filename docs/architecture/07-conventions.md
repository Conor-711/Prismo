# Engineering Conventions

本文件定义新增代码和重构时的默认规则。

## 新功能落点

- 新页面：`web/features/<domain>/` + `web/app` 路由组装。
- 新复用 UI：`web/shared/ui/`。
- 新布局能力：`web/shared/layout/`。
- 新图表基础件：`web/shared/charts/`。
- 新平台：`pipeline/platforms/<platform>/`。
- 新跨平台分析：`pipeline/domain/<domain>/`。
- 新完整任务：`pipeline/jobs/<job>/`。
- 新命令：`pipeline/cli/commands/`。
- 新跨平台对象：`docs/contracts/`。

## 边界约束

- `pipeline/cli/commands/<domain>.py` 只能调用对应的 `pipeline.jobs.<domain>`。
  例如 `commands/youtube.py` 只能调用 `pipeline.jobs.youtube`，`commands/smart_voice.py`
  只能调用 `pipeline.jobs.smart_voice`。
- `pipeline/domain` 不能导入 `pipeline.analyze`、`pipeline.ingest`、`pipeline.jobs`、
  `pipeline.platforms` 或 `pipeline.cli`。领域实现必须保持平台、任务编排和命令行无关。
- `web/features` 可以 `import type` 引用 `@/server/queries/*` 的类型，但不能运行时导入
  server query 函数；页面取数留在 `web/app` 或明确的 query adapter。
- `web/shared` 不依赖 `web/app`、`web/features`、`web/server`。
- `web/server` 不依赖 UI 层。

这些边界由 `python3 scripts/check_architecture.py` 检查。

## 文件大小约束

超过以下阈值时，新增逻辑必须优先拆分：

- React component：400 行。
- Query/view model 文件：500 行。
- CLI 注册文件：300 行。
- Python job/domain 文件：500 行。

旧文件可以逐步迁移；新代码不应继续扩大已超阈值文件。

## 命名

- 平台 source 使用稳定小写 key：`x`、`youtube`、`reddit`、`xueqiu`、`toss`、`yahoojp`。
- 前端业务类型以产品概念命名，不以数据库表命名。
- Python domain 函数以业务动作命名，例如 `score_candidates`、`normalize_opinion`。
- 构建期 JSON 使用 camelCase 字段，数据库列使用 snake_case。

## 验证

文档和目录调整：

- `git diff --check`
- `python3 scripts/check_architecture.py`

前端逻辑调整：

- `cd web && npx tsc --noEmit`
- 必要时 `npm run build`

管线逻辑调整：

- 单命令 smoke test。
- 对写库任务先用 `--only` 或小窗口验证。

## 文档同步

必须同步更新文档的情况：

- 新增或删除目录边界。
- 新增平台、表、命令、构建步骤。
- 改数据真源或部署路径。
- 改 Smart Account 口径。
- 改跨平台 contract。
