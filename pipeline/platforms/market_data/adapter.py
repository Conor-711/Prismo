"""Market data ingestion adapters."""
from __future__ import annotations


def backfill_price_history(
    *,
    db: str,
    start: str,
    end: str | None,
    top_n: int,
    min_count: int,
    tweet_dirs: list[str] | None,
    only: str,
    sleep: float,
    workers: int,
    limit: int,
) -> None:
    """Backfill daily OHLC prices for Smart Account scoring."""
    from .price_history import run

    run(
        db=db,
        start=start,
        end=end,
        top_n=top_n,
        min_count=min_count,
        tweet_dir=tweet_dirs,
        only=only,
        sleep=sleep,
        workers=workers,
        limit=limit,
    )
