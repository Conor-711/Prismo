from __future__ import annotations

import datetime as dt

import pytest

from pipeline.jobs.congress_holdings.workflows import build_unclosed_buys, mark_to_market, summarize


def trade(trade_id: int, **changes: object) -> dict:
    row = {"id": trade_id, "politician_id": 1, "politician_name": "Example", "ticker": "ABC",
           "asset_type": "Stock", "trade_type": "Buy", "transaction_date": "2026-07-10",
           "disclosure_date": "2026-09-01", "option_type": None,
           "strike_price": None, "option_expiry": None}
    row.update(changes)
    return row


def test_later_sale_excludes_old_lot_but_not_new_buy() -> None:
    lots, excluded = build_unclosed_buys([
        trade(1), trade(2, transaction_date="2026-08-01", trade_type="Sell"),
        trade(3, transaction_date="2026-08-20"), trade(4, transaction_date="2026-08-20"),
    ], dt.date(2026, 9, 29))
    assert len(lots) == 1
    assert lots[0]["source_trade_ids"] == ["3", "4"]
    assert excluded["later_exit_disclosed"] == 1


def test_sale_disclosed_after_as_of_does_not_close_known_lot() -> None:
    lots, _ = build_unclosed_buys([
        trade(1), trade(2, trade_type="Sell", transaction_date="2026-08-12",
                        disclosure_date="2026-10-05"),
    ], dt.date(2026, 9, 29))
    assert len(lots) == 1


def test_marks_from_transaction_day_and_requires_current_price() -> None:
    lots, _ = build_unclosed_buys([trade(1)], dt.date(2026, 9, 29))
    entry = dt.date(2026, 7, 10)
    latest = dt.date(2026, 9, 28)
    prices = {"SPY": {entry: 100, latest: 110}, "ABC": {entry: 50, latest: 75}}
    marked = mark_to_market(lots, prices)
    assert marked[0]["status"] == "priced_open_proxy"
    assert marked[0]["unrealized_asset_return_pct"] == pytest.approx(50)
    assert summarize(marked)[0]["positive_return_rate_pct"] == 100
    del prices["ABC"][latest]
    assert mark_to_market(lots, prices)[0]["status"] == "missing_latest_price"
