from __future__ import annotations

from ...jobs.smart_voice import (
    backfill_price_history,
    build_sv_indicator_backtest,
    export_sv_indicator_backtest_reports,
    build_ticker_sv_signals,
    build_overall_signals,
    match_x_topics,
    rollup_kol_newcomers,
    rollup_kol_sentiment,
    rollup_kol_volume,
    rollup_retail_newcomers,
    rollup_retail_sentiment,
    rollup_retail_volume,
    run_sv_v0,
    score_x_sentiment,
)
from ._utils import csv_values


def cmd_tw_sentiment(args):
    # X 推文情绪打分（DeepSeek/qwen flash 批量）→ 云端 tw_tweet_sentiment。供 KOL 每日净情绪 rollup。
    score_x_sentiment(batch_size=args.batch, workers=args.workers, only_new=not args.force, limit=args.limit)


def cmd_tw_match(args):
    # X 推文 ↔ 标的/主题硬匹配 → 云端 tw_tweet_topic。
    match_x_topics(page=args.page, batch=args.batch)


def cmd_sv_price_history(args):
    backfill_price_history(
        db=args.db,
        start=args.start,
        end=args.end,
        top_n=args.top_n,
        min_count=args.min_count,
        tweet_dirs=getattr(args, "tweet_dir", None),
        only=args.only or "",
        sleep=args.sleep,
        workers=args.workers,
        limit=args.limit,
    )


def cmd_sv_v0(args):
    run_sv_v0(
        stage=args.stage,
        source=args.source,
        candidate_limit=args.candidate_limit,
        extract_limit=args.extract_limit,
        extract_mode=args.extract_mode,
        per_author_min=args.per_author_min,
        per_author_max=args.per_author_max,
        min_score=args.min_score,
        workers=args.workers,
        only=args.only or "",
        tweet_dirs=getattr(args, "tweet_dir", None),
        reddit_author_limit=args.reddit_author_limit,
        reddit_since_days=args.reddit_since_days,
        reddit_min_author_posts=args.reddit_min_author_posts,
        youtube_min_subs=args.youtube_min_subs,
        youtube_since_days=args.youtube_since_days,
        xueqiu_pool_version=args.xueqiu_pool_version,
        xueqiu_since_days=args.xueqiu_since_days,
        xueqiu_allow_partial=args.xueqiu_allow_partial,
        force=args.force,
    )


def cmd_sv_ticker_signals(args):
    result = build_ticker_sv_signals(
        db_path=args.db,
        only=csv_values(args.only, upper=True),
        window_days=args.window_days,
        min_authors=args.min_authors,
        consensus_threshold=args.consensus_threshold,
        effective_voice_threshold=args.effective_voices,
    )
    print("[sv-ticker-signals] " + " ".join(f"{key}={value}" for key, value in result.items()))


def cmd_sv_indicator_backtest(args):
    windows = tuple(int(value) for value in csv_values(args.windows) if int(value) > 0)
    scopes = tuple(value.lower() for value in csv_values(args.source_scopes))
    result = build_sv_indicator_backtest(
        db_path=args.db,
        report_path=args.report,
        only=csv_values(args.only, upper=True),
        windows=windows,
        source_scopes=scopes,
    )
    print("[sv-indicator-backtest] " + " ".join(f"{key}={value}" for key, value in result.items()))


def cmd_sv_indicator_report(args):
    result = export_sv_indicator_backtest_reports(db_path=args.db, report_dir=args.report_dir)
    print("[sv-indicator-report] " + " ".join(f"{key}={value}" for key, value in result.items()))


def cmd_kol_sentiment(args):
    # KOL 每日净情绪 rollup：跨平台 情绪×ln(1+互动)×相关性 → 本地 kol_sentiment_daily（绿/红面积子面板）。
    rollup_kol_sentiment()


def cmd_kol_volume(args):
    # KOL 每日讨论度 rollup：跨平台帖子/视频计数 → 本地 kol_volume_daily（条状子面板）。
    rollup_kol_volume()


