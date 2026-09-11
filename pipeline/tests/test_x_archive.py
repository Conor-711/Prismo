"""Incremental imports must preserve prior evidence and be safe to resume."""
import json

from sqlalchemy import create_engine, text

from pipeline.platforms.x.archive import import_archives
from pipeline.domain.smart_voice import v0_impl


def test_archive_preserves_history_and_is_idempotent(tmp_path):
    engine = create_engine("sqlite:///:memory:")
    with engine.begin() as con:
        con.exec_driver_sql("CREATE TABLE price_daily(ticker TEXT, close REAL)")
        con.exec_driver_sql("INSERT INTO price_daily VALUES (?,?)", [("NVDA", 100)] * 80)
        con.exec_driver_sql("CREATE TABLE x_opinion(tweet_id TEXT,ticker TEXT,handle TEXT,text TEXT,lang TEXT,likes INTEGER,retweets INTEGER,replies INTEGER,quotes INTEGER,views INTEGER,bookmarks INTEGER,created TEXT,url TEXT,PRIMARY KEY(ticker,tweet_id))")
        con.exec_driver_sql("INSERT INTO x_opinion(tweet_id,ticker,text) VALUES ('old','NVDA','historical evidence')")
    post = {"tweet_id": "new", "text": "New evidence", "created_at": "2026-08-13T00:01:00Z", "cashtags": ["$nvda", "NVDA", "NOPE"]}
    path = tmp_path / "tweets_2026-08.jsonl"
    path.write_text("\n".join(json.dumps(p) for p in [post, post, {**post, "tweet_id": "rt", "tweet_type": "retweet"}]))
    assert import_archives(engine, [tmp_path], dry_run=True)["inserted"] == 0
    assert import_archives(engine, [tmp_path])["inserted"] == 1
    assert import_archives(engine, [tmp_path])["inserted"] == 0
    with engine.connect() as con:
        assert con.execute(text("SELECT tweet_id,text FROM x_opinion ORDER BY tweet_id")).all() == [("new", "New evidence"), ("old", "historical evidence")]


def test_recent_candidates_exclude_old_and_already_extracted():
    import sqlite3
    engine = create_engine("sqlite:///:memory:")
    with engine.connect() as connection:
        con = connection.connection.driver_connection
        con.row_factory = sqlite3.Row
        v0_impl.ensure_tables(con)
        con.executemany("INSERT INTO sv_call_candidate(candidate_id,tweet_id,ticker,source,created_at) VALUES (?,?,?,?,?)", [
            ("old", "old", "NVDA", "x", "2026-08-12T00:00:00Z"),
            ("done", "done", "NVDA", "x", "2026-08-13T00:00:00Z"),
            ("new", "new", "NVDA", "x", "2026-08-14T00:00:00Z"),
        ])
        con.execute("INSERT INTO sv_call(candidate_id,tweet_id,ticker,source) VALUES ('done','done','NVDA','x')")
        assert [row["candidate_id"] for row in v0_impl.ranked_candidate_rows(con, 0, False, {"x"}, created_since="2026-08-13")] == ["new"]
        assert {row["candidate_id"] for row in v0_impl.ranked_candidate_rows(con, 0, False, {"x"})} == {"old", "new"}
        con.row_factory = None


def test_display_filter_precedes_top_n(monkeypatch):
    import datetime as dt
    from contextlib import contextmanager
    from pipeline.domain.opinions import kol_refine

    engine = create_engine("sqlite:///:memory:")
    recent = (dt.date.today() - dt.timedelta(days=1)).isoformat()
    old = (dt.date.today() - dt.timedelta(days=90)).isoformat()
    with engine.begin() as con:
        con.exec_driver_sql("CREATE TABLE x_opinion(tweet_id TEXT,ticker TEXT,text TEXT,created TEXT,likes INTEGER,retweets INTEGER,replies INTEGER)")
        con.exec_driver_sql("INSERT INTO x_opinion VALUES (?,?,?,?,?,0,0)", [
            ("old", "NVDA", "Old popular opinion", old, 10000),
            ("recent", "NVDA", "Recent opinion", recent, 5),
            ("elsewhere", "AAPL", "Other ticker opinion", recent, 50000),
        ])

    @contextmanager
    def session():
        with engine.connect() as con:
            yield con

    monkeypatch.setattr(kol_refine, "session_scope", session)
    rows = kol_refine._load("x", 1, {"NVDA"}, 40)
    assert [row["item_id"] for row in rows] == ["recent"]
