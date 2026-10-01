import json
from datetime import date, datetime, timedelta, timezone

import pytest

from pipeline.domain.investor_ability.backtest import (
    PublicSignal,
    _next_open_day,
    replay,
)
from pipeline.domain.investor_ability.directional_win_rate import (
    latest_directional_win_rate,
)
from pipeline.domain.smart_voice.portfolio_backtest_engine import (
    PriceBar,
    make_price_series,
)
from pipeline.jobs.investor_ability.research import (
    _read_13f_signals,
    _read_congress_signals,
)


def _calendar():
    days = []
    current = date(2026, 1, 1)
    while current <= date(2026, 4, 1):
        if current.weekday() < 5:
            days.append(current.isoformat())
        current += timedelta(days=1)
    return days


def _signal(event_id="one", published=None, direction="bull"):
    return PublicSignal(
        "actor",
        "x",
        event_id,
        "TEST",
        published or datetime(2026, 2, 2, 12, tzinfo=timezone.utc),
        direction,
        "https://example.org/post",
    )


def _prices(*, split=False):
    days = _calendar()
    stock = []
    for day in days:
        price = 110.0 if day > "2026-02-02" else 100.0
        if split and day >= "2026-02-20":
            price *= 20
        stock.append(
            PriceBar(day, price, 110.0 if day == "2026-02-02" else price, 100_000)
        )
    benchmark = make_price_series(PriceBar(day, 100.0, 100.0, 100_000) for day in days)
    return {"TEST": make_price_series(stock)}, benchmark


def test_publication_delay_uses_first_available_open():
    days = tuple(_calendar())
    assert _next_open_day(_signal(), days) == "2026-02-02"
    after_cutoff = _signal(published=datetime(2026, 2, 2, 14, tzinfo=timezone.utc))
    assert _next_open_day(after_cutoff, days) == "2026-02-03"


def test_replay_deduplicates_and_holds_cash_in_unused_slots():
    prices, benchmark = _prices()
    result = replay(
        [_signal(), _signal("duplicate")],
        prices,
        benchmark,
        start=date(2026, 1, 1),
        end=date(2026, 4, 1),
    )
    assert result.settled_decisions == 1
    assert result.excluded["duplicate"] == 1
    assert result.win_rate == 1.0
    assert result.follow_return == pytest.approx(0.02 - 0.0005, abs=0.001)
    assert result.annualized_benchmark_return < 0


def test_opened_shares_drift_without_free_daily_rebalancing():
    prices, benchmark = _prices()
    prices["TEST"] = make_price_series(
        PriceBar(
            bar.day,
            121.0 if bar.day > "2026-02-03" else bar.open,
            121.0 if bar.day >= "2026-02-03" else bar.close,
            bar.volume,
        )
        for bar in prices["TEST"].bars
    )
    result = replay(
        [_signal()],
        prices,
        benchmark,
        start=date(2026, 1, 1),
        end=date(2026, 4, 1),
        round_trip_cost_bps=0,
    )
    assert result.follow_return == pytest.approx(0.2 * 0.21)


def test_higher_execution_cost_lowers_net_follow_return():
    prices, benchmark = _prices()
    low_cost = replay(
        [_signal()],
        prices,
        benchmark,
        start=date(2026, 1, 1),
        end=date(2026, 4, 1),
        round_trip_cost_bps=10,
    )
    high_cost = replay(
        [_signal()],
        prices,
        benchmark,
        start=date(2026, 1, 1),
        end=date(2026, 4, 1),
        round_trip_cost_bps=50,
    )
    assert low_cost.follow_return > high_cost.follow_return
    assert low_cost.trades[0].net_return > high_cost.trades[0].net_return


def test_suspected_reverse_split_is_not_counted_as_profit():
    prices, benchmark = _prices(split=True)
    result = replay(
        [_signal()], prices, benchmark, start=date(2026, 1, 1), end=date(2026, 4, 1)
    )
    assert result.win_rate is None
    assert result.follow_return == 0.0
    assert result.excluded["suspected_corporate_action"] == 1


