"""Global retail job-level workflows."""
from __future__ import annotations

from typing import Any

from ...domain.global_retail import rollup_tickers as rollup_tickers_domain
from ...domain.global_retail import tag_posts as tag_posts_domain
from ...platforms.global_retail import (
    crawl_regional_discussions as crawl_regional_discussions_platform,
)
from ...platforms.global_retail import fetch_quotes as fetch_quotes_platform
from ...platforms.global_retail import import_xueqiu_export as import_xueqiu_export_platform
from ...platforms.toss import crawl_community
from ...platforms.xueqiu import (
    backfill,
    crawl_direct,
    enrich_authors,
    expand_related,
    incremental,
    run_jobs,
    status,
    sync_to_global_retail,
)


def crawl_regional_discussions(
    *,
    per_board: int,
    since_days: int,
    regions: set[str] | None,
    only: list[str] | None,
) -> dict:
    """Fetch JP/KR/TW retail discussions."""
    return crawl_regional_discussions_platform(
        per_board=per_board,
        since_days=since_days,
        regions=regions,
        only=only,
    )


def tag_posts(
    *,
    batch_size: int,
    workers: int,
    only_new: bool,
    only: list[str] | None,
    sources: list[str] | None,
    regions: list[str] | None,
) -> int:
    """Score global retail posts."""
    return tag_posts_domain(
        batch_size=batch_size,
        workers=workers,
        only_new=only_new,
        only=only,
        sources=sources,
        regions=regions,
    )


def rollup_tickers(*, window_days: int) -> dict:
    """Aggregate global retail ticker/region signals."""
    return rollup_tickers_domain(window_days=window_days)


def import_xueqiu_export(*, path: str, since_days: int) -> dict:
    """Import browser-exported Xueqiu JSON."""
    return import_xueqiu_export_platform(path=path, since_days=since_days)


def crawl_xueqiu_direct(
    *,
    out_path: str,
    since_days: int,
    only: list[str] | None,
    per_page: int,
    max_pages: int,
    sleep: float,
    headless: bool,
    do_ingest: bool,
) -> dict:
    """Crawl Xueqiu directly and optionally ingest exported posts."""
    return crawl_direct(
        out_path=out_path,
        since_days=since_days,
        only=only,
        per_page=per_page,
        max_pages=max_pages,
        sleep=sleep,
        headless=headless,
        do_ingest=do_ingest,
    )


def backfill_xueqiu(
    *,
    days: int,
    only: list[str] | None,
    per_page: int,
    max_pages: int,
    max_jobs: int | None,
    sleep: float,
    headless: bool,
    force: bool,
    run: bool,
    sync: bool,
) -> dict[str, Any]:
    """Plan/run Xueqiu historical backfill, then optionally sync to gr_post."""
    result = backfill(
        days=days,
        only=only,
        per_page=per_page,
        max_pages=max_pages,
        max_jobs=max_jobs,
        sleep=sleep,
        headless=headless,
        force=force,
        run=run,
    )
    if sync and run:
        result["sync"] = sync_to_global_retail(since_days=days, only=only)
    return result


def incremental_xueqiu(
    *,
    days: int,
    only: list[str] | None,
    per_page: int,
    max_pages: int,
    max_jobs: int | None,
    sleep: float,
    headless: bool,
    force: bool,
    run: bool,
    sync: bool,
) -> dict[str, Any]:
    """Plan/run Xueqiu incremental crawl, then optionally sync to gr_post."""
    result = incremental(
        days=days,
        only=only,
        per_page=per_page,
        max_pages=max_pages,
        max_jobs=max_jobs,
        sleep=sleep,
        headless=headless,
        force=force,
        run=run,
    )
    if sync and run:
        result["sync"] = sync_to_global_retail(since_days=max(days, 14), only=only)
    return result


def run_xueqiu_jobs(
    *,
    max_jobs: int | None,
    sleep: float,
    headless: bool,
    retry_failed: bool,
    recover_running_hours: int,
) -> dict[str, Any]:
    """Run pending Xueqiu pipeline jobs."""
    return run_jobs(
        max_jobs=max_jobs,
        sleep=sleep,
        headless=headless,
        retry_failed=retry_failed,
        recover_running_hours=recover_running_hours,
    )


def sync_xueqiu_to_global_retail(*, since_days: int, only: list[str] | None) -> dict[str, int]:
    """Sync Xueqiu raw posts into gr_post."""
    return sync_to_global_retail(since_days=since_days, only=only)


def expand_xueqiu_related(*, since_days: int, enqueue_top: int) -> dict[str, int]:
    """Extract related Xueqiu tickers and optionally enqueue jobs."""
    return expand_related(since_days=since_days, enqueue_top=enqueue_top)


def enrich_xueqiu_authors(*, since_days: int) -> dict[str, int]:
    """Rebuild Xueqiu author snapshots."""
    return enrich_authors(since_days=since_days)


def xueqiu_status() -> dict[str, Any]:
    """Report Xueqiu pipeline status."""
    return status()


def fetch_quotes() -> dict:
    """Fetch latest global retail quotes."""
    return fetch_quotes_platform()


def crawl_toss(
    *,
    days: int,
    only: list[str] | None,
    max_pages: int,
    sleep: float,
    commit_pages: int,
    resume: bool,
) -> dict:
    """Fetch Toss stock-community posts."""
    return crawl_community(
        days=days,
        only=only,
        max_pages=max_pages,
        sleep=sleep,
        commit_pages=commit_pages,
        resume=resume,
    )

