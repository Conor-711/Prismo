"""Xueqiu platform operations."""
from __future__ import annotations

from typing import Any


def crawl_direct(
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
    """Crawl Xueqiu directly with Playwright-controlled Chrome."""
    from .direct import crawl

    return crawl(
        out_path=out_path,
        since_days=since_days,
        only=only,
        per_page=per_page,
        max_pages=max_pages,
        sleep=sleep,
        headless=headless,
        do_ingest=do_ingest,
    )


def backfill(
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
) -> dict[str, Any]:
    """Create and optionally run Xueqiu backfill jobs."""
    from .pipeline import backfill as run_backfill

    return run_backfill(
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


def incremental(
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
) -> dict[str, Any]:
    """Create and optionally run Xueqiu incremental jobs."""
    from .pipeline import incremental as run_incremental

    return run_incremental(
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


def run_jobs(
    *,
    max_jobs: int | None,
    sleep: float,
    headless: bool,
    retry_failed: bool,
    recover_running_hours: int,
) -> dict[str, Any]:
    """Run pending or failed Xueqiu crawl jobs."""
    from .pipeline import run_jobs as run_pending

    return run_pending(
        max_jobs=max_jobs,
        sleep=sleep,
        headless=headless,
        retry_failed=retry_failed,
        recover_running_hours=recover_running_hours,
    )


def sync_to_global_retail(*, since_days: int, only: list[str] | None) -> dict[str, int]:
    """Normalize Xueqiu raw posts into global retail posts."""
    from .pipeline import sync_to_gr_post

    return sync_to_gr_post(since_days=since_days, only=only)


def expand_related(*, since_days: int, enqueue_top: int) -> dict[str, int]:
    """Extract related tickers from Xueqiu raw posts."""
    from .pipeline import expand_related as run_expand

    return run_expand(since_days=since_days, enqueue_top=enqueue_top)


def enrich_authors(*, since_days: int) -> dict[str, int]:
    """Rebuild Xueqiu author snapshots from raw payloads."""
    from .pipeline import enrich_authors as run_enrich

    return run_enrich(since_days=since_days)


def authorize_authors(
    *, out_path: str, probe_user_id: str, timeout_seconds: int
) -> dict[str, Any]:
    """Capture a user-authorized Xueqiu browser session."""
    from .author_timeline import authorize_storage_state

    return authorize_storage_state(
        out_path=out_path,
        probe_user_id=probe_user_id,
        timeout_seconds=timeout_seconds,
    )


def plan_author_backfill(
    *,
    pool_version: str,
    days: int,
    include_reserve: bool,
    only_user_ids: list[str] | None,
    per_page: int,
    max_pages: int,
    force: bool,
) -> dict[str, int]:
    """Plan resumable author timeline backfill jobs."""
    from .author_timeline import plan_author_jobs

    return plan_author_jobs(
        pool_version=pool_version,
        days=days,
        include_reserve=include_reserve,
        only_user_ids=only_user_ids,
        per_page=per_page,
        max_pages=max_pages,
        force=force,
    )


def run_author_backfill(
    *,
    pool_version: str,
    only_user_ids: list[str] | None,
    selected_only: bool,
    order_mode: str,
    max_attempts: int,
    max_jobs: int | None,
    sleep: float,
    headless: bool,
    storage_state: str,
    retry_failed: bool,
    retry_blocked: bool,
    allow_guest_page_one: bool,
) -> dict[str, Any]:
    """Run pending author timeline backfill jobs."""
    from .author_timeline import run_author_jobs

    return run_author_jobs(
        pool_version=pool_version,
        only_user_ids=only_user_ids,
        selected_only=selected_only,
        order_mode=order_mode,
        max_attempts=max_attempts,
        max_jobs=max_jobs,
        sleep=sleep,
        headless=headless,
        storage_state=storage_state,
        retry_failed=retry_failed,
        retry_blocked=retry_blocked,
        allow_guest_page_one=allow_guest_page_one,
    )


def author_backfill_status(*, pool_version: str | None) -> dict[str, Any]:
    """Report author-pool and timeline-job status."""
    from .author_timeline import author_status

    return author_status(pool_version=pool_version)


def status() -> dict[str, Any]:
    """Report Xueqiu crawl-pipeline status."""
    from .pipeline import status as run_status

    return run_status()