def test_unsettled_signal_is_reported_not_treated_as_price_failure():
    prices, benchmark = _prices()
    recent = _signal(published=datetime(2026, 3, 20, 12, tzinfo=timezone.utc))
    result = replay(
        [recent], prices, benchmark, start=date(2026, 1, 1), end=date(2026, 4, 1)
    )
    assert result.executable_decisions == 0
    assert result.priced_decisions == 0
    assert result.excluded["unsettled"] == 1


def test_latest_directional_win_rate_counts_buys_sells_and_flat_prices():
    prices, benchmark = _prices()
    days = _calendar()
    prices["UP"] = make_price_series(
        PriceBar(day, 100 if day <= "2026-02-02" else 110, 110, 100_000)
        for day in days
    )
    prices["DOWN"] = make_price_series(
        PriceBar(day, 100 if day <= "2026-02-02" else 90, 90, 100_000)
        for day in days
    )
    prices["FLAT"] = make_price_series(
        PriceBar(day, 100, 100, 100_000) for day in days
    )
    published = datetime(2026, 2, 2, 12, tzinfo=timezone.utc)
    signals = [
        PublicSignal("actor", "congress", "buy", "UP", published, "bull", "https://example.org/1"),
        PublicSignal("actor", "congress", "repeat", "UP", published, "bull", "https://example.org/2"),
        PublicSignal("actor", "congress", "sell", "DOWN", published, "bear", "https://example.org/3"),
        PublicSignal("actor", "congress", "wrong", "UP", published, "bear", "https://example.org/4"),
        PublicSignal("actor", "congress", "flat", "FLAT", published, "bull", "https://example.org/5"),
    ]
    result = latest_directional_win_rate(
        signals, prices, benchmark, as_of=date(2026, 4, 1)
    )
    assert (result.wins, result.losses, result.flat) == (2, 1, 1)
    assert result.observations == 4
    assert result.rate == 0.5
    assert result.mean_directional_return == pytest.approx(0.0225)
    assert result.excluded["duplicate"] == 1


def test_directional_return_uses_30_day_exit_or_current_mark():
    prices, benchmark = _prices()
    prices["TEST"] = make_price_series(
        PriceBar(
            day,
            100 if day <= "2026-02-02" else 110 if day < "2026-03-20" else 120,
            100 if day <= "2026-02-02" else 110 if day < "2026-03-20" else 150,
            100_000,
        )
        for day in _calendar()
    )
    old = latest_directional_win_rate(
        [_signal()], prices, benchmark, as_of=date(2026, 4, 1)
    )
    assert old.wins == 1
    assert old.mean_directional_return == pytest.approx(0.0975)

    recent = latest_directional_win_rate(
        [_signal(published=datetime(2026, 3, 20, 12, tzinfo=timezone.utc))],
        prices,
        benchmark,
        as_of=date(2026, 4, 1),
    )
    assert recent.wins == 1
    assert recent.mean_directional_return == pytest.approx(150 / 120 - 1 - 0.0025)


def test_latest_directional_win_rate_excludes_pending_and_stale_quotes():
    prices, benchmark = _prices()
    stale_days = [day for day in _calendar() if day <= "2026-02-10"]
    prices["STALE"] = make_price_series(
        PriceBar(day, 100, 90, 100_000) for day in stale_days
    )
    signals = [
        PublicSignal("actor", "congress", "old", "STALE",
                     datetime(2026, 2, 2, 12, tzinfo=timezone.utc), "bear", "https://example.org/1"),
        PublicSignal("actor", "congress", "new", "TEST",
                     datetime(2026, 4, 1, 20, tzinfo=timezone.utc), "bull", "https://example.org/2"),
    ]
    result = latest_directional_win_rate(
        signals, prices, benchmark, as_of=date(2026, 4, 1)
    )
    assert result.rate is None
    assert result.excluded == {"stale_current_price": 1, "not_yet_executable": 1}


def test_latest_directional_win_rate_ignores_suspected_unadjusted_split():
    prices, benchmark = _prices(split=True)
    result = latest_directional_win_rate(
        [_signal()], prices, benchmark, as_of=date(2026, 4, 1)
    )
    assert result.rate is None
    assert result.excluded["suspected_corporate_action"] == 1


