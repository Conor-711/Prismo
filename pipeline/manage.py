"""统一 CLI 入口（被 Makefile 调用）。各子命令惰性导入，便于增量开发。

用法： python -m pipeline.manage <command> [options]
"""
from __future__ import annotations

import argparse
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def cmd_db_init(args):
    from .common.db import init_db
    init_db()
    print("[db-init] 建表完成。")


def cmd_migrate(args):
    """把已有库迁移到带 market 维度的新 schema（幂等）。"""
    from .common.db import migrate_market
    migrate_market()


def cmd_seed(args):
    from .ingest.seed_tickers import seed_tickers
    seed_tickers(use_fallback=args.fallback)


def cmd_seed_cn_hk(args):
    from .ingest.seed_tickers import seed_cn_hk
    seed_cn_hk()


def cmd_load_sample(args):
    from .ingest.sample_loader import load_sample
    load_sample()


def cmd_ensure_sample(args):
    """若库内无帖子（如真实爬取失败），用样本兜底，保证站点不空。"""
    from sqlalchemy import func, select
    from .common.db import session_scope
    from .common.models import Post
    with session_scope() as s:
        n = s.execute(select(func.count()).select_from(Post)).scalar_one()
    if n == 0:
        print("[ensure-sample] 库内无帖子，载入样本兜底。")
        from .ingest.sample_loader import load_sample
        load_sample()
    else:
        print(f"[ensure-sample] 已有 {n} 帖，跳过。")


def cmd_ingest(args):
    from .ingest.reddit_ingest import ingest_once
    ingest_once(with_comments=not args.no_comments)


def cmd_refresh(args):
    from .ingest.refresh import refresh_recent
    refresh_recent()


def cmd_scrape(args):
    from .ingest.arctic_scrape import scrape
    markets = {m.strip() for m in args.markets.split(",")} if getattr(args, "markets", None) else None
    scrape(days=args.days, limit_per=args.limit, markets=markets)


def cmd_scrape_china(args):
    """关键词/ticker 过滤扫描综合中国社区，引入 A 股(沪深)等中国股市内容。"""
    from .ingest.arctic_scrape import scrape_china_filtered
    subs = [x.strip() for x in args.subs.split(",")] if getattr(args, "subs", None) else None
    scrape_china_filtered(days=args.days, limit_per=args.limit, subs=subs)


def cmd_scrape_comments(args):
    from .ingest.arctic_scrape import scrape_comments
    scrape_comments(top_n=args.top, per_post=args.per_post, min_comments=args.min_comments)


def cmd_crawl_authors(args):
    """作者库：爬「实力榜」Top 作者历史帖（两级漏斗：DeepSeek 粗筛 → 千问深析）。"""
    from .ingest.author_crawl import crawl_top_authors
    crawl_top_authors(limit=args.limit, per_author_cap=args.per_author, refresh_days=args.refresh_days)


def cmd_extract(args):
    from .ingest.ticker_extract import extract_for_posts
    extract_for_posts(reextract=args.reextract)


def cmd_analyze(args):
    from .analyze.item_analyze import run_analyze
    run_analyze(mock=args.mock, qwen=getattr(args, "qwen", False), limit=args.limit,
                workers=getattr(args, "workers", 8), force=getattr(args, "force", False))


def _markets_arg(args) -> list[str]:
    """--market us|cn|all（默认 all = 美股 + 中概港股各跑一次）。"""
    mk = getattr(args, "market", "all") or "all"
    return ["us", "cn"] if mk == "all" else [mk]


def cmd_rollup(args):
    from .analyze.rollups import run_rollups
    for mk in _markets_arg(args):
        run_rollups(market=mk)


def cmd_mood(args):
    from .analyze.market_mood import run_market_mood
    for mk in _markets_arg(args):
        run_market_mood(market=mk)


def cmd_trending(args):
    from .analyze.trending import run_trending
    for mk in _markets_arg(args):
        run_trending(market=mk)


def cmd_narratives(args):
    from .analyze.narratives import run_narratives
    for mk in _markets_arg(args):
        run_narratives(mock=args.mock, market=mk)


def cmd_brief(args):
    from .analyze.brief import run_brief
    run_brief(mock=args.mock)


