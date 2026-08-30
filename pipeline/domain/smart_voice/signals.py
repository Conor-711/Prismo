"""Smart Account signal-domain workflows."""
from __future__ import annotations


def score_x_sentiment(
    *,
    batch_size: int,
    workers: int,
    only_new: bool,
    limit: int | None,
) -> int:
    """Score X tweet sentiment for KOL daily sentiment rollups."""
    from .tweet_sentiment import score

    return score(batch_size=batch_size, workers=workers, only_new=only_new, limit=limit)


def rollup_kol_sentiment() -> int:
    """Build daily KOL net sentiment rollups."""
    from .kol_sentiment import rollup

    return rollup()


def rollup_kol_volume() -> int:
    """Build daily KOL discussion-volume rollups."""
    from .kol_volume import rollup

    return rollup()


def rollup_retail_sentiment() -> int:
    """Build daily retail net sentiment rollups."""
    from .retail_sentiment import rollup

    return rollup()


def rollup_retail_volume() -> int:
    """Build daily retail discussion-volume rollups."""
    from .retail_volume import rollup

    return rollup()


def rollup_retail_newcomers() -> int:
    """Build daily retail newcomer rollups."""
    from .retail_newcomers import rollup

    return rollup()


def rollup_kol_newcomers() -> int:
    """Build daily KOL newcomer rollups."""
    from .kol_newcomers import rollup

    return rollup()


def build_overall_signals(
    *,
    ticker: str,
    kol_file: str,
    window: int,
    look: int,
    aspect_days: int,
    cap: int,
    skill_dir: str,
    recent_days: int,
    prior_days: int,
) -> None:
    """Build derived Smart Account signals for the ticker detail overview."""
    from .overall_signals import run

    run(ticker, kol_file, window, look, aspect_days, cap, skill_dir, recent_days, prior_days)
