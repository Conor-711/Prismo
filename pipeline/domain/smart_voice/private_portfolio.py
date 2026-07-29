"""Executable portfolio backtest for one Private Smart Voice author."""
from __future__ import annotations

import bisect
import math
import sqlite3
import statistics
from collections import defaultdict
from dataclasses import dataclass
from typing import Any

from .portfolio_backtest_engine import PriceBar, PriceSeries, make_price_series


PRIVATE_PORTFOLIO_VERSION = "private-sv-equal-weight-v1"


@dataclass(frozen=True)
class PrivatePosition:
    candidate_id: str
    ticker: str
    direction: int
    published_at: str
    entry_day: str
    exit_day: str


def _price_book(con: sqlite3.Connection) -> dict[str, PriceSeries]:
    grouped: dict[str, list[PriceBar]] = defaultdict(list)
    rows = con.execute(
        """
        SELECT upper(ticker) AS ticker,day,
               CASE
                 WHEN close>0 AND adj_close>0 THEN open*adj_close/close
                 ELSE open
               END AS open,
               COALESCE(NULLIF(adj_close,0),close) AS close
          FROM price_daily
         WHERE open>0 AND COALESCE(NULLIF(adj_close,0),close)>0
         ORDER BY ticker,day
        """
    ).fetchall()
    for row in rows:
        grouped[str(row["ticker"])].append(
            PriceBar(
                day=str(row["day"]),
                open=float(row["open"]),
                close=float(row["close"]),
            )
        )
    return {
        ticker: make_price_series(bars)
        for ticker, bars in grouped.items()
    }


def _canonical_positions(
    cases: list[dict[str, Any]],
    price_book: dict[str, PriceSeries],
) -> tuple[list[PrivatePosition], int]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for case in cases:
        if (
            case.get("direction") not in {"bull", "bear"}
            or not case.get("entry_day")
            or not case.get("exit_day")
        ):
            continue
        grouped[str(case["ticker"]).upper()].append(case)

    positions: list[PrivatePosition] = []
    replaced = 0
    for ticker, ticker_cases in grouped.items():
        series = price_book.get(ticker)
        if not series:
            continue
        latest_by_entry: dict[str, dict[str, Any]] = {}
        for case in sorted(
            ticker_cases,
            key=lambda item: (
                str(item["entry_day"]),
                str(item["published_at"]),
                str(item["candidate_id"]),
            ),
        ):
            entry_day = str(case["entry_day"])
            if entry_day in latest_by_entry:
                replaced += 1
            latest_by_entry[entry_day] = case
        ordered = [
            latest_by_entry[day] for day in sorted(latest_by_entry)
        ]
        for index, case in enumerate(ordered):
            entry_day = str(case["entry_day"])
            exit_day = str(case["exit_day"])
            if entry_day not in series.index_by_day or exit_day not in series.index_by_day:
                continue
            if index + 1 < len(ordered):
                next_entry = str(ordered[index + 1]["entry_day"])
                if next_entry <= exit_day:
                    next_index = bisect.bisect_left(series.days, next_entry)
                    if next_index <= 0:
                        replaced += 1
                        continue
                    exit_day = series.days[next_index - 1]
                    replaced += 1
            if exit_day < entry_day:
                continue
            positions.append(
                PrivatePosition(
                    candidate_id=str(case["candidate_id"]),
                    ticker=ticker,
                    direction=1 if case["direction"] == "bull" else -1,
                    published_at=str(case["published_at"]),
                    entry_day=entry_day,
                    exit_day=exit_day,
                )
            )
    positions.sort(
        key=lambda item: (item.entry_day, item.ticker, item.candidate_id)
    )
    return positions, replaced


def _max_drawdown(equity: list[float], days: list[str]) -> tuple[float, str, str]:
    peak = equity[0]
    peak_day = days[0]
    worst = 0.0
    worst_peak = peak_day
    trough_day = peak_day
    for day, value in zip(days, equity):
        if value > peak:
            peak = value
            peak_day = day
        drawdown = value / peak - 1.0 if peak else 0.0
        if drawdown < worst:
            worst = drawdown
            worst_peak = peak_day
            trough_day = day
    return worst, worst_peak, trough_day


