"""每日一次的全量流程（不再实时爬取）。

以 UTC+8 时区的 24 小时为界线，分析「过去 24 小时」的 Reddit 信息：
每天只需在 UTC+8 早上 08:00（= UTC 00:00）跑一次即可。

  run_daily()           只跑数据 + AI 分析（更新 data/dev.db）
  run_daily(rebuild=1)  分析完再构建静态站点（web/out），供本地/静态托管部署

被 `pipeline.worker`（调度器）与 `pipeline.manage daily` 复用。
"""
from __future__ import annotations

import datetime as dt
import os
import subprocess

from .common.config import ROOT, settings
from .common.db import init_db

# 过去 24 小时 → 爬 1 天即可覆盖窗口
WINDOW_DAYS = 1
SCRAPE_LIMIT_PER = 400  # 单板块单日上限，足以覆盖一天的活跃帖
MARKETS = ("us", "cn")  # 美股 / 中概·港股，各出一套聚合（互不污染）


def _safe(label: str, fn, *args, **kwargs):
    try:
        fn(*args, **kwargs)
        return True
    except Exception as e:  # noqa: BLE001
        print(f"[daily] {label} 失败：{e}")
        return False


def _post_count() -> int:
    from sqlalchemy import func, select

    from .common.db import session_scope
    from .common.models import Post

    with session_scope() as s:
        return int(s.execute(select(func.count()).select_from(Post)).scalar_one())


def run_daily(rebuild: bool = False) -> None:
    from .analyze.brief import run_brief
    from .analyze.item_analyze import run_analyze
    from .analyze.market_mood import run_market_mood
    from .analyze.narratives import run_narratives
    from .analyze.rollups import run_rollups
    from .analyze.trending import run_trending
    from .ingest.arctic_scrape import scrape, scrape_china_filtered, scrape_comments
    from .ingest.author_crawl import crawl_top_authors
    from .ingest.sample_loader import load_sample

    started = dt.datetime.now()
    use_qwen = settings.has_qwen          # 高档：逐帖投资打标（千问思考模式）
    mid_mock = not settings.has_deepseek  # 中档：叙事聚类 / 每日简报（DeepSeek deepseek-v4-pro）
    providers = "+".join(
        ([f"千问({settings.qwen_model})"] if use_qwen else [])
        + ([f"DeepSeek({settings.deepseek_model_mid})"] if not mid_mock else [])
    ) or "mock 启发式"
    print(f"[daily] 开始：过去 {WINDOW_DAYS*24} 小时分析（{providers}）— {started:%Y-%m-%d %H:%M %z}")

    init_db()

    # 1) 拉取过去 24 小时的帖子与高赞评论（Arctic Shift）
    _safe("scrape", scrape, days=WINDOW_DAYS, limit_per=SCRAPE_LIMIT_PER)
    # 1.5) 关键词/ticker 过滤扫描综合中国社区，补充 A 股(沪深)等中国股市内容（量小，市场=cn）
    _safe("scrape-china", scrape_china_filtered, days=WINDOW_DAYS, limit_per=SCRAPE_LIMIT_PER)

    # 2) 若库内仍为空（如网络受限爬取失败），用样本兜底，保证站点不空
    if _post_count() == 0:
        print("[daily] 库内无帖子，载入样本兜底。")
        _safe("load-sample", load_sample)

    # 3) 高档：逐帖 AI 打标（有千问→真实思考模式；否则 mock 启发式兜底） + 按 market 分别聚合
    if use_qwen:
        _safe("analyze", run_analyze, qwen=True, workers=10)
    else:
        _safe("analyze", run_analyze, mock=True)
    # 3.2) 作者库：爬「实力榜」Top 作者历史帖（两级漏斗：DeepSeek 粗筛 → 千问深析）。
    #      放在主分析之后（作者才可排名），过线帖再走一次增量分析（item_analyze 跳过已分析）。
    #      需 DeepSeek（粗筛闸）；作者库帖 source='author'，被所有实时聚合排除，只进作者页。
    if settings.has_deepseek:
        _safe("crawl-authors", crawl_top_authors, limit=50)
        if use_qwen:
            _safe("analyze-authors", run_analyze, qwen=True, workers=10)
        else:
            _safe("analyze-authors", run_analyze, mock=True)
    # 3.5) 抓「展示优先级最高」帖的评论快照（移到 analyze 之后，按质量分选帖）。
    #      Arctic 发帖瞬间存档 → num_comments≈0 不可信，故不按它过滤（min_comments=0）。
    _safe("scrape-comments", scrape_comments, top_n=700, per_post=15, min_comments=0)
    for mk in MARKETS:
        _safe(f"rollup[{mk}]", run_rollups, market=mk)
        _safe(f"mood[{mk}]", run_market_mood, market=mk)
        _safe(f"trending[{mk}]", run_trending, market=mk)
        # 中档：叙事聚类（有 DeepSeek→真实语义聚类；否则 mock 按主题分组）
        _safe(f"narratives[{mk}]", run_narratives, mock=mid_mock, market=mk)
    # 中档：每日简报润色
    _safe("brief", run_brief, mock=mid_mock)

    # 4) 低档：翻译成简体中文（标题/正文/AI 摘要/评论 → *_zh），保证 zh 模式 100% 中文。
    #    走 DeepSeek deepseek-v4-flash；缺 key 则跳过（_safe 兜底）。
    if settings.has_deepseek:
        from .analyze.translate import run as run_translate
        _safe("translate", run_translate, {"posts", "analysis", "comments"}, None)

    # 5) 可选：重建静态站点，让部署的页面反映最新一天的数据
    if rebuild:
        _build_site()

    took = (dt.datetime.now() - started).total_seconds()
    print(f"[daily] 完成，用时 {took:.0f}s。")


def _build_site() -> None:
    web = ROOT / "web"
    if not (web / "package.json").exists():
        print("[daily] 跳过站点构建：未找到 web/package.json。")
        return
    env = {**os.environ, "NODE_OPTIONS": "--experimental-sqlite"}
    print("[daily] 构建静态站点 web/out …")
    try:
        subprocess.run(["npm", "run", "build"], cwd=str(web), env=env, check=True)
        print("[daily] ✅ 站点已重建：web/out/")
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"[daily] 站点构建失败：{e}")


if __name__ == "__main__":
    import sys

    run_daily(rebuild="--rebuild" in sys.argv)
