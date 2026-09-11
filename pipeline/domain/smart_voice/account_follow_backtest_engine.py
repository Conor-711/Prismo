"""Pure stateful portfolio simulation for following one Smart Account."""
from __future__ import annotations

import bisect
import math
import statistics
from collections import defaultdict
from dataclasses import dataclass
from typing import Iterable

from .account_follow_backtest_state import (
    OpenPosition,
    apply_open_events,
    close_trade,
)
from .account_follow_backtest_types import (
    FollowCall,
    FollowStats,
    FollowTrade,
    ScheduledCall,
)
from .portfolio_backtest_engine import PriceSeries


@dataclass
class _Diagnostics:
    same_direction_updates: int = 0
    reversals: int = 0
    explicit_exits: int = 0
    price_history_end_exits: int = 0
    skipped_no_price: int = 0
    turnover_sides: float = 0.0


def _annualized_return(total_return: float, trading_days: int) -> float | None:
    if trading_days <= 0 or total_return <= -1.0:
        return None
    return (1.0 + total_return) ** (252.0 / trading_days) - 1.0


def _max_drawdown(daily_returns: list[float]) -> float:
    equity = 1.0
    peak = 1.0
    worst = 0.0
    for value in daily_returns:
        equity *= 1.0 + value
        peak = max(peak, equity)
        if peak > 0:
            worst = min(worst, equity / peak - 1.0)
    return worst


def schedule_calls(
    calls: Iterable[FollowCall],
    price_book: dict[str, PriceSeries],
) -> tuple[list[ScheduledCall], int]:
    """Map publication timestamps to executable next-session open events."""
    scheduled: list[ScheduledCall] = []
    skipped = 0
    for call in calls:
        series = price_book.get(call.ticker)
        if not series:
            skipped += 1
            continue
        entry_index = bisect.bisect_right(series.days, call.signal_day)
        if entry_index >= len(series.days):
            skipped += 1
            continue
        expiry_index = entry_index + max(1, call.horizon_sessions) - 1
        expiry_day = (
            series.days[expiry_index]
            if expiry_index < len(series.days)
            else None
        )
        scheduled.append(
            ScheduledCall(
                call=call,
                execution_day=series.days[entry_index],
                expiry_day=expiry_day,
            )
        )
    scheduled.sort(
        key=lambda item: (
            item.execution_day,
            item.call.created_at,
            item.call.candidate_id,
        )
    )
    return scheduled, skipped


