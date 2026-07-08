# Opinion Contract

Opinion 是标的详情页观点流的标准内容单元。它可以来自 X、YouTube、Reddit、雪球、Toss、Yahoo Finance 等平台。

## 必需字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | Prismo 内部唯一 ID，建议为 `${source}:${source_item_id}:${ticker}` |
| `source` | enum | 平台 key：`x`、`youtube`、`reddit`、`xueqiu`、`toss`、`yahoojp` |
| `source_item_id` | string | 平台原始内容 ID |
| `ticker` | string | 美股标的代码 |
| `author` | AuthorRef | 作者引用，见 `author.md` |
| `published_at` | ISO datetime | 发布时间 |
| `url` | string | 原平台链接，可为空但字段必须存在 |
| `original_text` | string | 原文或完整口播原文 |
| `language` | string | 原始语言 |

## 推荐字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `translated_text` | string | 完整忠实翻译，不是摘要 |
| `summary` | string | 投资者摘要或短摘要 |
| `stance` | `bull | neutral | bear` | 观点方向 |
| `sentiment` | number | 连续情绪分 |
| `relevance` | number | 与当前标的相关度，0-100 |
| `quality` | number | 内容质量，0-100 |
| `metrics` | object | 点赞、评论、浏览、收藏等平台互动 |
| `viewpoints` | string[] | 估值、成长、竞争、管理层、宏观、催化剂、资金等视角 |
| `judgment` | Judgment | 目标价/周期，见 `judgment.md` |
| `smart_voice` | SmartVoiceMeta | 作者 SV 信息，见 `smart_voice.md` |

## 关键约束

- `translated_text` 必须是完整翻译，不能用 TLDR 或分析文本替代。
- `summary` 可以经过提炼，但必须和翻译字段分开。
- `stance` 只表达该内容对当前 ticker 的方向，不表达作者整体偏好。
- 如果一条内容提到多个 ticker，应该拆成多条 ticker-scoped Opinion。
