"""YouTube target-price judgment workflows."""
from __future__ import annotations


def extract_judgment(*, force: bool, only: set[str] | None, workers: int) -> int:
    """Extract time horizon, target price and key judgment fields."""
    from .youtube_judgment import run

    return run(force=force, only=only, workers=workers)
