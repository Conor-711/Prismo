"""Production-oriented Xueqiu crawler pipeline.

The direct `gr-xueqiu-crawl` command is useful for ad-hoc exports. Year-scale
coverage needs a resumable pipeline:

1. create crawl jobs by ticker and time window;
2. fetch pages through a warmed Playwright Chrome session;
3. persist raw source JSON and author snapshots first;
4. expand post-to-ticker mappings from text;
5. sync normalized rows into `gr_post` for the existing product pages.
"""
from __future__ import annotations

import datetime as dt
import re
import time
from dataclasses import dataclass
from typing import Any

from sqlalchemy import func, select, update

from ...common.db import engine, session_scope
from ...common.models import (
    Base,
    GrPost,
    XueqiuAuthorSnapshot,
    XueqiuCrawlCheckpoint,
    XueqiuCrawlJob,
    XueqiuPostTicker,
    XueqiuRawPost,
)
from ..global_retail.regional import load_targets
from .direct import _fetch_page, _ms_to_dt, _row


XUEQIU_TABLES = [
    XueqiuCrawlJob.__table__,
    XueqiuCrawlCheckpoint.__table__,
    XueqiuRawPost.__table__,
    XueqiuPostTicker.__table__,
    XueqiuAuthorSnapshot.__table__,
    GrPost.__table__,
]


@dataclass(frozen=True)
class JobWindow:
    since: dt.datetime
    until: dt.datetime


def _utcnow() -> dt.datetime:
    return dt.datetime.utcnow()


def _ensure_tables() -> None:
    Base.metadata.create_all(engine, tables=XUEQIU_TABLES)


def _targets(only: list[str] | None = None) -> list[dict[str, Any]]:
    targets = load_targets()
    if only:
        wanted = {x.strip().upper() for x in only if x.strip()}
        targets = [t for t in targets if t["ticker"].upper() in wanted]
        missing = sorted(wanted - {t["ticker"].upper() for t in targets})
        if missing:
            print(f"[xueqiu-plan] 标的池未包含：{missing}", flush=True)
    return targets


def _window(days: int) -> JobWindow:
    until = _utcnow()
    return JobWindow(since=until - dt.timedelta(days=days), until=until)


def _job_key(mode: str, ticker: str, window: JobWindow) -> str:
    return f"xq:{mode}:{ticker}:{window.since:%Y%m%d}:{window.until:%Y%m%d}"


def _bulk_upsert(  # noqa: ANN001
    model,
    rows: list[dict[str, Any]],
    conflict_cols: list[str],
    update_exclude: set[str] | None = None,
) -> int:
    if not rows:
        return 0
    if engine.dialect.name == "sqlite":
        from sqlalchemy.dialects.sqlite import insert as sqlite_insert

        stmt = sqlite_insert(model.__table__).values(rows)
        excluded = set(conflict_cols) | set(update_exclude or set())
        updates = {
            col.name: getattr(stmt.excluded, col.name)
            for col in model.__table__.columns
            if col.name not in excluded
        }
        with engine.begin() as conn:
            conn.execute(stmt.on_conflict_do_update(index_elements=conflict_cols, set_=updates))
    else:
        with session_scope() as s:
            for row in rows:
                s.merge(model(**row))
    return len(rows)


def plan_jobs(
    *,
    mode: str,
    days: int,
    only: list[str] | None = None,
    per_page: int = 20,
    max_pages: int = 1200,
    priority: int = 100,
    force: bool = False,
) -> dict[str, int]:
    """Create resumable Xueqiu jobs for a ticker window."""
    _ensure_tables()
    window = _window(days)
    targets = _targets(only)
    created = 0
    reused = 0
    reset = 0
    now = _utcnow()
    with session_scope() as s:
        for target in targets:
            ticker = target["ticker"].upper()
            key = _job_key(mode, ticker, window)
            job = s.execute(select(XueqiuCrawlJob).where(XueqiuCrawlJob.job_key == key)).scalar_one_or_none()
            if job is None:
                s.add(
                    XueqiuCrawlJob(
                        job_key=key,
                        ticker=ticker,
                        mode=mode,
                        status="pending",
                        since_utc=window.since,
                        until_utc=window.until,
                        cursor_page=1,
                        per_page=per_page,
                        max_pages=max_pages,
                        priority=priority,
                        created_at=now,
                        updated_at=now,
                    )
                )
                created += 1
                continue
            if force or job.status in {"failed", "running"}:
                job.status = "pending"
                job.cursor_page = 1
                job.per_page = per_page
                job.max_pages = max_pages
                job.priority = priority
                job.attempts = 0
                job.rows_seen = 0
                job.rows_new = 0
                job.earliest_seen_utc = None
                job.latest_seen_utc = None
                job.stop_reason = ""
                job.last_error = ""
                job.updated_at = now
                job.started_at = None
                job.finished_at = None
                reset += 1
            else:
                reused += 1
    print(
        f"[xueqiu-plan] mode={mode} days={days} created={created} reset={reset} reused={reused}",
        flush=True,
    )
    return {"created": created, "reset": reset, "reused": reused}


