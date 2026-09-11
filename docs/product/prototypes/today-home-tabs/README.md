# 首页三场景原型

日期：2026-09-07。阶段：布局评审，尚未修改 iOS。

直接用浏览器打开 `index.html`，无需构建或服务。`styles.css` 是原型样式，`app.js` 管理三种布局和交互，`data.js` 是只读快照摘录。头像需要网络；标的 Logo 复用仓库 Asset Catalog，因此请保留本目录在仓库中的相对位置。Lucide 使用固定版本 CDN。

## 信息架构

| 子页 | 内容 | 阅读单位 |
| --- | --- | --- |
| 持仓与追踪 | 持仓相关、追踪账户动态 | 我的标的、我追踪的人 |
| 市场情况 | 热门标的、阿尔法标的 | 标的及其代表观点 |
| 聪明动态 | Smart Account / Smart Money 最新动态 | 投资者，附最近多条更新 |

推荐 A 顶部文字标签；B 原生分段控件作为备选；C 底部场景选择器用于对照单手操作与双层导航的取舍。三者使用完全相同的内容，不修改底部主导航。

默认进入持仓与追踪。三个子页可点击或横滑，各自保留滚动位置；详情进入独立内页，返回不丢位置。同一证据的已读状态跨模块同步。无持仓、无追踪、无近月动态均有独立空态。

市场页保留热门卡片上下两张，但建议取消内层横滑，更多内容进入完整列表，避免与外层切页手势竞争。此处是待评审建议，现有 App 轮播未变更。

## 数据边界

- Smart Account 摘自 `contracts/fixtures/smart-account-updates.json`，32 条本地近月记录，包含既有摘要、头像、Top 比例、真实来源时间及 URL。
- Smart Money 是本地 `smart-money-movements.json` 中 Ivan / NVDA 和 Iris / MSTR 两条 2026-08-14 资金记录。头像映射沿用现有 iOS 组件，方向沿用 fixture 字段，不在原型重新推断。
- 持仓、追踪集合以及热门/Alpha 分组是设计样例，不代表用户实际账户，也不代表重新计算的市场排名或 Alpha 策略结果。
- 仅展示摘要，不将分析摘要冒充完整原帖。证据页可打开原始来源。
- 所有交互状态仅存内存，不向真实账户写入、不启动抓取或交易。

## 调研依据

来自官方文档，未声称已实测这些产品的原生横滑：

- [Stocktwits Home Feed](https://help.stocktwits.com/c/navigating/articles/home-feed)：顶部区分 Following、Watchlist、Trending、Suggested。
- [Yahoo Finance iOS](https://uk.help.yahoo.com/kb/SLN24700.html)：组合和市场浏览有清楚的任务边界。
- [TradingView Watchlist Filter](https://www.tradingview.com/support/solutions/43000734013-filter-by-watchlist/)：按用户自选标的过滤信息。
- [Apple Segmented Controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)：相关子视图和独立一级功能使用不同导航层级。

## 后续原生落点

方案确认后，在 `Features/Today` 拆分三个容器，继续复用当前 holdings、tracked、market、investor activity 的业务模型和卡片。子页状态、导航路径与滚动位置各自保存，共享同一个追踪与阅读状态源；不新增后端算法、不改现有 Smart 评分，也不以 HTML / WebView 替代 SwiftUI。

## 原型验证

- JavaScript 语法检查通过。
- 浏览器验证 A/B/C 切页保留滚动位置、进入详情及返回；热门卡片均为 218px（包含边框）。
- 320 / 375 / 390 / 430px 宽度下三个子页均无横向溢出；黑夜和白天模式均检查。
- 验证横向拖动不误触详情、Smart Money 筛选、空态推荐 3 人、点击追踪后即时出现动态、近月无动态时不填充旧记录。
- Chromium 触屏模拟验证横滑进入市场情况、纵滑滚动持仓页且不切换场景；原生真机手势优先级仍需后续验证。
- X 头像依赖远程快照 URL，失效时显示作者首字母；不以其他作者头像替代。当前样本中有一个上游头像 URL 返回 404。
- 此处仅为浏览器原型验证，尚未进行 SwiftUI / 真机交互验收。
