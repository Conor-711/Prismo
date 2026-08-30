"""Refresh public X author profiles used by Smart Account clients.

The Smart Account score is intentionally not changed here. This module only
materializes public identity metadata (avatar, followers, bio and profile URL)
into a current table plus a daily history table. Client projections can then
show real author identities without depending on a live request at render time.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from ...common.config import RUNTIME_DATA_DIR


FXTWITTER_PROFILE_URL = "https://api.fxtwitter.com/{handle}"
USER_AGENT = "bSmartAuthorAssets/1.0"
QUALIFIED_X_FILTER = "source = 'x' AND n_eff >= 8 AND settled_calls >= 10"


@dataclass(frozen=True)
class XProfileCandidate:
    investor_id: str
    handle: str
    fallback_name: str


@dataclass(frozen=True)
class XProfile:
    author_id: str
    handle: str
    name: str
    avatar_url: str
    followers_count: int | None
    following_count: int | None
    posts_count: int | None
    media_count: int | None
    verified: bool
    verified_type: str
    description: str
    profile_url: str
    raw_json: str


def ensure_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS author_profile (
          source TEXT NOT NULL,
          author_id TEXT NOT NULL,
          handle TEXT NOT NULL,
          name TEXT NOT NULL DEFAULT '',
          avatar_url TEXT NOT NULL DEFAULT '',
          followers_count INTEGER,
          following_count INTEGER,
          posts_count INTEGER,
          media_count INTEGER,
          verified INTEGER NOT NULL DEFAULT 0,
          verified_type TEXT NOT NULL DEFAULT '',
          description TEXT NOT NULL DEFAULT '',
          profile_url TEXT NOT NULL DEFAULT '',
          fetched_at TEXT NOT NULL,
          raw_json TEXT,
          PRIMARY KEY (source, author_id)
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_author_profile_source_handle
          ON author_profile(source, handle);
        CREATE TABLE IF NOT EXISTS author_profile_snapshot (
          source TEXT NOT NULL,
          author_id TEXT NOT NULL,
          snapshot_date TEXT NOT NULL,
          handle TEXT NOT NULL,
          name TEXT NOT NULL DEFAULT '',
          avatar_url TEXT NOT NULL DEFAULT '',
          followers_count INTEGER,
          following_count INTEGER,
          posts_count INTEGER,
          media_count INTEGER,
          verified INTEGER NOT NULL DEFAULT 0,
          verified_type TEXT NOT NULL DEFAULT '',
          description TEXT NOT NULL DEFAULT '',
          profile_url TEXT NOT NULL DEFAULT '',
          fetched_at TEXT NOT NULL,
          raw_json TEXT,
          PRIMARY KEY (source, author_id, snapshot_date)
        );
        CREATE INDEX IF NOT EXISTS idx_author_profile_snapshot_handle_date
          ON author_profile_snapshot(source, handle, snapshot_date DESC);
        CREATE TABLE IF NOT EXISTS author_avatar (
          source TEXT NOT NULL,
          handle TEXT NOT NULL,
          url TEXT,
          fetched_at TEXT,
          PRIMARY KEY (source, handle)
        );
        """
    )


def profile_candidates(
    connection: sqlite3.Connection,
    *,
    qualified_only: bool,
    limit: int = 0,
) -> list[XProfileCandidate]:
    predicate = QUALIFIED_X_FILTER if qualified_only else "source = 'x'"
    limit_clause = " LIMIT ?" if limit > 0 else ""
    parameters: tuple[int, ...] = (limit,) if limit > 0 else ()
    rows = connection.execute(
        f"""
        SELECT investor_id,
               trim(replace(COALESCE(handle, ''), '@', '')) AS handle,
               COALESCE(NULLIF(name, ''), NULLIF(handle, ''), investor_id) AS fallback_name
          FROM sv_investor_score
         WHERE {predicate}
           AND trim(replace(COALESCE(handle, ''), '@', '')) <> ''
         ORDER BY sv DESC, n_eff DESC, settled_calls DESC, investor_id ASC
         {limit_clause}
        """,
        parameters,
    ).fetchall()
    seen: set[str] = set()
    candidates: list[XProfileCandidate] = []
    for investor_id, handle, fallback_name in rows:
        key = str(handle).lower()
        if key in seen:
            continue
        seen.add(key)
        candidates.append(
            XProfileCandidate(
                investor_id=str(investor_id),
                handle=str(handle),
                fallback_name=str(fallback_name),
            )
        )
    return candidates


