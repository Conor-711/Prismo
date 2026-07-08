"""Reddit platform adapter."""

from .adapter import (
    crawl_author_pool,
    ingest_recent,
    refresh_recent_posts,
    scrape_arctic_comments,
    scrape_arctic_posts,
    scrape_china_posts,
)

__all__ = [
    "crawl_author_pool",
    "ingest_recent",
    "refresh_recent_posts",
    "scrape_arctic_comments",
    "scrape_arctic_posts",
    "scrape_china_posts",
]

