# YouTube Smart Account Top / Bottom 报告（2026-07-11）

> **已停止作为正式榜单使用。** 本报告基于 `v1.7-platform-global`，其中 YouTube Call 可由标题和描述生成。`v1.8-transcript-lifecycle` 已要求完整口播证据并修复同交易日冲突；完成全量重跑后必须用新版报告替换本文结果。

## 结论摘要

YouTube Score 已完成平台内 Top/Bottom 正式分组并接入产品导出。

| 指标 | 结果 |
|---|---:|
| 版本化候选作者池 | 500 |
| 获得 YouTube Score | 427 |
| 正式排名池 | 336 |
| Top 10% / Bottom 10% | 各 34 人 |
| Top 25% / Bottom 25% | 各 84 人 |
| Top 10% 阈值 | `SV_Platform >= 114` |
| Bottom 10% 阈值 | `SV_Platform <= 85` |
| Top 25% 阈值 | `SV_Platform >= 107` |
| Bottom 25% 阈值 | `SV_Platform <= 94` |

正式排名池只包含满足 YouTube 资格门槛的作者：`n_eff >= 4` 且 `settled_calls >= 5`。91 位只获得观察分但未达到门槛的作者不会进入 Top/Bottom。

## 计算口径

Top/Bottom 使用 `SV_Platform`，不是 `SV_Global`：

```text
SV_Platform = 作者在 YouTube 合格作者分布中的平台内表现
SV_Global   = SV_Platform 按置信度向 100 收缩后的跨平台展示分
```

排序依次使用：`SV_Platform`、`n_eff`、已结算 call 数和稳定作者 ID。相同平台分下，证据更充分者优先。百分位人数使用向上取整，因此 336 人对应 34 人的 10% 分组和 84 人的 25% 分组。

平台内分布：

| Min | Q25 | Median | Q75 | Max |
|---:|---:|---:|---:|---:|
| 45 | 94 | 100 | 107 | 123 |

## 分组特征

| 分组 | 作者 | 平均平台 Score | 平均 Global Score | 平均 n_eff | 平均已结算 call | 平均覆盖标的 | 平均最大单标的权重 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Top 10% | 34 | 119.1 | 112.5 | 35.3 | 24.2 | 11.2 | 40.0% |
| Bottom 10% | 34 | 78.4 | 86.6 | 31.4 | 22.0 | 8.7 | 45.6% |

Top 与 Bottom 的样本量接近，分数差异不是由一边只有极少样本造成。Bottom 的标的集中度略高，部分频道高度集中于单一 meme stock 或单一主题；产品解释时应同时展示集中度和有效覆盖宽度。

## 已结算表现

以下是构成当前分数的样本内描述，不是独立样本外回测：

| 分组 | 去重 call | 加权命中率 | 加权方向性相对 SPY 超额 |
|---|---:|---:|---:|
| Top 10% | 824 | 57.9% | +6.41% |
| Bottom 10% | 749 | 23.9% | -10.87% |

按结算周期：

| 分组 | 周期 | Call | 加权命中率 | 加权方向性超额 |
|---|---:|---:|---:|---:|
| Top 10% | 1D | 824 | 63.0% | +1.88% |
| Top 10% | 5D | 802 | 58.5% | +1.82% |
| Top 10% | 20D | 728 | 61.9% | +4.34% |
| Top 10% | 60D | 610 | 54.2% | +4.81% |
| Top 10% | 90D | 544 | 56.0% | +14.83% |
| Top 10% | 180D | 323 | 44.4% | +20.89% |
| Bottom 10% | 1D | 749 | 27.1% | -2.62% |
| Bottom 10% | 5D | 721 | 34.3% | -3.40% |
| Bottom 10% | 20D | 648 | 25.8% | -9.48% |
| Bottom 10% | 60D | 538 | 20.5% | -12.86% |
| Bottom 10% | 90D | 486 | 16.3% | -18.29% |
| Bottom 10% | 180D | 295 | 14.0% | -19.82% |

