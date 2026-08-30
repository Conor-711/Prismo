from __future__ import annotations

from ...jobs.smart_voice import (
    backfill_price_history,
    build_sv_indicator_backtest,
    build_sv_segment_backtest,
    build_x_sv_portfolio_backtest,
    build_x_rank_event_research,
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
    run_hyperliquid_live,
    run_hyperliquid_smart_money,
    export_smart_account_client_read_model,
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


def cmd_hyperliquid_smart_money(args):
    result = run_hyperliquid_smart_money(
        db_path=args.db,
        output_path=args.output,
        stage=args.stage,
        lookback_days=args.lookback_days,
        max_markets=args.max_markets,
        max_wallets=args.max_wallets,
        api_pause=not args.no_api_pause,
        client_output_dir=args.client_output_dir,
    )
    print("[hyperliquid-smart-money] " + " ".join(f"{key}={value}" for key, value in result.items()))


def cmd_hyperliquid_smart_money_live(args):
    result = run_hyperliquid_live(
        db_path=args.db,
        output_path=args.output,
        client_output_dir=args.client_output_dir,
        health_output_path=args.health_output,
        lookback_days=args.lookback_days,
        refresh_seconds=args.refresh_seconds,
        publish_seconds=args.publish_seconds,
        candidate_backfill_per_cycle=args.candidate_backfill,
        max_active_wallets=args.max_active_wallets,
        max_profile_wallets=args.max_profile_wallets,
        profile_refresh_minutes=args.profile_refresh_minutes,
        instrument_refresh_minutes=args.instrument_refresh_minutes,
        max_cycles=args.max_cycles,
        api_pause=not args.no_api_pause,
    )
    print("[hyperliquid-smart-money-live] " + " ".join(f"{key}={value}" for key, value in result.items()))


def cmd_export_smart_account_read_model(args):
    result = export_smart_account_client_read_model(
        db_path=args.db,
        output_dir=args.output_dir,
        update_days=args.update_days,
        update_limit=args.update_limit,
        profile_limit=args.profile_limit,
    )
    print("[smart-account-read-model] " + " ".join(f"{key}={value}" for key, value in result.items()))


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


def cmd_sv_segment_backtest(args):
    result = build_sv_segment_backtest(
        db_path=args.db,
        report_path=args.report,
        only=csv_values(args.only, upper=True),
        windows=tuple(int(value) for value in csv_values(args.windows) if int(value) > 0),
        sources=tuple(value.lower() for value in csv_values(args.sources)),
        segment_types=tuple(value.lower() for value in csv_values(args.segment_types)),
        rank_bands=tuple(value.lower() for value in csv_values(args.rank_bands)),
        min_authors=args.min_authors,
        consensus_threshold=args.consensus_threshold,
        effective_voice_threshold=args.effective_voices,
        segment_min_n_eff=args.segment_min_n_eff,
        segment_min_settled_calls=args.segment_min_calls,
    )
    print("[sv-segment-backtest] " + " ".join(f"{key}={value}" for key, value in result.items()))


def cmd_sv_portfolio_backtest(args):
    result = build_x_sv_portfolio_backtest(
        db_path=args.db,
        report_dir=args.report_dir,
        windows=tuple(int(value) for value in csv_values(args.windows) if int(value) > 0),
        holding_days=tuple(int(value) for value in csv_values(args.holding_days) if int(value) > 0),
        position_modes=tuple(value.lower() for value in csv_values(args.position_modes)),
    )
    print("[sv-portfolio-backtest] " + " ".join(f"{key}={value}" for key, value in result.items()))


def cmd_sv_rank_event_research(args):
    result = build_x_rank_event_research(
        db_path=args.db,
        report_dir=args.report_dir,
    )
    print("[sv-rank-event-research] " + " ".join(f"{key}={value}" for key, value in result.items()))


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
    sp.add_argument(
        "--stage",
        choices=["candidates", "transcripts", "extract", "audit", "settle", "score", "export", "all"],
        default="all",
    )
    sp.add_argument("--source", default="x", help="Comma-separated source subset: x,youtube,reddit,xueqiu,toss,all. Default keeps legacy X-only behavior.")
    sp.add_argument("--candidate-limit", type=int, default=50_000, help="0 means insert all recalled candidates.")
    sp.add_argument(
        "--extract-limit",
        type=int,
        default=1_000,
        help="0 means all pending candidates; for --stage audit this caps active X calls.",
    )
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
    sp.add_argument("--youtube-min-subs", type=int, default=2_000, help="Minimum public YouTube subscribers for Score eligibility (shared product threshold).")
    sp.add_argument("--youtube-since-days", type=int, default=365, help="YouTube candidate lookback window.")
    sp.add_argument("--xueqiu-pool-version", default="", help="Versioned selected Xueqiu author pool; empty uses the latest pool.")
    sp.add_argument("--xueqiu-since-days", type=int, default=365, help="Xueqiu candidate lookback window.")
    sp.add_argument("--xueqiu-allow-partial", action="store_true", help="Allow candidate recall before every selected Xueqiu author job is done; disabled by default.")
    sp.add_argument("--force", action="store_true", help="Re-extract candidates already in sv_call.")
    sp.set_defaults(func=cmd_sv_v0)

    sp = sub.add_parser("hyperliquid-smart-money")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument("--output", default=str(root / "web" / "lib" / "data" / "hyperliquidSmartMoney.json"))
    sp.add_argument("--stage", choices=["markets", "wallets", "profiles", "score", "all"], default="all")
    sp.add_argument("--lookback-days", type=int, default=30)
    sp.add_argument("--max-markets", type=int, default=32, help="Highest-volume TradFi HIP-3 markets used for wallet discovery.")
    sp.add_argument("--max-wallets", type=int, default=32, help="Candidate wallets enriched per run, including public account analytics.")
    sp.add_argument("--no-api-pause", action="store_true", help="Disable conservative API pacing for local tests only.")
    sp.add_argument("--client-output-dir", default="", help="Optional contract-fixture/read-model directory for the enriched wallet collections.")
    sp.set_defaults(func=cmd_hyperliquid_smart_money)

    sp = sub.add_parser("hyperliquid-smart-money-live")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument("--output", default=str(root / "web" / "lib" / "data" / "hyperliquidSmartMoney.json"))
    sp.add_argument("--client-output-dir", default=str(root / "data" / "runtime" / "smart-money-live"))
    sp.add_argument("--health-output", default="", help="Atomic worker health JSON; defaults beside live client collections.")
    sp.add_argument("--lookback-days", type=int, default=30)
    sp.add_argument("--refresh-seconds", type=int, default=30)
    sp.add_argument("--publish-seconds", type=int, default=60)
    sp.add_argument(
        "--candidate-backfill",
        type=int,
        default=4,
        help="Highest-activity historical candidate wallets synchronized per catch-up batch.",
    )
    sp.add_argument("--max-active-wallets", type=int, default=8, help="Maximum live wallets per low-latency fill batch.")
    sp.add_argument("--max-profile-wallets", type=int, default=8, help="Oldest qualified profiles refreshed per cycle; 0 refreshes all.")
    sp.add_argument("--profile-refresh-minutes", type=int, default=5, help="Minimum age before a wallet state profile is refreshed again.")
    sp.add_argument("--instrument-refresh-minutes", type=int, default=60, help="Refresh HIP-3 market metadata and live subscriptions without restarting.")
    sp.add_argument("--max-cycles", type=int, default=0, help="0 runs until interrupted.")
    sp.add_argument("--no-api-pause", action="store_true", help="Disable conservative HTTP pacing for local tests only.")
    sp.set_defaults(func=cmd_hyperliquid_smart_money_live)

    sp = sub.add_parser("export-smart-account-read-model")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument("--output-dir", default=str(root / "data" / "runtime" / "read-model-staging"))
    sp.add_argument("--update-days", type=int, default=30)
    sp.add_argument("--update-limit", type=int, default=500)
    sp.add_argument("--profile-limit", type=int, default=0, help="0 exports every qualified ranked author.")
    sp.set_defaults(func=cmd_export_smart_account_read_model)

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

    sp = sub.add_parser("sv-segment-backtest")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument("--report", default=str(root / "data" / "reports" / "sv_segment_backtest" / "sv_segment_backtest.csv"))
    sp.add_argument("--only", default="", help="Comma-separated ticker subset; empty rebuilds the full market.")
    sp.add_argument("--windows", default="3,7,14,30", help="Comma-separated calendar-day signal windows.")
    sp.add_argument("--sources", default="x", help="Comma-separated source keys; the first production study uses X only.")
    sp.add_argument("--segment-types", default="horizon,narrative,investor_type")
    sp.add_argument("--rank-bands", default="top10,top25")
    sp.add_argument("--min-authors", type=int, default=3)
    sp.add_argument("--consensus-threshold", type=float, default=0.65)
    sp.add_argument("--effective-voices", type=float, default=2.5)
    sp.add_argument("--segment-min-n-eff", type=float, default=4.0)
    sp.add_argument("--segment-min-calls", type=int, default=5)
    sp.set_defaults(func=cmd_sv_segment_backtest)

    sp = sub.add_parser("sv-portfolio-backtest")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument(
        "--report-dir",
        default=str(root / "data" / "reports" / "sv_portfolio_backtest"),
    )
    sp.add_argument("--windows", default="1,3,7,14,30")
    sp.add_argument("--holding-days", default="1,5,20,60,90,180")
    sp.add_argument(
        "--position-modes",
        default="long_short,long_only,short_only",
        help="Comma-separated: long_short,long_only,short_only.",
    )
    sp.set_defaults(func=cmd_sv_portfolio_backtest)

    sp = sub.add_parser("sv-rank-event-research")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument(
        "--report-dir",
        default=str(root / "data" / "reports" / "sv_portfolio_backtest"),
    )
    sp.set_defaults(func=cmd_sv_rank_event_research)

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
