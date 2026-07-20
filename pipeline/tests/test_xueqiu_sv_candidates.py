from __future__ import annotations

import datetime as dt
import json
import sqlite3

from pipeline.domain.smart_voice.v0_impl import (
    build_xueqiu_candidates,
    investor_profile_assets,
    rank_platform_band_rows,
)


def _database() -> sqlite3.Connection:
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript(
        """
        CREATE TABLE price_daily (ticker TEXT, date TEXT, close REAL);
        CREATE TABLE xueqiu_author_pool (
          pool_version TEXT,
          user_id TEXT,
          screen_name TEXT,
          selected INTEGER,
          author_type TEXT,
          updated_at TEXT
        );
        CREATE TABLE xueqiu_author_crawl_job (
          pool_version TEXT,
          user_id TEXT,
          status TEXT,
          since_utc TEXT,
          until_utc TEXT
        );
        CREATE TABLE xueqiu_raw_post (
          native_id TEXT PRIMARY KEY,
          source_symbol TEXT,
          author_id TEXT,
          author TEXT,
          text TEXT,
          lang TEXT,
          url TEXT,
          like_count INTEGER,
          reply_count INTEGER,
          view_count INTEGER,
          retweet_count INTEGER,
          created_utc TEXT,
          raw TEXT,
          first_seen_at TEXT,
          last_seen_at TEXT
        );
        CREATE TABLE xueqiu_post_ticker (
          native_id TEXT,
          ticker TEXT,
          role TEXT,
          confidence REAL,
          created_utc TEXT,
          updated_at TEXT
        );
        """
    )
    start = dt.date(2025, 1, 1)
    con.executemany(
        "INSERT INTO price_daily(ticker,date,close) VALUES ('MU',?,100)",
        [((start + dt.timedelta(days=index)).isoformat(),) for index in range(90)],
    )
    con.executemany(
        "INSERT INTO xueqiu_author_pool VALUES ('pool-v1',?,?,1,'creator','2026-07-10')",
        [("1001", "Investor One"), ("1002", "Investor Two")],
    )
    con.executemany(
        "INSERT INTO xueqiu_author_crawl_job VALUES ('pool-v1',?,?,?,?)",
        [
            ("1001", "done", "2025-07-10", "2026-07-10"),
            ("1002", "pending", "2025-07-10", "2026-07-10"),
        ],
    )
    con.execute(
        """INSERT INTO xueqiu_raw_post VALUES (
             'post-1','', '1001','Investor One',?, 'zh',
             'https://xueqiu.com/1001/post-1',30,12,0,2,
             '2026-06-15T12:00:00','{}','2026-07-10','2026-07-10'
           )""",
        (
            '<p>$MU 美光当前估值偏低，我会继续加仓，未来三个月目标价看到 180 美元。'
            '核心催化来自 HBM 需求，若毛利率恶化则观点失效。</p>',
        ),
    )
    con.execute(
        "INSERT INTO xueqiu_post_ticker VALUES ('post-1','MU','mentioned',0.65,'2026-06-15','2026-07-10')"
    )
    return con


def test_xueqiu_candidate_recall_waits_for_complete_selected_pool() -> None:
    con = _database()

    inserted = build_xueqiu_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        pool_version="pool-v1",
        since_days=365,
    )

    assert inserted == 0
    assert con.execute("SELECT COUNT(*) FROM sv_call_candidate").fetchone()[0] == 0


def test_completed_xueqiu_pool_becomes_sv_candidate() -> None:
    con = _database()
    con.execute(
        "UPDATE xueqiu_author_crawl_job SET status='done' WHERE user_id='1002'"
    )

    inserted = build_xueqiu_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        pool_version="pool-v1",
        since_days=365,
    )

    row = con.execute(
        "SELECT * FROM sv_call_candidate WHERE candidate_id='xueqiu:post-1:MU'"
    ).fetchone()
    assert inserted == 1
    assert row is not None
    assert row["author_id"] == "xueqiu:1001"
    assert row["source"] == "xueqiu"
    assert "pool=pool-v1" in row["source_file"]
    assert "美光当前估值偏低" in row["text"]


def test_partial_xueqiu_pool_only_recalls_completed_authors() -> None:
    con = _database()

    inserted = build_xueqiu_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        pool_version="pool-v1",
        since_days=365,
        require_complete_pool=False,
    )

    assert inserted == 1
    row = con.execute(
        "SELECT author_id FROM sv_call_candidate WHERE candidate_id='xueqiu:post-1:MU'"
    ).fetchone()
    assert row is not None
    assert row["author_id"] == "xueqiu:1001"


def test_xueqiu_repost_is_not_recalled() -> None:
    con = _database()
    con.execute(
        "UPDATE xueqiu_author_crawl_job SET status='done' WHERE user_id='1002'"
    )
    con.execute(
        "UPDATE xueqiu_raw_post SET raw=? WHERE native_id='post-1'",
        (json.dumps({"retweeted_status": {"id": "original"}}),),
    )

    inserted = build_xueqiu_candidates(
        con,
        limit=0,
        min_score=0,
        only=None,
        pool_version="pool-v1",
        since_days=365,
    )

    assert inserted == 0


def test_xueqiu_profile_uses_native_author_url() -> None:
    avatar, url = investor_profile_assets(
        "xueqiu",
        "xueqiu:5206097204",
        "永不褪色的信笺",
    )

    assert avatar is None
    assert url == "https://xueqiu.com/u/5206097204"


def test_xueqiu_observation_pool_does_not_expand_formal_ranking() -> None:
    rows = [
        {
            "investor_id": f"xueqiu:{index}",
            "source": "xueqiu",
            "sv": 100 + index,
            "n_eff": 6 if index < 8 else 2,
            "settled_calls": 9 if index < 8 else 3,
            "platform_scores_json": json.dumps({"xueqiu": 100 + index}),
        }
        for index in range(10)
    ]

    band = rank_platform_band_rows(rows, "xueqiu")

    assert band["totalCount"] == 10
    assert band["qualifiedCount"] == 8
    assert len(band["rankedRows"]) == 8
    assert len(band["observedRows"]) == 10
