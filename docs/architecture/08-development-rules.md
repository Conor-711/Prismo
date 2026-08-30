# Development Rules

本文件是后续开发新功能时的入口规则，面向人类开发者和 AI 助手。开始实现前，先用这里的规则判断代码落点；如果规则和现有代码冲突，优先保持现有功能稳定，并同步更新架构文档。

## 产品术语

- 产品域统一称为 `Smart Account`，具体数值统一称为 `Score`。
- 新增页面路由、导航、metadata、文案和文档只能使用以上两个名称。
- `smart_voice`、`sv_*`、`smartVoice*` 仅是历史包名、表名、字段名和 adapter 名；没有迁移方案时保持兼容，但不得显示给用户。
- 提交前运行 `make terminology-check`，避免旧称回流。

## 先判断需求类型

接到新需求后，先把它拆成以下几类：

- iOS MVP 页面或交互：属于 `ios/BSmart/Features` + `ios/BSmart/Core`。
- Web 公开页或内部研究交互：属于 `web/app` + `web/features` + `web/shared`。
- 构建期取数或 view model：属于 `web/server`，必要时由 `web/features/<domain>/queries` 做页面级组装。
- 新平台数据接入：属于 `pipeline/platforms/<platform>`。
- 跨平台业务逻辑：属于 `pipeline/domain/<domain>`。
- 完整可运行任务：属于 `pipeline/jobs/<job>`。
- 命令行入口：属于 `pipeline/cli/commands`，只注册参数并调用 job。
- 新跨平台对象或字段契约：先更新 `docs/contracts`。
- 新客户端接口：先更新 `contracts/openapi/bsmart-v1.yaml` 和 fixture，再更新 Swift 模型。
- 新表、数据流、部署或命令：同步更新 `ARCHITECTURE.md` 和对应专题文档。

## iOS 扩展规则

iOS 是第一版 MVP 主客户端：

- App 生命周期和根导航放到 `ios/BSmart/App`。
- 业务页面放到 `ios/BSmart/Features/<domain>`。
- API model 放到 `ios/BSmart/Core/Models`。
- HTTP、fixture、状态和设备持久化放到 `ios/BSmart/Core/Data`。
- 原生通用控件和 token 放到 `ios/BSmart/Core/DesignSystem`。
- 先改 `contracts/openapi/bsmart-v1.yaml`，再让客户端消费稳定字段。
- 不使用 WebView 迁移网页，不直接读取 `data/dev.db`，不在 Swift 里重算 Score。
- 平台 API、prompt、打标、结算和链上地址评分只能留在后端/管线。

需要修改 Xcode target、scheme 或 build setting 时，修改 `ios/project.yml` 后运行 `make ios-generate`，不要只手工编辑生成的 Xcode project。

## Web 扩展规则

Web 处于保留和简化阶段。只有公开页面、内部研究工具、迁移回归或明确的 Web 用户需求才新增 Web 功能；面向 iOS MVP 的功能不得先做一套 Web-only 实现。

`web/app` 是路由层，只做页面组装：

- 解析 route params。
- 调用 server/query 层获取数据。
- 组装 feature shell。
- 提供 metadata 和 `generateStaticParams`。

业务 UI 和交互放到 `web/features/<domain>`：

- 标的详情、观点流、目标价、整体数据：`web/features/ticker`。
- 叙事轮动：`web/features/narrative`。
- 投资者榜单、作者详情：`web/features/investor`。
- 搜索页：`web/features/search`。
- 追踪页：`web/features/tracking`。
- Smart Account 展示：`web/features/smart-account`。

跨业务复用能力放到 `web/shared`：

- 通用 UI 控件：`web/shared/ui`。
- 布局和工作区：`web/shared/layout`。
- 通用图表：`web/shared/charts`。
- 市场展示基础件、logo、KOL 展示格式：`web/shared/market`。
- 格式化、i18n、图标等基础工具：`web/shared/formatting`、`web/shared/i18n`、`web/shared/icons`。

构建期查询放到 `web/server`：

- 数据库连接和低级 helper：`web/server/db`。
- SQL 查询和跨页面复用取数：`web/server/queries`。
- feature 组件不能运行时导入 server query；需要类型时只能 `import type`。

不要新增复杂实现到：

- `web/components/bsmart`：只保留旧 import 的兼容导出。
- `web/lib/*Queries.ts`：只保留旧查询兼容导出或薄封装。
- 单个大页面文件：页面不能承载复杂筛选、排序、图表配置或状态机。

## Pipeline 扩展规则

平台接入放到 `pipeline/platforms/<platform>`：

- 抓取、分页、鉴权、限速、重试。
- raw payload 保存。
- 平台字段到标准字段的基础映射。
- 平台作者资产和元信息刷新。

平台层不能写：

- Smart Account 排名。
- 个性化推荐。
- 观点质量、相关性、目标价、叙事分类。
- 跨平台聚合规则。

跨平台业务逻辑放到 `pipeline/domain/<domain>`：

- `opinions`：观点清洗、AI 提炼、翻译、质量、相关性、视角、摘要。
- `target_prices`：目标价、买入/卖出价、操作周期。
- `smart_voice`：Score 候选、结构化 call、结算、评分、导出、整体信号。
- `narratives`：固定叙事 taxonomy、内容归类、mindshare。
- `global_retail`：全球散户打标、region/ticker 聚合。
- `tickers`：ticker 种子、目录、基础提及抽取。
- `market`：市场 rollup、mood、trending、brief。
- `translations`：跨内容翻译工作流。
- `authors`：作者画像和作者级综合观点。

