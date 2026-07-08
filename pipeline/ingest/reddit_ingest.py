"""Compatibility wrapper for Reddit realtime ingestion."""
from __future__ import annotations

from ..platforms.reddit.realtime import (
    ingest_once,
    load_subreddit_config,
    store_mentions,
    upsert_author,
    upsert_post,
    upsert_subreddit,
)

__all__ = [
    "ingest_once",
    "load_subreddit_config",
    "store_mentions",
    "upsert_author",
    "upsert_post",
    "upsert_subreddit",
]


if __name__ == "__main__":
    ingest_once()