def _author_snapshot(item: dict[str, Any], now: dt.datetime) -> dict[str, Any] | None:
    user = item.get("user") or {}
    uid = user.get("id") or item.get("user_id")
    if not uid:
        return None
    return {
        "user_id": str(uid),
        "snapshot_date": now.strftime("%Y-%m-%d"),
        "screen_name": (user.get("screen_name") or item.get("user_screen_name") or "")[:160],
        "followers_count": int(user.get("followers_count") or 0),
        "friends_count": int(user.get("friends_count") or 0),
        "statuses_count": int(user.get("status_count") or user.get("statuses_count") or 0),
        "verified": bool(user.get("verified") or user.get("verified_realname")),
        "province": str(user.get("province") or "")[:64],
        "city": str(user.get("city") or "")[:64],
        "profile": user.get("profile") or f"/{uid}",
        "raw": user,
        "fetched_at": now,
    }


def _raw_record(ticker: str, item: dict[str, Any], now: dt.datetime) -> dict[str, Any] | None:
    row = _row(ticker, item)
    native_id = row.get("id")
    if not native_id:
        return None
    created = _ms_to_dt(row.get("ts")) or now
    uid = row.get("uid") or ""
    url = f"https://xueqiu.com/{uid}/{native_id}" if uid else f"https://xueqiu.com/statuses/{native_id}"
    return {
        "native_id": str(native_id),
        "source_symbol": ticker,
        "author_id": str(uid),
        "author": (row.get("u") or "雪球")[:160],
        "text": row.get("t") or "",
        "lang": "zh",
        "url": url,
        "like_count": int(row.get("like") or 0),
        "reply_count": int(row.get("reply") or 0),
        "view_count": int(row.get("view") or 0),
        "retweet_count": int(row.get("rt") or 0),
        "created_utc": created,
        "raw": item,
        "first_seen_at": now,
        "last_seen_at": now,
    }


def _persist_items(ticker: str, items: list[dict[str, Any]], since: dt.datetime, until: dt.datetime | None) -> dict[str, Any]:
    now = _utcnow()
    raw_rows: list[dict[str, Any]] = []
    map_rows: list[dict[str, Any]] = []
    author_rows: list[dict[str, Any]] = []
    old_count = 0
    future_count = 0
    earliest: dt.datetime | None = None
    latest: dt.datetime | None = None

    for item in items:
        rec = _raw_record(ticker, item, now)
        if rec is None:
            continue
        created = rec["created_utc"]
        if until and created > until:
            future_count += 1
            continue
        if created < since:
            old_count += 1
            continue
        earliest = created if earliest is None else min(earliest, created)
        latest = created if latest is None else max(latest, created)
        raw_rows.append(rec)
        map_rows.append({
            "native_id": rec["native_id"],
            "ticker": ticker,
            "role": "crawled",
            "confidence": 1.0,
            "created_utc": created,
            "updated_at": now,
        })
        snap = _author_snapshot(item, now)
        if snap:
            author_rows.append(snap)

    existing: set[str] = set()
    if raw_rows:
        ids = [r["native_id"] for r in raw_rows]
        with session_scope() as s:
            existing = set(s.execute(select(XueqiuRawPost.native_id).where(XueqiuRawPost.native_id.in_(ids))).scalars())

    _bulk_upsert(XueqiuRawPost, raw_rows, ["native_id"], update_exclude={"first_seen_at"})
    _bulk_upsert(XueqiuPostTicker, map_rows, ["native_id", "ticker"])
    _bulk_upsert(XueqiuAuthorSnapshot, author_rows, ["user_id", "snapshot_date"])

    return {
        "kept": len(raw_rows),
        "new": len([r for r in raw_rows if r["native_id"] not in existing]),
        "old": old_count,
        "future": future_count,
        "earliest": earliest,
        "latest": latest,
    }


