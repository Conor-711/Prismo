# Smart Voice Contract

Smart Voice 描述作者或观点在某个标的下的可信声音指标。

## Author SV Meta

| 字段 | 类型 | 说明 |
|---|---|---|
| `investor_id` | string | 标准作者 ID |
| `ticker` | string | 标的 |
| `source` | string | 平台 |
| `score` | number | SV 分数 |
| `rank` | number | 标的内排名 |
| `percentile` | number | 标的内百分位，0 表示最头部，100 表示最尾部 |
| `n_effective` | number | 有效样本量 |
| `settled_calls` | number | 已结算观点数 |
| `updated_at` | ISO datetime | 更新时间 |

## 前端筛选

SV 区间筛选使用 `percentile`：

- Top 25%：`0 <= percentile <= 25`
- Middle 50%：`25 < percentile < 75`
- Bottom 25%：`75 <= percentile <= 100`
- 自定义区间：用户选择 `[low, high]`

前端不得重新计算 `score`，只能基于已导出的 `percentile` 或 `rank` 过滤。
