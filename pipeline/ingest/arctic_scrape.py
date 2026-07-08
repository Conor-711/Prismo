"""Compatibility wrapper for Reddit Arctic Shift crawling."""
from __future__ import annotations

from ..platforms.reddit.arctic import (
    fetch_comments,
    fetch_subreddit,
    scrape,
    scrape_china_filtered,
    scrape_comments,
)

__all__ = [
    "fetch_comments",
    "fetch_subreddit",
    "scrape",
    "scrape_china_filtered",
    "scrape_comments",
]


if __name__ == "__main__":
    scrape()
