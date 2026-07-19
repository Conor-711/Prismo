"""YouTube job-level workflows."""
from __future__ import annotations

import os
from pathlib import Path

from ...common.config import RUNTIME_DATA_DIR, settings
from ...domain.authors.youtube import build_author_pool as build_author_pool_domain
from ...domain.authors.youtube import build_creator_view as build_creator_view_domain
from ...domain.opinions.youtube import (
    analyze_text as analyze_text_domain,
    analyze_videos as analyze_videos_domain,
    build_digest as build_digest_domain,
    generate_fulltext as generate_fulltext_domain,
)
from ...domain.target_prices.youtube import extract_judgment as extract_judgment_domain
from ...domain.tickers import map_author_uploads as map_author_uploads_domain
from ...platforms.youtube import crawl_videos as crawl_videos_platform
from ...platforms.youtube import backfill_author_uploads as backfill_author_uploads_platform
from ...platforms.youtube import hydrate_mapped_uploads as hydrate_mapped_uploads_platform
from ...platforms.youtube import refresh_channels as refresh_channels_platform


def _local_db_path() -> Path:
    return Path(os.environ.get("PRICE_DB", str(RUNTIME_DATA_DIR / "dev.db"))).resolve()


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


def build_author_pool(
    *,
    target_size: int,
    min_subscribers: int,
    since_days: int,
    pool_version: str | None,
) -> None:
    """Build the versioned candidate pool used by YouTube author backfills."""
    summary = build_author_pool_domain(
        _local_db_path(),
        target_size=target_size,
        min_subscribers=min_subscribers,
        since_days=since_days,
        pool_version=pool_version,
    )
    print(
        "[yt-author-pool] "
        f"version={summary.pool_version} considered={summary.considered} "
        f"creators={summary.creators} media={summary.media} selected={summary.selected}"
    )


def backfill_author_uploads(
    *,
    pool_version: str | None,
    since_days: int,
    workers: int,
    limit_channels: int | None,
    max_pages: int,
    force: bool,
    hydrate_metadata: bool,
) -> None:
    """Backfill one year of uploads for the selected YouTube creator pool."""
    summary = backfill_author_uploads_platform(
        _local_db_path(),
        api_key=settings.youtube_api_key,
        pool_version=pool_version,
        since_days=since_days,
        workers=workers,
        limit_channels=limit_channels,
        max_pages=max_pages,
        force=force,
        hydrate_metadata=hydrate_metadata,
    )
    print(
        "[yt-author-backfill] complete "
        f"version={summary.pool_version} requested={summary.requested_channels} "
        f"completed={summary.completed_channels} partial={summary.partial_channels} "
        f"failed={summary.failed_channels} videos={summary.videos_stored}"
    )


def map_author_uploads(
    *,
    pool_version: str | None,
    force: bool,
    limit: int | None,
    max_tickers: int,
) -> None:
    """Map author uploads to US stock and ETF tickers."""
    summary = map_author_uploads_domain(
        _local_db_path(),
        pool_version=pool_version,
        force=force,
        limit=limit,
        max_tickers=max_tickers,
    )
    print(
        "[yt-author-map] complete "
        f"version={summary.pool_version} scanned={summary.scanned_videos} "
        f"matched_videos={summary.matched_videos} mappings={summary.mappings} "
        f"matched_authors={summary.matched_authors}"
    )


def hydrate_author_uploads(
    *,
    pool_version: str | None,
    min_confidence: float,
    limit: int | None,
    workers: int,
    force: bool,
) -> None:
    """Hydrate mapped finance uploads with statistics and duration."""
    summary = hydrate_mapped_uploads_platform(
        _local_db_path(),
        api_key=settings.youtube_api_key,
        pool_version=pool_version,
        min_confidence=min_confidence,
        limit=limit,
        workers=workers,
        force=force,
    )
    print(
        "[yt-author-hydrate] complete "
        f"version={summary.pool_version} requested={summary.requested_videos} "
        f"hydrated={summary.hydrated_videos} missing={summary.missing_videos}"
    )


def analyze_videos(
    *,
    top_native: int,
    only_new: bool,
    mock: bool,
    per_ticker_cap: int | None,
    workers: int,
    only: list[str] | None,
    since_days: int | None,
    min_subscribers: int,
    min_duration_seconds: int,
    transcript_only: bool,
) -> None:
    """Run mixed native-video/subtitle analysis for YouTube videos."""
    analyze_videos_domain(
        top_native=top_native,
        only_new=only_new,
        mock=mock,
        per_ticker_cap=per_ticker_cap,
        workers=workers,
        only=only,
        since_days=since_days,
        min_subscribers=min_subscribers,
        min_duration_seconds=min_duration_seconds,
        transcript_only=transcript_only,
    )


def analyze_text(*, per_ticker: int, workers: int, only: set[str] | None = None,
                 since_days: int | None = None, min_subscribers: int = 0,
                 min_duration_seconds: int = 0) -> int:
    """Run text-only YouTube analysis for videos without native processing."""
    return analyze_text_domain(
        per_ticker=per_ticker,
        workers=workers,
        only=only,
        since_days=since_days,
        min_subscribers=min_subscribers,
        min_duration_seconds=min_duration_seconds,
    )


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
    video_ids: set[str] | None = None,
    db_path: str | Path | None = None,
    max_total_minutes: int | None = None,
    prefer_transcript: bool = False,
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
        video_ids=video_ids,
        db_path=db_path,
        max_total_minutes=max_total_minutes,
        prefer_transcript=prefer_transcript,
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
