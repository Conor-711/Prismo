from __future__ import annotations

import csv

import pytest

from pipeline.jobs.congress_follow.absolute import absolute_cohort, write_absolute_exports


def test_absolute_cohort_ignores_pending_and_has_no_benchmark() -> None:
    cohort = absolute_cohort([
        {"status": "settled", "asset_return_pct": 2.0},
        {"status": "settled", "asset_return_pct": -4.0},
        {"status": "pending", "asset_return_pct": None},
        {"status": "missing_price", "asset_return_pct": None},
    ])
    assert cohort == {"settled": 2, "pending": 1, "missing_price": 1,
                      "win_rate_pct": 50, "mean_return_pct": -1, "median_return_pct": -1}


def test_absolute_export_excludes_spy_fields(tmp_path) -> None:
    result = {"politician_name": "Example", "politician_id": "1", "ticker": "ABC",
              "disclosure_date": "2026-09-01", "trade_ids": "3", "line_items": 1,
              "side": "Buy", "horizon_days": 5, "status": "settled",
              "entry_date": "2026-09-02", "exit_date": "2026-09-10",
              "asset_return_pct": -2.0, "spy_return_pct": 1.0, "excess_return_pp": -3.0}
    summary = {"politician_name": "Example", "politician_id": "1", "chamber": "House",
               "party": "I", "side": "Buy", "horizon_days": 5, "decision_count": 1,
               "settled_count": 1, "pending_count": 0, "missing_price_count": 0,
               "disclosure_day_count": 1, "win_rate_pct": 0,
               "mean_follow_return_pct": -2.0, "mean_excess_pp": -3.0}
    diagnostics = write_absolute_exports(tmp_path, [result], [summary], [
        {"id": 3, "disclosure_date": "2026-09-01", "transaction_date": "2026-08-12"}
    ])
    exported = list(csv.DictReader((tmp_path / "absolute_decision_outcomes.csv").open()))
    assert exported[0]["asset_return_pct"] == "-2.0"
    assert "spy_return_pct" not in exported[0]
    assert "excess_return_pp" not in exported[0]
    assert diagnostics["median_transaction_to_disclosure_days"] == 20
    assert "-2.00%" in (tmp_path / "absolute_follow_returns.md").read_text()
