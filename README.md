<div align="center">
  <img src="web/public/logo.png" alt="Prismo" width="96" />
  <h1>Prismo</h1>
  <p>多社区美股舆情与 Smart Voice 看板</p>
</div>

Prismo 聚合 Reddit、X、YouTube、雪球、Toss、Yahoo Finance Japan、Naver、PTT 等平台的美股讨论，围绕标的、作者、叙事和 Smart Voice 做跨社区情绪、讨论度、目标价、观点流和投资者声音分析。

当前项目已经从早期 Reddit-only 原型演进为多平台静态 SaaS 看板。**本地 `data/dev.db` 是 Prismo 内容真源**；Next.js 在构建期读取该 sqlite 快照并导出静态站点。

## 架构入口

先读：
roster_tweets_20260626_20260711
- `ARCHITECTURE.md`：项目活地图，记录当前系统事实、数据真源、主要目录和关键命令。
- `docs/architecture/`：专题架构文档，包含前端、管线、数据模型、平台适配器、Smart Voice、部署和工程约定。
- `docs/contracts/`：跨平台产品契约，包含 Opinion、Author、Ticker、Judgment、Smart Voice、Narrative。
- `DESIGN_LANGUAGE.md`：视觉系统和 UI token。
- `CLOUD_DB.md` / `DEPLOY.md`：云端、快照和部署说明。

## 当前系统

```text
pipeline/                  Python 数据管线：抓取、标准化、AI 分析、聚合、导出
  ingest/                  迁移期抓取模块
  analyze/                 迁移期分析模块
  platforms/               目标边界：平台适配器
  domain/                  目标边界：跨平台业务逻辑
  jobs/                    目标边界：完整任务编排
  cli/                     目标边界：CLI 注册与参数解析

web/                       Next.js 14 静态站
  app/                     路由层
  features/                目标边界：按业务域组织页面能力
  shared/                  目标边界：跨业务 UI/layout/charts
  server/                  目标边界：构建期 DB/query
  components/              迁移期旧组件
  lib/                     迁移期旧查询和工具

docs/architecture/         架构专题文档
docs/contracts/            跨平台数据契约
data/dev.db                Prismo 内容真源
```

## 快速运行

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

- Prismo 内容默认写入本地 `data/dev.db`。
- 静态站构建读取本地 `data/dev.db`，输出 `web/out/`。
- 不要用只含旧 Reddit 核心表的云端快照覆盖本地 Prismo 真源。
- 部署推荐 Cloudflare Pages Direct Upload，上传本地构建好的 `web/out/`。
- Railway/Docker 路径必须确保完整 sqlite 快照能在构建期还原。

## 开发约定

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
