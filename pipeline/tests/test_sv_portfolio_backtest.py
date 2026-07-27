from __future__ import annotations

from datetime import date, timedelta

from pipeline.domain.smart_voice.portfolio_backtest_engine import (
    Position,
    PriceBar,
    make_price_series,
    select_non_overlapping_positions,
    simulate_portfolio_costs,
)
from pipeline.domain.smart_voice.rank_event_backtest import (
    RankSignalEvent,
    _band_states,
    _group_signal,
)
from pipeline.domain.smart_voice.rank_event_research import _condition_filters, _positions


def _series(values: list[tuple[str, float, float]]):
    return make_price_series(
        PriceBar(day=day, open=open_price, close=close_price)
        for day, open_price, close_price in values
    )


def test_non_overlapping_positions_keep_one_live_ticker_trade() -> None:
    positions = [
        Position("a", "MU", 1, "2026-01-02", "2026-01-06"),
        Position("b", "MU", 1, "2026-01-05", "2026-01-07"),
        Position("c", "MU", -1, "2026-01-07", "2026-01-08"),
        Position("d", "NVDA", 1, "2026-01-05", "2026-01-07"),
    ]

    selected, skipped = select_non_overlapping_positions(positions)

    assert [position.position_id for position in selected] == ["a", "d", "c"]
    assert skipped == 1


def test_long_short_portfolio_uses_cash_days_and_costs() -> None:
    spy = _series(
        [
            ("2026-01-02", 100.0, 100.0),
            ("2026-01-05", 100.0, 101.0),
            ("2026-01-06", 101.0, 102.0),
            ("2026-01-07", 102.0, 102.0),
        ]
    )
    price_book = {
        "SPY": spy,
        "AAA": _series(
            [
                ("2026-01-02", 100.0, 100.0),
                ("2026-01-05", 100.0, 110.0),
                ("2026-01-06", 110.0, 121.0),
                ("2026-01-07", 121.0, 121.0),
            ]
        ),
        "BBB": _series(
            [
                ("2026-01-02", 100.0, 100.0),
                ("2026-01-05", 100.0, 90.0),
                ("2026-01-06", 90.0, 81.0),
                ("2026-01-07", 81.0, 81.0),
            ]
        ),
    }
    positions = [
        Position("long", "AAA", 1, "2026-01-05", "2026-01-06"),
        Position("short", "BBB", -1, "2026-01-05", "2026-01-06"),
    ]

    result = simulate_portfolio_costs(positions, price_book, spy, (0, 10))

    assert result[0].n_trades == 2
    assert result[0].trading_days == 2
    assert result[0].active_days == 2
    assert round(result[0].total_return, 6) == 0.21
    assert result[10].total_return < result[0].total_return
    assert result[10].trade_hit_rate == 1.0


def test_short_direction_loses_when_price_rises() -> None:
    spy = _series(
        [
            ("2026-01-02", 100.0, 100.0),
            ("2026-01-05", 100.0, 100.0),
        ]
    )
    price_book = {
        "SPY": spy,
        "AAA": _series(
            [
                ("2026-01-02", 100.0, 100.0),
                ("2026-01-05", 100.0, 110.0),
            ]
        ),
    }

    result = simulate_portfolio_costs(
        [Position("short", "AAA", -1, "2026-01-05", "2026-01-05")],
        price_book,
        spy,
        (0,),
    )

    assert round(result[0].total_return, 6) == -0.1
    assert result[0].trade_hit_rate == 0.0


