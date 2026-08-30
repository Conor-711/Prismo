from __future__ import annotations

import datetime as dt

import pytest

from pipeline.domain.congress_score.schema import TradeOutcome
from pipeline.domain.congress_score.scoring import (
    build_member_scores,
    build_trade_events,
    settle_trade_events,
)
from pipeline.platforms.congress import CongressDisclosure, CongressMember


def member(member_id: str, name: str) -> CongressMember:
    return CongressMember(member_id, name, "house", "I", "CA", None, None)


def disclosure(
    trade_id: str,
    person: CongressMember,
    day: dt.date,
    *,
    ticker: str = "ABC",
    transaction_type: str = "Purchase",
    amount_low: int = 1001,
    amount_high: int = 15000,
) -> CongressDisclosure:
    return CongressDisclosure(
        trade_id=trade_id,
        member=person,
        source_id="house_clerk",
        transaction_date=day,
        filing_date=day + dt.timedelta(days=20),
        notification_date=None,
        owner="Self",
        ticker=ticker,
        asset_name=f"{ticker} Common Stock",
        asset_type="ST",
        transaction_type=transaction_type,
        amount_low=amount_low,
        amount_high=amount_high,
        days_to_file=20,
        is_late=False,
        filing_type="PTR",
        evidence_url=f"https://example.gov/{trade_id}.pdf",
    )


def test_build_trade_events_collapses_same_day_line_items() -> None:
    person = member("m1", "One")
    day = dt.date(2026, 1, 5)
    events = build_trade_events(
        [
            disclosure("a", person, day),
            disclosure("b", person, day, amount_low=15001, amount_high=50000),
        ]
    )

    assert len(events) == 1
    assert events[0].trade_count == 2
    assert events[0].amount_midpoint == pytest.approx(40501.0)
    assert len(events[0].evidence_urls) == 2


def test_settlement_enters_after_transaction_and_directionalizes_sales() -> None:
    person = member("m1", "One")
    start = dt.date(2026, 1, 1)
    events = build_trade_events(
        [
            disclosure("buy", person, start, ticker="BUY"),
            disclosure("sell", person, start, ticker="SELL", transaction_type="Sale (Full)"),
        ]
    )
    days = [start + dt.timedelta(days=index) for index in range(25)]
    prices = {
        "SPY": [(day, 100.0 + index * 0.5) for index, day in enumerate(days)],
        "BUY": [(day, 100.0 + index) for index, day in enumerate(days)],
        "SELL": [(day, 100.0 - index * 0.5) for index, day in enumerate(days)],
    }

    outcomes = settle_trade_events(events, prices, horizons=(20,))

    assert len(outcomes) == 2
    assert all(outcome.entry_date == start + dt.timedelta(days=1) for outcome in outcomes)
    assert all(outcome.exit_date == start + dt.timedelta(days=21) for outcome in outcomes)
    assert all(outcome.directional_excess > 0 for outcome in outcomes)


def test_member_score_uses_decision_days_and_qualifies_only_enough_history() -> None:
    strong = member("strong", "Strong")
    weak = member("weak", "Weak")
    sparse = member("sparse", "Sparse")
    people = [strong, weak, sparse]
    raw = []
    events = []
    outcomes = []
    for person, excess, count in [(strong, 4.0, 5), (weak, -4.0, 5), (sparse, 20.0, 1)]:
        for index in range(count):
            day = dt.date(2025, 9, 1) + dt.timedelta(days=index * 7)
            item = disclosure(f"{person.member_id}-{index}", person, day)
            raw.append(item)
            event = build_trade_events([item])[0]
            events.append(event)
            for horizon in (20, 60):
                outcomes.append(
                    TradeOutcome(
                        event_id=event.event_id,
                        member=person,
                        ticker="ABC",
                        direction="purchase",
                        transaction_date=day,
                        entry_date=day + dt.timedelta(days=1),
                        exit_date=day + dt.timedelta(days=horizon + 1),
                        horizon=horizon,
                        asset_return=excess + 1.0,
                        benchmark_return=1.0,
                        directional_excess=excess,
                        trade_count=1,
                        amount_midpoint=8000.5,
                        evidence_urls=(item.evidence_url or "",),
                    )
                )

    scores = build_member_scores(
        members=people,
        disclosures=raw,
        events=events,
        outcomes=outcomes,
        min_purchase_days=5,
    )
    by_id = {row.member.member_id: row for row in scores}

    assert by_id["strong"].rank == 1
    assert by_id["strong"].score == pytest.approx(100.0)
    assert by_id["weak"].rank == 2
    assert by_id["weak"].score == pytest.approx(0.0)
    assert by_id["sparse"].status == "observation"
    assert by_id["sparse"].score is None
