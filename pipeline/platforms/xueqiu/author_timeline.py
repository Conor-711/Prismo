"""Authenticated, resumable Xueqiu author timeline backfill."""
from __future__ import annotations

import datetime as dt
import random
import time
from pathlib import Path
from typing import Any

from sqlalchemy import and_, func, select, update

from ...common.db import engine, session_scope
from ...common.models import (
    Base,
    XueqiuAuthorCrawlJob,
    XueqiuAuthorPoolCandidate,
    XueqiuRawPost,
)
from .direct import _fetch_author_page
from .pipeline import _persist_items, _utcnow


DEFAULT_STORAGE_STATE = ".xueqiu_storage_state.json"
AUTHOR_TABLES = [
    XueqiuAuthorPoolCandidate.__table__,
    XueqiuAuthorCrawlJob.__table__,
    XueqiuRawPost.__table__,
]


def _ensure_tables() -> None:
    Base.metadata.create_all(engine, tables=AUTHOR_TABLES)


def _author_job_key(
    pool_version: str, user_id: str, since: dt.datetime, until: dt.datetime
) -> str:
    return f"xq:author:{pool_version}:{user_id}:{since:%Y%m%d}:{until:%Y%m%d}"


def authorize_storage_state(
    *,
    out_path: str = DEFAULT_STORAGE_STATE,
    probe_user_id: str = "9692447746",
    timeout_seconds: int = 300,
) -> dict[str, Any]:
    """Open Xueqiu for user-driven login and save Playwright storage state."""
    try:
        from playwright.sync_api import sync_playwright
    except Exception as exc:  # pragma: no cover - environment guidance
        raise RuntimeError("Python Playwright is required for Xueqiu authorization.") from exc

    out = Path(out_path)
    # Kept in the public signature for CLI compatibility. Login completion is
    # explicit because polling the timeline endpoint itself triggers throttling.
    _ = probe_user_id, timeout_seconds
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            channel="chrome",
            headless=False,
            args=["--disable-blink-features=AutomationControlled"],
        )
        context = browser.new_context(locale="zh-CN")
        page = context.new_page()
        page.goto("https://xueqiu.com/", wait_until="domcontentloaded", timeout=45_000)
        print("[xueqiu-auth] 请在打开的 Chrome 中自行登录雪球；管道不会读取账号密码。", flush=True)
        input("[xueqiu-auth] 登录完成后按 Enter 保存本地会话：")
        context.storage_state(path=str(out))
        browser.close()
    print(f"[xueqiu-auth] 已保存本地会话 → {out}", flush=True)
    return {"authenticated": True, "storage_state": str(out)}


def plan_author_jobs(
    *,
    pool_version: str,
    days: int = 365,
    include_reserve: bool = True,
    only_user_ids: list[str] | None = None,
    per_page: int = 20,
    max_pages: int = 1200,
    force: bool = False,
) -> dict[str, int]:
    """Create one resumable timeline job per eligible author."""
    _ensure_tables()
    until = _utcnow()
    since = until - dt.timedelta(days=days)
    wanted = {str(value).strip() for value in only_user_ids or [] if str(value).strip()}
    with session_scope() as session:
        stmt = select(XueqiuAuthorPoolCandidate).where(
            XueqiuAuthorPoolCandidate.pool_version == pool_version,
            XueqiuAuthorPoolCandidate.author_type == "creator",
        )
        if not include_reserve:
            stmt = stmt.where(XueqiuAuthorPoolCandidate.selected.is_(True))
        if wanted:
            stmt = stmt.where(XueqiuAuthorPoolCandidate.user_id.in_(wanted))
        candidates = list(
            session.execute(
                stmt.order_by(
                    XueqiuAuthorPoolCandidate.selected.desc(),
                    XueqiuAuthorPoolCandidate.pool_rank.asc(),
                )
            ).scalars()
        )
        if wanted:
            found = {row.user_id for row in candidates}
            missing = sorted(wanted - found)
            if missing:
                raise ValueError(f"authors not found in pool {pool_version}: {missing}")

        created = reused = reset = 0
        now = _utcnow()
        for candidate in candidates:
            job_key = _author_job_key(pool_version, candidate.user_id, since, until)
            job = session.execute(
                select(XueqiuAuthorCrawlJob).where(XueqiuAuthorCrawlJob.job_key == job_key)
            ).scalar_one_or_none()
            if job is None:
                session.add(
                    XueqiuAuthorCrawlJob(
                        job_key=job_key,
                        pool_version=pool_version,
                        user_id=candidate.user_id,
                        screen_name=candidate.screen_name,
                        mode="backfill",
                        status="pending",
                        since_utc=since,
                        until_utc=until,
                        cursor_page=1,
                        per_page=per_page,
                        max_pages=max_pages,
                        priority=candidate.pool_rank or 9999,
                        created_at=now,
                        updated_at=now,
                    )
                )
                created += 1
                continue
            if force or job.status in {"failed", "blocked", "running"}:
                job.status = "pending"
                job.cursor_page = 1
                job.per_page = per_page
                job.max_pages = max_pages
                job.attempts = 0
                job.rows_seen = 0
                job.rows_new = 0
                job.earliest_seen_utc = None
                job.latest_seen_utc = None
                job.stop_reason = ""
                job.last_error = ""
                job.started_at = None
                job.finished_at = None
                job.updated_at = now
                reset += 1
            else:
                reused += 1
    print(
        f"[xueqiu-author-plan] pool={pool_version} authors={len(candidates)} "
        f"created={created} reset={reset} reused={reused}",
        flush=True,
    )
    return {"authors": len(candidates), "created": created, "reset": reset, "reused": reused}