完整任务编排放到 `pipeline/jobs/<job>`：

- 读取参数。
- 调用 platform/domain 模块。
- 控制窗口、批次、断点续跑、输出报告。
- 不直接写平台解析、SQL 细节或 prompt 核心逻辑。

CLI 放到 `pipeline/cli/commands`：

- 只定义 argparse 参数。
- 只调用对应 `pipeline.jobs.<job>`。
- 不直接调用 `pipeline.domain`、`pipeline.platforms`、`pipeline.ingest` 或 `pipeline.analyze`。

不要新增真实实现到：

- `pipeline/ingest`：只保留历史命令/导入兼容 wrapper。
- `pipeline/analyze`：只保留历史导入兼容 wrapper。
- `pipeline/manage.py`：只保留兼容入口，实际命令注册在 `pipeline/cli`。

## 数据契约规则

新增或修改跨平台对象前，先检查 `docs/contracts`：

- 观点内容：`docs/contracts/opinion.md`。
- 作者和投资者：`docs/contracts/author.md`。
- 标的：`docs/contracts/ticker.md`。
- 目标价和操作周期：`docs/contracts/judgment.md`。
- Smart Account：`docs/contracts/smart_account.md`。
- 叙事：`docs/contracts/narrative.md`。

如果新功能需要新增稳定字段，先更新 contract，再实现 pipeline 和前端消费。平台私有 payload 不应直接进入前端功能。

## 常见需求落点

新增平台：

1. 在 `pipeline/platforms/<platform>` 建 adapter。
2. 如要进入观点流，映射到 Opinion contract。
3. 平台无关分析放到 `pipeline/domain/opinions`、`target_prices` 或 `smart_voice`。
4. 任务编排放到 `pipeline/jobs/<job>`。
5. CLI 只新增命令入口。
6. 更新 `ARCHITECTURE.md`、`docs/architecture/04-platform-adapters.md` 和相关 contract。

新增标的详情页功能：

1. UI 放到 `web/features/ticker`。
2. 共用 UI 放到 `web/shared`。
3. 取数放到 `web/server/queries` 或 `web/features/ticker/queries`。
4. 如涉及新 AI 标签，pipeline 实现放到 `pipeline/domain`，任务放到 `pipeline/jobs`。
5. 不扩大 `web/app/[lang]/(app)/tickers/[symbol]/page.tsx` 的复杂度。

新增 Smart Account 功能：

1. 先更新 `docs/contracts/smart_account.md` 或 `docs/architecture/05-smart-account.md`。
2. 算法和口径放到 `pipeline/domain/smart_voice`。
3. 任务编排放到 `pipeline/jobs/smart_voice`。
4. 前端展示放到 `web/features/smart-account` 或消费方 feature。
5. 构建期查询放到 `web/server/queries`。

新增叙事功能：

1. 固定 taxonomy、归类、mindshare 放到 `pipeline/domain/narratives`。
2. 导出任务放到 `pipeline/jobs/narrative_rotation`。
3. 前端展示放到 `web/features/narrative`。
4. 先确认 `docs/contracts/narrative.md`。

新增筛选、排序、推荐：

1. 纯前端状态和排序逻辑放到对应 feature 的 `hooks` 或 `logic` 文件。
2. 需要跨平台数据或 AI 标签时，先进入 `pipeline/domain` 生成稳定字段。
3. 服务端 view model 放到 `web/server/queries`。
4. 不在组件里写 SQL，不在平台 adapter 里写推荐算法。

## 文件大小和拆分

新增逻辑触达以下阈值时，必须拆分：

- React component：400 行。
- Query/view model 文件：500 行。
- CLI 注册文件：300 行。
- Python job/domain 文件：500 行。

一个文件同时包含 UI、状态、排序算法、数据转换、平台适配或 prompt 时，即使没超过行数，也应拆分。

## 提交前检查

结构性改动至少运行：

```bash
python3 scripts/check_architecture.py
git diff --check
```

前端改动运行：

```bash
cd web && npx tsc --noEmit
```

iOS 改动运行：

```bash
make ios-build
make ios-test
```

Python 管线改动运行：

```bash
python3 -m compileall -q pipeline/common pipeline/domain pipeline/platforms pipeline/ingest pipeline/analyze pipeline/jobs pipeline/cli pipeline/daily.py
pipeline/.venv/bin/python -m pytest pipeline/tests/test_ticker_extract.py pipeline/tests/test_architecture_boundaries.py
```

写库任务先用 `--only`、小窗口或 mock/smoke 命令验证，不要直接跑全量破坏本地数据。

## AI 助手执行规则

AI 在新对话中开始复杂开发前，应先阅读：

1. `ARCHITECTURE.md`
2. 本文件
3. 相关专题文档，例如 `01-frontend.md`、`02-pipeline.md`、`04-platform-adapters.md`
4. 相关 contract

如果需求属于 iOS MVP，还必须阅读 `09-ios.md` 和 `contracts/openapi/bsmart-v1.yaml`。

实现时必须说明新代码落到哪个边界。如果发现旧文件更方便，也不能直接把新实现写进去；应新增目标边界文件，并让旧文件只做兼容导出。
