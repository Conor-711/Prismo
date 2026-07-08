# Web Server Boundary

`web/server` 是前端构建期/服务端取数的目标边界。页面级 SQL 和构建期 view model 查询应逐步移动到这里，`web/lib/*Queries.ts` 在迁移期只保留兼容导出。

目标结构：

```text
server/
  db/
    sqlite.ts
    safeQuery.ts
  queries/
    ticker.ts
    opinions.ts
    narratives.ts
    investors.ts
    regions.ts
```

规则：

- `db/` 只处理连接、错误兜底和低级 query 工具。
- `queries/` 返回平台无关的 view model。
- feature query 可以组合多个 server query，但不应直接散写 SQL。

当前已迁移：

- `queries/globalQueries.ts`：全球散户 `gr_*` 标的、地区、行情查询。
- `queries/kolQueries.ts`：标的详情查询兼容导出；具体实现拆到 `queries/kol/`：
  - `shared.ts`：通用兜底、价格、立场、日期和 RawOp 工具。
  - `lookups.ts`：refined/viewpoint/avatar/channel/digest/relevance/quality/judgment/replies 映射。
  - `sources.ts`：Reddit、YouTube、雪球、Toss、Yahoo JP、X/SV 原始观点读取。
  - `flow.ts` / `opinions.ts` / `targets.ts` / `arguments.ts` / `daily.ts` / `boards.ts`：页面消费的稳定查询入口。
- `queries/investorQueries.ts`：投资者榜单聚合。
- `queries/creatorQueries.ts`：YouTube 作者详情。
- `queries/smartVoiceQueries.ts`：Smart Voice 标的榜单。
- `queries/narrativeRotation.ts`：叙事轮动构建期 JSON 查询。
- `queries/overallData.ts`：标的整体数据派生信号构建期 JSON 查询。
- `queries/legacyRedditQueries.ts`：旧 Reddit 单站查询兼容导出；实现拆到 `queries/legacyReddit/core.ts` 和 `queries/legacyReddit/detail.ts`，迁移期供 status 等遗留页面使用。

兼容路径：

- `web/lib/globalQueries.ts`
- `web/lib/kolQueries.ts`
- `web/lib/investorQueries.ts`
- `web/lib/creatorQueries.ts`
- `web/lib/smartVoiceQueries.ts`
- `web/lib/narrativeRotation.ts`
- `web/lib/overallData.ts`
- `web/lib/queries.ts`
