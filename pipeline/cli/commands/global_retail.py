from __future__ import annotations

from ._utils import csv_values
from ...jobs.global_retail import (
    backfill_xueqiu,
    crawl_regional_discussions,
    crawl_toss,
    crawl_xueqiu_direct,
    enrich_xueqiu_authors,
    expand_xueqiu_related,
    fetch_quotes,
    import_xueqiu_export,
    incremental_xueqiu,
    rollup_tickers,
    run_xueqiu_jobs,
    sync_xueqiu_to_global_retail,
    tag_posts,
    xueqiu_status,
)


def cmd_gr_crawl(args):
    crawl_regional_discussions(
        per_board=args.per_board,
        since_days=args.since_days,
        regions=csv_values(getattr(args, "regions", None), as_set=True),
        only=csv_values(getattr(args, "only", None), upper=True),
    )


def cmd_gr_tag(args):
    tag_posts(
        batch_size=args.batch,
        workers=args.workers,
        only_new=not args.force,
        only=csv_values(getattr(args, "only", None), upper=True),
        sources=csv_values(getattr(args, "source", None)),
        regions=csv_values(getattr(args, "regions", None)),
    )


def cmd_gr_rollup(args):
    rollup_tickers(window_days=args.window_days)


def cmd_gr_xueqiu(args):
    # 雪球(中国大陆)讨论经 Claude-in-Chrome 浏览器过 WAF 导出为 JSON，这里收进 gr_post(region=cn)。
    import_xueqiu_export(path=args.path, since_days=args.since_days)


def cmd_gr_xueqiu_crawl(args):
    # 雪球(中国大陆)讨论：不用 Codex Chrome 插件，直接用 Playwright-controlled Chrome 过 WAF 并导出+入库。
    crawl_xueqiu_direct(
        out_path=args.out,
        since_days=args.since_days,
        only=csv_values(getattr(args, "only", None), upper=True),
        per_page=args.per_page,
        max_pages=args.max_pages,
        sleep=args.sleep,
        headless=args.headless,
        do_ingest=not args.no_ingest,
    )


def cmd_gr_xueqiu_backfill(args):
    # 雪球长期管道：创建并运行回填任务。结果先入 raw/job/checkpoint，再同步到 gr_post。
    backfill_xueqiu(
        days=args.days,
        only=csv_values(getattr(args, "only", None), upper=True),
        per_page=args.per_page,
        max_pages=args.max_pages,
        max_jobs=args.max_jobs,
        sleep=args.sleep,
        headless=args.headless,
        force=args.force,
        run=not args.plan_only,
        sync=args.sync,
    )


def cmd_gr_xueqiu_incremental(args):
    # 雪球长期管道：日常增量任务，默认只补近 3 天。
    incremental_xueqiu(
        days=args.days,
        only=csv_values(getattr(args, "only", None), upper=True),
        per_page=args.per_page,
        max_pages=args.max_pages,
        max_jobs=args.max_jobs,
        sleep=args.sleep,
        headless=args.headless,
        force=args.force,
        run=not args.plan_only,
        sync=args.sync,
    )


def cmd_gr_xueqiu_run_jobs(args):
    # 雪球长期管道：只运行已经创建的 pending/failed 任务。
    run_xueqiu_jobs(
        max_jobs=args.max_jobs,
        sleep=args.sleep,
        headless=args.headless,
        retry_failed=args.retry_failed,
        recover_running_hours=args.recover_running_hours,
    )


def cmd_gr_xueqiu_sync(args):
    # 雪球长期管道：把 raw + post_ticker 映射同步到产品正在读取的 gr_post。
    sync_xueqiu_to_global_retail(
        since_days=args.since_days,
        only=csv_values(getattr(args, "only", None), upper=True),
    )


def cmd_gr_xueqiu_expand_related(args):
    # 雪球长期管道：从 raw 正文抽关联标的，必要时为高频关联标的创建 related 回填任务。
    expand_xueqiu_related(since_days=args.since_days, enqueue_top=args.enqueue_top)


def cmd_gr_xueqiu_enrich_authors(args):
    # 雪球长期管道：从 raw payload 重建作者粉丝数等快照。
    enrich_xueqiu_authors(since_days=args.since_days)


def cmd_gr_xueqiu_status(args):
    xueqiu_status()


def cmd_gr_quote(args):
    # 各 gr 标的最新价（Yahoo 15m chart）→ gr_quote，供标的页展示最新价/涨跌幅。
    fetch_quotes()


def cmd_toss(args):
    # Toss(토스증권) 종목 커뮤니티评论 → gr_post(source='toss', region='kr')。游标翻页 RECENT。
    crawl_toss(
        days=args.days,
        only=csv_values(getattr(args, "only", None), upper=True),
        max_pages=args.max_pages,
        sleep=args.sleep,
        commit_pages=args.commit_pages,
        resume=args.resume,
    )


