"""Core pipeline job-level workflows."""
from __future__ import annotations

from collections.abc import Iterable

from ...domain.market import (
    build_brief as build_brief_domain,
    build_mood,
    build_rollups as build_rollups_domain,
    build_trending as build_trending_domain,
)
from ...domain.narratives.legacy import build_legacy_narratives as build_legacy_narratives_domain
from ...domain.opinions.items import analyze_items as analyze_items_domain
from ...domain.tickers import (
    extract_mentions,
    seed_cn_hk_tickers as seed_cn_hk_tickers_domain,
    seed_us_tickers as seed_us_tickers_domain,
)
from ...domain.translations import translate_legacy_content
from ...platforms.reddit import (
    crawl_author_pool,
    ingest_recent,
    refresh_recent_posts,
    scrape_arctic_comments,
    scrape_arctic_posts,
    scrape_china_posts as scrape_china_posts_platform,
)
from ...platforms.local import load_sample_data as load_sample_data_platform


def init_database() -> None:
    """Initialize database tables."""
    from ...common.db import init_db

    init_db()
    print("[db-init] 建表完成。")


def migrate_database() -> None:
    """Run idempotent database migrations."""
    from ...common.db import migrate_market

    migrate_market()


def seed_us_tickers(*, use_fallback: bool) -> int:
    """Seed US tickers."""
    return seed_us_tickers_domain(use_fallback=use_fallback)


def seed_cn_hk_tickers() -> int:
    """Seed China/Hong Kong tickers."""
    return seed_cn_hk_tickers_domain()


def load_sample_data() -> dict:
    """Load bundled sample data."""
    return load_sample_data_platform()


def ensure_sample_data() -> None:
    """Load sample data when the post table is empty."""
    from sqlalchemy import func, select

    from ...common import models as M
    from ...common.db import session_scope

    with session_scope() as s:
        n = s.execute(select(func.count()).select_from(M.Post)).scalar_one()
    if n == 0:
        print("[ensure-sample] 库内无帖子，载入样本兜底。")
        load_sample_data()
    else:
        print(f"[ensure-sample] 已有 {n} 帖，跳过。")


def ingest_reddit(*, with_comments: bool) -> dict:
    """Ingest recent Reddit content."""
    return ingest_recent(with_comments=with_comments)


def refresh_reddit() -> int:
    """Refresh recent Reddit content."""
    return refresh_recent_posts()


def scrape_reddit_posts(
    *,
    days: int,
    limit_per: int,
    markets: set[str] | None,
) -> dict:
    """Scrape Reddit posts through Arctic Shift."""
    return scrape_arctic_posts(days=days, limit_per=limit_per, markets=markets)


def scrape_china_posts(
    *,
    days: int,
    limit_per: int,
    subs: list[str] | None,
) -> dict:
    """Scrape China-market Reddit posts."""
    return scrape_china_posts_platform(days=days, limit_per=limit_per, subs=subs)


def scrape_reddit_comments(*, top_n: int, per_post: int, min_comments: int) -> dict:
    """Scrape Reddit comments."""
    return scrape_arctic_comments(top_n=top_n, per_post=per_post, min_comments=min_comments)


def crawl_authors(
    *,
    limit: int,
    per_author_cap: int,
    refresh_days: int,
    max_fetch_per: int,
    since_days: int,
    refresh_profiles: bool,
    pool: str,
    min_ticker_posts: int,
    quality_mode: str,
) -> dict:
    """Crawl Reddit author histories."""
    return crawl_author_pool(
        limit=limit,
        per_author_cap=per_author_cap,
        refresh_days=refresh_days,
        max_fetch_per=max_fetch_per,
        since_days=since_days,
        refresh_profiles=refresh_profiles,
        pool=pool,
        min_ticker_posts=min_ticker_posts,
        quality_mode=quality_mode,
    )