def cmd_daily(args):
    """每日一次：分析过去 24 小时（UTC+8 08:00 跑）。--rebuild 同时重建静态站点。"""
    from .daily import run_daily
    run_daily(rebuild=args.rebuild)


def cmd_stats(args):
    from sqlalchemy import func, select
    from .common.db import session_scope
    from .common import models as M

    with session_scope() as s:
        def count(model):
            return s.execute(select(func.count()).select_from(model)).scalar_one()

        print("==== 表行数 ====")
        for model in M.ALL_TABLES:
            print(f"  {model.__tablename__:18s} {count(model):>6d}")

        print("\n==== 提及最多的 ticker（原始计数 / 加权置信） ====")
        rows = s.execute(
            select(M.Mention.ticker, func.count().label("n"), func.sum(M.Mention.confidence).label("w"))
            .group_by(M.Mention.ticker).order_by(func.count().desc()).limit(15)
        ).all()
        for tk, n, w in rows:
            print(f"  {tk:8s} n={n:<4d} weighted={float(w or 0):.2f}")

        ms = s.execute(
            select(M.TickerRollup.ticker, M.TickerRollup.mindshare_pct, M.TickerRollup.sentiment_avg)
            .where(M.TickerRollup.bucket == "window").order_by(M.TickerRollup.mindshare_pct.desc()).limit(12)
        ).all()
        if ms:
            total = 0.0
            print("\n==== Mindshare（window，应≈100%） ====")
            for tk, share, sent in ms:
                total += share or 0
                print(f"  {tk:8s} mindshare={share:5.1f}%  sentiment={sent:+.2f}")
            allrows = s.execute(select(func.sum(M.TickerRollup.mindshare_pct)).where(M.TickerRollup.bucket == "window")).scalar()
            print(f"  --- 全部 mindshare 合计 = {float(allrows or 0):.1f}% ---")

        mood = s.execute(select(M.MarketMood).where(M.MarketMood.bucket == "window").limit(1)).scalars().first()
        if mood:
            print(f"\n==== 市场情绪 ====\n  {mood.label}  mood={mood.mood_score:+.2f}  "
                  f"多{mood.bull_pct:.0f}% / 空{mood.bear_pct:.0f}% / 中{mood.neutral_pct:.0f}%")


def cmd_cloud_push(args):
    from .sync import push
    push()


def cmd_cloud_pull(args):
    from .sync import pull
    pull()


# ----------------------------- 亚洲散户舆情实验（日 Yahoo / 韩 Naver，隔离表） -----------------------------
def cmd_asia_crawl(args):
    from .ingest.asia_crawl import crawl
    markets = {m.strip() for m in args.markets.split(",")} if getattr(args, "markets", None) else None
    crawl(per_board=args.per_board, sample_fallback=not args.no_sample, markets=markets,
          since_days=args.since_days)


def cmd_asia_analyze(args):
    from .analyze.asia_analyze import run_asia_analyze
    run_asia_analyze(limit_per=args.limit_per, mock=args.mock, workers=args.workers)


def cmd_asia_summarize(args):
    from .analyze.asia_analyze import summarize_asia
    summarize_asia(mock=args.mock)


def cmd_asia_score(args):
    from .analyze.asia_analyze import score_all_flash
    score_all_flash(batch_size=args.batch, workers=args.workers, only_new=not args.force)


def cmd_asia_price(args):
    from .ingest.asia_price import fetch_prices
    fetch_prices(days=args.days)


# ----------------------------- 全球散户多区看板（US Reddit 复用 + 日韩台新爬，隔离表 gr_*） -----------------------------
def cmd_gr_crawl(args):
    from .ingest.global_retail_crawl import crawl
    regions = {m.strip() for m in args.regions.split(",")} if getattr(args, "regions", None) else None
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    crawl(per_board=args.per_board, since_days=args.since_days, regions=regions, only=only)


def cmd_gr_tag(args):
    from .analyze.global_retail_tag import tag_all
    tag_all(batch_size=args.batch, workers=args.workers, only_new=not args.force)


def cmd_gr_rollup(args):
    from .analyze.global_retail_rollup import rollup
    rollup(window_days=args.window_days)


