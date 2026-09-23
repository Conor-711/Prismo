import sqlite3
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from pipeline.platforms.market_data import daily_prices


def database(*, inactive: bool, last_day: str | None) -> sqlite3.Connection:
    connection = sqlite3.connect(":memory:")
    connection.execute("CREATE TABLE price_daily (ticker TEXT, day TEXT)")
    connection.execute("CREATE TABLE ticker_meta (ticker TEXT, is_active INTEGER)")
    connection.execute("INSERT INTO ticker_meta VALUES ('OLD', ?)", (0 if inactive else 1,))
    if last_day:
        connection.execute("INSERT INTO price_daily VALUES ('OLD', ?)", (last_day,))
    return connection


def test_refresh_accepts_historical_price_for_inactive_security(monkeypatch):
    connection = database(inactive=True, last_day="2026-01-02")
    monkeypatch.setattr(daily_prices, "fetch_history", lambda *_: [])

    result = daily_prices.refresh(connection, ["OLD"])

    assert result["terminalTickers"] == ["OLD"]
    assert result["through"] is None


def test_refresh_still_blocks_stale_active_security(monkeypatch):
    connection = database(inactive=False, last_day="2026-01-02")
    monkeypatch.setattr(daily_prices, "fetch_history", lambda *_: [])

    with pytest.raises(RuntimeError, match="OLD"):
        daily_prices.refresh(connection, ["OLD"])


def test_refresh_still_blocks_inactive_security_without_any_price(monkeypatch):
    connection = database(inactive=True, last_day=None)
    monkeypatch.setattr(daily_prices, "fetch_history", lambda *_: [])

    with pytest.raises(RuntimeError, match="OLD"):
        daily_prices.refresh(connection, ["OLD"])


def test_refresh_does_not_refetch_completed_current_day(monkeypatch):
    now = datetime.now(ZoneInfo("America/New_York"))
    completed = now.date() if now.hour >= 18 else now.date() - timedelta(days=1)
    connection = database(inactive=False, last_day=completed.isoformat())

    def unexpected_fetch(*_):
        raise AssertionError("current series should not be fetched again")

    monkeypatch.setattr(daily_prices, "fetch_history", unexpected_fetch)
    result = daily_prices.refresh(connection, ["OLD"])

    assert result["through"] == completed.isoformat()
    assert result["terminalTickers"] == []
