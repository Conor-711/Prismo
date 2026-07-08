"""Global retail signal-domain workflows."""
from __future__ import annotations


def tag_posts(
    *,
    batch_size: int,
    workers: int,
    only_new: bool,
    only: list[str] | None,
    sources: list[str] | None,
    regions: list[str] | None,
) -> int:
    """Score global retail posts and derive stance."""
    from .tag import tag_all

    return tag_all(
        batch_size=batch_size,
        workers=workers,
        only_new=only_new,
        only=only,
        sources=sources,
        regions=regions,
    )


def rollup_tickers(*, window_days: int) -> dict:
    """Aggregate global retail region/ticker rollups."""
    from .rollup import rollup

    return rollup(window_days=window_days)