def cmd_retail_sentiment(args):
    # 整体散户 每日净情绪 rollup：全量散户 + 本土论坛(Naver/YahooJP/PTT)、不含 YouTube → 本地 retail_sentiment_daily。
    rollup_retail_sentiment()


def cmd_retail_volume(args):
    # 整体散户 每日讨论度 rollup：全量散户 + 本土论坛、不含 YouTube → 本地 retail_volume_daily（条状子面板）。
    rollup_retail_volume()


def cmd_retail_newcomers(args):
    # 整体散户 每日『新增散户』rollup：各平台首次参与该标的讨论的去重作者数（不含 X/YouTube）→ 本地 retail_newcomers_daily。
    rollup_retail_newcomers()


def cmd_kol_newcomers(args):
    # KOL 每日『新增 KOL』rollup：X/YouTube/雪球（有身份/粉丝象征）首次参与该标的讨论的去重作者数 → 本地 kol_newcomers_daily。
    rollup_kol_newcomers()


def cmd_overall_signals(args):
    # 整体数据『异动归因 + 讨论方面 + 聪明钱↔散户分歧 + 新叙事』（仅 KOL）→ web/lib/data/overallData.json。需 QWEN_API_KEY。
    kol_file = args.kol_file or f"/tmp/{args.ticker.lower()}_x6m.jsonl"
    build_overall_signals(
        ticker=args.ticker.upper(),
        kol_file=kol_file,
        window=args.window,
        look=args.look,
        aspect_days=args.aspect_days,
        cap=args.cap,
        skill_dir=args.skill_dir,
        recent_days=args.recent_days,
        prior_days=args.prior_days,
    )


