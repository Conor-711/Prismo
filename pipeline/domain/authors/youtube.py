"""YouTube author-domain workflows."""
from __future__ import annotations

from pathlib import Path

from .youtube_pool import PoolSummary, build_pool


def build_creator_view(*, force: bool, only: set[str] | None, workers: int) -> int:
    """Aggregate a creator's repeated views on the same ticker."""
    from .youtube_creator_view import run

    return run(force=force, only=only, workers=workers)


def build_author_pool(
    db_path: str | Path,
    *,
    target_size: int = 500,
    min_subscribers: int = 1_000,
    since_days: int = 365,
    pool_version: str | None = None,
) -> PoolSummary:
    """Build a versioned YouTube creator candidate pool."""
    return build_pool(
        db_path,
        target_size=target_size,
        min_subscribers=min_subscribers,
        since_days=since_days,
        pool_version=pool_version,
    )
