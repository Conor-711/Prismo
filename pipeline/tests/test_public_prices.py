import json
import sqlite3
from datetime import date

from pipeline.platforms.market_data import public_prices
from pipeline.platforms.market_data.price_history import row_tuple


def bar(day, close, adjusted=None, source="yahoo"):
    return row_tuple("AAPL", day, close, close, close, close, 100,
                     adjusted if adjusted is not None else close, source)


def test_recent_nasdaq_close_bridges_yahoo_adjusted_history(monkeypatch):
    monkeypatch.setattr(public_prices, "fetch_yahoo_history", lambda *_: [
        bar("2026-09-24", 100, 90), bar("2026-09-25", 110, 99),
    ])
    monkeypatch.setattr(public_prices, "fetch_nasdaq_history", lambda *_: [
        bar("2026-09-25", 110, 110, "nasdaq"),
        bar("2026-09-28", 120, 120, "nasdaq"),
    ])

    rows = public_prices.fetch_public_history("AAPL", date(2026, 9, 24), date(2026, 9, 29))

    assert [row[1] for row in rows] == ["2026-09-24", "2026-09-25", "2026-09-28"]
    assert rows[-1][5] == 120
    assert rows[-1][7] == 108
    assert rows[-1][8] == "nasdaq_yahoo_bridge"


def test_mismatched_overlap_does_not_bridge(monkeypatch):
    monkeypatch.setattr(public_prices, "fetch_yahoo_history", lambda *_: [bar("2026-09-25", 110)])
    monkeypatch.setattr(public_prices, "fetch_nasdaq_history", lambda *_: [
        bar("2026-09-25", 90, source="nasdaq"),
        bar("2026-09-28", 120, source="nasdaq"),
    ])

    rows = public_prices.fetch_public_history("AAPL", date(2026, 9, 24), date(2026, 9, 29))

    assert [row[1] for row in rows] == ["2026-09-25"]


def test_nasdaq_fallback_is_marked_raw(monkeypatch):
    monkeypatch.setattr(public_prices, "fetch_yahoo_history", lambda *_: [])
    monkeypatch.setattr(public_prices, "fetch_nasdaq_history", lambda *_: [
        bar("2026-09-25", 110, source="nasdaq"),
    ])

    rows = public_prices.fetch_public_history("AAPL", date(2026, 9, 24), date(2026, 9, 29))

    assert rows[0][8] == "nasdaq_raw"


def test_raw_fallback_keeps_existing_split_adjusted_rows(tmp_path, monkeypatch):
    db = tmp_path / "prices.db"
    feed = tmp_path / "feed.json"
    feed.write_text(json.dumps({"events": [{"ticker": "AAPL", "type": "trade",
                                         "occurredDay": "2026-09-24"}]}))
    with sqlite3.connect(db) as connection:
        public_prices.ensure_schema(connection)
        public_prices.upsert_rows(connection, [bar("2026-09-25", 50, source="massive_split")])
    monkeypatch.setattr(public_prices, "fetch_public_history", lambda *_: [
        bar("2026-09-25", 110, source="nasdaq_raw"),
        bar("2026-09-28", 120, source="nasdaq_raw"),
    ])

    result = public_prices.run(db=db, feed_path=feed, tickers="AAPL",
                               end=date(2026, 9, 29), limit=1, sleep_seconds=0)

    assert result["rows"] == 1
    with sqlite3.connect(db) as connection:
        assert connection.execute("SELECT close,source FROM price_daily WHERE day='2026-09-25'").fetchone() == (50, "massive_split")
        assert connection.execute("SELECT close,source FROM price_daily WHERE day='2026-09-28'").fetchone() == (120, "nasdaq_raw")


def test_default_batch_fetches_only_tickers_with_missing_event_prices(tmp_path, monkeypatch):
    db = tmp_path / "prices.db"
    feed = tmp_path / "feed.json"
    feed.write_text(json.dumps({"events": [
        {"ticker": "AAPL", "type": "trade", "occurredDay": "2026-09-24",
         "eventDayAdjustedClose": 100, "latestAdjustedClose": 110},
        {"ticker": "MSFT", "type": "trade", "occurredDay": "2026-09-24"},
    ]}))
    fetched = []

    def fetch(ticker, *_):
        fetched.append(ticker)
        return []

    monkeypatch.setattr(public_prices, "fetch_public_history", fetch)
    result = public_prices.run(db=db, feed_path=feed, tickers="",
                               end=date(2026, 9, 29), limit=0, sleep_seconds=0)

    assert result["requested"] == 1
    assert fetched == ["MSFT"]


def test_default_batch_refreshes_recent_social_tickers_with_stale_closes(tmp_path, monkeypatch):
    db = tmp_path / "prices.db"
    feed = tmp_path / "feed.json"
    feed.write_text(json.dumps({"events": []}))
    with sqlite3.connect(db) as connection:
        public_prices.ensure_schema(connection)
        connection.execute(
            "CREATE TABLE sv_call (ticker TEXT, created_at TEXT, is_actionable_call INTEGER)"
        )
        connection.executemany("INSERT INTO sv_call VALUES (?, ?, 1)", [
            ("APP", "2026-09-28T10:08:55Z"),
            ("OUST", "2026-09-28T10:05:50Z"),
        ])
        public_prices.upsert_rows(connection, [bar("2026-09-25", 100)])
    fetched = []

    def fetch(ticker, *_):
        fetched.append(ticker)
        return []

    monkeypatch.setattr(public_prices, "fetch_public_history", fetch)
    result = public_prices.run(db=db, feed_path=feed, tickers="",
                               end=date(2026, 9, 28), limit=0, sleep_seconds=0)

    assert result["requested"] == 2
    assert set(fetched) == {"APP", "OUST"}
