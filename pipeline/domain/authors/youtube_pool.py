"""Build a reproducible YouTube creator candidate pool for Smart Account."""
from __future__ import annotations

import datetime as dt
import json
import math
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path


KNOWN_MEDIA_NAMES = (
    "bloomberg",
    "cnbc",
    "fox business",
    "reuters",
    "wall street journal",
    "yahoo finance",
    "financial times",
    "business insider",
    "marketwatch",
    "morningstar",
    "benzinga",
    "seeking alpha",
    "motley fool",
    "investing.com",
    "zacks investment research",
    "the street",
)

MEDIA_TEXT_PATTERNS = (
    re.compile(r"\bbusiness news\b", re.I),
    re.compile(r"\bfinancial news\b", re.I),
    re.compile(r"\bnews network\b", re.I),
    re.compile(r"\btelevision network\b", re.I),
    re.compile(r"\bbreaking news\b", re.I),
    re.compile(r"\bmarket news channel\b", re.I),
)


@dataclass(frozen=True)
class PoolSummary:
    pool_version: str
    considered: int
    selected: int
    media: int
    creators: int
    min_subscribers: int
    target_size: int


def _ensure_schema(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS yt_author_pool_run (
          pool_version TEXT PRIMARY KEY,
          created_at TEXT NOT NULL,
          since_days INTEGER NOT NULL,
          min_subscribers INTEGER NOT NULL,
          target_size INTEGER NOT NULL,
          considered_count INTEGER NOT NULL,
          selected_count INTEGER NOT NULL,
          creator_count INTEGER NOT NULL,
          media_count INTEGER NOT NULL,
          rules_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS yt_author_pool (
          pool_version TEXT NOT NULL,
          channel_id TEXT NOT NULL,
          pool_rank INTEGER,
          selected INTEGER NOT NULL DEFAULT 0,
          channel_type TEXT NOT NULL DEFAULT 'creator',
          type_reason TEXT NOT NULL DEFAULT '',
          title TEXT NOT NULL DEFAULT '',
          handle TEXT NOT NULL DEFAULT '',
          subscriber_count INTEGER NOT NULL DEFAULT 0,
          platform_video_count INTEGER NOT NULL DEFAULT 0,
          collected_videos INTEGER NOT NULL DEFAULT 0,
          covered_tickers INTEGER NOT NULL DEFAULT 0,
          analyzed_videos INTEGER NOT NULL DEFAULT 0,
          analyzed_tickers INTEGER NOT NULL DEFAULT 0,
          judgment_videos INTEGER NOT NULL DEFAULT 0,
          judgment_tickers INTEGER NOT NULL DEFAULT 0,
          actionable_calls INTEGER NOT NULL DEFAULT 0,
          actionable_tickers INTEGER NOT NULL DEFAULT 0,
          selection_score REAL NOT NULL DEFAULT 0,
          selection_reason TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          PRIMARY KEY (pool_version, channel_id)
        );

        CREATE INDEX IF NOT EXISTS idx_yt_author_pool_selected
          ON yt_author_pool(pool_version, selected, pool_rank);
        CREATE INDEX IF NOT EXISTS idx_yt_author_pool_channel
          ON yt_author_pool(channel_id);
        """
    )


def classify_channel_type(
    *, title: str, handle: str, description: str, platform_video_count: int
) -> tuple[str, str]:
    """Conservatively split high-volume publishers from creator channels."""
    name = f"{title} {handle}".lower()
    text = f"{title} {description}"
    for marker in KNOWN_MEDIA_NAMES:
        if marker in name:
            return "media", f"known_media:{marker}"
    if platform_video_count >= 10_000:
        return "media", "publisher_volume>=10000"
    for pattern in MEDIA_TEXT_PATTERNS:
        if pattern.search(text):
            return "media", f"publisher_text:{pattern.pattern}"
    return "creator", "creator_default"


def _selection_score(row: sqlite3.Row) -> float:
    videos = max(0, int(row["collected_videos"] or 0))
    tickers = max(0, int(row["covered_tickers"] or 0))
    analyzed = max(0, int(row["analyzed_videos"] or 0))
    calls = max(0, int(row["actionable_calls"] or 0))
    subscribers = max(1, int(row["subscriber_count"] or 0))

    video_score = min(42.0, 15.0 * math.log2(1 + videos))
    ticker_score = min(20.0, 10.0 * math.log2(1 + tickers))
    analysis_score = 14.0 * min(1.0, analyzed / max(1, videos))
    call_score = min(9.0, 3.0 * math.log2(1 + calls))
    subscriber_score = min(15.0, max(0.0, (math.log10(subscribers) - 3.0) * 5.0))
    return round(video_score + ticker_score + analysis_score + call_score + subscriber_score, 4)


def build_pool(
    db_path: str | Path,
    *,
    target_size: int = 500,
    min_subscribers: int = 1_000,
    since_days: int = 365,
    pool_version: str | None = None,
) -> PoolSummary:
    """Rank eligible channels and persist a versioned candidate pool snapshot."""
    if target_size <= 0:
        raise ValueError("target_size must be positive")
    if min_subscribers < 0:
        raise ValueError("min_subscribers must be non-negative")
    if since_days <= 0:
        raise ValueError("since_days must be positive")

    now = dt.datetime.now(dt.timezone.utc)
    pool_version = pool_version or f"youtube-sv-pool-{now:%Y%m%dT%H%M%SZ}"
    cutoff = (now - dt.timedelta(days=since_days)).isoformat()
    con = sqlite3.connect(str(db_path), timeout=30)
    con.row_factory = sqlite3.Row
    _ensure_schema(con)

    rows = list(
        con.execute(
            """
            WITH evidence AS (
              SELECT
                v.channel_id,
                COUNT(DISTINCT v.id) AS collected_videos,
                COUNT(DISTINCT v.ticker) AS covered_tickers,
                COUNT(DISTINCT a.video_id) AS analyzed_videos,
                COUNT(DISTINCT CASE WHEN a.video_id IS NOT NULL THEN v.ticker END) AS analyzed_tickers,
                COUNT(DISTINCT j.video_id) AS judgment_videos,
                COUNT(DISTINCT CASE WHEN j.video_id IS NOT NULL THEN v.ticker END) AS judgment_tickers,
                COUNT(DISTINCT CASE WHEN c.is_actionable_call = 1 THEN c.candidate_id END) AS actionable_calls,
                COUNT(DISTINCT CASE WHEN c.is_actionable_call = 1 THEN c.ticker END) AS actionable_tickers
              FROM yt_video v
              LEFT JOIN yt_analysis a ON a.video_id = v.id
              LEFT JOIN yt_judgment j ON j.video_id = v.id
              LEFT JOIN sv_call c ON c.source = 'youtube' AND c.tweet_id = v.id
              WHERE datetime(v.published_utc) >= datetime(?)
                AND v.channel_id IS NOT NULL AND v.channel_id <> ''
              GROUP BY v.channel_id
            ), metadata AS (
              SELECT
                channel_id,
                MAX(title) AS title,
                MAX(handle) AS handle,
                MAX(description) AS description,
                MAX(subscriber_count) AS subscriber_count,
                MAX(video_count) AS platform_video_count
              FROM yt_channel
              GROUP BY channel_id
            )
            SELECT e.*, m.title, m.handle, m.description, m.subscriber_count, m.platform_video_count
            FROM evidence e
            JOIN metadata m USING(channel_id)
            WHERE COALESCE(m.subscriber_count, -1) >= ?
            """,
            (cutoff, min_subscribers),
        )
    )

    enriched: list[dict] = []
    for row in rows:
        channel_type, type_reason = classify_channel_type(
            title=row["title"] or "",
            handle=row["handle"] or "",
            description=row["description"] or "",
            platform_video_count=int(row["platform_video_count"] or 0),
        )
        enriched.append(
            {
                **dict(row),
                "channel_type": channel_type,
                "type_reason": type_reason,
                "selection_score": _selection_score(row),
            }
        )

    creators = sorted(
        (row for row in enriched if row["channel_type"] == "creator"),
        key=lambda row: (
            -float(row["selection_score"]),
            -int(row["collected_videos"] or 0),
            -int(row["covered_tickers"] or 0),
            -int(row["subscriber_count"] or 0),
            str(row["channel_id"]),
        ),
    )
    selected_ids = {row["channel_id"] for row in creators[:target_size]}
    rank_by_id = {row["channel_id"]: rank for rank, row in enumerate(creators[:target_size], 1)}

    con.execute("DELETE FROM yt_author_pool WHERE pool_version = ?", (pool_version,))
    payload = []
    for row in enriched:
        selected = int(row["channel_id"] in selected_ids)
        reason = (
            "selected_by_creator_rank"
            if selected
            else ("separate_media_pool" if row["channel_type"] == "media" else "below_target_rank")
        )
        payload.append(
            (
                pool_version,
                row["channel_id"],
                rank_by_id.get(row["channel_id"]),
                selected,
                row["channel_type"],
                row["type_reason"],
                row["title"] or "",
                row["handle"] or "",
                int(row["subscriber_count"] or 0),
                int(row["platform_video_count"] or 0),
                int(row["collected_videos"] or 0),
                int(row["covered_tickers"] or 0),
                int(row["analyzed_videos"] or 0),
                int(row["analyzed_tickers"] or 0),
                int(row["judgment_videos"] or 0),
                int(row["judgment_tickers"] or 0),
                int(row["actionable_calls"] or 0),
                int(row["actionable_tickers"] or 0),
                float(row["selection_score"]),
                reason,
                now.isoformat(),
            )
        )
    con.executemany(
        """
        INSERT INTO yt_author_pool (
          pool_version, channel_id, pool_rank, selected, channel_type, type_reason,
          title, handle, subscriber_count, platform_video_count, collected_videos,
          covered_tickers, analyzed_videos, analyzed_tickers, judgment_videos,
          judgment_tickers, actionable_calls, actionable_tickers, selection_score,
          selection_reason, created_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """,
        payload,
    )
    rules = {
        "min_subscribers": min_subscribers,
        "min_collected_videos": 1,
        "since_days": since_days,
        "target_size": target_size,
        "exclude_media_from_creator_pool": True,
    }
    con.execute(
        """
        INSERT INTO yt_author_pool_run (
          pool_version, created_at, since_days, min_subscribers, target_size,
          considered_count, selected_count, creator_count, media_count, rules_json
        ) VALUES (?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(pool_version) DO UPDATE SET
          created_at=excluded.created_at,
          since_days=excluded.since_days,
          min_subscribers=excluded.min_subscribers,
          target_size=excluded.target_size,
          considered_count=excluded.considered_count,
          selected_count=excluded.selected_count,
          creator_count=excluded.creator_count,
          media_count=excluded.media_count,
          rules_json=excluded.rules_json
        """,
        (
            pool_version,
            now.isoformat(),
            since_days,
            min_subscribers,
            target_size,
            len(enriched),
            len(selected_ids),
            len(creators),
            len(enriched) - len(creators),
            json.dumps(rules, ensure_ascii=False, sort_keys=True),
        ),
    )
    con.commit()
    con.close()
    return PoolSummary(
        pool_version=pool_version,
        considered=len(enriched),
        selected=len(selected_ids),
        media=len(enriched) - len(creators),
        creators=len(creators),
        min_subscribers=min_subscribers,
        target_size=target_size,
    )