def extract_ticker_mentions(*, reextract: bool) -> int:
    """Extract ticker mentions from posts."""
    return extract_mentions(reextract=reextract)


def analyze_items(
    *,
    mock: bool,
    qwen: bool,
    limit: int | None,
    workers: int,
    force: bool,
) -> int:
    """Run item-level analysis."""
    return analyze_items_domain(mock=mock, qwen=qwen, limit=limit, workers=workers, force=force)


def translate_content(*, only: set[str], limit: int | None) -> None:
    """Translate legacy Reddit content fields used by the site."""
    translate_legacy_content(only=only, limit=limit)


def build_rollups(*, markets: Iterable[str]) -> None:
    """Build rollups for one or more markets."""
    for market in markets:
        build_rollups_domain(market=market)


def build_market_mood(*, markets: Iterable[str]) -> None:
    """Build market mood for one or more markets."""
    for market in markets:
        build_mood(market=market)


def build_trending(*, markets: Iterable[str]) -> None:
    """Build trending tickers for one or more markets."""
    for market in markets:
        build_trending_domain(market=market)


def build_legacy_narratives(*, markets: Iterable[str], mock: bool) -> None:
    """Build legacy narrative clusters for one or more markets."""
    for market in markets:
        build_legacy_narratives_domain(mock=mock, market=market)


def build_brief(*, mock: bool) -> str:
    """Build the market brief."""
    return build_brief_domain(mock=mock)


def run_daily_job(*, rebuild: bool) -> None:
    """Run the daily pipeline."""
    from ...daily import run_daily

    run_daily(rebuild=rebuild)


def show_stats() -> None:
    """Print database stats."""
    from sqlalchemy import func, select

    from ...common import models as M
    from ...common.db import session_scope

    with session_scope() as s:
        def count(model):
            return s.execute(select(func.count()).select_from(model)).scalar_one()

        print("==== 表行数 ====")
        for model in M.ALL_TABLES:
            print(f"  {model.__tablename__:18s} {count(model):>6d}")

        print("\n==== 提及最多的 ticker（原始计数 / 加权置信） ====")
        rows = s.execute(
            select(M.Mention.ticker, func.count().label("n"), func.sum(M.Mention.confidence).label("w"))
            .group_by(M.Mention.ticker)
            .order_by(func.count().desc())
            .limit(15)
        ).all()
        for tk, n, w in rows:
            print(f"  {tk:8s} n={n:<4d} weighted={float(w or 0):.2f}")

        ms = s.execute(
            select(M.TickerRollup.ticker, M.TickerRollup.mindshare_pct, M.TickerRollup.sentiment_avg)
            .where(M.TickerRollup.bucket == "window")
            .order_by(M.TickerRollup.mindshare_pct.desc())
            .limit(12)
        ).all()
        if ms:
            total = 0.0
            print("\n==== Mindshare（window，应≈100%） ====")
            for tk, share, sent in ms:
                total += share or 0
                print(f"  {tk:8s} mindshare={share:5.1f}%  sentiment={sent:+.2f}")
            allrows = s.execute(
                select(func.sum(M.TickerRollup.mindshare_pct)).where(M.TickerRollup.bucket == "window")
            ).scalar()
            print(f"  --- 全部 mindshare 合计 = {float(allrows or 0):.1f}% ---")

        mood = s.execute(select(M.MarketMood).where(M.MarketMood.bucket == "window").limit(1)).scalars().first()
        if mood:
            print(
                f"\n==== 市场情绪 ====\n  {mood.label}  mood={mood.mood_score:+.2f}  "
                f"多{mood.bull_pct:.0f}% / 空{mood.bear_pct:.0f}% / 中{mood.neutral_pct:.0f}%"
            )


def cloud_push() -> None:
    """Push the local database snapshot to cloud storage."""
    from ...sync import push

    push()


def cloud_pull() -> None:
    """Pull the cloud database snapshot into the local environment."""
    from ...sync import pull

    pull()