def _annualized_return(total_return: float, trading_days: int) -> float | None:
    if trading_days <= 0 or total_return <= -1:
        return None
    return (1 + total_return) ** (252 / trading_days) - 1


def _year_returns(
    days: list[str],
    strategy_returns: list[float],
    benchmark_returns: list[float],
) -> list[dict[str, Any]]:
    grouped: dict[str, list[tuple[float, float]]] = defaultdict(list)
    for day, strategy, benchmark in zip(
        days,
        strategy_returns,
        benchmark_returns,
    ):
        grouped[day[:4]].append((strategy, benchmark))
    return [
        {
            "year": year,
            "return": math.prod(1 + item[0] for item in values) - 1,
            "benchmarkReturn": math.prod(1 + item[1] for item in values) - 1,
        }
        for year, values in sorted(grouped.items())
    ]


def _simulate(
    positions: list[PrivatePosition],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    cost_bps: int,
) -> dict[str, Any]:
    daily_components: dict[str, list[tuple[float, bool, bool]]] = defaultdict(list)
    for position in positions:
        series = price_book[position.ticker]
        entry_index = series.index_by_day[position.entry_day]
        exit_index = series.index_by_day[position.exit_day]
        for index in range(entry_index, exit_index + 1):
            bar = series.bars[index]
            base = bar.open if index == entry_index else series.bars[index - 1].close
            if base <= 0:
                continue
            daily_components[bar.day].append(
                (
                    position.direction * (bar.close / base - 1),
                    index == entry_index,
                    index == exit_index,
                )
            )

    first_day = min(position.entry_day for position in positions)
    last_day = max(position.exit_day for position in positions)
    benchmark_bars = [
        bar for bar in benchmark.bars if first_day <= bar.day <= last_day
    ]
    days = [bar.day for bar in benchmark_bars]
    strategy_returns: list[float] = []
    benchmark_returns: list[float] = []
    active_counts: list[int] = []
    turnover: list[float] = []
    half_cost = max(0, cost_bps) / 20_000

    previous_benchmark_close = 0.0
    for bar in benchmark_bars:
        components = daily_components.get(bar.day, [])
        count = len(components)
        active_counts.append(count)
        if components:
            gross = statistics.fmean(component[0] for component in components)
            day_turnover = sum(
                int(component[1]) + int(component[2])
                for component in components
            ) / count
        else:
            gross = 0.0
            day_turnover = 0.0
        strategy_returns.append(max(-0.99, gross - half_cost * day_turnover))
        turnover.append(day_turnover)
        base = bar.open if not previous_benchmark_close else previous_benchmark_close
        benchmark_returns.append(bar.close / base - 1 if base > 0 else 0.0)
        previous_benchmark_close = bar.close

    strategy_equity: list[float] = []
    benchmark_equity: list[float] = []
    strategy_value = benchmark_value = 1.0
    for strategy_return, benchmark_return in zip(
        strategy_returns,
        benchmark_returns,
    ):
        strategy_value *= 1 + strategy_return
        benchmark_value *= 1 + benchmark_return
        strategy_equity.append(strategy_value)
        benchmark_equity.append(benchmark_value)

    total_return = strategy_equity[-1] - 1
    benchmark_total_return = benchmark_equity[-1] - 1
    annualized_return = _annualized_return(total_return, len(days))
    benchmark_annualized_return = _annualized_return(
        benchmark_total_return,
        len(days),
    )
    volatility = (
        statistics.stdev(strategy_returns) if len(strategy_returns) > 1 else None
    )
    annualized_volatility = (
        volatility * math.sqrt(252) if volatility is not None else None
    )
    sharpe = (
        statistics.fmean(strategy_returns) / volatility * math.sqrt(252)
        if volatility and volatility > 0
        else None
    )
    downside = math.sqrt(
        statistics.fmean(min(0.0, value) ** 2 for value in strategy_returns)
    )
    sortino = (
        statistics.fmean(strategy_returns) / downside * math.sqrt(252)
        if downside > 0
        else None
    )
    max_drawdown, peak_day, trough_day = _max_drawdown(strategy_equity, days)
    benchmark_drawdown, _, _ = _max_drawdown(benchmark_equity, days)
    covariance = (
        statistics.covariance(strategy_returns, benchmark_returns)
        if len(strategy_returns) > 1
        else 0.0
    )
    benchmark_variance = (
        statistics.variance(benchmark_returns)
        if len(benchmark_returns) > 1
        else 0.0
    )
    beta = covariance / benchmark_variance if benchmark_variance > 0 else None
    alpha = (
        (
            statistics.fmean(strategy_returns)
            - beta * statistics.fmean(benchmark_returns)
        )
        * 252
        if beta is not None
        else None
    )
    active_returns = [
        value
        for value, count in zip(strategy_returns, active_counts)
        if count > 0
    ]
    return {
        "costBps": cost_bps,
        "startDay": days[0],
        "endDay": days[-1],
        "tradingDays": len(days),
        "activeDays": sum(count > 0 for count in active_counts),
        "tradeCount": len(positions),
        "exposurePct": sum(count > 0 for count in active_counts) / len(days),
        "averageActivePositions": statistics.fmean(active_counts),
        "turnoverUnits": sum(turnover),
        "totalReturn": total_return,
        "annualizedReturn": annualized_return,
        "annualizedExcessReturn": (
            annualized_return - benchmark_annualized_return
            if annualized_return is not None
            and benchmark_annualized_return is not None
            else None
        ),
        "annualizedVolatility": annualized_volatility,
        "sharpe": sharpe,
        "sortino": sortino,
        "maxDrawdown": max_drawdown,
        "drawdownPeakDay": peak_day,
        "drawdownTroughDay": trough_day,
        "calmar": (
            annualized_return / abs(max_drawdown)
            if annualized_return is not None and max_drawdown < 0
            else None
        ),
        "positiveActiveDayRate": (
            sum(value > 0 for value in active_returns) / len(active_returns)
            if active_returns
            else None
        ),
        "benchmarkTotalReturn": benchmark_total_return,
        "benchmarkAnnualizedReturn": benchmark_annualized_return,
        "benchmarkMaxDrawdown": benchmark_drawdown,
        "beta": beta,
        "annualizedAlpha": alpha,
        "yearReturns": _year_returns(
            days,
            strategy_returns,
            benchmark_returns,
        ),
        "equityCurve": [
            {
                "day": day,
                "strategy": strategy,
                "benchmark": benchmark_value,
                "drawdown": strategy / max(strategy_equity[: index + 1]) - 1,
                "activePositions": active_counts[index],
            }
            for index, (day, strategy, benchmark_value) in enumerate(
                zip(days, strategy_equity, benchmark_equity)
            )
        ],
    }


