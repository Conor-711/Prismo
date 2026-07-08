"""Compatibility wrapper for Reddit author-pool crawling."""
from __future__ import annotations

from ..platforms.reddit.authors import (
    crawl_top_authors,
    fetch_author,
    prescreen_quality,
    refresh_author_profiles,
    repeat_ticker_authors,
    top_authors,
)

__all__ = [
    "crawl_top_authors",
    "fetch_author",
    "prescreen_quality",
    "refresh_author_profiles",
    "repeat_ticker_authors",
    "top_authors",
]


if __name__ == "__main__":
    import sys

    n = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    crawl_top_authors(limit=n)