def _mark_job(job_id: int, **values: Any) -> None:
    values["updated_at"] = _utcnow()
    with session_scope() as s:
        s.execute(update(XueqiuCrawlJob).where(XueqiuCrawlJob.id == job_id).values(**values))


def _update_checkpoint(job_id: int) -> None:
    with session_scope() as s:
        job = s.get(XueqiuCrawlJob, job_id)
        if job is None:
            return
        existing = s.get(XueqiuCrawlCheckpoint, job.ticker)
        raw_count = s.execute(
            select(func.count()).select_from(XueqiuPostTicker).where(XueqiuPostTicker.ticker == job.ticker)
        ).scalar_one()
        if existing is None:
            existing = XueqiuCrawlCheckpoint(ticker=job.ticker)
            s.add(existing)
        if job.latest_seen_utc:
            existing.newest_post_utc = (
                job.latest_seen_utc
                if existing.newest_post_utc is None
                else max(existing.newest_post_utc, job.latest_seen_utc)
            )
        if job.earliest_seen_utc:
            existing.oldest_post_utc = (
                job.earliest_seen_utc
                if existing.oldest_post_utc is None
                else min(existing.oldest_post_utc, job.earliest_seen_utc)
            )
        if job.mode == "backfill" and job.status == "done":
            existing.last_backfill_since_utc = job.since_utc
        if job.mode == "incremental" and job.status == "done":
            existing.last_incremental_at = job.finished_at or _utcnow()
        existing.last_page = max(existing.last_page or 0, job.cursor_page or 0)
        existing.raw_count = int(raw_count or 0)
        existing.last_status = job.status
        existing.last_error = job.last_error or ""
        existing.updated_at = _utcnow()


def _run_job(page, job_id: int, *, sleep: float) -> dict[str, Any]:  # noqa: ANN001
    with session_scope() as s:
        job = s.get(XueqiuCrawlJob, job_id)
        if job is None:
            return {"job_id": job_id, "status": "missing"}
        ticker = job.ticker
        cursor_page = max(job.cursor_page or 1, 1)
        max_pages = job.max_pages
        per_page = job.per_page
        since = job.since_utc
        until = job.until_utc
        attempts = (job.attempts or 0) + 1
        job.status = "running"
        job.attempts = attempts
        job.started_at = job.started_at or _utcnow()
        job.updated_at = _utcnow()

    rows_seen = 0
    rows_new = 0
    earliest: dt.datetime | None = None
    latest: dt.datetime | None = None
    stop_reason = "max_pages"
    last_error = ""

    try:
        page.goto(f"https://xueqiu.com/S/{ticker}", wait_until="domcontentloaded", timeout=45_000)
        page.wait_for_timeout(1200)
    except Exception:
        # Page warmup can fail while the same-origin API still works from an existing xueqiu page.
        pass

    for page_no in range(cursor_page, max_pages + 1):
        data: dict[str, Any] | None = None
        for attempt in range(1, 4):
            try:
                data = _fetch_page(page, ticker, page_no, per_page)
                if data.get("ok"):
                    break
                if page_no == cursor_page:
                    page.goto(f"https://xueqiu.com/S/{ticker}", wait_until="domcontentloaded", timeout=45_000)
                    page.wait_for_timeout(1800)
                    data = _fetch_page(page, ticker, page_no, per_page)
                    if data.get("ok"):
                        break
                last_error = (
                    f"non-json status={data.get('status')} ctype={data.get('ctype')} "
                    f"sample={data.get('text')!r}"
                )
            except Exception as exc:
                last_error = str(exc).splitlines()[0]
                try:
                    page.goto(f"https://xueqiu.com/S/{ticker}", wait_until="domcontentloaded", timeout=45_000)
                    page.wait_for_timeout(1800)
                except Exception:
                    pass
            if attempt < 3:
                time.sleep(max(sleep * 2, 0.8))

        if data is None or not data.get("ok"):
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
            _update_checkpoint(job_id)
            print(f"  [xueqiu-job] {ticker} failed page={page_no}: {last_error}", flush=True)
            return {"job_id": job_id, "ticker": ticker, "status": "failed", "error": last_error}

        items = ((data.get("data") or {}).get("list") or [])
        if not items:
            stop_reason = "empty_page"
            break

        rows_seen += len(items)
        page_stats = _persist_items(ticker, items, since, until)
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
            print(f"  [xueqiu-job] {ticker} page={page_no} seen={rows_seen} new={rows_new}", flush=True)
        if page_stats["old"] and not page_stats["kept"]:
            stop_reason = "reached_since_cutoff"
            break
        time.sleep(max(sleep, 0))

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
    _update_checkpoint(job_id)
    print(f"  [xueqiu-job] {ticker} done seen={rows_seen} new={rows_new} stop={stop_reason}", flush=True)
    return {"job_id": job_id, "ticker": ticker, "status": "done", "seen": rows_seen, "new": rows_new}


