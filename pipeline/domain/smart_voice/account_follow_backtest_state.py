"""Open-position state transitions for Smart Account follow strategies."""
from __future__ import annotations

from dataclasses import dataclass

from .account_follow_backtest_types import FollowCall, FollowTrade, ScheduledCall


@dataclass
class OpenPosition:
    ticker: str
    direction: int
    entry_candidate_id: str
    entry_day: str
    entry_price: float
    expiry_day: str | None
    thesis: str
    evidence_url: str
    signal_updates: int = 1
    last_candidate_id: str = ""


def _direction_name(direction: int) -> str:
    return "bull" if direction > 0 else "bear"


def _direction_value(call: FollowCall, *, long_only: bool) -> int:
    if call.direction == "bull":
        return 1
    if call.direction == "bear" and not long_only:
        return -1
    return 0


def _later_day(left: str | None, right: str | None) -> str | None:
    if left is None or right is None:
        return None
    return max(left, right)


def _turnover_sides(before: int, after: int) -> int:
    if before == after:
        return 0
    if before == 0 or after == 0:
        return 1
    return 2


def close_trade(
    position: OpenPosition,
    *,
    source: str,
    investor_id: str,
    exit_candidate_id: str,
    exit_day: str,
    exit_price: float,
    exit_timing: str,
    exit_reason: str,
    round_trip_cost_bps: int,
) -> FollowTrade:
    gross_return = position.direction * (
        exit_price / position.entry_price - 1.0
    )
    return FollowTrade(
        source=source,
        investor_id=investor_id,
        ticker=position.ticker,
        direction=_direction_name(position.direction),
        entry_candidate_id=position.entry_candidate_id,
        entry_day=position.entry_day,
        entry_price=position.entry_price,
        exit_candidate_id=exit_candidate_id,
        exit_day=exit_day,
        exit_price=exit_price,
        exit_timing=exit_timing,
        exit_reason=exit_reason,
        gross_return=gross_return,
        net_return=gross_return - max(0, round_trip_cost_bps) / 10_000.0,
        signal_updates=position.signal_updates,
        thesis=position.thesis,
        evidence_url=position.evidence_url,
    )


def apply_open_events(
    *,
    ticker: str,
    day: str,
    events: list[ScheduledCall],
    open_price: float,
    positions: dict[str, OpenPosition],
    source: str,
    investor_id: str,
    round_trip_cost_bps: int,
    long_only: bool,
) -> tuple[list[FollowTrade], int, int, int, int]:
    """Net every call known before one open, then execute one state change."""
    before = positions.get(ticker)
    before_direction = before.direction if before else 0
    target_direction = before_direction
    target_expiry = before.expiry_day if before else None
    target_updates = before.signal_updates if before else 0
    target_event: ScheduledCall | None = None
    exit_reason = ""
    same_direction_updates = 0

    for event in events:
        call = event.call
        action = call.lifecycle or "open_call"
        affected = call.affected_direction or "unknown"
        if action in {"close_prior_call", "invalidate_prior_call"}:
            if target_direction and affected in {
                "unknown",
                _direction_name(target_direction),
            }:
                target_direction = 0
                target_expiry = None
                target_updates = 0
                target_event = event
                exit_reason = action
            continue

        desired_direction = _direction_value(call, long_only=long_only)
        if desired_direction == 0:
            if target_direction:
                target_direction = 0
                target_expiry = None
                target_updates = 0
                target_event = event
                exit_reason = "bearish_exit_long_only"
            continue
        if target_direction == desired_direction:
            target_expiry = _later_day(target_expiry, event.expiry_day)
            target_updates += 1
            target_event = event
            same_direction_updates += 1
            continue

        target_direction = desired_direction
        target_expiry = event.expiry_day
        target_updates = 1
        target_event = event
        exit_reason = (
            "reverse_call" if action == "reverse_call" else "opposite_judgment"
        )

    trades: list[FollowTrade] = []
    if before and before_direction != target_direction:
        exit_event = target_event or events[-1]
        trades.append(
            close_trade(
                before,
                source=source,
                investor_id=investor_id,
                exit_candidate_id=exit_event.call.candidate_id,
                exit_day=day,
                exit_price=open_price,
                exit_timing="open",
                exit_reason=exit_reason or "latest_judgment",
                round_trip_cost_bps=round_trip_cost_bps,
            )
        )

    if target_direction == 0:
        positions.pop(ticker, None)
    elif before and before_direction == target_direction:
        before.expiry_day = target_expiry
        before.signal_updates = target_updates
        if target_event:
            before.last_candidate_id = target_event.call.candidate_id
    else:
        entry_event = target_event or events[-1]
        call = entry_event.call
        positions[ticker] = OpenPosition(
            ticker=ticker,
            direction=target_direction,
            entry_candidate_id=call.candidate_id,
            entry_day=day,
            entry_price=open_price,
            expiry_day=target_expiry,
            thesis=call.thesis,
            evidence_url=call.evidence_url,
            signal_updates=target_updates,
            last_candidate_id=call.candidate_id,
        )

    turnover = _turnover_sides(before_direction, target_direction)
    reversals = int(
        before_direction != 0
        and target_direction != 0
        and before_direction != target_direction
    )
    explicit_exits = int(before_direction != 0 and target_direction == 0)
    return trades, turnover, same_direction_updates, reversals, explicit_exits
