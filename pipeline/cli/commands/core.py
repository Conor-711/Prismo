from __future__ import annotations

from ._utils import csv_values
from ...jobs.core import (
    analyze_items,
    build_brief,
    build_legacy_narratives,
    build_market_mood,
    build_rollups,
    build_trending,
    cloud_pull,
    cloud_push,
    crawl_authors,
    ensure_sample_data,
    extract_ticker_mentions,
    ingest_reddit,
    init_database,
    load_sample_data,
    migrate_database,
    refresh_reddit,
    run_daily_job,
    scrape_china_posts,
    scrape_reddit_comments,
    scrape_reddit_posts,
    seed_cn_hk_tickers,
    seed_us_tickers,
    show_stats,
    translate_content,
)


def cmd_db_init(args):
    init_database()


def cmd_migrate(args):
    """把已有库迁移到带 market 维度的新 schema（幂等）。"""
    migrate_database()


def cmd_seed(args):
    seed_us_tickers(use_fallback=args.fallback)


def cmd_seed_cn_hk(args):
    seed_cn_hk_tickers()


def cmd_load_sample(args):
    load_sample_data()


def cmd_ensure_sample(args):
    """若库内无帖子（如真实爬取失败），用样本兜底，保证站点不空。"""
    ensure_sample_data()


def cmd_ingest(args):
    ingest_reddit(with_comments=not args.no_comments)


def cmd_refresh(args):
    refresh_reddit()


def cmd_scrape(args):
    scrape_reddit_posts(
        days=args.days,
        limit_per=args.limit,
        markets=csv_values(getattr(args, "markets", None), as_set=True),
    )


def cmd_scrape_china(args):
    """关键词/ticker 过滤扫描综合中国社区，引入 A 股(沪深)等中国股市内容。"""
    scrape_china_posts(
        days=args.days,
        limit_per=args.limit,
        subs=csv_values(getattr(args, "subs", None)),
    )


def cmd_scrape_comments(args):
    scrape_reddit_comments(top_n=args.top, per_post=args.per_post, min_comments=args.min_comments)


def cmd_crawl_authors(args):
    """作者库：爬「实力榜」Top 作者历史帖（两级漏斗：DeepSeek 粗筛 → 千问深析）。"""
    crawl_authors(
        limit=args.limit,
        per_author_cap=args.per_author,
        refresh_days=args.refresh_days,
        max_fetch_per=args.max_fetch_per,
        since_days=args.since_days,
        refresh_profiles=not args.no_profile_refresh,
        pool=args.pool,
        min_ticker_posts=args.min_ticker_posts,
        quality_mode=args.quality_mode,
    )


def cmd_extract(args):
    extract_ticker_mentions(reextract=args.reextract)


def cmd_analyze(args):
    analyze_items(
        mock=args.mock,
        qwen=getattr(args, "qwen", False),
        limit=args.limit,
        workers=getattr(args, "workers", 8),
        force=getattr(args, "force", False),
    )


def cmd_translate(args):
    only = csv_values(getattr(args, "only", None), as_set=True) or {"posts", "analysis", "comments"}
    translate_content(only=only, limit=args.limit)


def _markets_arg(args) -> list[str]:
    """--market us|cn|all（默认 all = 美股 + 中概港股各跑一次）。"""
    mk = getattr(args, "market", "all") or "all"
    return ["us", "cn"] if mk == "all" else [mk]


def cmd_rollup(args):
    build_rollups(markets=_markets_arg(args))


def cmd_mood(args):
    build_market_mood(markets=_markets_arg(args))


def cmd_trending(args):
    build_trending(markets=_markets_arg(args))


def cmd_narratives(args):
    build_legacy_narratives(markets=_markets_arg(args), mock=args.mock)


def cmd_brief(args):
    build_brief(mock=args.mock)


def cmd_daily(args):
    """每日一次：分析过去 24 小时（UTC+8 08:00 跑）。--rebuild 同时重建静态站点。"""
    run_daily_job(rebuild=args.rebuild)


def cmd_stats(args):
    show_stats()


def cmd_cloud_push(args):
    cloud_push()


def cmd_cloud_pull(args):
    cloud_pull()


