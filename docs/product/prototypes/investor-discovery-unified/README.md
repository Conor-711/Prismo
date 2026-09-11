# Unified Investor Discovery

2026-09-09。A 头像池、D 观点入口、C 共享作者领域筛选、B 统一详细档案的融合原型。独立文件为 `bsmart-discovery-unified.html`，可直接离线打开。旧四方案评审保留不变。

## 行为

- 看人/看观点共用研究领域与人物选择；该人物无观点快照时，观点模式展示同领域有观点的作者，不移除其头像入口。
- 档案复制进入时的候选 ID 顺序。上一位/下一位不越过该领域或搜索结果边界；返回恢复原首页选择与滚动位置。
- 在任意入口追踪，所有页面同步；下方观点按标的聚合，可切换全市场、追踪、示例持仓。
- 代表判断来自已有代表证据，保留结算窗口和真实标的涨跌，不能读作作者账户收益。
- 28 位 X 平台作者、25 张内嵌头像、88 条近期观点沿用旧原型的项目快照；Score/领域/风格不重算。赛道指作者研究领域，不给原始观点重新打行业标签。
- 搜索、追踪目录、完整观点、证据链接可用。持仓仅展示 NVDA/MU/MSTR 的评审假设；Mr Collie 明确未接入 AI，不生成回答。所有持久化隔离在原型 localStorage。

## 文件

`index.html`、`styles.css`、`app.js` 是源文件。`bundle.mjs` 只读既有原型数据及代表作 fixture，生成 `evidence.js` 与内嵌所有依赖的 `bsmart-discovery-unified.html`。无需网络或服务器：

```sh
node docs/product/prototypes/investor-discovery-unified/bundle.mjs
```

本目录仍为离线评审快照，不作为 App 运行时数据。其交互现已落地 SwiftUI 首页，原生通过 AppModel 消费真实作者/观点，见 `docs/product/investor-discovery-home.md`；不改变管线、Score、API 或生产数据。

## 验证记录

2026-09-09：Playwright 验证共享赛道、人物/观点切换、追踪同步、代表判断、候选范围前后边界、搜索空态、搜索结果连续浏览、嵌套观点返回、首页滚动恢复与追踪刷新持久化。320/360/390/414/1440px 检查无页面或关键容器横向溢出，25 张内嵌头像全部解码；独立文件加载没有外部资源请求。检查了桌面、手机人物池、观点模式和代表判断页面。JavaScript 语法、架构边界与差异格式检查通过。未构建原生 App。
