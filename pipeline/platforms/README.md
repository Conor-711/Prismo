# Pipeline Platforms

`pipeline/platforms` 是平台适配器目标目录。每个平台目录负责抓取、raw 保存、标准化和作者元信息。

目标平台：

```text
platforms/
  reddit/
  x/
  youtube/
  xueqiu/
  toss/
  yahoojp/
  naver/
  ptt/
  market_data/
  author_assets/
```

平台层不实现跨平台业务逻辑。Smart Voice、目标价、观点质量、叙事分类等逻辑应放在 `pipeline/domain` 或 `pipeline/jobs`。

## 当前落点

- `youtube/adapter.py`：YouTube 搜索抓取和频道作者元信息刷新入口。
- `x/adapter.py`：X 推文与 ticker/topic 硬匹配入口；`cloud_pull.py` / `complete_universe.py` 承接云端 X 拉取与完整 X ticker universe。
- `global_retail/adapter.py`：Yahoo JP、Naver、PTT 多区散户抓取、雪球导出导入、全球散户报价入口。
- `xueqiu/adapter.py`：雪球直抓、回填、增量、任务运行、同步、关联标的、作者快照、状态入口。
- `toss/adapter.py`：Toss 股票社区抓取入口。
- `reddit/adapter.py`：Reddit ingest、Arctic Shift 抓取、评论抓取、作者历史抓取入口。
- `local/adapter.py`：本地样本数据加载入口。
- `market_data/adapter.py`：SV 价格结算所需日线价格回填入口；`short_window_prices.py` 承接短窗口 `price_daily` 加载。
- `author_assets/avatars.py`：观点作者头像快照刷新入口。

`pipeline/ingest` 现在仅作为旧命令路径兼容层保留；新增平台实现必须落到 `pipeline/platforms/<platform>/`。
