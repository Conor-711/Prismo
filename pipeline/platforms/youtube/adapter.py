"""YouTube platform operations."""
from __future__ import annotations


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
    from .discovery import crawl

    crawl(
        only=only,
        since_hours=since_hours,
        min_views=min_views,
        per_ticker_results=per_ticker_results,
        max_pages=max_pages,
        mock=mock,
    )


def refresh_channels() -> None:
    """Refresh YouTube channel author metadata."""
    from .channels import main

    main()