def fetch_x_profile(handle: str, *, timeout: float = 20) -> dict[str, Any]:
    encoded = urllib.parse.quote(handle.lstrip("@"), safe="")
    request = urllib.request.Request(
        FXTWITTER_PROFILE_URL.format(handle=encoded),
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.load(response)
    if int(payload.get("code") or 0) != 200 or not isinstance(payload.get("user"), dict):
        raise ValueError(str(payload.get("message") or "X profile not found"))
    return payload["user"]


def normalize_x_profile(
    candidate: XProfileCandidate,
    payload: dict[str, Any],
) -> XProfile:
    handle = str(payload.get("screen_name") or candidate.handle).lstrip("@")
    verification = payload.get("verification") if isinstance(payload.get("verification"), dict) else {}
    author_id = str(payload.get("id") or candidate.investor_id)
    return XProfile(
        author_id=author_id,
        handle=handle,
        name=str(payload.get("name") or candidate.fallback_name).lstrip("@"),
        avatar_url=str(payload.get("avatar_url") or "").replace("_normal.", "_400x400."),
        followers_count=_optional_int(payload.get("followers")),
        following_count=_optional_int(payload.get("following")),
        posts_count=_optional_int(payload.get("tweets")),
        media_count=_optional_int(payload.get("media_count")),
        verified=bool(verification.get("verified")),
        verified_type=str(verification.get("type") or ""),
        description=str(payload.get("description") or ""),
        profile_url=str(payload.get("url") or f"https://x.com/{handle}"),
        raw_json=json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
    )


def _optional_int(value: Any) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _recent_handles(
    connection: sqlite3.Connection,
    *,
    max_age_hours: float,
) -> set[str]:
    cutoff = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=max_age_hours)).isoformat()
    return {
        str(row[0]).lower()
        for row in connection.execute(
            "SELECT handle FROM author_profile WHERE source='x' AND datetime(fetched_at) >= datetime(?)",
            (cutoff,),
        ).fetchall()
    }


def persist_x_profile(
    connection: sqlite3.Connection,
    profile: XProfile,
    *,
    fetched_at: dt.datetime,
) -> None:
    timestamp = fetched_at.astimezone(dt.timezone.utc).isoformat()
    values = (
        "x",
        profile.author_id,
        profile.handle,
        profile.name,
        profile.avatar_url,
        profile.followers_count,
        profile.following_count,
        profile.posts_count,
        profile.media_count,
        int(profile.verified),
        profile.verified_type,
        profile.description,
        profile.profile_url,
        timestamp,
        profile.raw_json,
    )
    connection.execute(
        """
        INSERT INTO author_profile (
          source, author_id, handle, name, avatar_url, followers_count,
          following_count, posts_count, media_count, verified, verified_type,
          description, profile_url, fetched_at, raw_json
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(source, author_id) DO UPDATE SET
          handle=excluded.handle, name=excluded.name, avatar_url=excluded.avatar_url,
          followers_count=excluded.followers_count, following_count=excluded.following_count,
          posts_count=excluded.posts_count, media_count=excluded.media_count,
          verified=excluded.verified, verified_type=excluded.verified_type,
          description=excluded.description, profile_url=excluded.profile_url,
          fetched_at=excluded.fetched_at, raw_json=excluded.raw_json
        """,
        values,
    )
    connection.execute(
        """
        INSERT INTO author_profile_snapshot (
          source, author_id, snapshot_date, handle, name, avatar_url,
          followers_count, following_count, posts_count, media_count, verified,
          verified_type, description, profile_url, fetched_at, raw_json
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(source, author_id, snapshot_date) DO UPDATE SET
          handle=excluded.handle, name=excluded.name, avatar_url=excluded.avatar_url,
          followers_count=excluded.followers_count, following_count=excluded.following_count,
          posts_count=excluded.posts_count, media_count=excluded.media_count,
          verified=excluded.verified, verified_type=excluded.verified_type,
          description=excluded.description, profile_url=excluded.profile_url,
          fetched_at=excluded.fetched_at, raw_json=excluded.raw_json
        """,
        ("x", profile.author_id, fetched_at.date().isoformat(), *values[2:]),
    )
    connection.execute(
        """
        INSERT INTO author_avatar(source, handle, url, fetched_at)
        VALUES ('x', ?, ?, ?)
        ON CONFLICT(source, handle) DO UPDATE SET
          url=excluded.url, fetched_at=excluded.fetched_at
        """,
        (profile.handle, profile.avatar_url, timestamp),
    )