def simulate_account_follow(
    calls: Iterable[FollowCall],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    *,
    round_trip_cost_bps: int = 10,
    long_only: bool = False,
    evaluation_end: str | None = None,
) -> tuple[FollowStats | None, list[FollowTrade]]:
    """Simulate next-open execution with latest same-ticker judgment winning.

    Same-direction calls extend the existing holding horizon. Opposite calls
    close and reverse at the next session open. Explicit close/invalidation
    calls flatten matching exposure. Active tickers are equal weighted each
    day and the portfolio holds cash when no recommendation is active.
    """
    raw_calls = list(calls)
    scheduled, skipped = schedule_calls(raw_calls, price_book)
    if not scheduled:
        return None, []

    source = scheduled[0].call.source
    investor_id = scheduled[0].call.investor_id
    last_day = evaluation_end or benchmark.days[-1]
    scheduled = [item for item in scheduled if item.execution_day <= last_day]
    if not scheduled:
        return None, []

    events_by_day: dict[str, list[ScheduledCall]] = defaultdict(list)
    for item in scheduled:
        events_by_day[item.execution_day].append(item)

    start_day = scheduled[0].execution_day
    calendar = [bar for bar in benchmark.bars if start_day <= bar.day <= last_day]
    if not calendar:
        return None, []

    open_positions: dict[str, OpenPosition] = {}
    trades: list[FollowTrade] = []
    diagnostics = _Diagnostics(skipped_no_price=skipped)
    daily_returns: list[float] = []
    benchmark_returns: list[float] = []
    active_counts: list[int] = []
    previous_benchmark_close = 0.0
    half_cost = max(0, round_trip_cost_bps) / 20_000.0

    for benchmark_bar in calendar:
        day = benchmark_bar.day
        old_directions = {
            ticker: position.direction
            for ticker, position in open_positions.items()
        }
        transitions: dict[str, int] = defaultdict(int)

        for ticker, day_events in _events_by_ticker(events_by_day.get(day, [])):
            series = price_book[ticker]
            bar_index = series.index_by_day.get(day)
            if bar_index is None:
                diagnostics.skipped_no_price += len(day_events)
                continue
            open_price = series.bars[bar_index].open
            day_trades, turnover, same_updates, reversals, explicit_exits = (
                apply_open_events(
                    ticker=ticker,
                    day=day,
                    events=day_events,
                    open_price=open_price,
                    positions=open_positions,
                    source=source,
                    investor_id=investor_id,
                    round_trip_cost_bps=round_trip_cost_bps,
                    long_only=long_only,
                )
            )
            trades.extend(day_trades)
            transitions[ticker] += turnover
            diagnostics.same_direction_updates += same_updates
            diagnostics.reversals += reversals
            diagnostics.explicit_exits += explicit_exits

        new_directions = {
            ticker: position.direction
            for ticker, position in open_positions.items()
        }
        active_tickers = sorted(set(old_directions) | set(new_directions))
        ticker_returns: list[float] = []
        for ticker in active_tickers:
            series = price_book.get(ticker)
            bar_index = series.index_by_day.get(day) if series else None
            if series is None or bar_index is None:
                ticker_returns.append(0.0)
                continue
            bar = series.bars[bar_index]
            overnight_factor = 1.0
            old_direction = old_directions.get(ticker, 0)
            if old_direction and bar_index > 0:
                prior_close = series.bars[bar_index - 1].close
                if prior_close > 0:
                    overnight_factor += old_direction * (
                        bar.open / prior_close - 1.0
                    )
            intraday_factor = 1.0
            new_direction = new_directions.get(ticker, 0)
            if new_direction and bar.open > 0:
                intraday_factor += new_direction * (
                    bar.close / bar.open - 1.0
                )
            ticker_returns.append(overnight_factor * intraday_factor - 1.0)

        close_turnover = 0
        for ticker, position in list(open_positions.items()):
            series = price_book.get(ticker)
            bar_index = series.index_by_day.get(day) if series else None
            if series is None or bar_index is None:
                continue
            price_history_ends = day == series.days[-1] and day < calendar[-1].day
            if position.expiry_day != day and not price_history_ends:
                continue
            trades.append(
                close_trade(
                    position,
                    source=source,
                    investor_id=investor_id,
                    exit_candidate_id=position.last_candidate_id,
                    exit_day=day,
                    exit_price=series.bars[bar_index].close,
                    exit_timing="close",
                    exit_reason=(
                        "horizon_expiry"
                        if position.expiry_day == day
                        else "price_history_end"
                    ),
                    round_trip_cost_bps=round_trip_cost_bps,
                )
            )
            if price_history_ends and position.expiry_day != day:
                diagnostics.price_history_end_exits += 1
            del open_positions[ticker]
            close_turnover += 1

        denominator = len(active_tickers)
        day_turnover = sum(transitions.values()) + close_turnover
        diagnostics.turnover_sides += day_turnover
        gross_return = statistics.fmean(ticker_returns) if ticker_returns else 0.0
        cost_return = half_cost * day_turnover / denominator if denominator else 0.0
        daily_returns.append(max(-0.999999, gross_return - cost_return))
        active_counts.append(denominator)

        benchmark_base = previous_benchmark_close or benchmark_bar.open
        benchmark_returns.append(
            benchmark_bar.close / benchmark_base - 1.0
            if benchmark_base > 0
            else 0.0
        )
        previous_benchmark_close = benchmark_bar.close

    final_day = calendar[-1].day
    for ticker, position in list(open_positions.items()):
        series = price_book.get(ticker)
        if not series:
            continue
        index = bisect.bisect_right(series.days, final_day) - 1
        if index < 0:
            continue
        trades.append(
            close_trade(
                position,
                source=source,
                investor_id=investor_id,
                exit_candidate_id=position.last_candidate_id,
                exit_day=series.days[index],
                exit_price=series.bars[index].close,
                exit_timing="close",
                exit_reason="mark_to_market",
                round_trip_cost_bps=round_trip_cost_bps,
            )
        )

    total_return = math.prod(1.0 + value for value in daily_returns) - 1.0
    benchmark_total = math.prod(1.0 + value for value in benchmark_returns) - 1.0
    cagr = _annualized_return(total_return, len(calendar))
    benchmark_cagr = _annualized_return(benchmark_total, len(calendar))
    volatility = (
        statistics.stdev(daily_returns)
        if len(daily_returns) > 1
        else None
    )
    trade_returns = [trade.net_return for trade in trades]
    return (
        FollowStats(
            start_day=calendar[0].day,
            end_day=calendar[-1].day,
            trading_days=len(calendar),
            active_days=sum(count > 0 for count in active_counts),
            signal_count=len(scheduled),
            trade_count=len(trades),
            long_trades=sum(trade.direction == "bull" for trade in trades),
            short_trades=sum(trade.direction == "bear" for trade in trades),
            exposure_pct=(
                sum(count > 0 for count in active_counts) / len(active_counts)
            ),
            average_active_positions=statistics.fmean(active_counts),
            turnover_sides=diagnostics.turnover_sides,
            total_return=total_return,
            annualized_return=cagr,
            benchmark_total_return=benchmark_total,
            benchmark_annualized_return=benchmark_cagr,
            annualized_excess_return=(
                cagr - benchmark_cagr
                if cagr is not None and benchmark_cagr is not None
                else None
            ),
            annualized_volatility=(
                volatility * math.sqrt(252.0)
                if volatility is not None
                else None
            ),
            sharpe=(
                statistics.fmean(daily_returns) / volatility * math.sqrt(252.0)
                if volatility and volatility > 0
                else None
            ),
            max_drawdown=_max_drawdown(daily_returns),
            trade_hit_rate=(
                sum(value > 0 for value in trade_returns) / len(trade_returns)
                if trade_returns
                else None
            ),
            average_trade_return=(
                statistics.fmean(trade_returns) if trade_returns else None
            ),
            same_direction_updates=diagnostics.same_direction_updates,
            reversals=diagnostics.reversals,
            explicit_exits=diagnostics.explicit_exits,
            price_history_end_exits=diagnostics.price_history_end_exits,
            skipped_no_price=diagnostics.skipped_no_price,
        ),
        trades,
    )


def _events_by_ticker(
    events: Iterable[ScheduledCall],
) -> list[tuple[str, list[ScheduledCall]]]:
    grouped: dict[str, list[ScheduledCall]] = defaultdict(list)
    for event in events:
        grouped[event.call.ticker].append(event)
    return sorted(grouped.items())
