"""YouTube author-domain workflows."""
from __future__ import annotations


def build_creator_view(*, force: bool, only: set[str] | None, workers: int) -> int:
    """Aggregate a creator's repeated views on the same ticker."""
    from .youtube_creator_view import run

    return run(force=force, only=only, workers=workers)
