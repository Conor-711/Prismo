from __future__ import annotations

import gzip
import json
from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest

from pipeline.domain.investor_ability.backtest import PublicSignal
from pipeline.domain.smart_voice.portfolio_backtest_engine import (
    PriceBar,
    make_price_series,
)
from pipeline.jobs.subject_open_returns.__main__ import (
    group_summary,
    institutional_lots,
    subject_summary,
)
from pipeline.jobs.subject_open_returns.directional import calculate


def _report(period: str, filed: str, accession: str, cusip: str = "594918104") -> dict:
    return {
        "form": "13F-HR",
        "periodOfReport": period,
        "filedAt": filed,
        "accession": accession,
        "reportType": "13F HOLDINGS REPORT",
        "amendmentType": None,
        "holdings": [
            {
                "cusip": cusip,
                "issuer": "MICROSOFT CORP",
                "securityClass": "COM",
                "option": None,
                "shareType": "SH",
                "discretion": "SOLE",
                "reportedShares": "100",
                "reportedValueUsd": 10000,
            }
        ],
    }


def test_institutional_entry_is_first_uninterrupted_public_filing(
    tmp_path, monkeypatch
) -> None:
    from pipeline.jobs.subject_open_returns import __main__ as job

    subject = job.SUBJECTS[0]
    monkeypatch.setattr(job, "SUBJECTS", (subject,))
    folder = tmp_path / str(subject.filer_cik)
    folder.mkdir()
    reports = [
        _report("2025-12-31", "2026-02-14", "old"),
        _report("2026-03-31", "2026-05-15", "mid", cusip="037833100"),
        _report("2026-06-30", "2026-08-15", "latest"),
    ]
    for report in reports:
        with gzip.open(folder / f"{report['accession']}.json.gz", "wt") as handle:
            json.dump(report, handle)
    lots, meta = institutional_lots(
        tmp_path, date(2023, 9, 30), date(2026, 9, 30), {"594918104": "MSFT"}
    )
    assert len(lots) == 1
    assert lots[0]["transaction_date"] == "2026-08-15"
    assert meta["subject_coverage"][subject.id]["latest_period"] == "2026-06-30"


def test_summary_marks_open_positions_to_latest_without_30_day_exit() -> None:
    marked = [
        {
            "subject_id": "politician:1",
            "subject_type": "politician",
            "politician_name": "Example",
            "status": "priced_open_proxy",
            "unrealized_asset_return_pct": 60.0,
            "latest_disclosure_date": "2023-10-01",
        },
        {
            "subject_id": "politician:1",
            "subject_type": "politician",
            "politician_name": "Example",
            "status": "priced_open_proxy",
            "unrealized_asset_return_pct": -10.0,
            "latest_disclosure_date": "2024-02-01",
        },
    ]
    result = subject_summary(marked)[0]
    assert result["open_position_positive_rate_pct"] == pytest.approx(50.0)
    assert result["mean_open_return_pct"] == pytest.approx(25.0)
    result["directional_observations"] = 0
    grouped = group_summary(marked, [result])
    assert grouped["politician"]["open_position_win_rate_pct"] == pytest.approx(50.0)
    assert grouped["politician"]["equal_lot_mean_return_pct"] == pytest.approx(25.0)


def test_stale_13f_does_not_imply_current_holding(tmp_path, monkeypatch) -> None:
    from pipeline.jobs.subject_open_returns import __main__ as job

    subject = job.SUBJECTS[0]
    monkeypatch.setattr(job, "SUBJECTS", (subject,))
    folder = tmp_path / str(subject.filer_cik)
    folder.mkdir()
    report = _report("2025-09-30", "2025-11-03", "stale")
    with gzip.open(folder / "stale.json.gz", "wt") as handle:
        json.dump(report, handle)
    lots, meta = institutional_lots(
        tmp_path, date(2023, 9, 30), date(2026, 9, 30), {"594918104": "MSFT"}
    )
    assert not lots
    assert meta["excluded"]["stale_latest_report_subject"] == 1


def test_directional_win_rate_keeps_sale_signals_separate_from_open_return() -> None:
    market = make_price_series(
        [
            PriceBar("2026-09-02", 100.0, 100.0),
            PriceBar("2026-09-29", 120.0, 120.0),
        ]
    )
    published = datetime(2026, 9, 1, 23, 59, tzinfo=ZoneInfo("America/New_York"))
    signals = {
        "politician:1": [
            PublicSignal(
                "politician:1",
                "congress",
                str(i),
                "ABC",
                published,
                direction,
                "https://example.com",
            )
            for i, direction in enumerate(("bull", "bear"))
        ]
    }
    result = calculate(signals, {"SPY": market, "ABC": market}, date(2026, 9, 30))
    assert result["politician:1"]["directional_wins"] == 1
    assert result["politician:1"]["directional_losses"] == 1
    assert result["politician:1"]["directional_win_rate_pct"] == pytest.approx(50.0)


def test_selected_research_rejects_unknown_ids_and_default_output(tmp_path):
    from pipeline.jobs.subject_open_returns import __main__ as job

    with pytest.raises(ValueError, match="Unknown or empty"):
        job.run(subject_ids={"unverified"}, output=tmp_path)
    with pytest.raises(ValueError, match="separate output"):
        job.run(subject_ids={"duan-yongping"})


def test_selected_signals_do_not_read_congress_or_unselected_reports(tmp_path, monkeypatch):
    from pipeline.jobs.subject_open_returns import directional

    selected = tuple(s for s in directional.SUBJECTS if s.id == "duan-yongping")
    def forbidden(*args, **kwargs):
        raise AssertionError("Scoped job must not read Congress")
    monkeypatch.setattr(directional, "load_disclosures", forbidden)
    monkeypatch.setattr(directional, "app_politician_ids", lambda *args: {})
    calls = []
    def reports(history, cik, since, as_of):
        calls.append(cik)
        return [], []
    monkeypatch.setattr(directional, "reports_by_cik", reports)
    signals, names, _ = directional.collect_signals(
        tmp_path / "missing.zip", tmp_path, date(2023, 9, 30), date(2026, 9, 30), subjects=selected)
    assert calls == [1759760]
    assert names == {"celebrity:duan-yongping": "Duan Yongping"}
    assert not signals
