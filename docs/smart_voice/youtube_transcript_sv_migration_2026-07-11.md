# YouTube Transcript-backed SV Migration（2026-07-11）

## 结论

YouTube SV 已从“标题/描述可生成 Call”迁移为“完整口播是正式 Call 的强制证据”。
`v1.8-transcript-lifecycle` 已完成正式结算并发布产品导出。最终有 302 位 YouTube 作者同时满足
`n_eff >= 4` 和 `settled_calls >= 5`，超过 300 位正式作者池门槛。

## 新口径

- 评分版本：`v1.8-transcript-lifecycle`
- YouTube 口播 Call 版本：`youtube-transcript-v2`
- 标题和描述仅用于候选召回，不得生成正式 Call。
- 长口播按 speech segment 分块并覆盖到结尾，再合并为一个 `(video_id, ticker)` Call。
- 期权策略必须另有明确标的方向；风险管理、教学、新闻和回顾默认不参与结算。
- 嘉宾与第三方观点不得计入频道；只有频道主持人本人观点或明确认同才可参与。
- 同一作者、标的和交易日的重复观点共享证据上限；反向观点先反转或净额化。

## 真实迁移进度

| 指标 | 当前结果 |
|---|---:|
| 完整口播 | 9,280 |
| 新版口播标签记录 | 9,054 |
| 标签覆盖作者 | 495 |
| 新版 actionable Call | 3,358 |
| 缺少口播 provenance | 0 |
| 已收集 Gemini Batch | 23 |
| Batch 请求 / 成功 / 失败 | 7,350 / 5,807 / 1,543 |

新版标签分布：

| statement mode | actionable | non-actionable |
|---|---:|---:|
| prediction | 3,049 | 1,838 |
| position_action | 309 | 81 |
| education | 0 | 1,110 |
| news | 0 | 1,461 |
| retrospective | 0 | 1,073 |
| risk_management | 0 | 60 |
| other | 0 | 73 |

正式结算门禁要求 `call_owner=channel_host` 且 statement mode 为 `prediction` 或
`position_action`。5 条历史兼容记录虽曾标为 actionable，但因 owner 为 unknown 已在正式结算中排除。

## 结算验证

在 SQLite 一致性快照上重跑共享结算，并在主库复核：

- 结算行：174,900
- 原始 Call：41,144
- 有效 Call：31,436
- 同交易日重复组：1,938
- 同方向证据封顶：701
- 反向证据净额化：206
- 多空接近后中性化：305
- 旧版 YouTube 结算：0
- YouTube scored 作者：385
- YouTube 正式 qualified 作者：302
- YouTube SV 区间：约 53–115；正式 qualified 池以 100 为平台中位基线

The Black BOSS Channel 经完整口播复核后保留：12 个结算 Call、`n_eff=23.70`、SV=103。
绝大多数证据是主持人明确持仓或预测；误归于频道主的 1 条分析师目标价已改为第三方并排除出评分。

## 继续运行

交互式任务可继续用于小批量增量：

```bash
python -m pipeline.manage sv-v0 --source youtube --stage transcripts \
  --extract-limit 10000 --per-author-min 20 --per-author-max 40 --workers 4

python -m pipeline.manage sv-v0 --source youtube --stage extract \
  --extract-limit 0 --extract-mode author-balanced \
  --per-author-min 20 --per-author-max 40 --workers 8
```

大批量增量应使用独立配额和半价计费的 Gemini Batch API：

```bash
PYTHONPATH=. pipeline/.venv/bin/python scripts/run_youtube_sv_batch.py --limit 500
```

日常续跑也可直接使用：

```bash
scripts/run_youtube_sv_transcript_migration.sh
```

脚本默认只生成口播和抽取标签。只有原始证据作者达到 300，且正式结算后至少 300 位作者同时满足
`n_eff >= 4` 和 `settled_calls >= 5`，并显式设置 `PUBLISH=1` 时才允许导出和生成部署快照。

本次产品导出已于 2026-07-12 02:10（UTC+8）后重新生成；中文第三方分析师归属修复后再次
结算，最终 qualified 为 302。
