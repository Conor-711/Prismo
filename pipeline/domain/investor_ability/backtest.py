"""Point-in-time, long-only research replay for the fixed follow policy.

This produces candidate metrics, not an audited or publishable Score. Daily
bars cannot prove intraday availability, borrowability, corporate actions or
the actual spread paid by a follower.
"""

from __future__ import annotations

import bisect
import math
import statistics
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from itertools import pairwise
from zoneinfo import ZoneInfo

from pipeline.domain.smart_voice.portfolio_backtest_engine import PriceSeries

NEW_YORK = ZoneInfo("America/New_York")
MAX_POSITIONS = 5
HOLD_DAYS = 30
ROUND_TRIP_COST_BPS = 25
MIN_PRIOR_DOLLAR_VOLUME = 1_000_000


@dataclass(frozen=True)
class PublicSignal:
    actor_id: str
    source: str
    event_id: str
    ticker: str
    published_at: datetime
    direction: str
    evidence_url: str


@dataclass(frozen=True)
class PreparedSignal:
    signal: PublicSignal
    execution_day: str
    entry_price: float
    scheduled_exit_day: str


@dataclass(frozen=True)
class ClosedTrade:
    ticker: str
    entry_day: str
    exit_day: str
    net_return: float
    event_id: str


@dataclass(frozen=True)
class ReplayResult:
    win_rate: float | None
    follow_return: float
    annualized_net_return: float
    annualized_benchmark_return: float
    annualized_volatility: float
    max_drawdown: float
    independent_decision_days: int
    executable_decisions: int
    priced_decisions: int
    settled_decisions: int
    excluded: dict[str, int]
    trades: tuple[ClosedTrade, ...]


def _next_open_day(signal: PublicSignal, market_days: tuple[str, ...]) -> str | None:
    ready = (signal.published_at + timedelta(hours=1)).astimezone(NEW_YORK)
    day = ready.date().isoformat()
    index = bisect.bisect_left(market_days, day)
    if (
        index < len(market_days)
        and market_days[index] == day
        and ready.time() > time(9, 30)
    ):
        index += 1
    return market_days[index] if index < len(market_days) else None


def _prepare(
    signals: list[PublicSignal],
    prices: dict[str, PriceSeries],
    benchmark: PriceSeries,
    start: date,
    end: date,
) -> tuple[list[PreparedSignal], list[tuple[str, PublicSignal]], dict[str, int], int]:
    prepared: list[PreparedSignal] = []
    exits: list[tuple[str, PublicSignal]] = []
    excluded: dict[str, int] = {}
    seen: set[tuple[str, str, str, str]] = set()
    executable = 0
    for signal in sorted(signals, key=lambda s: (s.published_at, s.event_id)):
        if signal.direction not in {"bull", "bear"}:
            excluded["invalid_direction"] = excluded.get("invalid_direction", 0) + 1
            continue
        if signal.published_at.tzinfo is None:
            excluded["missing_timezone"] = excluded.get("missing_timezone", 0) + 1
            continue
        public_day = signal.published_at.astimezone(NEW_YORK).date().isoformat()
        key = (signal.actor_id, signal.ticker, signal.direction, public_day)
        if key in seen:
            excluded["duplicate"] = excluded.get("duplicate", 0) + 1
            continue
        seen.add(key)
        day = _next_open_day(signal, benchmark.days)
        if day is None or not start.isoformat() <= day <= end.isoformat():
            excluded["outside_window"] = excluded.get("outside_window", 0) + 1
            continue
        if signal.direction == "bear":
            exits.append((day, signal))
            excluded["short_not_verified"] = excluded.get("short_not_verified", 0) + 1
            continue
        deadline = (date.fromisoformat(day) + timedelta(days=HOLD_DAYS)).isoformat()
        if deadline > end.isoformat():
            excluded["unsettled"] = excluded.get("unsettled", 0) + 1
            continue
        executable += 1
        series = prices.get(signal.ticker)
        if series is None or day not in series.index_by_day:
            excluded["no_entry_price"] = excluded.get("no_entry_price", 0) + 1
            continue
        index = series.index_by_day[day]
        if index < 20:
            excluded["insufficient_liquidity_history"] = (
                excluded.get("insufficient_liquidity_history", 0) + 1
            )
            continue
        prior = series.bars[index - 20 : index]
        if (
            statistics.fmean(bar.close * bar.volume for bar in prior)
            < MIN_PRIOR_DOLLAR_VOLUME
        ):
            excluded["illiquid"] = excluded.get("illiquid", 0) + 1
            continue
        exit_index = bisect.bisect_left(series.days, deadline)
        if exit_index >= len(series.days) or series.days[exit_index] > end.isoformat():
            excluded["unsettled"] = excluded.get("unsettled", 0) + 1
            continue
        exit_day = series.days[exit_index]
        audit_bars = series.bars[index - 20 : exit_index + 1]
        if any(
            current.open / previous.close > 2 or current.open / previous.close < 0.5
            for previous, current in pairwise(audit_bars)
        ):
            excluded["suspected_corporate_action"] = (
                excluded.get("suspected_corporate_action", 0) + 1
            )
            continue
        market_slice = benchmark.days[
            bisect.bisect_left(benchmark.days, day) : bisect.bisect_right(
                benchmark.days, exit_day
            )
        ]
        if any(market_day not in series.index_by_day for market_day in market_slice):
            excluded["price_gap"] = excluded.get("price_gap", 0) + 1
            continue
        prepared.append(PreparedSignal(signal, day, series.bars[index].open, exit_day))
    return prepared, exits, excluded, executable


