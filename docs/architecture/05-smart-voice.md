# Smart Voice Architecture

Smart Voice 是跨平台作者可信度和观点质量系统，不应该被实现为某个页面的排序函数。

## 文档真源

算法文档位于：

- `docs/smart_voice/GLOBAL_ALGORITHM.md`
- `docs/smart_voice/TWITTER_ALGORITHM.md`
- `docs/smart_voice/YOUTUBE_ALGORITHM.md`
- `docs/smart_voice/REDDIT_ALGORITHM.md`
- `docs/smart_voice/XUEQIU_ALGORITHM.md`
- `docs/smart_voice/TOSS_ALGORITHM.md`

本文件只记录工程边界。

## 目标代码边界

```text
pipeline/domain/smart_voice/
  candidates.py        # 候选观点/作者召回
  evidence.py          # 证据标准化
  settlement.py        # 价格/事件结算
  scoring.py           # 平台内分数和 global score
  export.py            # web/lib/data/smartVoice.json
  README.md
```

平台专属逻辑留在 `pipeline/platforms/<platform>/`，SV 只消费标准化 evidence。

## 前端消费

前端不重新计算 SV，只消费构建期输出或查询层 view model：

- 作者榜单
- 标的详情页 SV 筛选
- 观点流 SV 排序
- Smart Voice 独立页面

前端允许做轻量筛选，例如 Top 25% 区间过滤，但不能改变 SV 分数口径。

## 数据要求

每个平台接入 SV 前必须提供：

- 作者唯一 ID
- 内容唯一 ID
- 标的映射
- 发布时间
- 原始观点或摘要
- 明确 stance 或可推导 stance
- 质量/相关性输入
- 可结算目标或观点方向

缺少结算条件的平台可以先作为 discovery source，不直接进入正式 SV 排名。