def _mark_job(job_id: int, **values: Any) -> None:
    values["updated_at"] = _utcnow()
    with session_scope() as session:
        session.execute(
            update(XueqiuAuthorCrawlJob)
            .where(XueqiuAuthorCrawlJob.id == job_id)
            .values(**values)
        )


def _run_author_job(page, job_id: int, *, sleep: float) -> dict[str, Any]:  # noqa: ANN001
    with session_scope() as session:
        job = session.get(XueqiuAuthorCrawlJob, job_id)
        if job is None:
            return {"job_id": job_id, "status": "missing"}
        user_id = job.user_id
        screen_name = job.screen_name
        cursor_page = max(job.cursor_page or 1, 1)
        per_page = job.per_page
        max_pages = job.max_pages
        since = job.since_utc
        until = job.until_utc
        rows_seen = int(job.rows_seen or 0)
        rows_new = int(job.rows_new or 0)
        earliest = job.earliest_seen_utc
        latest = job.latest_seen_utc
        job.status = "running"
        job.attempts = int(job.attempts or 0) + 1
        job.started_at = job.started_at or _utcnow()
        job.updated_at = _utcnow()

    try:
        page.goto(f"https://xueqiu.com/u/{user_id}", wait_until="domcontentloaded", timeout=45_000)
        page.wait_for_timeout(900)
    except Exception:
        pass

    stop_reason = "max_pages"
    last_error = ""
    for page_no in range(cursor_page, max_pages + 1):
        data: dict[str, Any] | None = None
        for attempt in range(1, 4):
            try:
                data = _fetch_author_page(page, user_id, page_no, per_page)
            except Exception as exc:
                last_error = str(exc).splitlines()[0]
                data = None
            if data and data.get("ok"):
                break
            if data and str(data.get("errorCode") or "") == "10022":
                last_error = data.get("error") or "Xueqiu login required"
                _mark_job(
                    job_id,
                    status="blocked",
                    cursor_page=page_no,
                    rows_seen=rows_seen,
                    rows_new=rows_new,
                    earliest_seen_utc=earliest,
                    latest_seen_utc=latest,
                    stop_reason="auth_required",
                    last_error=last_error,
                    finished_at=_utcnow(),
                )
                print(
                    f"  [xueqiu-author] {screen_name} ({user_id}) blocked page={page_no}: auth required",
                    flush=True,
                )
                return {"job_id": job_id, "user_id": user_id, "status": "blocked"}
            if data:
                last_error = data.get("error") or data.get("text") or f"HTTP {data.get('status')}"
            if attempt < 3:
                time.sleep(max(sleep * (attempt + 2), 5.0))

        if not data or not data.get("ok"):
            _mark_job(
                job_id,
                status="failed",
                cursor_page=page_no,
                rows_seen=rows_seen,
                rows_new=rows_new,
                earliest_seen_utc=earliest,
                latest_seen_utc=latest,
                stop_reason="fetch_failed",
                last_error=last_error,
                finished_at=_utcnow(),
            )
            return {"job_id": job_id, "user_id": user_id, "status": "failed", "error": last_error}

        items = ((data.get("data") or {}).get("statuses") or [])
        if not items:
            stop_reason = "empty_page"
            break
        rows_seen += len(items)
        page_stats = _persist_items("", items, since, until, map_ticker=False)
        rows_new += int(page_stats["new"])
        if page_stats["earliest"]:
            earliest = page_stats["earliest"] if earliest is None else min(earliest, page_stats["earliest"])
        if page_stats["latest"]:
            latest = page_stats["latest"] if latest is None else max(latest, page_stats["latest"])
        _mark_job(
            job_id,
            cursor_page=page_no + 1,
            rows_seen=rows_seen,
            rows_new=rows_new,
            earliest_seen_utc=earliest,
            latest_seen_utc=latest,
            stop_reason="",
            last_error="",
        )
        if page_no % 25 == 0:
            print(
                f"  [xueqiu-author] {screen_name} page={page_no} "
                f"seen={rows_seen} new={rows_new}",
                flush=True,
            )
        if page_stats["old"] and not page_stats["kept"]:
            stop_reason = "reached_since_cutoff"
            break
        time.sleep(max(sleep, 0) + random.uniform(0.0, 0.35))

    _mark_job(
        job_id,
        status="done",
        rows_seen=rows_seen,
        rows_new=rows_new,
        earliest_seen_utc=earliest,
        latest_seen_utc=latest,
        stop_reason=stop_reason,
        last_error="",
        finished_at=_utcnow(),
    )
    print(
        f"  [xueqiu-author] {screen_name} ({user_id}) done "
        f"seen={rows_seen} new={rows_new} stop={stop_reason}",
        flush=True,
    )
    return {
        "job_id": job_id,
        "user_id": user_id,
        "status": "done",
        "seen": rows_seen,
        "new": rows_new,
    }


