"""X/Twitter ingestion adapters."""
from __future__ import annotations


def match_tweet_topics(*, page: int, batch: int) -> None:
    """Rebuild the hard-matched tweet-to-topic table."""
    from .ticker_match import run

    run(page=page, batch=batch)