def replay(
    signals: list[PublicSignal],
    prices: dict[str, PriceSeries],
    benchmark: PriceSeries,
    *,
    start: date,
    end: date,
    round_trip_cost_bps: int = ROUND_TRIP_COST_BPS,
) -> ReplayResult:
    """Replay one actor on a common calendar; idle slots remain in cash."""
    if end < start or round_trip_cost_bps < 0:
        raise ValueError("Invalid window or transaction cost")
    prepared, exits, excluded, executable = _prepare(
        signals, prices, benchmark, start, end
    )
    entries_by_day: dict[str, list[PreparedSignal]] = {}
    exits_by_day: dict[str, list[PublicSignal]] = {}
    for item in prepared:
        entries_by_day.setdefault(item.execution_day, []).append(item)
    for day, signal in exits:
        exits_by_day.setdefault(day, []).append(signal)
    for items in entries_by_day.values():
        items.sort(key=lambda item: (item.signal.published_at, item.signal.event_id))
    for items in exits_by_day.values():
        items.sort(key=lambda item: (item.published_at, item.event_id))

    active: dict[str, PreparedSignal] = {}
    shares: dict[str, float] = {}
    benchmark_shares: dict[str, float] = {}
    trades: list[ClosedTrade] = []
    cash = benchmark_cash = 1.0
    net_equity = benchmark_equity = peak = 1.0
    worst_drawdown = 0.0
    entered_decision_days: set[date] = set()
    daily_returns: list[float] = []
    half_cost = round_trip_cost_bps / 20_000.0
    current = start
    while current <= end:
        day = current.isoformat()
        bench_index = benchmark.index_by_day.get(day)
        if bench_index is None:
            daily_returns.append(0.0)
            current += timedelta(days=1)
            continue
        bench_bar = benchmark.bars[bench_index]
        previous_equity = net_equity
        old = dict(active)
        closing: set[str] = {
            ticker for ticker, item in old.items() if item.scheduled_exit_day <= day
        }
        closing.update(
            signal.ticker
            for signal in exits_by_day.get(day, ())
            if signal.ticker in old
        )
        latest_bear: dict[str, datetime] = {}
        for signal in exits_by_day.get(day, ()):
            previous = latest_bear.get(signal.ticker)
            if previous is None or signal.published_at > previous:
                latest_bear[signal.ticker] = signal.published_at
        for ticker in sorted(closing):
            item = active.pop(ticker)
            bar = prices[ticker].bars[prices[ticker].index_by_day[day]]
            cash += shares.pop(ticker) * bar.open * (1.0 - half_cost)
            benchmark_cash += (
                benchmark_shares.pop(ticker) * bench_bar.open * (1.0 - half_cost)
            )
            trades.append(
                ClosedTrade(
                    ticker,
                    item.execution_day,
                    day,
                    bar.open / item.entry_price * (1.0 - half_cost) / (1.0 + half_cost)
                    - 1.0,
                    item.signal.event_id,
                )
            )
        for item in entries_by_day.get(day, ()):
            ticker = item.signal.ticker
            if (
                ticker in latest_bear
                and latest_bear[ticker] >= item.signal.published_at
            ):
                excluded["same_open_superseded"] = (
                    excluded.get("same_open_superseded", 0) + 1
                )
            elif ticker in active or ticker in old:
                excluded["overlap"] = excluded.get("overlap", 0) + 1
            elif len(active) >= MAX_POSITIONS:
                excluded["capacity"] = excluded.get("capacity", 0) + 1
            else:
                at_open = cash + sum(
                    owned * prices[symbol].bars[prices[symbol].index_by_day[day]].open
                    for symbol, owned in shares.items()
                )
                benchmark_at_open = (
                    benchmark_cash + sum(benchmark_shares.values()) * bench_bar.open
                )
                amount = min(cash, at_open / MAX_POSITIONS)
                benchmark_amount = min(
                    benchmark_cash, benchmark_at_open / MAX_POSITIONS
                )
                if amount <= 0 or benchmark_amount <= 0:
                    excluded["cash_shortfall"] = excluded.get("cash_shortfall", 0) + 1
                    continue
                cash -= amount
                benchmark_cash -= benchmark_amount
                shares[ticker] = amount / (item.entry_price * (1.0 + half_cost))
                benchmark_shares[ticker] = benchmark_amount / (
                    bench_bar.open * (1.0 + half_cost)
                )
                active[ticker] = item
                entered_decision_days.add(
                    item.signal.published_at.astimezone(NEW_YORK).date()
                )
        net_equity = cash + sum(
            owned * prices[symbol].bars[prices[symbol].index_by_day[day]].close
            for symbol, owned in shares.items()
        )
        benchmark_equity = (
            benchmark_cash + sum(benchmark_shares.values()) * bench_bar.close
        )
        peak = max(peak, net_equity)
        worst_drawdown = min(worst_drawdown, net_equity / peak - 1.0)
        daily_returns.append(net_equity / previous_equity - 1.0)
        current += timedelta(days=1)

    observed = (end - start).days + 1
    settled = len(trades)
    decision_days = len(entered_decision_days)
    win_rate = (
        sum(trade.net_return > 0 for trade in trades) / settled if settled else None
    )
    vol = (
        statistics.stdev(daily_returns) * math.sqrt(365)
        if len(daily_returns) > 1
        else 0.0
    )
    return ReplayResult(
        win_rate=win_rate,
        follow_return=net_equity - 1.0,
        annualized_net_return=net_equity ** (365 / observed) - 1.0,
        annualized_benchmark_return=benchmark_equity ** (365 / observed) - 1.0,
        annualized_volatility=vol,
        max_drawdown=worst_drawdown,
        independent_decision_days=decision_days,
        executable_decisions=executable,
        priced_decisions=len(prepared),
        settled_decisions=settled,
        excluded=excluded,
        trades=tuple(trades),
    )