def cmd_gr_xueqiu(args):
    # 雪球(中国大陆)讨论经 Claude-in-Chrome 浏览器过 WAF 导出为 JSON，这里收进 gr_post(region=cn)。
    from .ingest.global_retail_xueqiu import ingest
    ingest(path=args.path, since_days=args.since_days)


def cmd_gr_quote(args):
    # 各 gr 标的最新价（Yahoo 15m chart）→ gr_quote，供标的页展示最新价/涨跌幅。
    from .ingest.gr_quote import fetch_quotes
    fetch_quotes()


def cmd_toss(args):
    # Toss(토스증권) 종목 커뮤니티评论 → gr_post(source='toss', region='kr')。游标翻页 RECENT。
    from .ingest.toss import crawl
    only = [t.strip().upper() for t in args.only.split(",")] if getattr(args, "only", None) else None
    crawl(days=args.days, only=only, max_pages=args.max_pages)


def cmd_youtube_crawl(args):
    # YouTube 观点：按标的搜近 24h、浏览量>阈值的视频 → yt_video（全语种）。缺 key/--mock 出样本。
    from .ingest.youtube_crawl import crawl
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    crawl(only=only, since_hours=args.since_hours, min_views=args.min_views, mock=args.mock)


def cmd_yt_channels(args):
    # YouTube 频道作者基础信息（粉丝/视频/简介）→ 本地 yt_channel。Data API channels.list；需 YOUTUBE_API_KEY。
    from .ingest.youtube_channels import main as run
    run()


def cmd_youtube_tag(args):
    # 混合分析（top N 原生看视频 + 其余字幕）→ yt_analysis + 聚合 yt_ticker_summary。缺 key/--mock 出样本。
    from .analyze.youtube_analyze import tag
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    tag(top_native=args.top_native, only_new=not args.force, mock=args.mock,
        per_ticker_cap=args.per_ticker, workers=args.workers, only=only)


def cmd_youtube_tag_text(args):
    # 无 Gemini 配额兜底：标题+简介 → DeepSeek flash 出双语观点 → yt_analysis(mode=text)。
    from .analyze.youtube_analyze import tag_text
    tag_text(per_ticker=args.per_ticker, workers=args.workers)


def cmd_youtube_fulltext(args):
    # Gemini 真看视频 → 完整内容还原（优化字幕+关键画面）→ yt_fulltext。
    from .analyze.youtube_analyze import gen_fulltext
    only = {t.strip() for t in args.only.split(",")} if getattr(args, "only", None) else None
    gen_fulltext(only=only, per_ticker=args.per_ticker, workers=args.workers,
                 force=args.force, low_res=args.low_res, frames=not getattr(args, "no_frames", False))


def cmd_youtube_digest(args):
    # YouTube 完整口播 → 投资者摘要 + 内容目录(章节) → 本地 yt_digest（LOW 档读文本，不重看视频）。
    from .analyze.youtube_digest import run
    run(force=args.force, only={t.strip() for t in args.only.split(",")} if getattr(args, "only", None) else None)


def cmd_youtube_judgment(args):
    # 从已有 yt_analysis 观点/论据抽「时间周期/目标价/关键位置」→ 本地 yt_judgment（LOW 档纯文本，不重看视频）。
    from .analyze.youtube_judgment import run
    run(force=args.force, workers=args.workers,
        only={t.strip().upper() for t in args.only.split(",")} if getattr(args, "only", None) else None)


def cmd_youtube_creator_view(args):
    # 把同一博主对同一标的的多条视频判断综合成「整体立场+几点关键判断」→ 本地 yt_creator_view（LOW 档，不重看视频）。
    from .analyze.youtube_creator_view import run
    run(force=args.force, workers=args.workers,
        only={t.strip().upper() for t in args.only.split(",")} if getattr(args, "only", None) else None)


def cmd_kol_refine(args):
    # KOL 个体观点 AI 提炼+双语（reddit/x/xueqiu 文本源）→ kol_refined。YouTube 复用 yt_analysis。
    from .analyze.kol_refine import refine
    sources = [t.strip() for t in args.source.split(",")] if getattr(args, "source", None) else None
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    refine(sources=sources, per_source=args.per_source, only=only, force=args.force,
           workers=args.workers, since_days=args.since_days)


