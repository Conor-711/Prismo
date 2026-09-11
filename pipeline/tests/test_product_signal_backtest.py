from __future__ import annotations

import sqlite3

from pipeline.domain.smart_voice.product_signal_backtest import (
    AdjustedPriceBar,
    PointInTimeCall,
    PriceSeries,
    ProductSignalEvent,
    build_alpha_events,
    build_consensus_events,
    calculate_outcomes,
    load_point_in_time_calls,
)


def _call(
    candidate: str,
    author: str,
    ticker: str,
    day: str,
    *,
    direction: str = "bull",
    rank: int = 1,
    population: int = 100,
    lifecycle: str = "open_call",
) -> PointInTimeCall:
    return PointInTimeCall(
        candidate_id=candidate,
        ticker=ticker,
        source="x",
        investor_id=author,
        created_at=f"{day}T12:00:00Z",
        day=day,
        direction=direction,
        lifecycle=lifecycle,
        call_weight=1,
        target_price=120,
        invalidation="below support",
        horizon="20D",
        evidence_url=f"https://example.com/{candidate}",
        platform_sv=120,
        platform_rank=rank,
        platform_population=population,
        platform_percentile=(rank - 1) / (population - 1),
    )


def test_consensus_requires_distinct_point_in_time_top_quartile_authors() -> None:
    calls = [
        _call("a1", "a", "AAA", "2026-01-02", rank=1),
        _call("a2", "a", "AAA", "2026-01-03", rank=1),
        _call("b1", "b", "AAA", "2026-01-03", rank=25, direction="bear"),
        _call("c1", "c", "BBB", "2026-01-03", rank=26),
    ]

    events = build_consensus_events(
        calls,
        start_day="2026-01-02",
        end_day="2026-01-03",
    )

    assert len(events) == 1
    assert events[0].ticker == "AAA"
    assert events[0].source_count == 2
    assert events[0].direction == "mixed"


def test_alpha_reproduces_ui_overlap_and_pure_variant_excludes_consensus() -> None:
    calls = [
        _call("a1", "a", "AAA", "2026-01-02", rank=1),
        _call("b1", "b", "AAA", "2026-01-03", rank=2),
        _call("c1", "c", "BBB", "2026-01-03", rank=3),
    ]
    consensus = build_consensus_events(
        calls,
        start_day="2026-01-02",
        end_day="2026-01-03",
    )

    alpha = build_alpha_events(
        calls,
        start_day="2026-01-02",
        end_day="2026-01-03",
        consensus_events=consensus,
    )

    exact = [event for event in alpha if event.signal_type == "smart_alpha_ui"]
    pure = [event for event in alpha if event.signal_type == "smart_alpha_pure"]
    assert exact[-1].ticker == "AAA"
    assert exact[-1].overlaps_consensus == 1
    assert pure[-1].ticker == "BBB"
    assert pure[-1].overlaps_consensus == 0


def test_outcome_enters_next_session_open_and_uses_direction() -> None:
    event = ProductSignalEvent(
        event_id="alpha:AAA:2026-01-02:a",
        signal_type="smart_alpha_pure",
        ticker="AAA",
        signal_day="2026-01-02",
        occurred_at="2026-01-02T23:00:00Z",
        direction="bear",
        source_count=1,
        bullish_count=0,
        bearish_count=1,
        agreement=1,
        priority=0.9,
        author_keys="x:a",
        candidate_ids="a",
        best_platform_rank=1,
        best_platform_population=100,
        overlaps_consensus=0,
    )
    bars = (
        AdjustedPriceBar("2026-01-02", 90, 101, 89, 100),
        AdjustedPriceBar("2026-01-05", 110, 112, 99, 100),
        AdjustedPriceBar("2026-01-06", 100, 101, 89, 90),
    )
    series = PriceSeries(bars, tuple(bar.day for bar in bars), {bar.day: i for i, bar in enumerate(bars)})

    outcomes = calculate_outcomes([event], {"AAA": series}, horizons=(1, 2))

    assert outcomes[0].entry_day == "2026-01-05"
    assert round(outcomes[0].directional_return, 6) == round(1 - 100 / 110, 6)
    assert round(outcomes[1].directional_return, 6) == round(1 - 90 / 110, 6)


def test_call_does_not_use_a_future_author_rank_snapshot() -> None:
    connection = sqlite3.connect(":memory:")
    connection.executescript(
        """
        CREATE TABLE sv_call (
          candidate_id TEXT, ticker TEXT, source TEXT, investor_id TEXT, created_at TEXT,
          direction TEXT, lifecycle_action TEXT, call_weight REAL, target_price REAL,
          invalidation_condition TEXT, horizon_bucket TEXT, is_actionable_call INTEGER
        );
        CREATE TABLE sv_investor_score_asof (
          asof_day TEXT, investor_id TEXT, source TEXT, platform_sv REAL,
          platform_rank_no INTEGER, platform_population INTEGER,
          platform_percentile REAL, platform_qualified INTEGER
        );
        CREATE TABLE sv_call_candidate (candidate_id TEXT, url TEXT);
        INSERT INTO sv_call VALUES (
          'a1','AAA','x','author','2026-01-02T12:00:00Z','bull','open_call',1,120,
          'below support','20D',1
        );
        INSERT INTO sv_call_candidate VALUES ('a1','https://example.com/a1');
        INSERT INTO sv_investor_score_asof VALUES (
          '2026-01-03','author','x',130,1,100,0,1
        );
        """
    )

    calls = load_point_in_time_calls(
        connection,
        start_day="2026-01-02",
        end_day="2026-01-02",
        sources=("x",),
    )
    assert calls == []

    connection.execute(
        "INSERT INTO sv_investor_score_asof VALUES (?,?,?,?,?,?,?,?)",
        ("2026-01-02", "author", "x", 110, 10, 100, 9, 1),
    )
    calls = load_point_in_time_calls(
        connection,
        start_day="2026-01-02",
        end_day="2026-01-02",
        sources=("x",),
    )
    assert len(calls) == 1
    assert calls[0].platform_sv == 110