def register_commands(sub, root) -> None:
    sp = sub.add_parser("gr-crawl")
    sp.add_argument("--per-board", type=int, default=120)
    sp.add_argument("--since-days", type=int, default=14)
    sp.add_argument("--regions", type=str, default=None, help="逗号分隔 jp,kr,tw；省略=全部")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker（调试用）")
    sp.set_defaults(func=cmd_gr_crawl)

    sp = sub.add_parser("gr-tag")
    sp.add_argument("--batch", type=int, default=15)
    sp.add_argument("--workers", type=int, default=8)
    sp.add_argument("--force", action="store_true", help="重打全部（默认只打未打的）")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--source", type=str, default=None, help="逗号分隔 gr_post.source，如 yahoo_jp,toss")
    sp.add_argument("--regions", type=str, default=None, help="逗号分隔 region，如 jp,kr,tw")
    sp.set_defaults(func=cmd_gr_tag)

    sp = sub.add_parser("gr-rollup")
    sp.add_argument("--window-days", type=int, default=14)
    sp.set_defaults(func=cmd_gr_rollup)

    sp = sub.add_parser("gr-xueqiu")
    sp.add_argument("--path", type=str, default="data/exports/gr_cn_xueqiu.json", help="浏览器导出的雪球帖 JSON")
    sp.add_argument("--since-days", type=int, default=14)
    sp.set_defaults(func=cmd_gr_xueqiu)

    sp = sub.add_parser("gr-xueqiu-crawl")
    sp.add_argument("--out", type=str, default="data/exports/gr_cn_xueqiu_direct.json", help="导出的雪球 JSON")
    sp.add_argument("--since-days", type=int, default=14)
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--per-page", type=int, default=20)
    sp.add_argument("--max-pages", type=int, default=80)
    sp.add_argument("--sleep", type=float, default=0.35)
    sp.add_argument("--headless", action="store_true", help="无头模式；雪球可能要求有头 Chrome 才能过 WAF")
    sp.add_argument("--no-ingest", action="store_true", help="只导出 JSON，不入 gr_post")
    sp.set_defaults(func=cmd_gr_xueqiu_crawl)

    sp = sub.add_parser("gr-xueqiu-backfill")
    sp.add_argument("--days", type=int, default=365, help="回填过去 N 天")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--per-page", type=int, default=20)
    sp.add_argument("--max-pages", type=int, default=1600)
    sp.add_argument("--max-jobs", type=int, default=None, help="本轮最多运行 N 个任务；省略=全部 pending")
    sp.add_argument("--sleep", type=float, default=0.35)
    sp.add_argument("--headless", action="store_true")
    sp.add_argument("--force", action="store_true", help="重置同窗口已有任务")
    sp.add_argument("--plan-only", action="store_true", help="只创建任务，不启动浏览器")
    sp.add_argument("--sync", action="store_true", help="运行后同步 raw 到 gr_post")
    sp.set_defaults(func=cmd_gr_xueqiu_backfill)

    sp = sub.add_parser("gr-xueqiu-incremental")
    sp.add_argument("--days", type=int, default=3, help="增量补近 N 天")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--per-page", type=int, default=20)
    sp.add_argument("--max-pages", type=int, default=120)
    sp.add_argument("--max-jobs", type=int, default=None)
    sp.add_argument("--sleep", type=float, default=0.35)
    sp.add_argument("--headless", action="store_true")
    sp.add_argument("--force", action="store_true")
    sp.add_argument("--plan-only", action="store_true")
    sp.add_argument("--sync", action="store_true", help="运行后同步 raw 到 gr_post")
    sp.set_defaults(func=cmd_gr_xueqiu_incremental)

    sp = sub.add_parser("gr-xueqiu-run-jobs")
    sp.add_argument("--max-jobs", type=int, default=None)
    sp.add_argument("--sleep", type=float, default=0.35)
    sp.add_argument("--headless", action="store_true")
    sp.add_argument("--retry-failed", action="store_true")
    sp.add_argument("--recover-running-hours", type=int, default=0, help="把超过 N 小时仍 running 的任务恢复为 pending；0=不处理")
    sp.set_defaults(func=cmd_gr_xueqiu_run_jobs)

    sp = sub.add_parser("gr-xueqiu-sync")
    sp.add_argument("--since-days", type=int, default=365)
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.set_defaults(func=cmd_gr_xueqiu_sync)

    sp = sub.add_parser("gr-xueqiu-expand-related")
    sp.add_argument("--since-days", type=int, default=365)
    sp.add_argument("--enqueue-top", type=int, default=0, help="为提及最多的 N 个关联标的创建 related 任务；0=只写映射")
    sp.set_defaults(func=cmd_gr_xueqiu_expand_related)

    sp = sub.add_parser("gr-xueqiu-enrich-authors")
    sp.add_argument("--since-days", type=int, default=365)
    sp.set_defaults(func=cmd_gr_xueqiu_enrich_authors)

    sub.add_parser("gr-xueqiu-status").set_defaults(func=cmd_gr_xueqiu_status)
    sub.add_parser("gr-quote").set_defaults(func=cmd_gr_quote)

    sp = sub.add_parser("toss")
    sp.add_argument("--days", type=int, default=14, help="爬近 N 天")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker（省略=TOSS_STOCKS 全部）")
    sp.add_argument("--max-pages", type=int, default=1500, help="每标的最多翻页数（每页 11 条）")
    sp.add_argument("--sleep", type=float, default=0.3, help="分页请求间隔秒数")
    sp.add_argument("--commit-pages", type=int, default=100, help="每 N 页提交一次，避免大体量标的长跑回滚")
    sp.add_argument("--resume", action="store_true", help="基于本地已有 Toss 数据补新并从最旧游标继续向前抓")
    sp.set_defaults(func=cmd_toss)
