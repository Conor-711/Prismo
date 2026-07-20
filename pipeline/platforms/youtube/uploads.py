"""Backfill one-year uploads for the versioned YouTube SV author pool."""
from __future__ import annotations

import concurrent.futures
import datetime as dt
import json
import re
import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests


API_BASE = "https://www.googleapis.com/youtube/v3"
_PRINT_LOCK = threading.Lock()


@dataclass(frozen=True)
class BackfillSummary:
    pool_version: str
    requested_channels: int
    completed_channels: int
    partial_channels: int
    failed_channels: int
    videos_seen: int
    videos_stored: int


@dataclass(frozen=True)
class HydrationSummary:
    pool_version: str
    requested_videos: int
    hydrated_videos: int
    missing_videos: int


def _ensure_schema(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS yt_channel_upload (
          video_id TEXT PRIMARY KEY,
          channel_id TEXT NOT NULL,
          channel_title TEXT NOT NULL DEFAULT '',
          title TEXT NOT NULL DEFAULT '',
          description TEXT NOT NULL DEFAULT '',
          published_utc TEXT NOT NULL,
          default_language TEXT NOT NULL DEFAULT '',
          duration_s INTEGER NOT NULL DEFAULT 0,
          view_count INTEGER NOT NULL DEFAULT 0,
          like_count INTEGER NOT NULL DEFAULT 0,
          comment_count INTEGER NOT NULL DEFAULT 0,
          category_id TEXT NOT NULL DEFAULT '',
          tags_json TEXT NOT NULL DEFAULT '[]',
          topic_categories_json TEXT NOT NULL DEFAULT '[]',
          thumbnail TEXT NOT NULL DEFAULT '',
          url TEXT NOT NULL DEFAULT '',
          metadata_level TEXT NOT NULL DEFAULT 'playlist',
          fetched_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_yt_channel_upload_channel_date
          ON yt_channel_upload(channel_id, published_utc DESC);

        CREATE TABLE IF NOT EXISTS yt_channel_upload_pool (
          pool_version TEXT NOT NULL,
          channel_id TEXT NOT NULL,
          video_id TEXT NOT NULL,
          found_at TEXT NOT NULL,
          PRIMARY KEY (pool_version, channel_id, video_id)
        );

        CREATE INDEX IF NOT EXISTS idx_yt_channel_upload_pool_video
          ON yt_channel_upload_pool(video_id);

        CREATE TABLE IF NOT EXISTS yt_channel_upload_checkpoint (
          pool_version TEXT NOT NULL,
          channel_id TEXT NOT NULL,
          uploads_playlist_id TEXT NOT NULL DEFAULT '',
          cutoff_utc TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          pages_fetched INTEGER NOT NULL DEFAULT 0,
          videos_seen INTEGER NOT NULL DEFAULT 0,
          videos_stored INTEGER NOT NULL DEFAULT 0,
          newest_published_utc TEXT NOT NULL DEFAULT '',
          oldest_published_utc TEXT NOT NULL DEFAULT '',
          error TEXT NOT NULL DEFAULT '',
          started_at TEXT NOT NULL DEFAULT '',
          updated_at TEXT NOT NULL,
          PRIMARY KEY (pool_version, channel_id)
        );
        """
    )
    columns = {row[1] for row in con.execute("PRAGMA table_info(yt_channel_upload)")}
    if "metadata_level" not in columns:
        con.execute(
            "ALTER TABLE yt_channel_upload ADD COLUMN metadata_level TEXT NOT NULL DEFAULT 'playlist'"
        )


def _connect(db_path: str | Path) -> sqlite3.Connection:
    con = sqlite3.connect(str(db_path), timeout=60)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=60000")
    return con


def _request_json(
    session: requests.Session,
    endpoint: str,
    params: dict[str, Any],
    *,
    attempts: int = 5,
) -> dict[str, Any]:
    def safe_error(value: object) -> str:
        message = str(value)
        key = str(params.get("key") or "")
        return message.replace(key, "<redacted>") if key else message

    delay = 1.0
    last_error = "request failed"
    for attempt in range(attempts):
        try:
            response = session.get(f"{API_BASE}/{endpoint}", params=params, timeout=30)
        except requests.RequestException as exc:
            last_error = f"network:{type(exc).__name__}:{safe_error(exc)}"
        else:
            if response.status_code == 200:
                return response.json()
            body = response.text[:500]
            last_error = f"http:{response.status_code}:{body}"
            if response.status_code not in {429, 500, 502, 503, 504}:
                break
        if attempt + 1 < attempts:
            time.sleep(delay)
            delay = min(16.0, delay * 2)
    raise RuntimeError(last_error)


def _duration_seconds(value: str) -> int:
    match = re.fullmatch(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", value or "")
    if not match:
        return 0
    hours, minutes, seconds = (int(part or 0) for part in match.groups())
    return hours * 3600 + minutes * 60 + seconds


def _parse_utc(value: str) -> dt.datetime | None:
    if not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _latest_pool_version(con: sqlite3.Connection) -> str:
    row = con.execute(
        "SELECT pool_version FROM yt_author_pool_run ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    if not row:
        raise RuntimeError("yt_author_pool_run is empty; run youtube-author-pool first")
    return str(row[0])


def _selected_channels(
    con: sqlite3.Connection, pool_version: str, *, force: bool, cutoff_utc: str
) -> list[str]:
    rows = con.execute(
        """
        SELECT p.channel_id, c.status, c.cutoff_utc
        FROM yt_author_pool p
        LEFT JOIN yt_channel_upload_checkpoint c
          ON c.pool_version = p.pool_version AND c.channel_id = p.channel_id
        WHERE p.pool_version = ? AND p.selected = 1
        ORDER BY p.pool_rank
        """,
        (pool_version,),
    ).fetchall()
    selected = []
    for row in rows:
        already_complete = row["status"] == "complete" and row["cutoff_utc"] == cutoff_utc
        if force or not already_complete:
            selected.append(str(row["channel_id"]))
    return selected


def _playlist_ids(channel_ids: list[str], api_key: str) -> dict[str, str]:
    session = requests.Session()
    session.headers["User-Agent"] = "prismo-youtube-author-backfill/0.1"
    playlists: dict[str, str] = {}
    for index in range(0, len(channel_ids), 50):
        chunk = channel_ids[index : index + 50]
        payload = _request_json(
            session,
            "channels",
            {
                "part": "contentDetails",
                "id": ",".join(chunk),
                "maxResults": 50,
                "key": api_key,
            },
        )
        for item in payload.get("items", []):
            channel_id = item.get("id", "")
            uploads = (
                ((item.get("contentDetails") or {}).get("relatedPlaylists") or {}).get("uploads")
                or ""
            )
            if channel_id and uploads:
                playlists[channel_id] = uploads
    return playlists


def _hydrate_videos(
    session: requests.Session, video_ids: list[str], api_key: str
) -> list[dict[str, Any]]:
    if not video_ids:
        return []
    payload = _request_json(
        session,
        "videos",
        {
            "part": "snippet,statistics,contentDetails,topicDetails",
            "id": ",".join(video_ids),
            "maxResults": 50,
            "key": api_key,
        },
    )
    output = []
    for item in payload.get("items", []):
        snippet = item.get("snippet") or {}
        stats = item.get("statistics") or {}
        details = item.get("contentDetails") or {}
        topics = item.get("topicDetails") or {}
        output.append(
            {
                "video_id": item.get("id", ""),
                "channel_id": snippet.get("channelId", ""),
                "channel_title": snippet.get("channelTitle", ""),
                "title": snippet.get("title", ""),
                "description": (snippet.get("description") or "")[:10_000],
                "published_utc": snippet.get("publishedAt", ""),
                "default_language": snippet.get("defaultAudioLanguage")
                or snippet.get("defaultLanguage")
                or "",
                "duration_s": _duration_seconds(details.get("duration", "")),
                "view_count": int(stats.get("viewCount", 0) or 0),
                "like_count": int(stats.get("likeCount", 0) or 0),
                "comment_count": int(stats.get("commentCount", 0) or 0),
                "category_id": snippet.get("categoryId", ""),
                "tags_json": json.dumps(snippet.get("tags") or [], ensure_ascii=False),
                "topic_categories_json": json.dumps(
                    topics.get("topicCategories") or [], ensure_ascii=False
                ),
                "thumbnail": ((snippet.get("thumbnails") or {}).get("medium") or {}).get(
                    "url", ""
                ),
                "metadata_level": "hydrated",
            }
        )
    return output


def _store_page(
    con: sqlite3.Connection,
    *,
    pool_version: str,
    channel_id: str,
    videos: list[dict[str, Any]],
    fetched_at: str,
) -> int:
    stored = 0
    for video in videos:
        video_id = video["video_id"]
        if not video_id:
            continue
        con.execute(
            """
            INSERT INTO yt_channel_upload (
              video_id, channel_id, channel_title, title, description, published_utc,
              default_language, duration_s, view_count, like_count, comment_count,
              category_id, tags_json, topic_categories_json, thumbnail, url,
              metadata_level, fetched_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(video_id) DO UPDATE SET
              channel_id=excluded.channel_id,
              channel_title=excluded.channel_title,
              title=excluded.title,
              description=excluded.description,
              published_utc=excluded.published_utc,
              default_language=CASE WHEN excluded.default_language<>'' THEN excluded.default_language ELSE yt_channel_upload.default_language END,
              duration_s=MAX(yt_channel_upload.duration_s, excluded.duration_s),
              view_count=MAX(yt_channel_upload.view_count, excluded.view_count),
              like_count=MAX(yt_channel_upload.like_count, excluded.like_count),
              comment_count=MAX(yt_channel_upload.comment_count, excluded.comment_count),
              category_id=CASE WHEN excluded.category_id<>'' THEN excluded.category_id ELSE yt_channel_upload.category_id END,
              tags_json=CASE WHEN excluded.tags_json<>'[]' THEN excluded.tags_json ELSE yt_channel_upload.tags_json END,
              topic_categories_json=CASE WHEN excluded.topic_categories_json<>'[]' THEN excluded.topic_categories_json ELSE yt_channel_upload.topic_categories_json END,
              thumbnail=excluded.thumbnail,
              url=excluded.url,
              metadata_level=CASE WHEN yt_channel_upload.metadata_level='hydrated' THEN 'hydrated' ELSE excluded.metadata_level END,
              fetched_at=excluded.fetched_at
            """,
            (
                video_id,
                video["channel_id"] or channel_id,
                video["channel_title"],
                video["title"],
                video["description"],
                video["published_utc"],
                video["default_language"],
                video["duration_s"],
                video["view_count"],
                video["like_count"],
                video["comment_count"],
                video["category_id"],
                video["tags_json"],
                video["topic_categories_json"],
                video["thumbnail"],
                f"https://www.youtube.com/watch?v={video_id}",
                video.get("metadata_level", "playlist"),
                fetched_at,
            ),
        )
        con.execute(
            """
            INSERT OR IGNORE INTO yt_channel_upload_pool
              (pool_version, channel_id, video_id, found_at)
            VALUES (?,?,?,?)
            """,
            (pool_version, channel_id, video_id, fetched_at),
        )
        stored += 1
    return stored


def _checkpoint(
    con: sqlite3.Connection,
    *,
    pool_version: str,
    channel_id: str,
    playlist_id: str,
    cutoff_utc: str,
    status: str,
    pages_fetched: int,
    videos_seen: int,
    videos_stored: int,
    newest: str,
    oldest: str,
    error: str,
    started_at: str,
) -> None:
    updated_at = dt.datetime.now(dt.timezone.utc).isoformat()
    con.execute(
        """
        INSERT INTO yt_channel_upload_checkpoint (
          pool_version, channel_id, uploads_playlist_id, cutoff_utc, status,
          pages_fetched, videos_seen, videos_stored, newest_published_utc,
          oldest_published_utc, error, started_at, updated_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(pool_version, channel_id) DO UPDATE SET
          uploads_playlist_id=excluded.uploads_playlist_id,
          cutoff_utc=excluded.cutoff_utc,
          status=excluded.status,
          pages_fetched=excluded.pages_fetched,
          videos_seen=excluded.videos_seen,
          videos_stored=excluded.videos_stored,
          newest_published_utc=excluded.newest_published_utc,
          oldest_published_utc=excluded.oldest_published_utc,
          error=excluded.error,
          started_at=excluded.started_at,
          updated_at=excluded.updated_at
        """,
        (
            pool_version,
            channel_id,
            playlist_id,
            cutoff_utc,
            status,
            pages_fetched,
            videos_seen,
            videos_stored,
            newest,
            oldest,
            error[:1000],
            started_at,
            updated_at,
        ),
    )
    con.commit()


def _crawl_channel(
    *,
    db_path: str | Path,
    api_key: str,
    pool_version: str,
    channel_id: str,
    playlist_id: str,
    cutoff: dt.datetime,
    max_pages: int,
    hydrate_metadata: bool,
) -> dict[str, Any]:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    cutoff_utc = cutoff.isoformat()
    session = requests.Session()
    session.headers["User-Agent"] = "prismo-youtube-author-backfill/0.1"
    con = _connect(db_path)
    pages = 0
    seen = 0
    stored = 0
    newest = ""
    oldest = ""
    page_token = ""
    status = "running"
    error = ""
    try:
        _checkpoint(
            con,
            pool_version=pool_version,
            channel_id=channel_id,
            playlist_id=playlist_id,
            cutoff_utc=cutoff_utc,
            status=status,
            pages_fetched=0,
            videos_seen=0,
            videos_stored=0,
            newest="",
            oldest="",
            error="",
            started_at=started_at,
        )
        while True:
            params: dict[str, Any] = {
                "part": "snippet,contentDetails",
                "playlistId": playlist_id,
                "maxResults": 50,
                "key": api_key,
            }
            if page_token:
                params["pageToken"] = page_token
            payload = _request_json(session, "playlistItems", params)
            pages += 1
            page_items = payload.get("items", [])
            in_window_videos: list[dict[str, Any]] = []
            reached_cutoff = False
            for item in page_items:
                details = item.get("contentDetails") or {}
                snippet = item.get("snippet") or {}
                video_id = details.get("videoId") or ((snippet.get("resourceId") or {}).get("videoId"))
                published = details.get("videoPublishedAt") or snippet.get("publishedAt") or ""
                published_dt = _parse_utc(published)
                if published_dt is not None:
                    newest = max(newest, published) if newest else published
                    oldest = min(oldest, published) if oldest else published
                    if published_dt < cutoff:
                        reached_cutoff = True
                        continue
                if video_id:
                    in_window_videos.append(
                        {
                            "video_id": video_id,
                            "channel_id": snippet.get("channelId", "") or channel_id,
                            "channel_title": snippet.get("channelTitle", ""),
                            "title": snippet.get("title", ""),
                            "description": (snippet.get("description") or "")[:10_000],
                            "published_utc": published,
                            "default_language": "",
                            "duration_s": 0,
                            "view_count": 0,
                            "like_count": 0,
                            "comment_count": 0,
                            "category_id": "",
                            "tags_json": "[]",
                            "topic_categories_json": "[]",
                            "thumbnail": ((snippet.get("thumbnails") or {}).get("medium") or {}).get(
                                "url", ""
                            ),
                            "metadata_level": "playlist",
                        }
                    )
            seen += len(in_window_videos)
            videos = (
                _hydrate_videos(
                    session,
                    [video["video_id"] for video in in_window_videos],
                    api_key,
                )
                if hydrate_metadata
                else in_window_videos
            )
            fetched_at = dt.datetime.now(dt.timezone.utc).isoformat()
            stored += _store_page(
                con,
                pool_version=pool_version,
                channel_id=channel_id,
                videos=videos,
                fetched_at=fetched_at,
            )
            page_token = payload.get("nextPageToken") or ""
            status = "running"
            if reached_cutoff or not page_token:
                status = "complete"
            elif max_pages > 0 and pages >= max_pages:
                status = "partial"
            _checkpoint(
                con,
                pool_version=pool_version,
                channel_id=channel_id,
                playlist_id=playlist_id,
                cutoff_utc=cutoff_utc,
                status=status,
                pages_fetched=pages,
                videos_seen=seen,
                videos_stored=stored,
                newest=newest,
                oldest=oldest,
                error="",
                started_at=started_at,
            )
            if status != "running":
                break
    except Exception as exc:
        status = "failed"
        error = f"{type(exc).__name__}:{exc}"
        _checkpoint(
            con,
            pool_version=pool_version,
            channel_id=channel_id,
            playlist_id=playlist_id,
            cutoff_utc=cutoff_utc,
            status=status,
            pages_fetched=pages,
            videos_seen=seen,
            videos_stored=stored,
            newest=newest,
            oldest=oldest,
            error=error,
            started_at=started_at,
        )
    finally:
        con.close()
    return {
        "channel_id": channel_id,
        "status": status,
        "pages": pages,
        "videos_seen": seen,
        "videos_stored": stored,
        "error": error,
    }


def backfill_author_uploads(
    db_path: str | Path,
    *,
    api_key: str,
    pool_version: str | None = None,
    since_days: int = 365,
    workers: int = 6,
    limit_channels: int | None = None,
    max_pages: int = 0,
    force: bool = False,
    hydrate_metadata: bool = False,
) -> BackfillSummary:
    """Backfill selected creator uploads and keep per-channel checkpoints."""
    if not api_key:
        raise RuntimeError("YOUTUBE_API_KEY is required")
    if since_days <= 0:
        raise ValueError("since_days must be positive")
    if workers <= 0:
        raise ValueError("workers must be positive")

    cutoff_day = dt.datetime.now(dt.timezone.utc).date() - dt.timedelta(days=since_days)
    cutoff = dt.datetime.combine(cutoff_day, dt.time.min, tzinfo=dt.timezone.utc)
    cutoff_utc = cutoff.isoformat()
    con = _connect(db_path)
    con.execute("PRAGMA journal_mode=WAL")
    _ensure_schema(con)
    pool_version = pool_version or _latest_pool_version(con)
    channel_ids = _selected_channels(con, pool_version, force=force, cutoff_utc=cutoff_utc)
    if limit_channels is not None:
        channel_ids = channel_ids[: max(0, limit_channels)]
    con.commit()
    con.close()
    if not channel_ids:
        return BackfillSummary(pool_version, 0, 0, 0, 0, 0, 0)

    playlists = _playlist_ids(channel_ids, api_key)
    missing = [channel_id for channel_id in channel_ids if channel_id not in playlists]
    if missing:
        con = _connect(db_path)
        for channel_id in missing:
            _checkpoint(
                con,
                pool_version=pool_version,
                channel_id=channel_id,
                playlist_id="",
                cutoff_utc=cutoff_utc,
                status="failed",
                pages_fetched=0,
                videos_seen=0,
                videos_stored=0,
                newest="",
                oldest="",
                error="uploads_playlist_missing",
                started_at=dt.datetime.now(dt.timezone.utc).isoformat(),
            )
        con.close()

    work = [(channel_id, playlists[channel_id]) for channel_id in channel_ids if channel_id in playlists]
    results: list[dict[str, Any]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(
                _crawl_channel,
                db_path=db_path,
                api_key=api_key,
                pool_version=pool_version,
                channel_id=channel_id,
                playlist_id=playlist_id,
                cutoff=cutoff,
                max_pages=max_pages,
                hydrate_metadata=hydrate_metadata,
            ): channel_id
            for channel_id, playlist_id in work
        }
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            result = future.result()
            results.append(result)
            with _PRINT_LOCK:
                print(
                    f"[yt-author-backfill] {index}/{len(work)} {result['channel_id']} "
                    f"status={result['status']} pages={result['pages']} "
                    f"videos={result['videos_stored']}",
                    flush=True,
                )

    completed = sum(result["status"] == "complete" for result in results)
    partial = sum(result["status"] == "partial" for result in results)
    failed = len(missing) + sum(result["status"] == "failed" for result in results)
    return BackfillSummary(
        pool_version=pool_version,
        requested_channels=len(channel_ids),
        completed_channels=completed,
        partial_channels=partial,
        failed_channels=failed,
        videos_seen=sum(int(result["videos_seen"]) for result in results),
        videos_stored=sum(int(result["videos_stored"]) for result in results),
    )


def hydrate_mapped_uploads(
    db_path: str | Path,
    *,
    api_key: str,
    pool_version: str | None = None,
    min_confidence: float = 0.78,
    limit: int | None = None,
    workers: int = 6,
    force: bool = False,
) -> HydrationSummary:
    """Hydrate only mapped finance videos with statistics and duration metadata."""
    if not api_key:
        raise RuntimeError("YOUTUBE_API_KEY is required")
    if not 0 <= min_confidence <= 1:
        raise ValueError("min_confidence must be between 0 and 1")
    con = _connect(db_path)
    _ensure_schema(con)
    pool_version = pool_version or _latest_pool_version(con)
    con.execute(
        """
        UPDATE yt_channel_upload
        SET metadata_level='hydrated'
        WHERE metadata_level<>'hydrated'
          AND (duration_s>0 OR view_count>0 OR like_count>0 OR comment_count>0)
        """
    )
    hydration_filter = "" if force else "AND u.metadata_level <> 'hydrated'"
    sql = f"""
        SELECT DISTINCT u.video_id
        FROM yt_channel_upload u
        JOIN yt_channel_upload_ticker m ON m.video_id=u.video_id AND m.confidence>=?
        JOIN yt_author_pool p
          ON p.channel_id=u.channel_id AND p.pool_version=? AND p.selected=1
        WHERE 1=1 {hydration_filter}
        ORDER BY u.published_utc DESC
    """
    # SQL placeholder order follows the JOIN clauses.
    params: list[Any] = [min_confidence, pool_version]
    if limit is not None:
        sql += " LIMIT ?"
        params.append(max(0, limit))
    video_ids = [str(row[0]) for row in con.execute(sql, params)]
    con.commit()
    if not video_ids:
        con.close()
        return HydrationSummary(pool_version, 0, 0, 0)

    chunks = [video_ids[index : index + 50] for index in range(0, len(video_ids), 50)]

    def fetch(chunk: list[str]) -> list[dict[str, Any]]:
        session = requests.Session()
        session.headers["User-Agent"] = "prismo-youtube-author-hydrate/0.1"
        return _hydrate_videos(session, chunk, api_key)

    hydrated = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
        futures = {executor.submit(fetch, chunk): chunk for chunk in chunks}
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                videos = future.result()
            except Exception as exc:
                print(
                    f"[yt-author-hydrate] batch_failed size={len(futures[future])} "
                    f"error={type(exc).__name__}:{str(exc)[:240]}",
                    flush=True,
                )
                continue
            by_channel: dict[str, list[dict[str, Any]]] = {}
            for video in videos:
                by_channel.setdefault(str(video["channel_id"] or ""), []).append(video)
            fetched_at = dt.datetime.now(dt.timezone.utc).isoformat()
            for channel_id, channel_videos in by_channel.items():
                hydrated += _store_page(
                    con,
                    pool_version=pool_version,
                    channel_id=channel_id,
                    videos=channel_videos,
                    fetched_at=fetched_at,
                )
            con.commit()
            if index % 20 == 0 or index == len(chunks):
                print(
                    f"[yt-author-hydrate] batches={index}/{len(chunks)} hydrated={hydrated}",
                    flush=True,
                )
    con.close()
    return HydrationSummary(
        pool_version=pool_version,
        requested_videos=len(video_ids),
        hydrated_videos=hydrated,
        missing_videos=max(0, len(video_ids) - hydrated),
    )
