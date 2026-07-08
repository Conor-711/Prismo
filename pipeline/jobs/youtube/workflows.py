"""YouTube job-level workflows."""
from __future__ import annotations

from ...domain.authors.youtube import build_creator_view as build_creator_view_domain
from ...domain.opinions.youtube import (
    analyze_text as analyze_text_domain,
    analyze_videos as analyze_videos_domain,
    build_digest as build_digest_domain,
    generate_fulltext as generate_fulltext_domain,
)
from ...domain.target_prices.youtube import extract_judgment as extract_judgment_domain
from ...platforms.youtube import crawl_videos as crawl_videos_platform
from ...platforms.youtube import refresh_channels as refresh_channels_platform


def crawl_videos(
    *,
    only: list[str] | None,
    since_hours: int,
    min_views: int | None,
    per_ticker_results: int,
    max_pages: int,
    mock: bool,
) -> None:
    """Fetch YouTube videos for ticker queries into the local video table."""
    crawl_videos_platform(
        only=only,
        since_hours=since_hours,
        min_views=min_views,
        per_ticker_results=per_ticker_results,
        max_pages=max_pages,
        mock=mock,
    )


def refresh_channels() -> None:
    """Refresh YouTube channel author metadata."""
    refresh_channels_platform()


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
    analyze_videos_domain(
        top_native=top_native,
        only_new=only_new,
        mock=mock,
        per_ticker_cap=per_ticker_cap,
        workers=workers,
        only=only,
    )


def analyze_text(*, per_ticker: int, workers: int, only: set[str] | None = None) -> int:
    """Run text-only YouTube analysis for videos without native processing."""
    return analyze_text_domain(per_ticker=per_ticker, workers=workers, only=only)


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
    return generate_fulltext_domain(
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
    return build_digest_domain(force=force, only=only, workers=workers)


def extract_judgment(*, force: bool, only: set[str] | None, workers: int) -> int:
    """Extract time horizon, target price and key judgment fields."""
    return extract_judgment_domain(force=force, only=only, workers=workers)


def build_creator_view(*, force: bool, only: set[str] | None, workers: int) -> int:
    """Aggregate a creator's repeated views on the same ticker."""
    return build_creator_view_domain(force=force, only=only, workers=workers)
