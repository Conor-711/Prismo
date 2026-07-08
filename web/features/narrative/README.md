# Narrative Feature

叙事页只处理固定板块叙事，不处理单一事件。数据来源是构建期 JSON `web/lib/data/narrativeRotation.json`。

目标拆分：

```text
narrative/
  components/
    NarrativeWorkspace.tsx
    NarrativeRankTable.tsx
    NarrativeMindshareChart.tsx
    NarrativeDetailPanel.tsx
  queries/
    getNarrativeRotation.ts
  types.ts
  taxonomy.ts
```

关键约束：

- 占比图必须归一化到 0-100。
- 叙事定义应与 `docs/contracts/narrative.md` 对齐。
- 财报、政策、估值等驱动因素不作为固定叙事板块。

当前已迁移：

- `components/NarrativeRotationCharts.tsx`
- `index.ts`
