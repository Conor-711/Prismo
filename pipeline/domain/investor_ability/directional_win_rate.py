"""Research-only direction accuracy against the latest available daily close."""

from __future__ import annotations

import bisect
import math
from collections import Counter
from dataclasses import dataclass
from datetime import date, timedelta
from itertools import pairwise

from pipeline.domain.smart_voice.portfolio_backtest_engine import PriceSeries

from .backtest import HOLD_DAYS, NEW_YORK, ROUND_TRIP_COST_BPS, PublicSignal, _next_open_day


@dataclass(frozen=True)
class DirectionalWinRate:
    as_of: str
    wins: int
    losses: int
    flat: int
    observations: int
    rate: float | None
    mean_directional_return: float | None
    excluded: dict[str, int]


def latest_directional_win_rate(
    signals: list[PublicSignal],
    prices: dict[str, PriceSeries],
    benchmark: PriceSeries,
    *,
    as_of: date,
) -> DirectionalWinRate:
    """Compare direction to today's close and estimate a fixed-horizon return.

    Flat observations remain in the denominator. Missing or stale quotes and
    signals not yet executable are not losses; they are separately reported.
    The return uses the first open on/after day 30, or today's close while
    the signal is still open. It is not an executable short portfolio.
    """
    wins = losses = flat = 0
    directional_returns: list[float] = []
    excluded: Counter[str] = Counter()
    seen: set[tuple[str, str, str, str]] = set()
    cutoff = as_of.isoformat()
    for signal in sorted(signals, key=lambda item: (item.published_at, item.event_id)):
        if signal.direction not in {"bull", "bear"} or signal.published_at.tzinfo is None:
            excluded["invalid_signal"] += 1
            continue
        public_day = signal.published_at.astimezone(NEW_YORK).date().isoformat()
        key = (signal.actor_id, signal.ticker, signal.direction, public_day)
        if key in seen:
            excluded["duplicate"] += 1
            continue
        seen.add(key)
        entry_day = _next_open_day(signal, benchmark.days)
        if entry_day is None or entry_day > cutoff:
            excluded["not_yet_executable"] += 1
            continue
        series = prices.get(signal.ticker)
        if series is None or entry_day not in series.index_by_day:
            excluded["no_entry_price"] += 1
            continue
        latest_index = bisect.bisect_right(series.days, cutoff) - 1
        if latest_index < 0 or series.days[latest_index] < entry_day:
            excluded["no_current_price"] += 1
            continue
        latest_day = date.fromisoformat(series.days[latest_index])
        if (as_of - latest_day).days > 7:
            excluded["stale_current_price"] += 1
            continue
        entry_index = series.index_by_day[entry_day]
        if any(
            current.open / previous.close > 2 or current.open / previous.close < 0.5
            for previous, current in pairwise(series.bars[entry_index : latest_index + 1])
        ):
            excluded["suspected_corporate_action"] += 1
            continue
        entry_price = series.bars[entry_index].open
        latest_price = series.bars[latest_index].close
        if not math.isfinite(entry_price) or not math.isfinite(latest_price) or entry_price <= 0 or latest_price <= 0:
            excluded["invalid_price"] += 1
            continue
        exit_target = (date.fromisoformat(entry_day) + timedelta(days=HOLD_DAYS)).isoformat()
        exit_index = bisect.bisect_left(series.days, exit_target)
        exit_price = (
            series.bars[exit_index].open
            if exit_index <= latest_index else latest_price
        )
        if not math.isfinite(exit_price) or exit_price <= 0:
            excluded["invalid_exit_price"] += 1
            continue
        direction = 1 if signal.direction == "bull" else -1
        directional_returns.append(
            direction * (exit_price / entry_price - 1.0)
            - ROUND_TRIP_COST_BPS / 10_000.0
        )
        if math.isclose(latest_price, entry_price, rel_tol=1e-9):
            flat += 1
        elif (latest_price > entry_price) == (signal.direction == "bull"):
            wins += 1
        else:
            losses += 1
    observations = wins + losses + flat
    return DirectionalWinRate(
        as_of=cutoff,
        wins=wins,
        losses=losses,
        flat=flat,
        observations=observations,
        rate=wins / observations if observations else None,
        mean_directional_return=(math.fsum(directional_returns) / observations)
        if observations else None,
        excluded=dict(excluded),
    )
