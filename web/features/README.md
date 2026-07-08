# Web Features

`web/features` 是前端业务模块的目标落点。新增页面能力应优先放在这里，而不是继续堆进 `web/components/prismo` 或 `web/lib/*Queries.ts`。

推荐结构：

```text
features/<domain>/
  components/
  hooks/
  queries/
  types.ts
  constants.ts
  index.ts
```

当前迁移优先级：

1. `ticker`：标的详情页、观点流、个性化推荐、SV 筛选、整体数据。
2. `narrative`：叙事轮动总览和详情。
3. `investor`：投资者榜单和 YouTube 作者页。
4. `region`：区域总览和区域详情。
5. `smart-voice`：独立 SV 页面和作者排名。

迁移期允许旧组件继续留在 `web/components/prismo`，但新复杂逻辑不再向旧大文件追加。

Feature 组件可以用 `import type` 读取 `@/server/queries/*` 暴露的类型，但不能运行时导入
server query 函数。页面取数应留在 `web/app` 路由层，或后续放入明确的 feature query adapter。