def test_rank_band_and_consensus_use_latest_point_in_time_rank() -> None:
    states = [
        {
            "investor_id": "top-a",
            "platform_rank_no": 1,
            "platform_population": 20,
            "direction": "bull",
            "weight": 1.2,
        },
        {
            "investor_id": "top-b",
            "platform_rank_no": 2,
            "platform_population": 20,
            "direction": "bull",
            "weight": 0.8,
        },
        {
            "investor_id": "bottom-a",
            "platform_rank_no": 19,
            "platform_population": 20,
            "direction": "bear",
            "weight": 1.0,
        },
        {
            "investor_id": "bottom-b",
            "platform_rank_no": 20,
            "platform_population": 20,
            "direction": "bear",
            "weight": 1.0,
        },
    ]

    top, bottom = _band_states(states, 10)
    top_signal = _group_signal(top, min_authors=2, consensus_threshold=0.65)
    bottom_signal = _group_signal(bottom, min_authors=2, consensus_threshold=0.65)

    assert top_signal and top_signal["direction"] == "bull"
    assert bottom_signal and bottom_signal["direction"] == "bear"
    assert top_signal["consensus"] == 1.0
    assert bottom_signal["consensus"] == 1.0


def test_fixed_evaluation_period_keeps_idle_cash_days() -> None:
    spy = _series(
        [
            ("2026-01-02", 100.0, 100.0),
            ("2026-01-05", 100.0, 100.0),
            ("2026-01-06", 100.0, 100.0),
            ("2026-01-07", 100.0, 100.0),
        ]
    )
    price_book = {
        "SPY": spy,
        "AAA": _series(
            [
                ("2026-01-02", 100.0, 100.0),
                ("2026-01-05", 100.0, 110.0),
                ("2026-01-06", 110.0, 121.0),
                ("2026-01-07", 121.0, 121.0),
            ]
        ),
    }

    result = simulate_portfolio_costs(
        [Position("long", "AAA", 1, "2026-01-05", "2026-01-06")],
        price_book,
        spy,
        (0,),
        evaluation_start="2026-01-02",
        evaluation_end="2026-01-07",
    )

    assert result[0].trading_days == 4
    assert result[0].active_days == 2
    assert result[0].exposure_pct == 0.5


def test_rank_event_position_can_delay_entry_without_changing_hold_length() -> None:
    series = _series(
        [
            ("2026-01-02", 10.0, 10.0),
            ("2026-01-05", 11.0, 11.0),
            ("2026-01-06", 12.0, 12.0),
            ("2026-01-07", 13.0, 13.0),
            ("2026-01-08", 14.0, 14.0),
        ]
    )
    event = RankSignalEvent(
        event_id="top:MU:2026-01-02",
        ticker="MU",
        strategy="top_follow",
        rank_band_pct=20,
        window_days=1,
        direction="bull",
        signal_day="2026-01-02",
        end_day="2026-01-02",
        signal_value=2.0,
        top_authors=2,
        bottom_authors=0,
        top_consensus=1.0,
        bottom_consensus=0.0,
    )

    immediate = _positions([event], {"MU": series}, 2, "long_only", "unfiltered")
    delayed = _positions(
        [event],
        {"MU": series},
        2,
        "long_only",
        "unfiltered",
        entry_lag_days=1,
    )

    assert (immediate[0].entry_day, immediate[0].exit_day) == (
        "2026-01-05",
        "2026-01-06",
    )
    assert (delayed[0].entry_day, delayed[0].exit_day) == (
        "2026-01-06",
        "2026-01-07",
    )


def test_strength_filter_does_not_change_when_future_events_are_added() -> None:
    start = date(2026, 1, 1)

    def event(index: int, strength: float) -> RankSignalEvent:
        day = (start + timedelta(days=index)).isoformat()
        return RankSignalEvent(
            event_id=f"event-{index}",
            ticker=f"T{index}",
            strategy="top_follow",
            rank_band_pct=20,
            window_days=1,
            direction="bull",
            signal_day=day,
            end_day=day,
            signal_value=strength,
            top_authors=2,
            bottom_authors=0,
            top_consensus=1.0,
            bottom_consensus=0.0,
        )

    history = [event(index, float(index + 1)) for index in range(20)]
    target = event(20, 11.0)
    future = [event(index, 100.0) for index in range(21, 51)]

    predicate_without_future = _condition_filters(history + [target])["strength_top50"]
    predicate_with_future = _condition_filters(history + [target] + future)["strength_top50"]

    assert predicate_without_future(target)
    assert predicate_with_future(target)
