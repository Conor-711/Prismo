"""Generic item-analysis workflows."""
from __future__ import annotations


def analyze_items(
    *,
    mock: bool,
    qwen: bool,
    limit: int | None,
    workers: int,
    force: bool,
) -> int:
    """Run item-level opinion analysis."""
    from .item_analysis import run_analyze

    return run_analyze(mock=mock, qwen=qwen, limit=limit, workers=workers, force=force)