def run_jobs(
    *,
    max_jobs: int | None = None,
    sleep: float = 0.35,
    headless: bool = False,
    retry_failed: bool = False,
    recover_running_hours: int = 0,
) -> dict[str, Any]:
    _ensure_tables()
    if recover_running_hours > 0:
        cutoff = _utcnow() - dt.timedelta(hours=recover_running_hours)
        with session_scope() as s:
            res = s.execute(
                update(XueqiuCrawlJob)
                .where(XueqiuCrawlJob.status == "running", XueqiuCrawlJob.updated_at < cutoff)
                .values(status="pending", last_error="recovered stale running job", updated_at=_utcnow())
            )
            if res.rowcount:
                print(f"[xueqiu-run] recovered stale running jobs={res.rowcount}", flush=True)
    statuses = ["pending"]
    if retry_failed:
        statuses.append("failed")
    with session_scope() as s:
        stmt = (
            select(XueqiuCrawlJob.id)
            .where(XueqiuCrawlJob.status.in_(statuses))
            .order_by(XueqiuCrawlJob.priority.asc(), XueqiuCrawlJob.created_at.asc(), XueqiuCrawlJob.id.asc())
        )
        if max_jobs:
            stmt = stmt.limit(max_jobs)
        job_ids = list(s.execute(stmt).scalars())
    if not job_ids:
        print("[xueqiu-run] 没有待运行任务。", flush=True)
        return {"jobs": 0, "done": 0, "failed": 0}

    try:
        from playwright.sync_api import sync_playwright
    except Exception as exc:
        raise RuntimeError("Python Playwright is required. Run `pipeline/.venv/bin/pip install playwright`.") from exc

    print(f"[xueqiu-run] jobs={len(job_ids)} headless={headless}", flush=True)
    results: list[dict[str, Any]] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome",
            headless=headless,
            args=["--disable-blink-features=AutomationControlled"],
        )
        context = browser.new_context(locale="zh-CN")
        page = context.new_page()
        try:
            page.goto("https://xueqiu.com/S/MU", wait_until="domcontentloaded", timeout=45_000)
            page.wait_for_timeout(1800)
            for job_id in job_ids:
                results.append(_run_job(page, job_id, sleep=sleep))
        finally:
            browser.close()

    done = sum(1 for r in results if r.get("status") == "done")
    failed = sum(1 for r in results if r.get("status") == "failed")
    print(f"[xueqiu-run] 完成 done={done} failed={failed}", flush=True)
    return {"jobs": len(job_ids), "done": done, "failed": failed}


def backfill(
    *,
    days: int = 365,
    only: list[str] | None = None,
    per_page: int = 20,
    max_pages: int = 1600,
    max_jobs: int | None = None,
    sleep: float = 0.35,
    headless: bool = False,
    force: bool = False,
    run: bool = True,
) -> dict[str, Any]:
    planned = plan_jobs(
        mode="backfill",
        days=days,
        only=only,
        per_page=per_page,
        max_pages=max_pages,
        priority=50,
        force=force,
    )
    ran = run_jobs(max_jobs=max_jobs, sleep=sleep, headless=headless) if run else {"jobs": 0}
    return {"planned": planned, "run": ran}


