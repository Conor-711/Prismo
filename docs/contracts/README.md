# Data Contracts

本目录定义 Prismo 的跨平台领域对象。它们不是数据库 schema，而是前端和管线之间必须保持稳定的产品契约。

## 合同列表

- `opinion.md`：观点流的标准内容单元。
- `author.md`：作者、KOL、平台账号的标准字段。
- `ticker.md`：标的元信息和展示字段。
- `judgment.md`：目标价、买卖点、操作周期。
- `smart_voice.md`：Smart Voice 分数、排名、区间筛选。
- `narrative.md`：固定叙事板块、热度、情绪、来源分布。

## 使用规则

- 新平台接入时，先说明如何映射到这些 contract。
- 前端 feature 只消费 contract 或 feature view model，不直接依赖 raw payload。
- 数据库表可以不同，但导出给页面的数据必须满足 contract。
- Contract 修改属于架构改动，必须同步更新 `ARCHITECTURE.md`。