def register_commands(sub, root) -> None:
    sub.add_parser("db-init").set_defaults(func=cmd_db_init)
    sub.add_parser("migrate").set_defaults(func=cmd_migrate)

    sp = sub.add_parser("seed-tickers")
    sp.add_argument("--fallback", action="store_true")
    sp.set_defaults(func=cmd_seed)

    sub.add_parser("seed-cn-hk").set_defaults(func=cmd_seed_cn_hk)
    sub.add_parser("load-sample").set_defaults(func=cmd_load_sample)
    sub.add_parser("ensure-sample").set_defaults(func=cmd_ensure_sample)

    sp = sub.add_parser("ingest")
    sp.add_argument("--once", action="store_true")
    sp.add_argument("--no-comments", action="store_true")
    sp.set_defaults(func=cmd_ingest)

    sub.add_parser("refresh").set_defaults(func=cmd_refresh)

    sp = sub.add_parser("scrape")
    sp.add_argument("--days", type=int, default=3)
    sp.add_argument("--limit", type=int, default=300)
    sp.add_argument("--markets", type=str, default=None, help="逗号分隔，如 us,cn；省略=全部")
    sp.set_defaults(func=cmd_scrape)

    sp = sub.add_parser("scrape-china")
    sp.add_argument("--days", type=int, default=30)
    sp.add_argument("--limit", type=int, default=300)
    sp.add_argument("--subs", type=str, default=None, help="逗号分隔的来源版块；省略=默认综合中国社区")
    sp.set_defaults(func=cmd_scrape_china)

    sp = sub.add_parser("scrape-comments")
    sp.add_argument("--top", type=int, default=400)
    sp.add_argument("--per-post", type=int, default=15)
    sp.add_argument("--min-comments", type=int, default=4)
    sp.set_defaults(func=cmd_scrape_comments)

    sp = sub.add_parser("crawl-authors")
    sp.add_argument("--limit", type=int, default=50, help="爬实力榜 Top N 作者")
    sp.add_argument("--per-author", type=int, default=20, help="每位作者最多并入作者库篇数")
    sp.add_argument("--refresh-days", type=int, default=7, help="距上次爬取超过几天才重爬")
    sp.add_argument("--max-fetch-per", type=int, default=120, help="每位作者最多从 Arctic Shift 拉多少历史帖")
    sp.add_argument("--since-days", type=int, default=365, help="只纳入近 N 天作者历史帖；0=不限")
    sp.add_argument("--pool", choices=["leaderboard", "ticker-repeat"], default="leaderboard", help="作者池：旧实力榜或重复 ticker 作者池")
    sp.add_argument("--min-ticker-posts", type=int, default=3, help="ticker-repeat 池最少 ticker 相关帖数")
    sp.add_argument("--quality-mode", choices=["llm", "heuristic"], default="llm", help="作者历史帖质量过滤方式：llm 精筛或 heuristic 快速补数据")
    sp.add_argument("--no-profile-refresh", action="store_true", help="跳过 Reddit 作者 profile/karma 刷新")
    sp.set_defaults(func=cmd_crawl_authors)

    sp = sub.add_parser("extract")
    sp.add_argument("--reextract", action="store_true")
    sp.set_defaults(func=cmd_extract)

    sp = sub.add_parser("analyze")
    sp.add_argument("--mock", action="store_true")
    sp.add_argument("--qwen", action="store_true")
    sp.add_argument("--force", action="store_true")
    sp.add_argument("--workers", type=int, default=8)
    sp.add_argument("--limit", type=int, default=None)
    sp.set_defaults(func=cmd_analyze)

    sp = sub.add_parser("translate")
    sp.add_argument("--only", default="posts,analysis,comments", help="逗号分隔：posts,analysis,comments")
    sp.add_argument("--limit", type=int, default=None)
    sp.set_defaults(func=cmd_translate)

    sp = sub.add_parser("rollup")
    sp.add_argument("--market", type=str, default="all", help="us|cn|all")
    sp.set_defaults(func=cmd_rollup)

    sp = sub.add_parser("mood")
    sp.add_argument("--market", type=str, default="all")
    sp.set_defaults(func=cmd_mood)

    sp = sub.add_parser("trending")
    sp.add_argument("--market", type=str, default="all")
    sp.set_defaults(func=cmd_trending)

    sp = sub.add_parser("narratives")
    sp.add_argument("--mock", action="store_true")
    sp.add_argument("--market", type=str, default="all")
    sp.set_defaults(func=cmd_narratives)

    sp = sub.add_parser("brief")
    sp.add_argument("--mock", action="store_true")
    sp.set_defaults(func=cmd_brief)

    sp = sub.add_parser("daily")
    sp.add_argument("--rebuild", action="store_true")
    sp.set_defaults(func=cmd_daily)

    sub.add_parser("stats").set_defaults(func=cmd_stats)
    sub.add_parser("cloud-push").set_defaults(func=cmd_cloud_push)
    sub.add_parser("cloud-pull").set_defaults(func=cmd_cloud_pull)
