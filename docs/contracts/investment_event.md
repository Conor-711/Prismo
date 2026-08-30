# Investment Event Contract (Legacy)

> 状态：1.0 兼容层。新开发使用 `smart_intelligence_signal.md` 中的 `PortfolioSignal` 和 `/v1/feed`。

Investment Event 是早期 iOS fixture 使用的统一事件对象。它保留用于旧客户端和旧数据导出迁移，不再是
MVP 的产品真源。

机器契约以 `contracts/openapi/bsmart-v1.yaml` 的 `InvestmentEvent` 为准。

## 核心字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 稳定事件标识 |
| `ticker` | string | 标准大写美股代码 |
| `companyName` | string | 公司展示名 |
| `title` | string | 变化本身，不写泛化新闻标题 |
| `summary` | string | 发生了什么 |
| `occurredAt` | datetime | 事件形成时间 |
| `severity` | enum | `critical` / `important` / `notable` |
| `kind` | enum | 确认、背离、Smart Account 变化或 Smart Money 变化 |
| `smartMoneyCoverage` | enum | `available` / `unavailable` |
| `conclusion` | string | 证据综合解释 |
| `positionImpact` | string | 与当前持仓的关系 |
| `nextStep` | string | 下一步研究建议，不是买卖指令 |
| `evidence` | EventEvidence[] | 可追溯证据 |

## Smart Money 覆盖语义

- `available`：公开代币化美股仓位数据达到当前最低门槛，可以讨论确认、背离或无明显变化。
- `unavailable`：资金数据不足，客户端必须显示“暂无资金验证”；不能解释为中性、无交易或反向信号。

覆盖状态必须由服务端明确返回，客户端不得通过 `evidence` 中是否出现 `smart_money` 自行猜测。

## 客户端职责

- 只展示当前持仓 ticker 的事件。
- 在相同服务端优先级语义下，可用 severity、仓位占比和时间做本地个性化排序。
- 允许用户打开原始证据。
- 不在客户端生成事件、重算 Score 或钱包评分。
- `nextStep` 只能引导继续研究，不生成个性化买卖或仓位指令。