def register_commands(sub, root) -> None:
    sp = sub.add_parser("tw-sentiment")
    sp.add_argument("--batch", type=int, default=20, help="每次 LLM 打多少条")
    sp.add_argument("--workers", type=int, default=8, help="LLM 并发数")
    sp.add_argument("--limit", type=int, default=None, help="只打前 N（调试）")
    sp.add_argument("--force", action="store_true", help="重打全部（默认只打未打分的）")
    sp.set_defaults(func=cmd_tw_sentiment)

    sp = sub.add_parser("tw-match")
    sp.add_argument("--page", type=int, default=20000, help="每页读取推文数")
    sp.add_argument("--batch", type=int, default=8000, help="预留的写入批大小参数，兼容旧实现")
    sp.set_defaults(func=cmd_tw_match)

    sp = sub.add_parser("sv-price-history")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument("--start", default="2025-06-01")
    sp.add_argument("--end", default=None, help="Inclusive YYYY-MM-DD. Defaults to today UTC.")
    sp.add_argument("--top-n", type=int, default=1000, help="Top cashtags to include from tweet JSONL.")
    sp.add_argument("--min-count", type=int, default=25)
    sp.add_argument("--tweet-dir", action="append", default=[], help="Folder containing tweets_*.jsonl.")
    sp.add_argument("--only", default="", help="Comma-separated tickers for a focused run.")
    sp.add_argument("--sleep", type=float, default=0.12)
    sp.add_argument("--workers", type=int, default=6)
    sp.add_argument("--limit", type=int, default=0, help="Debug cap after ticker selection.")
    sp.set_defaults(func=cmd_sv_price_history)

    sp = sub.add_parser("sv-v0")
    sp.add_argument("--stage", choices=["candidates", "transcripts", "extract", "settle", "score", "export", "all"], default="all")
    sp.add_argument("--source", default="x", help="Comma-separated source subset: x,youtube,reddit,xueqiu,toss,all. Default keeps legacy X-only behavior.")
    sp.add_argument("--candidate-limit", type=int, default=50_000, help="0 means insert all recalled candidates.")
    sp.add_argument("--extract-limit", type=int, default=1_000, help="0 means all pending candidates.")
    sp.add_argument("--extract-mode", choices=["rank", "author-balanced"], default="rank")
    sp.add_argument("--per-author-min", type=int, default=20)
    sp.add_argument("--per-author-max", type=int, default=80)
    sp.add_argument("--min-score", type=float, default=12.0)
    sp.add_argument("--workers", type=int, default=4)
    sp.add_argument("--only", default="", help="Comma-separated ticker subset.")
    sp.add_argument("--tweet-dir", action="append", default=[], help="Override/add tweet JSONL directories.")
    sp.add_argument("--reddit-author-limit", type=int, default=1_000, help="Top Reddit author pool size for candidate recall; 0 means all authors.")
    sp.add_argument("--reddit-since-days", type=int, default=365, help="Reddit candidate lookback window.")
    sp.add_argument("--reddit-min-author-posts", type=int, default=8, help="Minimum ticker-mentioned Reddit posts for Reddit author-pool eligibility.")
    sp.add_argument("--youtube-min-subs", type=int, default=2_000, help="Minimum public YouTube subscribers for SV eligibility (shared product threshold).")
    sp.add_argument("--youtube-since-days", type=int, default=365, help="YouTube candidate lookback window.")
    sp.add_argument("--xueqiu-pool-version", default="", help="Versioned selected Xueqiu author pool; empty uses the latest pool.")
    sp.add_argument("--xueqiu-since-days", type=int, default=365, help="Xueqiu candidate lookback window.")
    sp.add_argument("--xueqiu-allow-partial", action="store_true", help="Allow candidate recall before every selected Xueqiu author job is done; disabled by default.")
    sp.add_argument("--force", action="store_true", help="Re-extract candidates already in sv_call.")
    sp.set_defaults(func=cmd_sv_v0)

    sp = sub.add_parser("sv-ticker-signals")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument("--only", default="", help="Comma-separated ticker subset; empty rebuilds all tickers.")
    sp.add_argument("--window-days", type=int, default=7, help="Calendar-day clustering window.")
    sp.add_argument("--min-authors", type=int, default=3)
    sp.add_argument("--consensus-threshold", type=float, default=0.65)
    sp.add_argument("--effective-voices", type=float, default=2.5)
    sp.set_defaults(func=cmd_sv_ticker_signals)

    sp = sub.add_parser("sv-indicator-backtest")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument("--report", default=str(root / "data" / "reports" / "sv_indicator_backtest.csv"))
    sp.add_argument("--only", default="", help="Comma-separated ticker subset; empty rebuilds the full market.")
    sp.add_argument("--windows", default="1,3,7,30,90", help="Comma-separated calendar-day signal windows.")
    sp.add_argument("--source-scopes", default="all,x,youtube,reddit,xueqiu", help="Comma-separated source scopes.")
    sp.set_defaults(func=cmd_sv_indicator_backtest)

    sp = sub.add_parser("sv-indicator-report")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument("--report-dir", default=str(root / "data" / "reports"))
    sp.set_defaults(func=cmd_sv_indicator_report)

    sub.add_parser("kol-sentiment").set_defaults(func=cmd_kol_sentiment)
    sub.add_parser("kol-volume").set_defaults(func=cmd_kol_volume)
    sub.add_parser("retail-sentiment").set_defaults(func=cmd_retail_sentiment)
    sub.add_parser("retail-volume").set_defaults(func=cmd_retail_volume)
    sub.add_parser("retail-newcomers").set_defaults(func=cmd_retail_newcomers)
    sub.add_parser("kol-newcomers").set_defaults(func=cmd_kol_newcomers)

    sp = sub.add_parser("overall-signals")
    sp.add_argument("--ticker", default="PLTR")
    sp.add_argument("--kol-file", default=None, help="KOL 推文抽取 jsonl；默认 /tmp/<ticker>_x6m.jsonl")
    sp.add_argument("--window", type=int, default=11)
    sp.add_argument("--look", type=int, default=14)
    sp.add_argument("--aspect-days", type=int, default=14)
    sp.add_argument("--cap", type=int, default=3)
    sp.add_argument("--skill-dir", default="/tmp", help="技能 z / stance 缓存目录")
    sp.add_argument("--recent-days", type=int, default=7)
    sp.add_argument("--prior-days", type=int, default=21)
    sp.set_defaults(func=cmd_overall_signals)