def build_private_portfolio_backtest(
    con: sqlite3.Connection,
    cases: list[dict[str, Any]],
) -> dict[str, Any]:
    """Build a no-lookahead, equal-weight follow-the-call portfolio."""
    price_book = _price_book(con)
    benchmark = price_book.get("SPY")
    if not benchmark:
        raise RuntimeError("SPY price history is required for Private SV backtest")
    positions, replaced = _canonical_positions(cases, price_book)
    if not positions:
        raise RuntimeError("no executable Private SV positions are available")
    simulations = {
        cost: _simulate(positions, price_book, benchmark, cost)
        for cost in (0, 10, 25)
    }
    base = simulations[10]
    return {
        "version": PRIVATE_PORTFOLIO_VERSION,
        "methodology": {
            "mode": "long_short",
            "entry": "next_trading_day_adjusted_open",
            "exit": "primary_horizon_or_next_same_ticker_call",
            "allocation": "equal_weight_active_tickers",
            "cashWhenInactive": True,
            "roundTripCostBps": 10,
            "riskFreeRate": 0,
            "sameTickerRule": "latest_call_replaces_previous",
            "overlappingCallsReplaced": replaced,
        },
        "base": base,
        "costSensitivity": [
            {
                "costBps": cost,
                "totalReturn": simulation["totalReturn"],
                "annualizedReturn": simulation["annualizedReturn"],
                "sharpe": simulation["sharpe"],
            }
            for cost, simulation in simulations.items()
        ],
    }
