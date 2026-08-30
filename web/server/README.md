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
  - `sources.ts`：Reddit、YouTube、雪球、Toss、Yahoo JP、X/Score 原始观点读取。
  - `flow.ts` / `opinions.ts` / `targets.ts` / `arguments.ts` / `daily.ts` / `boards.ts`：页面消费的稳定查询入口。
- `queries/investorQueries.ts`：投资者榜单聚合。
- `queries/creatorQueries.ts`：YouTube 作者详情。
- `queries/smartVoiceQueries.ts`：Smart Account 查询兼容入口，不承载实现。
  - `smartVoiceTypes.ts`：公开查询契约及内部标准化 Call 类型。
  - `smartVoiceMarketQueries.ts`：市场发现 SQL、时间窗口编排和证据补全。
  - `smartVoiceMarketAggregation.ts`：单条 Call 权重、聚合状态和证据选择基础件。
  - `smartVoiceMarketBuilder.ts`：Top/Bottom 作者榜、新覆盖与作者转向榜单构建。
  - `smartVoiceOverviewQueries.ts`：概览统计和实时观点查询。
- `queries/smartVoiceInvestorQueries.ts`：Smart Account 作者证据查询兼容入口，不承载实现。
  - `smartVoiceInvestorTypes.ts`：作者证据、代表观点和价格序列契约。
  - `smartVoiceInvestorEvidenceQueries.ts`：单作者历史证据、结算表现和价格窗口查询。
  - `smartVoiceRepresentativeQueries.ts`：榜单作者代表加分/扣分标的及紧凑价格序列查询。
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

缺表或本地快照不完整时需要降级空结果的查询统一使用 `server/db/safeQuery.ts`；不要在各查询文件
重复实现 `try/catch` 包装。业务校验错误不应吞掉，只有明确允许降级的数据库读取使用该工具。
