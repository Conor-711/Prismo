from __future__ import annotations

import datetime as dt

import pytest

from pipeline.jobs.congress_follow.workflows import build_decisions, settle_decisions, summarize


def trade(id: int, **overrides: object) -> dict:
    row = {"id": id, "politician_id": 7, "politician_name": "Example", "ticker": "ABC",
           "trade_type": "Buy", "asset_type": "Stock", "disclosure_date": "2026-09-01",
           "option_type": None, "strike_price": None, "option_expiry": None}
    row.update(overrides)
    return row


def test_decisions_deduplicate_and_exclude_non_equity_options() -> None:
    decisions, excluded = build_decisions([
        trade(1), trade(2), trade(3, option_type="call"), trade(4, ticker="N/A"),
        trade(5, asset_type="Bond"), trade(6, ticker="XYZ", trade_type="Sell"),
    ], dt.date(2026, 9, 10))
    assert len(decisions) == 2
    assert next(row for row in decisions if row["side"] == "Buy")["trade_ids"] == ["1", "2"]
    assert excluded == {"option": 1, "invalid_ticker": 1, "non_stock_or_etf": 1}


def test_conflicting_same_day_directions_are_not_followable() -> None:
    decisions, excluded = build_decisions([trade(1), trade(2, trade_type="Sell")], dt.date(2026, 9, 10))
    assert decisions == []
    assert excluded["conflicting_sides"] == 2


def test_settlement_uses_next_session_and_never_counts_pending_as_loss() -> None:
    decisions, _ = build_decisions([trade(1)], dt.date(2026, 9, 10))
    days = [dt.date(2026, 9, d) for d in (1, 2, 3, 4)]
    prices = {"SPY": dict(zip(days, (100, 100, 101, 102))),
              "ABC": dict(zip(days, (50, 50, 55, 60)))}
    outcomes = settle_decisions(decisions, prices, (1, 5))
    assert outcomes[0]["entry_date"] == "2026-09-02"
    assert outcomes[0]["exit_date"] == "2026-09-03"
    assert outcomes[0]["asset_return_pct"] == pytest.approx(10)
    assert outcomes[1]["status"] == "pending"
    summary = summarize(outcomes)
    assert summary[0]["win_rate_pct"] == 100
    assert summary[1]["win_rate_pct"] is None


def test_missing_exact_session_price_is_not_forward_filled() -> None:
    decisions, _ = build_decisions([trade(1)], dt.date(2026, 9, 10))
    days = [dt.date(2026, 9, d) for d in (1, 2, 3)]
    prices = {"SPY": dict(zip(days, (100, 100, 101))), "ABC": {days[0]: 50, days[2]: 55}}
    assert settle_decisions(decisions, prices, (1,))[0]["status"] == "missing_price"