def incremental(
    *,
    days: int = 3,
    only: list[str] | None = None,
    per_page: int = 20,
    max_pages: int = 120,
    max_jobs: int | None = None,
    sleep: float = 0.35,
    headless: bool = False,
    force: bool = False,
    run: bool = True,
) -> dict[str, Any]:
    planned = plan_jobs(
        mode="incremental",
        days=days,
        only=only,
        per_page=per_page,
        max_pages=max_pages,
        priority=20,
        force=force,
    )
    ran = run_jobs(max_jobs=max_jobs, sleep=sleep, headless=headless) if run else {"jobs": 0}
    return {"planned": planned, "run": ran}


def _upsert_gr_posts(records: list[dict[str, Any]]) -> int:
    return _bulk_upsert(GrPost, records, ["id"])


def sync_to_gr_post(*, since_days: int = 365, only: list[str] | None = None) -> dict[str, int]:
    """Normalize xueqiu_raw_post + xueqiu_post_ticker into the existing gr_post table."""
    _ensure_tables()
    since = _utcnow() - dt.timedelta(days=since_days)
    only_set = {x.strip().upper() for x in only or [] if x.strip()}
    records: list[dict[str, Any]] = []
    with session_scope() as s:
        stmt = (
            select(XueqiuRawPost, XueqiuPostTicker)
            .join(XueqiuPostTicker, XueqiuPostTicker.native_id == XueqiuRawPost.native_id)
            .where(XueqiuRawPost.created_utc >= since)
        )
        if only_set:
            stmt = stmt.where(XueqiuPostTicker.ticker.in_(only_set))
        rows = s.execute(stmt).all()
        now = _utcnow()
        for raw, mapping in rows:
            body = (raw.text or "").strip()
            if not body:
                continue
            records.append({
                "id": f"cn:xueqiu:{mapping.ticker}:{raw.native_id}",
                "region": "cn",
                "source": "xueqiu",
                "ticker": mapping.ticker,
                "board_code": mapping.ticker,
                "lang": "zh",
                "author": (raw.author or "—")[:120],
                "title": "",
                "body": body[:1500],
                "label": mapping.role if mapping.role != "crawled" else None,
                "url": raw.url or f"https://xueqiu.com/statuses/{raw.native_id}",
                "likes": int(raw.like_count or 0),
                "dislikes": 0,
                "views": int(raw.view_count or 0),
                "comments": int(raw.reply_count or 0),
                "images": 0,
                "verified": False,
                "created_utc": raw.created_utc,
                "fetched_at": now,
            })
    n = _upsert_gr_posts(records)
    by: dict[str, int] = {}
    for rec in records:
        by[rec["ticker"]] = by.get(rec["ticker"], 0) + 1
    print(f"[xueqiu-sync] gr_post upsert={n} tickers={len(by)} top={sorted(by.items(), key=lambda x: -x[1])[:8]}", flush=True)
    return {"upserted": n, "tickers": len(by)}


def enrich_authors(*, since_days: int = 365) -> dict[str, int]:
    """Rebuild author snapshots from raw post payloads.

    This is cheap and lets old raw imports gain follower/friend metadata even if
    the direct crawler inserted raw before snapshot support existed.
    """
    _ensure_tables()
    since = _utcnow() - dt.timedelta(days=since_days)
    now = _utcnow()
    snapshots: list[dict[str, Any]] = []
    with session_scope() as s:
        raws = s.execute(
            select(XueqiuRawPost.raw).where(XueqiuRawPost.created_utc >= since, XueqiuRawPost.raw.is_not(None))
        ).scalars()
        for raw in raws:
            if not isinstance(raw, dict):
                continue
            snap = _author_snapshot(raw, now)
            if snap:
                snapshots.append(snap)
    n = _bulk_upsert(XueqiuAuthorSnapshot, snapshots, ["user_id", "snapshot_date"])
    print(f"[xueqiu-authors] snapshots upsert={n}", flush=True)
    return {"snapshots": n}


