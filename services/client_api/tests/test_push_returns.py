import csv
from decimal import Decimal

import pytest
from services.client_api.content_release.push_returns import read_returns, sync_returns


def report(tmp_path, rows):
    path = tmp_path / "returns.csv"
    with path.open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=["investor_id", "total_return", "end_day", "trade_count"])
        writer.writeheader()
        writer.writerows(rows)
    return path


def row(actor="reddit:test", value="-0.12", trades="1", day="2026-09-30"):
    return dict(investor_id=actor, total_return=value, end_day=day, trade_count=trades)


def test_returns_keep_observed_losses_and_small_samples(tmp_path):
    rows = read_returns(report(tmp_path, [row(actor="REDDIT:Test"), row(actor="x", value="0.8", trades="2")]))
    assert rows[0]["actor_id"] == "reddit:test"
    assert rows[0]["follow_return"] == Decimal("-0.12")
    assert rows[1]["follow_return"] == Decimal("0.8")
    assert all(r["method"] == "full_history_follow_backtest" for r in rows)


@pytest.mark.parametrize("value", ["NaN", "Infinity", "-Infinity", "", "invalid"])
def test_returns_reject_nonfinite_and_missing_values(tmp_path, value):
    assert read_returns(report(tmp_path, [row(value=value)])) == []


def test_returns_reject_zero_trades_future_and_duplicates(tmp_path):
    assert read_returns(report(tmp_path, [row(trades="0"), row(day="2099-01-01")])) == []
    with pytest.raises(ValueError, match="Duplicate"):
        read_returns(report(tmp_path, [row(), row(actor="REDDIT:TEST")]))


def test_sync_preserves_newer_database_measurements(tmp_path):
    class Session:
        def execute(self, statement, rows):
            assert "excluded.as_of>=bsmart_push_return_metrics.as_of" in str(statement)
            assert len(rows) == 1
    assert sync_returns(Session(), report(tmp_path, [row()])) == 1
