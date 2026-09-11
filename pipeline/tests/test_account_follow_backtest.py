from __future__ import annotations

import sqlite3

from pipeline.domain.smart_voice.account_follow_backtest import _load_calls
from pipeline.domain.smart_voice.account_follow_backtest_engine import (
    simulate_account_follow,
)
from pipeline.domain.smart_voice.account_follow_backtest_types import FollowCall
from pipeline.domain.smart_voice.portfolio_backtest_engine import (
    PriceBar,
    make_price_series,
)


def _series(values: list[tuple[str, float, float]]):
    return make_price_series(
        PriceBar(day=day, open=open_price, close=close_price)
        for day, open_price, close_price in values
    )


def _call(
    candidate_id: str,
    created_at: str,
    direction: str,
    *,
    lifecycle: str = "open_call",
    horizon: int = 2,
) -> FollowCall:
    return FollowCall(
        candidate_id=candidate_id,
        source="x",
        investor_id="author",
        ticker="AAA",
        created_at=created_at,
        direction=direction,
        lifecycle=lifecycle,
        affected_direction="unknown",
        horizon_sessions=horizon,
    )


def _price_book():
    values = [
        ("2026-01-02", 100.0, 100.0),
        ("2026-01-05", 100.0, 110.0),
        ("2026-01-06", 110.0, 121.0),
        ("2026-01-07", 121.0, 108.9),
        ("2026-01-08", 108.9, 98.01),
        ("2026-01-09", 98.01, 98.01),
    ]
    series = _series(values)
    return {"AAA": series, "SPY": _series([(day, 100.0, 100.0) for day, _, _ in values])}


def test_follow_strategy_extends_same_direction_and_reverses_latest_call() -> None:
    prices = _price_book()
    stats, trades = simulate_account_follow(
        [
            _call("open-long", "2026-01-02T12:00:00Z", "bull"),
            _call("reinforce", "2026-01-05T12:00:00Z", "bull", lifecycle="reinforce_call"),
            _call("reverse", "2026-01-06T12:00:00Z", "bear", lifecycle="reverse_call"),
        ],
        prices,
        prices["SPY"],
        round_trip_cost_bps=0,
        evaluation_end="2026-01-09",
    )

    assert stats is not None
    assert stats.trade_count == 2
    assert stats.same_direction_updates == 1
    assert stats.reversals == 1
    assert stats.turnover_sides == 4
    assert [trade.direction for trade in trades] == ["bull", "bear"]
    assert trades[0].exit_reason == "reverse_call"
    assert trades[1].exit_reason == "horizon_expiry"
    assert round(stats.total_return, 4) == 0.4641


def test_explicit_close_exits_at_next_session_open() -> None:
    prices = _price_book()
    stats, trades = simulate_account_follow(
        [
            _call("open", "2026-01-02T12:00:00Z", "bull", horizon=20),
            _call(
                "close",
                "2026-01-05T12:00:00Z",
                "bull",
                lifecycle="close_prior_call",
            ),
        ],
        prices,
        prices["SPY"],
        round_trip_cost_bps=10,
        evaluation_end="2026-01-09",
    )

    assert stats is not None
    assert stats.explicit_exits == 1
    assert len(trades) == 1
    assert trades[0].exit_day == "2026-01-06"
    assert trades[0].exit_timing == "open"
    assert trades[0].exit_reason == "close_prior_call"
    assert round(trades[0].gross_return, 4) == 0.1
    assert round(trades[0].net_return, 4) == 0.099


def test_same_open_calls_are_netted_before_execution() -> None:
    prices = _price_book()
    stats, trades = simulate_account_follow(
        [
            _call("early-bull", "2026-01-02T10:00:00Z", "bull", horizon=1),
            _call("later-bear", "2026-01-02T20:00:00Z", "bear", horizon=1),
        ],
        prices,
        prices["SPY"],
        round_trip_cost_bps=0,
        evaluation_end="2026-01-09",
    )

    assert stats is not None
    assert stats.trade_count == 1
    assert stats.reversals == 0
    assert trades[0].entry_candidate_id == "later-bear"
    assert trades[0].direction == "bear"


def test_open_position_closes_when_ticker_price_history_ends() -> None:
    prices = _price_book()
    prices["AAA"] = _series(
        [
            ("2026-01-02", 100.0, 100.0),
            ("2026-01-05", 100.0, 110.0),
            ("2026-01-06", 110.0, 121.0),
            ("2026-01-07", 121.0, 108.9),
            ("2026-01-08", 108.9, 98.01),
        ]
    )
    stats, trades = simulate_account_follow(
        [_call("open", "2026-01-02T10:00:00Z", "bull", horizon=20)],
        prices,
        prices["SPY"],
        round_trip_cost_bps=0,
        evaluation_end="2026-01-09",
    )

    assert stats is not None
    assert len(trades) == 1
    assert trades[0].exit_day == "2026-01-08"
    assert trades[0].exit_reason == "price_history_end"


def test_long_only_treats_bear_call_as_exit_instead_of_short() -> None:
    prices = _price_book()
    stats, trades = simulate_account_follow(
        [
            _call("open", "2026-01-02T12:00:00Z", "bull", horizon=20),
            _call("bear", "2026-01-05T12:00:00Z", "bear", horizon=20),
        ],
        prices,
        prices["SPY"],
        round_trip_cost_bps=0,
        long_only=True,
        evaluation_end="2026-01-09",
    )

    assert stats is not None
    assert stats.trade_count == 1
    assert stats.short_trades == 0
    assert trades[0].exit_reason == "bearish_exit_long_only"


def test_call_qualification_uses_strictly_prior_snapshot() -> None:
    connection = sqlite3.connect(":memory:")
    connection.row_factory = sqlite3.Row
    connection.executescript(
        """
        CREATE TABLE sv_call (
          candidate_id TEXT PRIMARY KEY, source TEXT, investor_id TEXT,
          ticker TEXT, created_at TEXT, direction TEXT, lifecycle_action TEXT,
          affected_direction TEXT, horizon_bucket TEXT, summary_zh TEXT,
          summary_en TEXT, is_actionable_call INTEGER
        );
        CREATE TABLE sv_call_candidate (
          candidate_id TEXT PRIMARY KEY, text TEXT, url TEXT
        );
        CREATE TABLE sv_investor_score_asof (
          asof_day TEXT, investor_id TEXT, source TEXT, platform_qualified INTEGER
        );
        INSERT INTO sv_investor_score_asof VALUES
          ('2026-01-01','author','x',0),
          ('2026-01-02','author','x',1);
        INSERT INTO sv_call VALUES
          ('same-day','x','author','AAA','2026-01-02T10:00:00Z','bull',
           'open_call','unknown','20D','','',1),
          ('next-day','x','author','AAA','2026-01-03T10:00:00Z','bull',
           'open_call','unknown','20D','','',1);
        """
    )

    grouped = _load_calls(
        connection,
        [{"source": "x", "investor_id": "author"}],
    )

    assert [qualified for _, qualified in grouped[("x", "author")]] == [False, True]