def run_author_jobs(
    *,
    pool_version: str,
    only_user_ids: list[str] | None = None,
    selected_only: bool = False,
    order_mode: str = "rank",
    max_attempts: int = 5,
    max_jobs: int | None = None,
    sleep: float = 2.0,
    headless: bool = True,
    storage_state: str = DEFAULT_STORAGE_STATE,
    retry_failed: bool = False,
    retry_blocked: bool = False,
    allow_guest_page_one: bool = False,
) -> dict[str, Any]:
    """Run pending Xueqiu author jobs using a saved authenticated session."""
    _ensure_tables()
    state_path = Path(storage_state)
    if not state_path.exists() and not allow_guest_page_one:
        raise RuntimeError(
            f"Xueqiu authenticated storage state not found: {state_path}. "
            "Run the authorization command first."
        )
    statuses = ["pending"]
    if retry_failed:
        statuses.append("failed")
    if retry_blocked:
        statuses.append("blocked")
    wanted = {str(value).strip() for value in only_user_ids or [] if str(value).strip()}
    with session_scope() as session:
        stale_before = _utcnow() - dt.timedelta(minutes=10)
        recovered = session.execute(
            update(XueqiuAuthorCrawlJob)
            .where(
                XueqiuAuthorCrawlJob.pool_version == pool_version,
                XueqiuAuthorCrawlJob.status == "running",
                XueqiuAuthorCrawlJob.updated_at < stale_before,
            )
            .values(
                status="pending",
                stop_reason="stale_running_recovered",
                last_error="Recovered after an interrupted worker.",
                finished_at=None,
                updated_at=_utcnow(),
            )
        ).rowcount
        if recovered:
            print(
                f"[xueqiu-author-run] recovered stale running jobs={recovered}",
                flush=True,
            )
        stmt = select(XueqiuAuthorCrawlJob.id).where(
            XueqiuAuthorCrawlJob.pool_version == pool_version,
            XueqiuAuthorCrawlJob.status.in_(statuses),
            XueqiuAuthorCrawlJob.attempts < max(1, max_attempts),
        )
        if selected_only or order_mode == "activity":
            stmt = stmt.join(
                XueqiuAuthorPoolCandidate,
                and_(
                    XueqiuAuthorPoolCandidate.pool_version == XueqiuAuthorCrawlJob.pool_version,
                    XueqiuAuthorPoolCandidate.user_id == XueqiuAuthorCrawlJob.user_id,
                ),
            )
        if selected_only:
            stmt = stmt.where(XueqiuAuthorPoolCandidate.selected.is_(True))
        if order_mode == "activity":
            stmt = stmt.order_by(
                XueqiuAuthorPoolCandidate.statuses_count,
                XueqiuAuthorPoolCandidate.pool_rank,
                XueqiuAuthorCrawlJob.id,
            )
        else:
            stmt = stmt.order_by(XueqiuAuthorCrawlJob.priority, XueqiuAuthorCrawlJob.id)
        if wanted:
            stmt = stmt.where(XueqiuAuthorCrawlJob.user_id.in_(wanted))
        if max_jobs:
            stmt = stmt.limit(max_jobs)
        job_ids = list(session.execute(stmt).scalars())
    if not job_ids:
        return {"jobs": 0, "done": 0, "failed": 0, "blocked": 0}

    try:
        from playwright.sync_api import sync_playwright
    except Exception as exc:  # pragma: no cover - environment guidance
        raise RuntimeError("Python Playwright is required for Xueqiu author backfill.") from exc

    context_args: dict[str, Any] = {"locale": "zh-CN"}
    if state_path.exists():
        context_args["storage_state"] = str(state_path)
    results: list[dict[str, Any]] = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            channel="chrome",
            headless=headless,
            args=["--disable-blink-features=AutomationControlled"],
        )
        context = browser.new_context(**context_args)
        page = context.new_page()
        warmup_error: Exception | None = None
        for warmup_attempt in range(1, 4):
            try:
                page.goto(
                    "https://xueqiu.com/S/MU",
                    wait_until="domcontentloaded",
                    timeout=45_000,
                )
                warmup_error = None
                break
            except Exception as exc:
                warmup_error = exc
                if warmup_attempt < 3:
                    page.wait_for_timeout(5_000 * warmup_attempt)
        if warmup_error is not None:
            browser.close()
            raise RuntimeError(f"Xueqiu browser warmup failed: {warmup_error}") from warmup_error
        page.wait_for_timeout(1500)
        consecutive_failures = 0
        for job_id in job_ids:
            result = _run_author_job(page, job_id, sleep=sleep)
            results.append(result)
            if result.get("status") == "done":
                consecutive_failures = 0
                continue
            if result.get("status") == "blocked":
                print("[xueqiu-author-run] 登录失效，停止当前批次。", flush=True)
                break
            consecutive_failures += 1
            if consecutive_failures >= 2:
                print(
                    "[xueqiu-author-run] 连续 2 位作者抓取失败，触发限流熔断；"
                    "其余任务保持原状态。",
                    flush=True,
                )
                break
        if state_path.exists():
            context.storage_state(path=str(state_path))
        browser.close()

    result = {
        "jobs": len(results),
        "done": sum(row.get("status") == "done" for row in results),
        "failed": sum(row.get("status") == "failed" for row in results),
        "blocked": sum(row.get("status") == "blocked" for row in results),
    }
    print(f"[xueqiu-author-run] {result}", flush=True)
    return result


