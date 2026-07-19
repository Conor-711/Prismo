from __future__ import annotations

import datetime as dt
import json
import sqlite3

from pipeline.domain.smart_voice.v0_impl import (
    build_youtube_candidates,
    is_comparison_reference,
    rank_platform_band_rows,
    ranked_candidate_rows,
    youtube_transcript_candidate_rows,
)


def _database() -> sqlite3.Connection:
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript(
        """
        CREATE TABLE price_daily (ticker TEXT, date TEXT, close REAL);
        CREATE TABLE yt_author_pool_run (
          pool_version TEXT PRIMARY KEY,
          created_at TEXT NOT NULL
        );
        CREATE TABLE yt_author_pool (
          pool_version TEXT,
          channel_id TEXT,
          selected INTEGER,
          title TEXT,
          handle TEXT,
          subscriber_count INTEGER,
          platform_video_count INTEGER
        );
        CREATE TABLE yt_channel_upload (
          video_id TEXT PRIMARY KEY,
          channel_id TEXT,
          channel_title TEXT,
          title TEXT,
          description TEXT,
          published_utc TEXT,
          default_language TEXT,
          duration_s INTEGER,
          view_count INTEGER,
          like_count INTEGER,
          comment_count INTEGER,
          url TEXT
        );
        CREATE TABLE yt_channel_upload_ticker (
          video_id TEXT,
          ticker TEXT,
          method TEXT,
          confidence REAL,
          mapping_version TEXT
        );
        """
    )
    start = dt.date(2025, 1, 1)
    con.executemany(
        "INSERT INTO price_daily(ticker,date,close) VALUES ('MU',?,100)",
        [((start + dt.timedelta(days=index)).isoformat(),) for index in range(90)],
    )
    con.execute(
        "INSERT INTO yt_author_pool_run VALUES ('pool-v1','2026-07-10T00:00:00+00:00')"
    )
    con.execute(
        "INSERT INTO yt_author_pool VALUES ('pool-v1','channel-1',1,'Investor One','@one',25000,400)"
    )
    con.execute(
        """
        INSERT INTO yt_channel_upload VALUES (
          'video-1','channel-1','Investor One',
          '$MU stock could surge to $200 next month',
          'A detailed Micron valuation with catalysts, risks, entry levels, and a clear investment thesis.',
          '2026-07-09T12:00:00+00:00','en',720,10000,500,80,
          'https://www.youtube.com/watch?v=video-1'
        )
        """
    )
    con.execute(
        """
        INSERT INTO yt_channel_upload_ticker VALUES (
          'video-1','MU','title_cashtag',0.99,'youtube-title-v3'
        )
        """
    )
    return con


def test_author_pool_upload_becomes_youtube_sv_candidate() -> None:
    con = _database()

    inserted = build_youtube_candidates(
        con,
        limit=0,
        min_score=12,
        only=None,
        min_subscribers=1_000,
        since_days=365,
    )

    row = con.execute(
        "SELECT * FROM sv_call_candidate WHERE candidate_id='youtube:video-1:MU'"
    ).fetchone()
    assert inserted == 1
    assert row is not None
    assert row["author_id"] == "youtube:channel-1"
    assert "mapping=title_cashtag:0.99" in row["reason"]
    assert "mapping=title_cashtag:0.99" in row["source_file"]


def test_low_confidence_upload_mapping_is_not_recalled() -> None:
    con = _database()
    con.execute(
        "UPDATE yt_channel_upload_ticker SET confidence=0.89 WHERE video_id='video-1'"
    )

    inserted = build_youtube_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        min_subscribers=1_000,
        since_days=365,
    )

    assert inserted == 0
    assert con.execute("SELECT COUNT(*) FROM sv_call_candidate").fetchone()[0] == 0


def test_youtube_sv_candidate_requires_two_thousand_subscribers() -> None:
    con = _database()
    con.execute(
        "UPDATE yt_author_pool SET subscriber_count=1999 WHERE channel_id='channel-1'"
    )

    inserted = build_youtube_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        min_subscribers=1_000,
        since_days=365,
    )

    assert inserted == 0


def test_youtube_sv_candidate_requires_more_than_sixty_seconds() -> None:
    con = _database()
    con.execute("UPDATE yt_channel_upload SET duration_s=60 WHERE video_id='video-1'")

    inserted = build_youtube_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        min_subscribers=2_000,
        since_days=365,
    )

    assert inserted == 0


def test_existing_youtube_candidate_is_filtered_after_losing_eligibility() -> None:
    con = _database()
    build_youtube_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        min_subscribers=2_000,
        since_days=365,
    )
    con.execute(
        "UPDATE yt_author_pool SET subscriber_count=1999 WHERE channel_id='channel-1'"
    )

    assert ranked_candidate_rows(con, 10, False, {"youtube"}) == []


def test_youtube_extraction_selection_requires_complete_transcript() -> None:
    con = _database()
    build_youtube_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        min_subscribers=1_000,
        since_days=365,
    )
    con.execute(
        """CREATE TABLE yt_fulltext (
             video_id TEXT PRIMARY KEY, content_zh TEXT, content_en TEXT,
             segments TEXT, model TEXT, created_at TEXT
           )"""
    )

    assert ranked_candidate_rows(
        con, 10, False, {"youtube"}, transcript_backed=True
    ) == []

    con.execute(
        """INSERT INTO yt_fulltext VALUES
           ('video-1', ?, '', '[]', 'gemini:test', '2026-07-10T00:00:00Z')""",
        ("完整口播" * 30,),
    )
    rows = ranked_candidate_rows(
        con, 10, False, {"youtube"}, transcript_backed=True
    )

    assert [row["candidate_id"] for row in rows] == ["youtube:video-1:MU"]