def cmd_kol_viewpoint(args):
    # KOL 个体观点 视角分类（7 选 1-3）→ kol_viewpoint。读已蒸馏的 kol_refined + yt_analysis。
    from .analyze.kol_viewpoint import classify
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    classify(only=only, force=args.force, workers=args.workers,
             reclassify_other=getattr(args, "reclassify_other", False))


def cmd_kol_judgment(args):
    # KOL 目标价+操作周期 抽取（reddit/x/xueqiu 原帖文本，只抽明说）→ kol_judgment。YouTube 复用 yt_judgment。
    from .analyze.kol_judgment import run
    sources = [t.strip() for t in args.source.split(",")] if getattr(args, "source", None) else None
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    run(sources=sources, per_source=args.per_source, only=only, force=args.force,
        workers=args.workers, since_days=args.since_days)


def cmd_tw_sentiment(args):
    # X 推文情绪打分（DeepSeek/qwen flash 批量）→ 云端 tw_tweet_sentiment。供 KOL 每日净情绪 rollup。
    from .analyze.tweet_sentiment import score
    score(batch_size=args.batch, workers=args.workers, only_new=not args.force, limit=args.limit)


def cmd_kol_sentiment(args):
    # KOL 每日净情绪 rollup：跨平台 情绪×ln(1+互动)×相关性 → 本地 kol_sentiment_daily（绿/红面积子面板）。
    from .analyze.kol_sentiment import rollup
    rollup()


def cmd_kol_volume(args):
    # KOL 每日讨论度 rollup：跨平台帖子/视频计数 → 本地 kol_volume_daily（条状子面板）。
    from .analyze.kol_volume import rollup
    rollup()


def cmd_retail_sentiment(args):
    # 整体散户 每日净情绪 rollup：全量散户 + 本土论坛(Naver/YahooJP/PTT)、不含 YouTube → 本地 retail_sentiment_daily。
    from .analyze.retail_sentiment import rollup
    rollup()


def cmd_retail_volume(args):
    # 整体散户 每日讨论度 rollup：全量散户 + 本土论坛、不含 YouTube → 本地 retail_volume_daily（条状子面板）。
    from .analyze.retail_volume import rollup
    rollup()


def cmd_retail_newcomers(args):
    # 整体散户 每日『新增散户』rollup：各平台首次参与该标的讨论的去重作者数（不含 X/YouTube）→ 本地 retail_newcomers_daily。
    from .analyze.retail_newcomers import rollup
    rollup()


def cmd_kol_newcomers(args):
    # KOL 每日『新增 KOL』rollup：X/YouTube/雪球（有身份/粉丝象征）首次参与该标的讨论的去重作者数 → 本地 kol_newcomers_daily。
    from .analyze.kol_newcomers import rollup
    rollup()


def cmd_overall_signals(args):
    # 整体数据『异动归因 + 讨论方面 + 聪明钱↔散户分歧 + 新叙事』（仅 KOL）→ web/lib/data/overallData.json。需 QWEN_API_KEY。
    from .analyze.overall_signals import run
    kol_file = args.kol_file or f"/tmp/{args.ticker.lower()}_x6m.jsonl"
    run(args.ticker.upper(), kol_file, args.window, args.look, args.aspect_days, args.cap,
        args.skill_dir, args.recent_days, args.prior_days)


def cmd_narrative_rotation(args):
    # 跨社区固定叙事轮动 → web/lib/data/narrativeRotation.json。读 gr_post/Reddit/X/YouTube，不用旧 narratives 表。
    from .analyze.narrative_rotation import build
    build(db_path=args.db, out_path=args.out, window_days=args.window_days, recent_days=args.recent_days)


def cmd_kol_argument(args):
    # KOL 论点综合（每 标的×视角×立场 聚成 1-3 个论点）→ kol_argument。读 kol_refined+kol_viewpoint+yt_analysis。
    from .analyze.kol_argument import synthesize
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    synthesize(only=only, force=args.force, workers=args.workers)


