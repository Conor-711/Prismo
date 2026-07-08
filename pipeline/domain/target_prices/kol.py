"""KOL target-price judgment workflows."""
from __future__ import annotations


def extract_judgments(
    *,
    sources: list[str] | None,
    per_source: int,
    only: list[str] | None,
    force: bool,
    workers: int,
    since_days: int,
) -> int:
    """Extract explicit target price and operation horizon from KOL source posts."""
    from .kol_judgment import run

    return run(
        sources=sources,
        per_source=per_source,
        only=only,
        force=force,
        workers=workers,
        since_days=since_days,
    )
