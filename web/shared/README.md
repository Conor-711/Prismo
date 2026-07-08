# Web Shared

`web/shared` 放跨业务复用的前端基础设施。

推荐结构：

```text
shared/
  ui/          # Button, Select, Dropdown, Tooltip, Modal, Skeleton
  layout/      # Sidebar, app shell, viewport workspace
  charts/      # ECharts wrappers and shared chart options
  icons/       # icon mapping and platform icons
  formatting/  # number/date/text formatting
  i18n/        # locale helpers
  market/      # 跨页面市场内容展示基础件，如平台/立场配色、作者头像、原文/译文选择
```

不应放入具体业务逻辑，例如“标的观点排序”“叙事归类”“SV 过滤”。这些应放到对应 `web/features/<domain>`。

当前已迁移：

- `formatting/format.ts`：跨页面数字、时间、情绪颜色、stance 标签等格式化工具。
- `market/kolPresentation.tsx`：跨页面 KOL/观点展示基础件，提供来源/立场展示元数据、头像、原文/译文选择和旧观点卡兼容能力。
- `market/TickerLogo.tsx`：跨页面标的 logo 展示，包含 CDN 失败回退。
- `market/tickerMeta.ts`：标的交易所、TradingView symbol 和 logo CDN 元信息。
- `market/regions.ts`：五区顺序、展示名、来源平台和强调色。
- `market/mockDetail.ts`：兼容聚合导出；`market/mockDetail/marketMock.ts` 保存标的/地区 fallback，`kolTypes.ts` 保存 KOL 观点类型，`kolFlowMock.ts` 保存 KOL mock 流。
- `charts/PriceSparkline.tsx`：跨页面迷你价格走势折线图。
- `layout/ViewportWorkspace.tsx`：固定视窗工作区布局，负责禁止页面整体滚动并按视窗高度约束内容区。
- `ui/prismoBits.tsx`：跨页面 KPI、情绪分、共识、区域、多空条、价格标签等纯展示件。
- `ui/detailBits.tsx`：详情页模块外壳、统计条、徽标、变化量等纯展示件。
