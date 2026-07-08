"""Reddit and Arctic Shift platform operations."""
from __future__ import annotations


def ingest_recent(*, with_comments: bool) -> dict:
    """Ingest recent Reddit posts and optionally comments."""
    from .realtime import ingest_once

    return ingest_once(with_comments=with_comments)


def refresh_recent_posts() -> int:
    """Refresh recent Reddit posts."""
    from .refresh import refresh_recent

    return refresh_recent()


def scrape_arctic_posts(
    *,
    days: int,
    limit_per: int,
    markets: set[str] | None,
) -> dict:
    """Scrape Reddit posts through Arctic Shift."""
    from .arctic import scrape

    return scrape(days=days, limit_per=limit_per, markets=markets)


def scrape_china_posts(
    *,
    days: int,
    limit_per: int,
    subs: list[str] | None,
) -> dict:
    """Scrape China-market posts through Arctic Shift filters."""
    from .arctic import scrape_china_filtered

    return scrape_china_filtered(days=days, limit_per=limit_per, subs=subs)


def scrape_arctic_comments(*, top_n: int, per_post: int, min_comments: int) -> dict:
    """Scrape Reddit comments for top posts."""
    from .arctic import scrape_comments

    return scrape_comments(top_n=top_n, per_post=per_post, min_comments=min_comments)


def crawl_author_pool(
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
    """Crawl Reddit author histories for the KOL author pool."""
    from .authors import crawl_top_authors

    return crawl_top_authors(
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
