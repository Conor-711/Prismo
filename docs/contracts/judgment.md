# Judgment Contract

Judgment 描述一条观点中作者明确给出的交易判断、目标价或操作周期。

## 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `action` | `buy | sell | hold | watch | unknown` | 明确操作动作 |
| `buy_price` | number | 买入价，可为空 |
| `sell_price` | number | 卖出价，可为空 |
| `target_price` | number | 目标价，可为空 |
| `price_raw` | string | 原文价格表达 |
| `horizon_text` | string | 原文周期表达 |
| `horizon_bucket` | `short | mid | long | unknown` | 标准周期档 |
| `confidence` | number | 抽取置信度，0-1 |
| `evidence_text` | string | 支撑该抽取的原文片段 |

## 约束

- 只抽作者明说的信息，不能由估值推导或模型猜测。
- 目标价和股价线不是同一个字段；目标价来自观点，股价来自市场价格。
- `horizon_bucket` 仅用于筛选和图表分组，不能替代原文周期。
- 离谱价格需要按当前价 band 做二次过滤，并保留过滤规则说明。
