# Ticker Contract

Ticker 是产品中所有标的页面和聚合的基础对象。

## 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `symbol` | string | 标准美股代码 |
| `name` | string | 公司或 ETF 名称 |
| `exchange` | string | 交易所 |
| `market` | string | `us`、`cn` 等市场分组 |
| `sector` | string | 行业，可为空 |
| `aliases` | string[] | 公司名、别名、本地语言名 |
| `logo_url` | string | 标的 logo |
| `quote` | object | 最新价格、涨跌幅、时间 |

## 使用约束

- 页面路由使用大写 `symbol`。
- 平台抓取可以使用平台专属 symbol，但入库前必须映射到标准 `symbol`。
- 标的别名属于数据层，不应散落在前端组件里。
