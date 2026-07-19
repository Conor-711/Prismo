from __future__ import annotations

import datetime as dt
import sqlite3

from pipeline.domain.authors.youtube_pool import build_pool, classify_channel_type
from pipeline.platforms.youtube.uploads import _duration_seconds


def _seed_db(path) -> None:
    con = sqlite3.connect(path)
    con.executescript(
        """
        CREATE TABLE yt_channel (
          channel_id TEXT PRIMARY KEY,
          title TEXT,
          handle TEXT,
          description TEXT,
          subscriber_count INTEGER,
          video_count INTEGER
        );
        CREATE TABLE yt_video (
          id TEXT PRIMARY KEY,
          channel_id TEXT,
          ticker TEXT,
          published_utc TEXT
        );
        CREATE TABLE yt_analysis (video_id TEXT PRIMARY KEY);
        CREATE TABLE yt_judgment (video_id TEXT PRIMARY KEY);
        CREATE TABLE sv_call (
          source TEXT,
          tweet_id TEXT,
          candidate_id TEXT,
          is_actionable_call INTEGER,
          ticker TEXT
        );
        """
    )
    con.executemany(
        "INSERT INTO yt_channel VALUES (?,?,?,?,?,?)",
        [
            ("creator-a", "Focused Value", "@focused", "US stock analysis", 2_000, 80),
            ("creator-b", "Growth Investor", "@growth", "Growth stocks", 8_000, 120),
            ("media-a", "CNBC Markets", "@cnbc", "Business news", 4_000_000, 90_000),
            ("small-a", "Small Investor", "@small", "Stocks", 500, 40),
        ],
    )
    published = dt.datetime.now(dt.timezone.utc).isoformat()
    videos = [
        ("a1", "creator-a", "MU", published),
        ("a2", "creator-a", "NVDA", published),
        ("a3", "creator-a", "MU", published),
        ("b1", "creator-b", "TSLA", published),
        ("b2", "creator-b", "TSLA", published),
        ("m1", "media-a", "MU", published),
        ("s1", "small-a", "MU", published),
    ]
    con.executemany("INSERT INTO yt_video VALUES (?,?,?,?)", videos)
    con.executemany("INSERT INTO yt_analysis VALUES (?)", [(row[0],) for row in videos])
    con.executemany("INSERT INTO yt_judgment VALUES (?)", [(row[0],) for row in videos])
    con.executemany(
        "INSERT INTO sv_call VALUES ('youtube',?,?,1,?)",
        [(row[0], f"call-{row[0]}", row[2]) for row in videos],
    )
    con.commit()
    con.close()


def test_build_pool_keeps_creators_and_separates_media(tmp_path):
    db_path = tmp_path / "pool.db"
    _seed_db(db_path)

    summary = build_pool(
        db_path,
        target_size=2,
        min_subscribers=1_000,
        since_days=365,
        pool_version="test-v1",
    )

    assert summary.considered == 3
    assert summary.creators == 2
    assert summary.media == 1
    assert summary.selected == 2

    con = sqlite3.connect(db_path)
    rows = con.execute(
        "SELECT channel_id, selected, channel_type FROM yt_author_pool "
        "WHERE pool_version='test-v1' ORDER BY channel_id"
    ).fetchall()
    con.close()
    assert rows == [
        ("creator-a", 1, "creator"),
        ("creator-b", 1, "creator"),
        ("media-a", 0, "media"),
    ]


def test_channel_classification_is_conservative():
    assert classify_channel_type(
        title="Bloomberg Television",
        handle="@markets",
        description="Market news",
        platform_video_count=90_000,
    )[0] == "media"
    assert classify_channel_type(
        title="The Trading Channel",
        handle="@thetradingchannel",
        description="Trading education by a full-time trader",
        platform_video_count=420,
    )[0] == "creator"


def test_youtube_duration_parser():
    assert _duration_seconds("PT1H2M3S") == 3723
    assert _duration_seconds("PT14M") == 840
    assert _duration_seconds("") == 0
