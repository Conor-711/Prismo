"""YouTube opinion-domain workflows."""
from __future__ import annotations


def analyze_videos(
    *,
    top_native: int,
    only_new: bool,
    mock: bool,
    per_ticker_cap: int | None,
    workers: int,
    only: list[str] | None,
) -> None:
    """Run mixed native-video/subtitle analysis for YouTube videos."""
    from .youtube_analysis import tag

    tag(
        top_native=top_native,
        only_new=only_new,
        mock=mock,
        per_ticker_cap=per_ticker_cap,
        workers=workers,
        only=only,
    )


def analyze_text(*, per_ticker: int, workers: int, only: set[str] | None = None) -> int:
    """Run text-only YouTube analysis for videos without native processing."""
    from .youtube_analysis import tag_text

    return tag_text(per_ticker=per_ticker, workers=workers, only=only)


def generate_fulltext(
    *,
    only: set[str] | None,
    per_ticker: int,
    workers: int,
    force: bool,
    low_res: bool,
    frames: bool,
    limit: int | None,
    max_native_min: int,
    fail_after: int,
    max_rate_waits: int,
) -> int:
    """Generate full reconstructed YouTube transcripts and key-frame context."""
    from .youtube_analysis import gen_fulltext

    return gen_fulltext(
        only=only,
        per_ticker=per_ticker,
        workers=workers,
        force=force,
        low_res=low_res,
        frames=frames,
        limit=limit,
        max_native_min=max_native_min,
        fail_after=fail_after,
        max_rate_waits=max_rate_waits,
    )


def build_digest(*, force: bool, only: set[str] | None, workers: int) -> int:
    """Build investor summaries and chapter indexes from full YouTube text."""
    from .youtube_digest import run

    return run(force=force, only=only, workers=workers)
