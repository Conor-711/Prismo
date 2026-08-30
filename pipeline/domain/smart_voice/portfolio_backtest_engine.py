"""Pure portfolio simulation helpers for Smart Account strategy backtests."""
from __future__ import annotations

import math
import statistics
from collections import defaultdict
from dataclasses import dataclass
from typing import Iterable


@dataclass(frozen=True)
class PriceBar:
    day: str
    open: float
    close: float
    volume: float = 0.0


@dataclass(frozen=True)
class PriceSeries:
    bars: tuple[PriceBar, ...]
    days: tuple[str, ...]
    index_by_day: dict[str, int]


@dataclass(frozen=True)
class Position:
    position_id: str
    ticker: str
    direction: int
    entry_day: str
    exit_day: str
    base_weight: float = 1.0


@dataclass(frozen=True)
class PortfolioStats:
    start_day: str
    end_day: str
    trading_days: int
    active_days: int
    n_trades: int
    overlap_skipped: int
    exposure_pct: float
    average_positions: float
    total_return: float
    annualized_return: float | None
    annualized_volatility: float | None
    sharpe: float | None
    max_drawdown: float
    trade_hit_rate: float | None
    average_trade_return: float | None
    profit_factor: float | None
    benchmark_annualized_return: float | None


def make_price_series(bars: Iterable[PriceBar]) -> PriceSeries:
    ordered = tuple(sorted(bars, key=lambda bar: bar.day))
    days = tuple(bar.day for bar in ordered)
    return PriceSeries(
        ordered,
        days,
        {day: index for index, day in enumerate(days)},
    )


def select_non_overlapping_positions(
    positions: Iterable[Position],
) -> tuple[list[Position], int]:
    """Keep at most one live position per ticker inside one strategy."""
    by_ticker: dict[str, list[Position]] = defaultdict(list)
    for position in positions:
        by_ticker[position.ticker].append(position)

    selected: list[Position] = []
    skipped = 0
    for ticker_positions in by_ticker.values():
        current_exit = ""
        ordered = sorted(
            ticker_positions,
            key=lambda position: (
                position.entry_day,
                -position.base_weight,
                position.exit_day,
                position.position_id,
            ),
        )
        for position in ordered:
            if current_exit and position.entry_day <= current_exit:
                skipped += 1
                continue
            selected.append(position)
            current_exit = position.exit_day
    selected.sort(key=lambda position: (position.entry_day, position.ticker, position.position_id))
    return selected, skipped


def _annualized_return(total_return: float, trading_days: int) -> float | None:
    if trading_days <= 0 or total_return <= -1.0:
        return None
    return (1.0 + total_return) ** (252.0 / trading_days) - 1.0


def _max_drawdown(daily_returns: list[float]) -> float:
    equity = 1.0
    peak = 1.0
    worst = 0.0
    for daily_return in daily_returns:
        equity *= 1.0 + daily_return
        peak = max(peak, equity)
        if peak:
            worst = min(worst, equity / peak - 1.0)
    return worst


def _profit_factor(values: list[float]) -> float | None:
    gains = sum(value for value in values if value > 0)
    losses = sum(value for value in values if value < 0)
    if losses == 0:
        return None
    return gains / abs(losses)


def _benchmark_annualized_return(
    benchmark: PriceSeries,
    start_day: str,
    end_day: str,
    trading_days: int,
) -> float | None:
    start_index = benchmark.index_by_day.get(start_day)
    end_index = benchmark.index_by_day.get(end_day)
    if start_index is None or end_index is None:
        return None
    entry = benchmark.bars[start_index].open
    exit_price = benchmark.bars[end_index].close
    if entry <= 0 or exit_price <= 0:
        return None
    return _annualized_return(exit_price / entry - 1.0, trading_days)