def cmd_kol_translate(args):
    # KOL 原帖完整忠实翻译（逐句直译、不压缩）→ kol_refined.trans_zh/en。供「按视角·原帖流」的「译」选项。
    from .analyze.kol_translate import translate
    sources = [t.strip() for t in args.source.split(",")] if getattr(args, "source", None) else None
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    translate(sources=sources, per_source=args.per_source, only=only, force=args.force,
              workers=args.workers, since_days=args.since_days)


def cmd_kol_relevance(args):
    # KOL 相关性打分（每条帖文/视频 与标的的相关度 0-100）→ kol_relevance。供『按相关性』排序。
    from .analyze.kol_relevance import score
    sources = [t.strip() for t in args.source.split(",")] if getattr(args, "source", None) else None
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    score(sources=sources, per_source=args.per_source, only=only, force=args.force,
          workers=args.workers, since_days=args.since_days, include_youtube=not args.no_youtube)


def cmd_kol_quality(args):
    # KOL 帖子质量打分（每条帖文/视频本身的含金量 0-100，与标的无关）→ kol_quality。供『只看高质量』开关。
    from .analyze.kol_quality import score
    sources = [t.strip() for t in args.source.split(",")] if getattr(args, "source", None) else None
    only = [t.strip() for t in args.only.split(",")] if getattr(args, "only", None) else None
    score(sources=sources, per_source=args.per_source, only=only, force=args.force,
          workers=args.workers, since_days=args.since_days, include_youtube=not args.no_youtube)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="pipeline.manage")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("db-init").set_defaults(func=cmd_db_init)
    sub.add_parser("migrate").set_defaults(func=cmd_migrate)

    sp = sub.add_parser("seed-tickers"); sp.add_argument("--fallback", action="store_true"); sp.set_defaults(func=cmd_seed)
    sub.add_parser("seed-cn-hk").set_defaults(func=cmd_seed_cn_hk)
    sub.add_parser("load-sample").set_defaults(func=cmd_load_sample)
    sub.add_parser("ensure-sample").set_defaults(func=cmd_ensure_sample)

    sp = sub.add_parser("ingest"); sp.add_argument("--once", action="store_true"); sp.add_argument("--no-comments", action="store_true"); sp.set_defaults(func=cmd_ingest)
    sub.add_parser("refresh").set_defaults(func=cmd_refresh)
    sp = sub.add_parser("scrape"); sp.add_argument("--days", type=int, default=3); sp.add_argument("--limit", type=int, default=300); sp.add_argument("--markets", type=str, default=None, help="逗号分隔，如 us,cn；省略=全部"); sp.set_defaults(func=cmd_scrape)
    sp = sub.add_parser("scrape-china"); sp.add_argument("--days", type=int, default=30); sp.add_argument("--limit", type=int, default=300); sp.add_argument("--subs", type=str, default=None, help="逗号分隔的来源版块；省略=默认综合中国社区"); sp.set_defaults(func=cmd_scrape_china)
    sp = sub.add_parser("scrape-comments"); sp.add_argument("--top", type=int, default=400); sp.add_argument("--per-post", type=int, default=15); sp.add_argument("--min-comments", type=int, default=4); sp.set_defaults(func=cmd_scrape_comments)
    sp = sub.add_parser("crawl-authors"); sp.add_argument("--limit", type=int, default=50, help="爬实力榜 Top N 作者"); sp.add_argument("--per-author", type=int, default=20, help="每位作者最多并入作者库篇数"); sp.add_argument("--refresh-days", type=int, default=7, help="距上次爬取超过几天才重爬"); sp.set_defaults(func=cmd_crawl_authors)
    sp = sub.add_parser("extract"); sp.add_argument("--reextract", action="store_true"); sp.set_defaults(func=cmd_extract)

    sp = sub.add_parser("analyze"); sp.add_argument("--mock", action="store_true"); sp.add_argument("--qwen", action="store_true"); sp.add_argument("--force", action="store_true"); sp.add_argument("--workers", type=int, default=8); sp.add_argument("--limit", type=int, default=None); sp.set_defaults(func=cmd_analyze)
    sp = sub.add_parser("rollup"); sp.add_argument("--market", type=str, default="all", help="us|cn|all"); sp.set_defaults(func=cmd_rollup)
    sp = sub.add_parser("mood"); sp.add_argument("--market", type=str, default="all"); sp.set_defaults(func=cmd_mood)
    sp = sub.add_parser("trending"); sp.add_argument("--market", type=str, default="all"); sp.set_defaults(func=cmd_trending)
    sp = sub.add_parser("narratives"); sp.add_argument("--mock", action="store_true"); sp.add_argument("--market", type=str, default="all"); sp.set_defaults(func=cmd_narratives)
    sp = sub.add_parser("brief"); sp.add_argument("--mock", action="store_true"); sp.set_defaults(func=cmd_brief)
    sp = sub.add_parser("daily"); sp.add_argument("--rebuild", action="store_true"); sp.set_defaults(func=cmd_daily)
    sub.add_parser("stats").set_defaults(func=cmd_stats)
    sub.add_parser("cloud-push").set_defaults(func=cmd_cloud_push)
    sub.add_parser("cloud-pull").set_defaults(func=cmd_cloud_pull)

    # 亚洲散户舆情实验
    sp = sub.add_parser("asia-crawl"); sp.add_argument("--per-board", type=int, default=200); sp.add_argument("--since-days", type=int, default=7, help="只爬近 N 天（0=不限）"); sp.add_argument("--no-sample", action="store_true"); sp.add_argument("--markets", type=str, default=None, help="逗号分隔 jp,kr；省略=全部"); sp.set_defaults(func=cmd_asia_crawl)
    sp = sub.add_parser("asia-analyze"); sp.add_argument("--mock", action="store_true"); sp.add_argument("--limit-per", type=int, default=12, help="每格(市场×标的)最多分析帖数"); sp.add_argument("--workers", type=int, default=6); sp.set_defaults(func=cmd_asia_analyze)
    sp = sub.add_parser("asia-summarize"); sp.add_argument("--mock", action="store_true"); sp.set_defaults(func=cmd_asia_summarize)
    sp = sub.add_parser("asia-score"); sp.add_argument("--batch", type=int, default=12); sp.add_argument("--workers", type=int, default=8); sp.add_argument("--force", action="store_true", help="重打全部（默认只打未打分的）"); sp.set_defaults(func=cmd_asia_score)
    sp = sub.add_parser("asia-price"); sp.add_argument("--days", type=int, default=14); sp.set_defaults(func=cmd_asia_price)

    # 全球散户多区看板（gr-*）
    sp = sub.add_parser("gr-crawl"); sp.add_argument("--per-board", type=int, default=120); sp.add_argument("--since-days", type=int, default=14); sp.add_argument("--regions", type=str, default=None, help="逗号分隔 jp,kr,tw；省略=全部"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker（调试用）"); sp.set_defaults(func=cmd_gr_crawl)
    sp = sub.add_parser("gr-tag"); sp.add_argument("--batch", type=int, default=15); sp.add_argument("--workers", type=int, default=8); sp.add_argument("--force", action="store_true", help="重打全部（默认只打未打的）"); sp.set_defaults(func=cmd_gr_tag)
    sp = sub.add_parser("gr-rollup"); sp.add_argument("--window-days", type=int, default=14); sp.set_defaults(func=cmd_gr_rollup)
    sp = sub.add_parser("gr-xueqiu"); sp.add_argument("--path", type=str, default="data/exports/gr_cn_xueqiu.json", help="浏览器导出的雪球帖 JSON"); sp.add_argument("--since-days", type=int, default=14); sp.set_defaults(func=cmd_gr_xueqiu)
    sub.add_parser("gr-quote").set_defaults(func=cmd_gr_quote)
    sp = sub.add_parser("toss"); sp.add_argument("--days", type=int, default=14, help="爬近 N 天"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker（省略=TOSS_STOCKS 全部）"); sp.add_argument("--max-pages", type=int, default=1500, help="每标的最多翻页数（每页 11 条）"); sp.set_defaults(func=cmd_toss)
    sp = sub.add_parser("youtube-crawl"); sp.add_argument("--since-hours", type=int, default=24); sp.add_argument("--min-views", type=int, default=None, help="浏览量门槛，省略=用 YT_MIN_VIEWS(默认1000)"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--mock", action="store_true", help="无 key 时生成多语种样本"); sp.set_defaults(func=cmd_youtube_crawl)
    sub.add_parser("yt-channels").set_defaults(func=cmd_yt_channels)
    sp = sub.add_parser("youtube-tag"); sp.add_argument("--top-native", type=int, default=2, help="每标的用 Gemini 原生看视频的前 N 条（其余走字幕）"); sp.add_argument("--per-ticker", type=int, default=None, help="每标的最多分析前 N 条(按播放量)；省略=全部。配合 8h/天预算用，按档位跨标的铺开"); sp.add_argument("--force", action="store_true", help="重分析全部（默认只分析未分析的）"); sp.add_argument("--workers", type=int, default=1, help="并发线程数(>1 走并发真看视频，billing 解锁 8h 后用)"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker，只跑这些（如前十讨论度）"); sp.add_argument("--mock", action="store_true"); sp.set_defaults(func=cmd_youtube_tag)
    sp = sub.add_parser("youtube-tag-text"); sp.add_argument("--per-ticker", type=int, default=20, help="每标的按播放量取前 N（默认 20=前端 LIMIT）"); sp.add_argument("--workers", type=int, default=6, help="LLM 并发数"); sp.set_defaults(func=cmd_youtube_tag_text)
    sp = sub.add_parser("youtube-fulltext"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker，只跑这些（如 PLTR）"); sp.add_argument("--per-ticker", type=int, default=10, help="每标的按播放量取前 N"); sp.add_argument("--workers", type=int, default=4); sp.add_argument("--low-res", action="store_true", help="低清看视频(省 token，图表细节略差)"); sp.add_argument("--no-frames", action="store_true", help="只出优化口播、不抽关键画面帧(快、免下载)"); sp.add_argument("--force", action="store_true", help="重生成已有的"); sp.set_defaults(func=cmd_youtube_fulltext)
    sp = sub.add_parser("youtube-digest"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 video_id"); sp.add_argument("--force", action="store_true", help="重跑已有的"); sp.set_defaults(func=cmd_youtube_digest)
    sp = sub.add_parser("youtube-judgment"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--workers", type=int, default=8, help="LLM 并发数"); sp.add_argument("--force", action="store_true", help="重抽已有的"); sp.set_defaults(func=cmd_youtube_judgment)
    sp = sub.add_parser("youtube-creator-view"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--workers", type=int, default=8, help="LLM 并发数"); sp.add_argument("--force", action="store_true", help="重综合已有的"); sp.set_defaults(func=cmd_youtube_creator_view)
    sp = sub.add_parser("kol-refine"); sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu；省略=全部"); sp.add_argument("--per-source", type=int, default=40, help="每标的每源提炼前 N 条(按互动)，默认 40=前端各源 LIMIT"); sp.add_argument("--since-days", type=int, default=20, help="只提炼近 N 天(匹配前端价格窗口)；0=不限"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--workers", type=int, default=6, help="LLM 并发数"); sp.add_argument("--force", action="store_true", help="重提炼全部（默认只补未提炼的）"); sp.set_defaults(func=cmd_kol_refine)
    sp = sub.add_parser("kol-viewpoint"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--workers", type=int, default=8, help="LLM 并发数"); sp.add_argument("--force", action="store_true", help="重分类全部（默认只补未分类的）"); sp.add_argument("--reclassify-other", action="store_true", help="只重判当前 other 行（用新 prompt 把实质观点归到正确视角）"); sp.set_defaults(func=cmd_kol_viewpoint)
    sp = sub.add_parser("kol-judgment"); sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu；省略=全部"); sp.add_argument("--per-source", type=int, default=40, help="每标的每源前 N 条(镜像提炼/展示范围)"); sp.add_argument("--since-days", type=int, default=90, help="只抽近 N 天（默认 90=时间线窗口）；0=不限"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--workers", type=int, default=6, help="LLM 并发数"); sp.add_argument("--force", action="store_true", help="重抽全部（默认只补未抽的）"); sp.set_defaults(func=cmd_kol_judgment)
    sp = sub.add_parser("tw-sentiment"); sp.add_argument("--batch", type=int, default=20, help="每次 LLM 打多少条"); sp.add_argument("--workers", type=int, default=8, help="LLM 并发数"); sp.add_argument("--limit", type=int, default=None, help="只打前 N（调试）"); sp.add_argument("--force", action="store_true", help="重打全部（默认只打未打分的）"); sp.set_defaults(func=cmd_tw_sentiment)
    sub.add_parser("kol-sentiment").set_defaults(func=cmd_kol_sentiment)
    sub.add_parser("kol-volume").set_defaults(func=cmd_kol_volume)
    sub.add_parser("retail-sentiment").set_defaults(func=cmd_retail_sentiment)
    sub.add_parser("retail-volume").set_defaults(func=cmd_retail_volume)
    sub.add_parser("retail-newcomers").set_defaults(func=cmd_retail_newcomers)
    sub.add_parser("kol-newcomers").set_defaults(func=cmd_kol_newcomers)
    sp = sub.add_parser("overall-signals"); sp.add_argument("--ticker", default="PLTR"); sp.add_argument("--kol-file", default=None, help="KOL 推文抽取 jsonl；默认 /tmp/<ticker>_x6m.jsonl"); sp.add_argument("--window", type=int, default=11); sp.add_argument("--look", type=int, default=14); sp.add_argument("--aspect-days", type=int, default=14); sp.add_argument("--cap", type=int, default=3); sp.add_argument("--skill-dir", default="/tmp", help="技能 z / stance 缓存目录"); sp.add_argument("--recent-days", type=int, default=7); sp.add_argument("--prior-days", type=int, default=21); sp.set_defaults(func=cmd_overall_signals)
    sp = sub.add_parser("narrative-rotation"); sp.add_argument("--db", default=str(ROOT / "data" / "dev.db")); sp.add_argument("--out", default=str(ROOT / "web" / "lib" / "data" / "narrativeRotation.json")); sp.add_argument("--window-days", type=int, default=21); sp.add_argument("--recent-days", type=int, default=7); sp.set_defaults(func=cmd_narrative_rotation)
    sp = sub.add_parser("kol-argument"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--workers", type=int, default=8, help="LLM 并发数"); sp.add_argument("--force", action="store_true", help="重综合全部（默认只补未综合的 标的×视角×立场 组）"); sp.set_defaults(func=cmd_kol_argument)
    sp = sub.add_parser("kol-translate"); sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu；省略=全部"); sp.add_argument("--per-source", type=int, default=40, help="每标的每源前 N 条(镜像提炼/展示范围)"); sp.add_argument("--since-days", type=int, default=20, help="只译近 N 天；0=不限"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--workers", type=int, default=6, help="LLM 并发数"); sp.add_argument("--force", action="store_true", help="重译全部（默认只补未译的）"); sp.set_defaults(func=cmd_kol_translate)
    sp = sub.add_parser("kol-relevance"); sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu；省略=全部(+youtube)"); sp.add_argument("--per-source", type=int, default=200, help="每标的每源前 N 条(镜像展示范围)"); sp.add_argument("--since-days", type=int, default=30, help="只打近 N 天；0=不限"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--workers", type=int, default=8, help="LLM 并发数"); sp.add_argument("--no-youtube", action="store_true", help="跳过 youtube 源"); sp.add_argument("--force", action="store_true", help="重打全部（默认只补未打分的）"); sp.set_defaults(func=cmd_kol_relevance)
    sp = sub.add_parser("kol-quality"); sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu；省略=全部(+youtube)"); sp.add_argument("--per-source", type=int, default=800, help="每标的每源前 N 条(镜像展示范围；质量按 source+item 去重)"); sp.add_argument("--since-days", type=int, default=35, help="只打近 N 天；0=不限"); sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker"); sp.add_argument("--workers", type=int, default=8, help="LLM 并发数"); sp.add_argument("--no-youtube", action="store_true", help="跳过 youtube 源"); sp.add_argument("--force", action="store_true", help="重打全部（默认只补未打分的）"); sp.set_defaults(func=cmd_kol_quality)
    return p


def main():
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