def author_status(*, pool_version: str | None = None) -> dict[str, Any]:
    _ensure_tables()
    with session_scope() as session:
        job_stmt = select(XueqiuAuthorCrawlJob.status, func.count()).group_by(
            XueqiuAuthorCrawlJob.status
        )
        pool_stmt = select(
            XueqiuAuthorPoolCandidate.pool_status, func.count()
        ).group_by(XueqiuAuthorPoolCandidate.pool_status)
        if pool_version:
            job_stmt = job_stmt.where(XueqiuAuthorCrawlJob.pool_version == pool_version)
            pool_stmt = pool_stmt.where(XueqiuAuthorPoolCandidate.pool_version == pool_version)
        jobs = dict(session.execute(job_stmt).all())
        pool = dict(session.execute(pool_stmt).all())
        progress_stmt = select(
            func.count(),
            func.coalesce(func.sum(XueqiuAuthorCrawlJob.rows_seen), 0),
            func.coalesce(func.sum(XueqiuAuthorCrawlJob.rows_new), 0),
            func.min(XueqiuAuthorCrawlJob.earliest_seen_utc),
        )
        if pool_version:
            progress_stmt = progress_stmt.where(XueqiuAuthorCrawlJob.pool_version == pool_version)
        total, rows_seen, rows_new, earliest = session.execute(progress_stmt).one()
        selected_stmt = (
            select(XueqiuAuthorCrawlJob.status, func.count())
            .join(
                XueqiuAuthorPoolCandidate,
                and_(
                    XueqiuAuthorPoolCandidate.pool_version
                    == XueqiuAuthorCrawlJob.pool_version,
                    XueqiuAuthorPoolCandidate.user_id == XueqiuAuthorCrawlJob.user_id,
                ),
            )
            .where(
                XueqiuAuthorPoolCandidate.selected.is_(True),
                XueqiuAuthorPoolCandidate.author_type == "creator",
            )
            .group_by(XueqiuAuthorCrawlJob.status)
        )
        if pool_version:
            selected_stmt = selected_stmt.where(
                XueqiuAuthorCrawlJob.pool_version == pool_version
            )
        selected_jobs = dict(session.execute(selected_stmt).all())
    done = int(jobs.get("done") or 0)
    selected_done = int(selected_jobs.get("done") or 0)
    selected_total = sum(int(value or 0) for value in selected_jobs.values())
    result = {
        "pool_version": pool_version,
        "pool": pool,
        "jobs": jobs,
        "selected_jobs": selected_jobs,
        "progress": {
            "total_jobs": int(total or 0),
            "complete_pct": round(done / max(int(total or 0), 1) * 100, 2),
            "selected_total": selected_total,
            "selected_complete_pct": round(
                selected_done / max(selected_total, 1) * 100, 2
            ),
            "rows_seen": int(rows_seen or 0),
            "rows_new": int(rows_new or 0),
            "earliest_seen_utc": earliest.isoformat() if earliest else None,
        },
    }
    print(f"[xueqiu-author-status] {result}", flush=True)
    return result