def simulate_portfolio_costs(
    positions: Iterable[Position],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    round_trip_cost_bps: tuple[int, ...] = (0, 10, 25),
    evaluation_start: str | None = None,
    evaluation_end: str | None = None,
) -> dict[int, PortfolioStats]:
    """Simulate a fully invested equal-weight book with cash on inactive days."""
    canonical, overlap_skipped = select_non_overlapping_positions(positions)
    daily_components: dict[str, list[tuple[float, float, bool, bool]]] = defaultdict(list)
    trade_returns: list[float] = []
    valid_positions: list[Position] = []

    for position in canonical:
        if evaluation_start and position.entry_day < evaluation_start:
            continue
        if evaluation_end and position.exit_day > evaluation_end:
            continue
        series = price_book.get(position.ticker)
        if not series:
            continue
        entry_index = series.index_by_day.get(position.entry_day)
        exit_index = series.index_by_day.get(position.exit_day)
        if entry_index is None or exit_index is None or exit_index < entry_index:
            continue
        entry_bar = series.bars[entry_index]
        exit_bar = series.bars[exit_index]
        if entry_bar.open <= 0 or exit_bar.close <= 0:
            continue
        valid_positions.append(position)
        trade_returns.append(
            position.direction * (exit_bar.close / entry_bar.open - 1.0)
        )
        for index in range(entry_index, exit_index + 1):
            bar = series.bars[index]
            if bar.close <= 0:
                continue
            if index == entry_index:
                base = bar.open
            else:
                base = series.bars[index - 1].close
            if base <= 0:
                continue
            raw_return = bar.close / base - 1.0
            daily_components[bar.day].append(
                (
                    position.direction * raw_return,
                    max(0.01, position.base_weight),
                    index == entry_index,
                    index == exit_index,
                )
            )

    if not valid_positions:
        return {}

    start_day = evaluation_start or min(position.entry_day for position in valid_positions)
    end_day = evaluation_end or max(position.exit_day for position in valid_positions)
    calendar_days = [
        bar.day for bar in benchmark.bars if start_day <= bar.day <= end_day
    ]
    if not calendar_days:
        return {}

    gross_returns: list[float] = []
    cost_turnover: list[float] = []
    active_counts: list[int] = []
    for day in calendar_days:
        components = daily_components.get(day, [])
        if not components:
            gross_returns.append(0.0)
            cost_turnover.append(0.0)
            active_counts.append(0)
            continue
        total_weight = sum(component[1] for component in components)
        gross_returns.append(
            sum(component[0] * component[1] for component in components) / total_weight
        )
        entry_exit_weight = sum(
            component[1] * (int(component[2]) + int(component[3]))
            for component in components
        )
        cost_turnover.append(entry_exit_weight / total_weight)
        active_counts.append(len(components))

    output: dict[int, PortfolioStats] = {}
    for cost_bps in round_trip_cost_bps:
        half_cost = max(0, cost_bps) / 20_000.0
        daily_returns = [
            gross - half_cost * turnover
            for gross, turnover in zip(gross_returns, cost_turnover)
        ]
        equity = math.prod(1.0 + value for value in daily_returns)
        total_return = equity - 1.0
        volatility = statistics.stdev(daily_returns) if len(daily_returns) > 1 else None
        annualized_volatility = volatility * math.sqrt(252.0) if volatility is not None else None
        sharpe = None
        if volatility and volatility > 0:
            sharpe = statistics.fmean(daily_returns) / volatility * math.sqrt(252.0)
        adjusted_trade_returns = [
            value - max(0, cost_bps) / 10_000.0 for value in trade_returns
        ]
        output[cost_bps] = PortfolioStats(
            start_day=calendar_days[0],
            end_day=calendar_days[-1],
            trading_days=len(calendar_days),
            active_days=sum(count > 0 for count in active_counts),
            n_trades=len(valid_positions),
            overlap_skipped=overlap_skipped,
            exposure_pct=sum(count > 0 for count in active_counts) / len(calendar_days),
            average_positions=statistics.fmean(active_counts),
            total_return=total_return,
            annualized_return=_annualized_return(total_return, len(calendar_days)),
            annualized_volatility=annualized_volatility,
            sharpe=sharpe,
            max_drawdown=_max_drawdown(daily_returns),
            trade_hit_rate=(
                sum(value > 0 for value in adjusted_trade_returns)
                / len(adjusted_trade_returns)
                if adjusted_trade_returns
                else None
            ),
            average_trade_return=(
                statistics.fmean(adjusted_trade_returns)
                if adjusted_trade_returns
                else None
            ),
            profit_factor=_profit_factor(adjusted_trade_returns),
            benchmark_annualized_return=_benchmark_annualized_return(
                benchmark,
                calendar_days[0],
                calendar_days[-1],
                len(calendar_days),
            ),
        )
    return output