def test_youtube_queue_honors_ticker_and_date_scope() -> None:
    con = _database()
    build_youtube_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        min_subscribers=2_000,
        since_days=365,
    )

    assert ranked_candidate_rows(
        con,
        10,
        True,
        {"youtube"},
        tickers={"NVDA"},
        youtube_created_since="2026-07-01",
    ) == []
    assert ranked_candidate_rows(
        con,
        10,
        True,
        {"youtube"},
        tickers={"MU"},
        youtube_created_since="2026-07-10",
    ) == []
    rows = ranked_candidate_rows(
        con,
        10,
        True,
        {"youtube"},
        tickers={"MU"},
        youtube_created_since="2026-07-01",
    )
    assert [row["candidate_id"] for row in rows] == ["youtube:video-1:MU"]


def test_reddit_extraction_selection_honors_date_scope() -> None:
    con = _database()
    build_youtube_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        min_subscribers=2_000,
        since_days=365,
    )
    con.executemany(
        "INSERT INTO sv_call_candidate "
        "(candidate_id,tweet_id,ticker,source,created_at) VALUES (?,?,?,?,?)",
        [
            ("reddit:old:MU", "old", "MU", "reddit", "2026-05-01T00:00:00Z"),
            ("reddit:new:MU", "new", "MU", "reddit", "2026-07-17T00:00:00Z"),
        ],
    )

    rows = ranked_candidate_rows(
        con,
        10,
        False,
        {"reddit"},
        tickers={"MU"},
        reddit_created_since="2026-06-17",
    )

    assert [row["candidate_id"] for row in rows] == ["reddit:new:MU"]


def test_transcript_batch_spreads_first_slots_across_authors() -> None:
    con = _database()
    for author_index in range(2, 4):
        channel_id = f"channel-{author_index}"
        con.execute(
            "INSERT INTO yt_author_pool VALUES ('pool-v1',?,1,?,?,25000,400)",
            (channel_id, f"Investor {author_index}", f"@author{author_index}"),
        )
        for video_index in range(1, 4):
            video_id = f"video-{author_index}-{video_index}"
            con.execute(
                """INSERT INTO yt_channel_upload VALUES (
                     ?,?,?,?,'Detailed valuation, catalysts, risks, and investment thesis.',
                     '2026-07-09T12:00:00+00:00','en',720,10000,500,80,?
                   )""",
                (
                    video_id,
                    channel_id,
                    f"Investor {author_index}",
                    f"$MU stock analysis {video_index}",
                    f"https://www.youtube.com/watch?v={video_id}",
                ),
            )
            con.execute(
                "INSERT INTO yt_channel_upload_ticker VALUES (?, 'MU', 'title_cashtag', 0.99, 'youtube-title-v3')",
                (video_id,),
            )
    build_youtube_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        min_subscribers=1_000,
        since_days=365,
    )

    rows = youtube_transcript_candidate_rows(
        con,
        limit=3,
        per_author_min=2,
        per_author_max=4,
        force=False,
    )

    assert len({row["author_id"] for row in rows}) == 3


def test_comparison_reference_detection_for_youtube_titles() -> None:
    assert is_comparison_reference(
        "Video title: The Next Nvidia Revealed: This AI Chip Stock Is About to Explode",
        "NVDA",
    )
    assert is_comparison_reference(
        "Video title: You Missed NVDA + PLTR. Don't Miss These Three Stocks",
        "PLTR",
    )
    assert not is_comparison_reference(
        "Video title: Nvidia Stock Could Rally After Earnings",
        "NVDA",
    )


def test_youtube_platform_bands_use_only_qualified_authors() -> None:
    rows = [
        {
            "investor_id": f"youtube:channel-{index}",
            "source": "youtube",
            "sv": 100 + index,
            "platform_scores_json": json.dumps({"youtube": 90 + index}),
            "n_eff": 8 if index < 10 else 1,
            "settled_calls": 7 if index < 10 else 1,
        }
        for index in range(12)
    ]

    band = rank_platform_band_rows(rows, "youtube")

    assert band["totalCount"] == 12
    assert band["qualifiedCount"] == 10
    assert band["rankedCount"] == 10
    assert band["population"] == "qualified"
    assert [row["investor_id"] for row in band["top10Rows"]] == ["youtube:channel-9"]
    assert [row["investor_id"] for row in band["bottom10Rows"]] == ["youtube:channel-0"]
    assert len(band["top25Rows"]) == 3
    assert len(band["bottom25Rows"]) == 3


def test_reddit_platform_bands_export_complete_deciles() -> None:
    rows = [
        {
            "investor_id": f"reddit:author-{index:02d}",
            "source": "reddit",
            "sv": 100,
            "platform_scores_json": json.dumps({"reddit": 80 + index}),
            "n_eff": 3 + index,
            "settled_calls": 4 + index,
        }
        for index in range(20)
    ]

    band = rank_platform_band_rows(rows, "reddit")

    assert band["qualifiedCount"] == 20
    assert band["rankedCount"] == 20
    assert [row["investor_id"] for row in band["top10Rows"]] == [
        "reddit:author-19",
        "reddit:author-18",
    ]
    assert [row["investor_id"] for row in band["bottom10Rows"]] == [
        "reddit:author-00",
        "reddit:author-01",
    ]