def test_later_opposite_signal_before_same_open_prevents_entry():
    prices, benchmark = _prices()
    bearish = _signal(
        "bear",
        datetime(2026, 2, 2, 12, 30, tzinfo=timezone.utc),
        "bear",
    )
    result = replay(
        [_signal(), bearish],
        prices,
        benchmark,
        start=date(2026, 1, 1),
        end=date(2026, 4, 1),
    )
    assert result.settled_decisions == 0
    assert result.excluded["same_open_superseded"] == 1


def test_congress_uses_disclosure_date_not_trade_date(tmp_path):
    source = tmp_path / "congress.jsonl"
    source.write_text(
        json.dumps(
            {
                "trade_id": "filing-1",
                "member_id": "p1",
                "member_name": "Pat",
                "chamber": "house",
                "transaction_date": "2026-01-01",
                "filing_date": "2026-02-02",
                "action": "Purchase",
                "ticker": "TEST",
                "evidence_url": "https://example.org/filing.pdf",
            }
        )
        + "\n"
    )
    grouped, _, excluded = _read_congress_signals(
        source,
        {"TEST"},
        date(2026, 1, 1),
        date(2026, 4, 1),
    )
    signal = grouped[("congress", "p1")][0]
    assert _next_open_day(signal, tuple(_calendar())) == "2026-02-03"
    assert not excluded


def test_congress_with_unpriced_ticker_still_appears_as_subject(tmp_path):
    source = tmp_path / "congress.jsonl"
    source.write_text(json.dumps({
        "member_id": "p2", "member_name": "Alex", "chamber": "house",
        "filing_date": "2026-02-02", "action": "Purchase",
        "ticker": "UNMAPPED", "evidence_url": "https://example.org/filing.pdf",
    }) + "\n")
    grouped, names, excluded = _read_congress_signals(
        source, {"TEST"}, date(2026, 1, 1), date(2026, 4, 1)
    )
    assert grouped[("congress", "p2")] == []
    assert names["p2"] == "Alex"
    assert excluded["congress_unsupported_asset"] == 1


def test_13f_replay_input_uses_filing_not_quarter_end_and_keeps_all_subjects(
    tmp_path, monkeypatch
):
    monkeypatch.setattr(
        "pipeline.jobs.investor_ability.research.cached_cusip_tickers",
        lambda: {"037833100": "AAPL", "000000002": "MSFT"},
    )
    (tmp_path / "berkshire.json").write_text(json.dumps({
        "source": "SEC EDGAR Form 13F", "subjectId": "berkshire",
        "kind": "institution", "filerCik": 1067983,
        "filedAt": "2026-02-02", "periodOfReport": "2025-12-31",
        "filingUrl": "https://www.sec.gov/Archives/edgar/data/test",
        "coverage": "complete", "accession": "filing-1",
        "holdings": [
            {"shareType": "SH", "option": None, "cusip": "037833100", "reportedValueUsd": 100},
            {"shareType": "SH", "option": None, "cusip": "000000001", "reportedValueUsd": 50},
        ],
        "changes": [
            {"shareType": "SH", "option": None, "cusip": "037833100", "reportedShareChange": "10"},
            {"shareType": "SH", "option": None, "cusip": "000000002", "reportedShareChange": "-20"},
        ],
    }))
    grouped, directional, metadata, excluded = _read_13f_signals(
        tmp_path, date(2026, 1, 1), date(2026, 4, 1)
    )
    assert ("celebrity", "warren-buffett") in grouped
    assert grouped[("celebrity", "warren-buffett")] == []
    assert len(grouped[("institution", "berkshire")]) == 1
    signal = grouped[("institution", "berkshire")][0]
    assert signal.ticker == "AAPL"
    assert _next_open_day(signal, tuple(_calendar())) == "2026-02-03"
    assert excluded["13f_unmapped_cusip"] == 1
    assert {(signal.ticker, signal.direction) for signal in directional[("institution", "berkshire")]} == {
        ("AAPL", "bull"), ("MSFT", "bear")
    }
    assert metadata[("institution", "berkshire")]["report_period"] == "2025-12-31"
    assert metadata[("celebrity", "warren-buffett")]["disclosure_status"] == "snapshot_missing"