def refresh_x_profiles(
    *,
    db_path: str | Path,
    qualified_only: bool = True,
    limit: int = 0,
    force: bool = False,
    max_age_hours: float = 24,
    workers: int = 4,
    fetcher: Callable[[str], dict[str, Any]] = fetch_x_profile,
) -> dict[str, Any]:
    database = Path(db_path).resolve()
    connection = sqlite3.connect(database)
    ensure_schema(connection)
    candidates = profile_candidates(connection, qualified_only=qualified_only, limit=limit)
    recent = set() if force else _recent_handles(connection, max_age_hours=max_age_hours)
    pending = [candidate for candidate in candidates if candidate.handle.lower() not in recent]

    fetched = 0
    failed: list[dict[str, str]] = []
    started_at = dt.datetime.now(dt.timezone.utc)

    def load(candidate: XProfileCandidate) -> tuple[XProfileCandidate, XProfile]:
        payload = fetcher(candidate.handle)
        return candidate, normalize_x_profile(candidate, payload)

    with ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
        futures = {executor.submit(load, candidate): candidate for candidate in pending}
        for future in as_completed(futures):
            candidate = futures[future]
            try:
                _, profile = future.result()
            except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as error:
                failed.append({"handle": candidate.handle, "error": str(error)[:240]})
                continue
            persist_x_profile(connection, profile, fetched_at=dt.datetime.now(dt.timezone.utc))
            fetched += 1
            if fetched % 25 == 0:
                connection.commit()
                print(f"[x-profiles] {fetched}/{len(pending)} fetched")
            time.sleep(0.03)

    connection.commit()
    coverage = connection.execute(
        """
        SELECT COUNT(*)
          FROM sv_investor_score score
          JOIN author_profile profile
            ON profile.source='x'
           AND profile.author_id=score.investor_id
         WHERE score.source='x'
        """
    ).fetchone()[0]
    connection.close()
    return {
        "database": str(database),
        "scope": "qualified" if qualified_only else "all",
        "candidates": len(candidates),
        "skippedFresh": len(candidates) - len(pending),
        "fetched": fetched,
        "failed": failed,
        "profileCoverage": int(coverage),
        "startedAt": started_at.isoformat(),
        "finishedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Refresh X author avatars and follower counts")
    parser.add_argument("--db", default=str(RUNTIME_DATA_DIR / "dev.db"))
    parser.add_argument("--all", action="store_true", help="Include observing authors, not only qualified ranks")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--max-age-hours", type=float, default=24)
    parser.add_argument("--report")
    args = parser.parse_args()
    result = refresh_x_profiles(
        db_path=args.db,
        qualified_only=not args.all,
        limit=args.limit,
        force=args.force,
        max_age_hours=args.max_age_hours,
        workers=args.workers,
    )
    rendered = json.dumps(result, ensure_ascii=False, indent=2)
    print(rendered)
    if args.report:
        report = Path(args.report)
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(rendered + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
