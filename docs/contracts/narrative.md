# Narrative Contract

Narrative 是固定板块叙事，不是单一事件。示例：AI 与数据中心、半导体景气、加密资产与金融科技等。

## Narrative Definition

| 字段 | 类型 | 说明 |
|---|---|---|
| `slug` | string | 稳定路由 |
| `name_zh` | string | 中文名 |
| `name_en` | string | 英文名 |
| `description_zh` | string | 中文说明 |
| `description_en` | string | 英文说明 |
| `keywords` | string[] | 归类关键词 |
| `excluded_events` | string[] | 不应被当成叙事的事件词 |

## Daily Narrative Metrics

| 字段 | 类型 | 说明 |
|---|---|---|
| `date` | date | 日期 |
| `slug` | string | 叙事 slug |
| `rank` | number | 当日热度排名 |
| `share_pct` | number | 当日讨论占比，必须归一到 0-100 |
| `sentiment` | number | 情绪分 |
| `volume` | number | 样本数 |
| `sources` | object | 平台分布 |
| `regions` | object | 地区分布 |
| `tickers` | object | 标的分布 |

## 约束

- 财报、政策、估值、管理层讲话等事件或驱动因素不应作为固定叙事。
- 图表占比必须做 daily normalization，不能出现 100% 以上。
- 详情页可以展示来源、地区、标的分布，但代表原帖是否展示由产品需求控制。
