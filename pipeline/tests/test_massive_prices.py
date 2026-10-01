import json
import sqlite3
from datetime import date, datetime, timezone

import pytest

from pipeline.platforms.market_data import massive_prices


def test_feed_tickers_uses_event_date_and_ignores_samples():
    feed = {"events": [
        {"ticker": "AAPL", "type": "trade", "occurredDay": "2026-09-01",
         "displayDay": "2026-09-20"},
        {"ticker": "AAPL", "type": "opinion", "displayDay": "2026-08-15"},
        {"ticker": "NVDA", "type": "trade", "occurredDay": "2026-07-01", "isSample": True},
        {"ticker": "BAD/US", "type": "trade", "occurredDay": "2026-07-01"},
    ]}

    assert massive_prices.feed_tickers(feed) == {"AAPL": date(2026, 8, 15)}


def test_fetch_daily_bars_uses_header_and_split_adjustment(monkeypatch):
    received = []

    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

        def read(self, *_):
            return json.dumps({"status": "OK", "adjusted": True, "results": [{
                "t": int(datetime(2026, 9, 25, tzinfo=timezone.utc).timestamp() * 1000),
                "o": 99, "h": 101, "l": 98, "c": 100, "v": 42,
            }]}).encode()

    def open_request(request, timeout):
        received.append(request)
        return Response()

    monkeypatch.setattr(massive_prices, "urlopen", open_request)
    bars = massive_prices.fetch_daily_bars(
        "AAPL", date(2026, 9, 24), date(2026, 9, 26), key="secret"
    )

    assert len(bars) == 1
    assert bars[0][1] == "2026-09-25"
    assert bars[0][5] == bars[0][7] == 100
    assert bars[0][8] == "massive_split"
    assert received[0].get_header("Authorization") == "Bearer secret"
    assert "secret" not in received[0].full_url
    assert "adjusted=true" in received[0].full_url


def test_run_updates_existing_price_rows_from_massive(tmp_path, monkeypatch):
    db = tmp_path / "prices.db"
    feed = tmp_path / "feed.json"
    feed.write_text(json.dumps({"events": [{"ticker": "AAPL", "type": "trade",
                                         "occurredDay": "2026-09-24"}]}))
    monkeypatch.setattr(massive_prices, "api_key", lambda: "secret")
    called = []

    def fetch(ticker, start, end, *, key):
        called.append((ticker, start, end, key))
        return [massive_prices.row_tuple(ticker, "2026-09-25", 99, 101, 98,
                                        100, 42, 100, "massive_split")]

    monkeypatch.setattr(massive_prices, "fetch_daily_bars", fetch)
    kwargs = dict(db=db, feed_path=feed, tickers="AAPL", start=None,
                  end=date(2026, 9, 26), limit=1, sleep_seconds=0)
    assert massive_prices.run(**kwargs)["updated"] == 1
    assert massive_prices.run(**kwargs)["updated"] == 1
    assert called[0][1] == date(2026, 9, 24)
    assert called[1][1] == date(2026, 9, 24)
    with sqlite3.connect(db) as connection:
        assert connection.execute("SELECT COUNT(*) FROM price_daily").fetchone()[0] == 1


def test_default_run_requests_only_unpriced_feed_tickers(tmp_path, monkeypatch):
    db = tmp_path / "prices.db"
    feed = tmp_path / "feed.json"
    feed.write_text(json.dumps({"events": [
        {"ticker": "AAPL", "type": "trade", "occurredDay": "2026-09-24",
         "eventDayAdjustedClose": 100},
        {"ticker": "NVDA", "type": "trade", "occurredDay": "2026-09-24"},
    ]}))
    monkeypatch.setattr(massive_prices, "api_key", lambda: "secret")
    called = []
    def fetch(ticker, start, end, *, key):
        called.append(ticker)
        return []
    monkeypatch.setattr(massive_prices, "fetch_daily_bars", fetch)

    result = massive_prices.run(db=db, feed_path=feed, tickers="", start=None,
                                end=date(2026, 9, 26), limit=0, sleep_seconds=0)

    assert result["requested"] == 1
    assert called == ["NVDA"]


def test_missing_key_fails_without_network(monkeypatch):
    monkeypatch.delenv("MASSIVE_API_KEY", raising=False)
    monkeypatch.setattr(massive_prices.sys, "platform", "linux")
    with pytest.raises(RuntimeError, match="MASSIVE_API_KEY"):
        massive_prices.api_key()