同一个 call 会按多个适用周期产生结算行，表中的各周期行不能相加后当作独立观点总数。180D 的方向性超额可能由少量高波动标的放大，不能只依据平均值判断稳定性。

## Top 10 作者快照

| 平台排名 | 作者 | SV_Platform | SV_Global | n_eff | 已结算 call | 覆盖标的 |
|---:|---|---:|---:|---:|---:|---:|
| 1 | `@reyjayinvests` | 123 | 115 | 52.1 | 28 | 7 |
| 2 | `@dr.stock.` | 123 | 115 | 47.6 | 25 | 9 |
| 3 | `@theblackbosschannel` | 123 | 115 | 42.3 | 21 | 12 |
| 4 | `@theotrade` | 123 | 115 | 39.7 | 28 | 18 |
| 5 | `@greenisgreen31` | 123 | 115 | 36.7 | 21 | 16 |
| 6 | `@showtime.trades` | 123 | 115 | 34.8 | 25 | 17 |
| 7 | `@tickertakewithjonerlichman` | 123 | 115 | 21.4 | 18 | 15 |
| 8 | `@analisistecnicostreet` | 122 | 114 | 38.3 | 26 | 11 |
| 9 | `@stealthwealthinvesting` | 122 | 114 | 37.7 | 22 | 4 |
| 10 | `@felixfriends` | 122 | 114 | 30.6 | 17 | 9 |

## Bottom 10 作者快照

| 平台排名 | 作者 | SV_Platform | SV_Global | n_eff | 已结算 call | 覆盖标的 |
|---:|---|---:|---:|---:|---:|---:|
| 336 | `@amcdaily7032` | 45 | 64 | 47.3 | 29 | 2 |
| 335 | `@astspacemobilepodcast` | 53 | 69 | 32.9 | 24 | 1 |
| 334 | `@donnahuegeorgestocks` | 63 | 76 | 69.1 | 30 | 3 |
| 333 | `@wallstreettrapper` | 72 | 82 | 26.0 | 15 | 9 |
| 332 | `@adamlivingstonbtc` | 73 | 82 | 28.8 | 25 | 6 |
| 331 | `@lotterystocks` | 74 | 83 | 27.2 | 24 | 4 |
| 330 | `@mrmtrades` | 75 | 84 | 28.4 | 26 | 19 |
| 329 | `@equity4keeps` | 76 | 84 | 25.2 | 22 | 18 |
| 328 | `@stockaustin` | 76 | 84 | 22.3 | 15 | 6 |
| 327 | `@paulngumah` | 76 | 92 | 10.7 | 8 | 6 |

完整 34/84 人名单保存在 `web/lib/data/smartVoice.json` 的：

```text
platformBands.youtube.top10
platformBands.youtube.bottom10
platformBands.youtube.top25
platformBands.youtube.bottom25
```

每条记录同时提供全局排名 `rank`、平台排名 `platformRank`、平台分 `platformScores.youtube`、Global 分 `sv`、置信度、`nEff`、结算数、分周期分数和集中度。

## 产品接入

- 全局标签继续使用 `investors` / `bottomInvestors` 和 `SV_Global`。
- YouTube 标签使用 `platformBands.youtube` 和 `SV_Platform`。
- Top/Bottom 切换在 YouTube 标签下保持平台口径，不再回退到全局榜单。
- 作者详情页优先展示平台排名、平台阈值和平台分解释。
- Bottom 表示历史方向性观点表现位于平台尾部，不表示应自动反向交易。

## 限制与下一步

1. 当前没有 high confidence 的 YouTube 作者；应随新视频和结算自然积累，不应降低 high 门槛。
2. 当前分组与表现指标使用同一批历史结算，属于样本内描述。需要按月冻结作者分位，再用未来窗口做样本外跟踪。
3. 频道删除、标题映射修订和 call 生命周期变化会改变后续排名；报告以 2026-07-11 快照为准。
4. 高波动、小盘和 meme stock 可能放大方向性超额，应结合集中度、标的分段 Score 和置信区间阅读。
5. 该榜单是内容阅读优先级工具，不构成投资建议。
