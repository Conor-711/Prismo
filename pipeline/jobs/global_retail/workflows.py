"""Global retail job-level workflows."""
from __future__ import annotations

import time
from typing import Any

from ...domain.authors import build_xueqiu_author_pool
from ...domain.global_retail import rollup_tickers as rollup_tickers_domain
from ...domain.global_retail import tag_posts as tag_posts_domain
from ...platforms.global_retail import (
    crawl_regional_discussions as crawl_regional_discussions_platform,
)
from ...platforms.global_retail import fetch_quotes as fetch_quotes_platform
from ...platforms.global_retail import import_xueqiu_export as import_xueqiu_export_platform
from ...platforms.toss import crawl_community
from ...platforms.xueqiu import (
    author_backfill_status,
    authorize_authors,
    backfill,
    crawl_direct,
    enrich_authors,
    expand_related,
    incremental,
    plan_author_backfill,
    run_author_backfill,
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


def authorize_xueqiu_author_backfill(
    *, out_path: str, probe_user_id: str, timeout_seconds: int
) -> dict[str, Any]:
    """Let the user log in and persist a local-only Xueqiu browser session."""
    return authorize_authors(
        out_path=out_path,
        probe_user_id=probe_user_id,
        timeout_seconds=timeout_seconds,
    )


def prepare_xueqiu_author_backfill(
    *,
    csv_path: str,
    pool_version: str,
    target_size: int,
    minimum_size: int,
    min_followers: int,
    min_statuses: int,
    days: int,
    include_reserve: bool,
    only_user_ids: list[str] | None,
    per_page: int,
    max_pages: int,
    force: bool,
) -> dict[str, Any]:
    """Import a candidate pool and create resumable one-year author jobs."""
    pool = build_xueqiu_author_pool(
        csv_path,
        pool_version=pool_version,
        target_size=target_size,
        minimum_size=minimum_size,
        min_followers=min_followers,
        min_statuses=min_statuses,
    )
    jobs = plan_author_backfill(
        pool_version=pool_version,
        days=days,
        include_reserve=include_reserve,
        only_user_ids=only_user_ids,
        per_page=per_page,
        max_pages=max_pages,
        force=force,
    )
    return {"pool": pool, "jobs": jobs}


def execute_xueqiu_author_backfill(
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
    expand_tickers: bool,
    since_days: int,
) -> dict[str, Any]:
    """Run pending timeline jobs and optionally expand ticker mappings."""
    result = run_author_backfill(
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
    if expand_tickers:
        result["expand"] = expand_related(since_days=since_days, enqueue_top=0)
    return result


def xueqiu_author_backfill_status(*, pool_version: str | None) -> dict[str, Any]:
    """Report the versioned author pool and crawl jobs."""
    return author_backfill_status(pool_version=pool_version)


def drain_xueqiu_author_backfill(
    *,
    pool_version: str,
    batch_size: int,
    cooldown_seconds: int,
    failure_cooldown_seconds: int,
    max_failure_cooldown_seconds: int,
    max_cycles: int,
    sleep: float,
    headless: bool,
    storage_state: str,
    max_attempts: int,
    expand_tickers: bool,
    since_days: int,
) -> dict[str, Any]:
    """Drain selected-author jobs in cooldown-protected resumable batches."""
    cycles = done = failed = blocked = 0
    failure_streak = 0
    db_lock_streak = 0
    transport_streak = 0
    retry_mode = False
    while max_cycles <= 0 or cycles < max_cycles:
        try:
            result = run_author_backfill(
                pool_version=pool_version,
                only_user_ids=None,
                selected_only=True,
                order_mode="activity",
                max_attempts=max_attempts,
                max_jobs=max(1, batch_size),
                sleep=sleep,
                headless=headless,
                storage_state=storage_state,
                retry_failed=retry_mode,
                retry_blocked=False,
                allow_guest_page_one=False,
            )
            db_lock_streak = 0
            transport_streak = 0
        except Exception as exc:
            error_text = str(exc).lower()
            is_db_lock = "database is locked" in error_text
            is_transport_error = any(
                marker in error_text
                for marker in (
                    "net::err_",
                    "connection reset",
                    "browser warmup failed",
                    "page.goto",
                    "navigation timeout",
                    "target page, context or browser has been closed",
                )
            )
            if not is_db_lock and not is_transport_error:
                raise
            if is_db_lock:
                db_lock_streak += 1
                transport_streak = 0
                transient_streak = db_lock_streak
                transient_kind = "sqlite writer busy"
            else:
                transport_streak += 1
                db_lock_streak = 0
                transient_streak = transport_streak
                transient_kind = "xueqiu transport unavailable"
            wait_seconds = min(
                max(failure_cooldown_seconds, cooldown_seconds)
                * (2 ** (transient_streak - 1)),
                max(max_failure_cooldown_seconds, cooldown_seconds),
            )
            print(
                f"[xueqiu-author-drain] {transient_kind}; cooldown={wait_seconds}s "
                f"transient_streak={transient_streak}. Jobs will resume by cursor.",
                flush=True,
            )
            try:
                time.sleep(max(0, wait_seconds))
            except KeyboardInterrupt:
                print("[xueqiu-author-drain] 已停止；下次从已保存游标继续。", flush=True)
                break
            continue
        if not result.get("jobs"):
            if not retry_mode:
                retry_mode = True
                print("[xueqiu-author-drain] pending 已清空，开始断点重试 failed。", flush=True)
                continue
            break
        cycles += 1
        done += int(result.get("done") or 0)
        failed += int(result.get("failed") or 0)
        blocked += int(result.get("blocked") or 0)
        if result.get("blocked"):
            print("[xueqiu-author-drain] 登录会话失效，停止长跑。", flush=True)
            break
        if max_cycles > 0 and cycles >= max_cycles:
            break
        cycle_done = int(result.get("done") or 0)
        cycle_failed = int(result.get("failed") or 0)
        if cycle_failed:
            if cycle_done:
                # Partial progress means the session was healthy and merely
                # exhausted its current request budget. A fixed recovery
                # window is enough; escalating to multi-hour waits wastes time.
                failure_streak = 1
                wait_seconds = max(failure_cooldown_seconds, cooldown_seconds)
            else:
                failure_streak += 1
                wait_seconds = min(
                    max(failure_cooldown_seconds, cooldown_seconds)
                    * (2 ** (failure_streak - 1)),
                    max(max_failure_cooldown_seconds, cooldown_seconds),
                )
        else:
            failure_streak = 0
            wait_seconds = cooldown_seconds
        print(
            f"[xueqiu-author-drain] cycle={cycles} done={done} failed={failed} "
            f"cooldown={wait_seconds}s failure_streak={failure_streak}",
            flush=True,
        )
        try:
            time.sleep(max(0, wait_seconds))
        except KeyboardInterrupt:
            print("[xueqiu-author-drain] 已停止；下次从已保存游标继续。", flush=True)
            break

    result = {
        "cycles": cycles,
        "done": done,
        "failed": failed,
        "blocked": blocked,
        "retry_mode": retry_mode,
        "failure_streak": failure_streak,
        "db_lock_streak": db_lock_streak,
        "transport_streak": transport_streak,
    }
    if expand_tickers:
        result["expand"] = expand_related(since_days=since_days, enqueue_top=0)
    result["status"] = author_backfill_status(pool_version=pool_version)
    return result


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