def _latin_pattern(alias: str) -> re.Pattern[str]:
    return re.compile(rf"(?<![A-Za-z0-9]){re.escape(alias)}(?![A-Za-z0-9])", re.I)


def _build_matchers() -> list[tuple[str, list[str], list[re.Pattern[str]]]]:
    matchers: list[tuple[str, list[str], list[re.Pattern[str]]]] = []
    for target in load_targets():
        ticker = target["ticker"].upper()
        cjk: list[str] = []
        latin: list[re.Pattern[str]] = [re.compile(rf"\${re.escape(ticker)}\b", re.I)]
        aliases = set(target.get("aliases") or [])
        aliases.add(ticker)
        aliases.add(target.get("name_en") or "")
        aliases.add(target.get("name_zh") or "")
        for alias in sorted(a.strip() for a in aliases if isinstance(a, str) and a.strip()):
            if any("\u4e00" <= ch <= "\u9fff" for ch in alias):
                cjk.append(alias)
            elif len(alias) >= 3:
                latin.append(_latin_pattern(alias))
            elif alias.upper() == ticker and len(alias) >= 2:
                latin.append(_latin_pattern(alias))
        matchers.append((ticker, sorted(set(cjk), key=len, reverse=True), latin))
    return matchers


def expand_related(*, since_days: int = 365, enqueue_top: int = 0) -> dict[str, int]:
    """Extract related tickers from raw Xueqiu text and optionally enqueue them."""
    _ensure_tables()
    since = _utcnow() - dt.timedelta(days=since_days)
    matchers = _build_matchers()
    rows: list[dict[str, Any]] = []
    counts: dict[str, int] = {}
    now = _utcnow()
    with session_scope() as s:
        raw_rows = s.execute(
            select(XueqiuRawPost.native_id, XueqiuRawPost.source_symbol, XueqiuRawPost.text, XueqiuRawPost.created_utc)
            .where(XueqiuRawPost.created_utc >= since)
        ).all()
    for native_id, source_symbol, text, created in raw_rows:
        text = text or ""
        for ticker, cjk_aliases, latin_patterns in matchers:
            hit = ticker == (source_symbol or "").upper()
            if not hit:
                hit = any(alias and alias in text for alias in cjk_aliases) or any(p.search(text) for p in latin_patterns)
            if not hit:
                continue
            role = "crawled" if ticker == (source_symbol or "").upper() else "mentioned"
            rows.append({
                "native_id": native_id,
                "ticker": ticker,
                "role": role,
                "confidence": 1.0 if role == "crawled" else 0.65,
                "created_utc": created,
                "updated_at": now,
            })
            if role == "mentioned":
                counts[ticker] = counts.get(ticker, 0) + 1

    n = _bulk_upsert(XueqiuPostTicker, rows, ["native_id", "ticker"])
    if enqueue_top > 0 and counts:
        top = [ticker for ticker, _ in sorted(counts.items(), key=lambda x: -x[1])[:enqueue_top]]
        plan_jobs(mode="related", days=since_days, only=top, per_page=20, max_pages=600, priority=80, force=False)
    print(f"[xueqiu-related] mappings upsert={n} mentioned_top={sorted(counts.items(), key=lambda x: -x[1])[:10]}", flush=True)
    return {"mappings": n, "mentioned_tickers": len(counts)}


def status() -> dict[str, Any]:
    _ensure_tables()
    with session_scope() as s:
        jobs = dict(s.execute(select(XueqiuCrawlJob.status, func.count()).group_by(XueqiuCrawlJob.status)).all())
        raw_posts = s.execute(select(func.count()).select_from(XueqiuRawPost)).scalar_one()
        maps = s.execute(select(func.count()).select_from(XueqiuPostTicker)).scalar_one()
        authors = s.execute(select(func.count()).select_from(XueqiuAuthorSnapshot)).scalar_one()
        checkpoints = s.execute(select(func.count()).select_from(XueqiuCrawlCheckpoint)).scalar_one()
    result = {
        "jobs": jobs,
        "raw_posts": int(raw_posts or 0),
        "post_ticker_maps": int(maps or 0),
        "author_snapshots": int(authors or 0),
        "checkpoints": int(checkpoints or 0),
    }
    print(f"[xueqiu-status] {result}", flush=True)
    return result
