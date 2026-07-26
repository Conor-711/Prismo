"""Wide-grid and split-sample research for X SV rank events."""
from __future__ import annotations

import bisect
import collections
import csv
import sqlite3
import statistics
from pathlib import Path
from typing import Any, Callable

from .portfolio_backtest import _load_price_book
from .portfolio_backtest_engine import (
    Position,
    PortfolioStats,
    PriceSeries,
    select_non_overlapping_positions,
    simulate_portfolio_costs,
)
from .rank_event_backtest import RankSignalEvent, build_rank_signal_events

RESEARCH_RANK_BANDS = (5, 10, 15, 20, 25, 33)
RESEARCH_WINDOWS = (1, 3, 5, 7, 10, 14, 21, 30, 45)
RESEARCH_HOLDING_DAYS = (1, 3, 5, 10, 20, 40, 60, 90, 120, 180)
RESEARCH_MODES = ("long_short", "long_only", "short_only")
EXECUTION_PROFILES = {
    "unfiltered": (0.0, 0.0),
    "price5_adv1m": (5.0, 1_000_000.0),
    "price10_adv10m": (10.0, 10_000_000.0),
    "price10_adv50m": (10.0, 50_000_000.0),
}


def _mode_allows(mode: str, event: RankSignalEvent) -> bool:
    if mode == "long_short":
        return True
    if mode == "long_only":
        return event.direction == "bull"
    return event.direction == "bear"


def _positions(
    events: list[RankSignalEvent],
    price_book: dict[str, PriceSeries],
    holding_days: int,
    mode: str,
    execution_filter: str,
    entry_lag_days: int = 0,
) -> list[Position]:
    min_price, min_dollar_volume = EXECUTION_PROFILES[execution_filter]
    output: list[Position] = []
    for event in events:
        if not _mode_allows(mode, event):
            continue
        series = price_book.get(event.ticker)
        if not series:
            continue
        entry_index = bisect.bisect_right(series.days, event.signal_day) + max(
            0,
            entry_lag_days,
        )
        exit_index = entry_index + holding_days - 1
        if entry_index >= len(series.days) or exit_index >= len(series.days):
            continue
        entry_bar = series.bars[entry_index]
        history = series.bars[max(0, entry_index - 20) : entry_index]
        average_dollar_volume = (
            statistics.fmean(bar.close * bar.volume for bar in history)
            if history
            else 0.0
        )
        if entry_bar.open < min_price or average_dollar_volume < min_dollar_volume:
            continue
        output.append(
            Position(
                position_id=event.event_id,
                ticker=event.ticker,
                direction=1 if event.direction == "bull" else -1,
                entry_day=series.days[entry_index],
                exit_day=series.days[exit_index],
            )
        )
    return output


def _stats_fields(stats: PortfolioStats | None, prefix: str) -> dict[str, Any]:
    if stats is None:
        return {
            f"{prefix}_n_trades": 0,
            f"{prefix}_trading_days": 0,
            f"{prefix}_annualized_return": None,
            f"{prefix}_total_return": None,
            f"{prefix}_sharpe": None,
            f"{prefix}_max_drawdown": None,
            f"{prefix}_hit_rate": None,
            f"{prefix}_exposure": None,
            f"{prefix}_benchmark_annualized_return": None,
        }
    return {
        f"{prefix}_n_trades": stats.n_trades,
        f"{prefix}_trading_days": stats.trading_days,
        f"{prefix}_annualized_return": stats.annualized_return,
        f"{prefix}_total_return": stats.total_return,
        f"{prefix}_sharpe": stats.sharpe,
        f"{prefix}_max_drawdown": stats.max_drawdown,
        f"{prefix}_hit_rate": stats.trade_hit_rate,
        f"{prefix}_exposure": stats.exposure_pct,
        f"{prefix}_benchmark_annualized_return": stats.benchmark_annualized_return,
    }


def _simulate_period(
    positions: list[Position],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    start: str,
    end: str,
    cost_bps: int = 10,
) -> PortfolioStats | None:
    result = simulate_portfolio_costs(
        positions,
        price_book,
        benchmark,
        (cost_bps,),
        evaluation_start=start,
        evaluation_end=end,
    )
    return result.get(cost_bps)


def _study_periods(
    events: list[RankSignalEvent],
    benchmark: PriceSeries,
) -> dict[str, tuple[str, str]]:
    first_signal = min(event.signal_day for event in events)
    start_index = next(
        index for index, day in enumerate(benchmark.days) if day > first_signal
    )
    end_index = len(benchmark.days) - 1
    midpoint = (start_index + end_index) // 2
    return {
        "full": (benchmark.days[start_index], benchmark.days[end_index]),
        "early": (benchmark.days[start_index], benchmark.days[midpoint]),
        "late": (benchmark.days[midpoint + 1], benchmark.days[end_index]),
    }


def _evaluate_scenario(
    events: list[RankSignalEvent],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    periods: dict[str, tuple[str, str]],
    holding_days: int,
    mode: str,
    execution_filter: str = "unfiltered",
) -> dict[str, Any]:
    positions = _positions(
        events,
        price_book,
        holding_days,
        mode,
        execution_filter,
    )
    output: dict[str, Any] = {"n_input_events": len(positions)}
    for name, (start, end) in periods.items():
        output.update(
            _stats_fields(
                _simulate_period(
                    positions,
                    price_book,
                    benchmark,
                    start,
                    end,
                ),
                name,
            )
        )
    early = output.get("early_annualized_return")
    late = output.get("late_annualized_return")
    output["min_half_annualized_return"] = (
        min(float(early), float(late))
        if early is not None and late is not None
        else None
    )
    return output


def _event_metric(event: RankSignalEvent, metric: str) -> float:
    if metric == "consensus":
        if event.strategy == "top_follow":
            return event.top_consensus
        if event.strategy == "bottom_contrarian":
            return event.bottom_consensus
        return min(event.top_consensus, event.bottom_consensus)
    if event.strategy == "top_follow":
        return float(event.top_authors)
    if event.strategy == "bottom_contrarian":
        return float(event.bottom_authors)
    return float(min(event.top_authors, event.bottom_authors))


def _point_in_time_strength_ids(
    events: list[RankSignalEvent],
    quantile: float,
    min_history: int = 20,
) -> set[str]:
    """Qualify strength using only events strictly earlier than the signal day."""
    by_day: dict[str, list[RankSignalEvent]] = collections.defaultdict(list)
    for event in events:
        by_day[event.signal_day].append(event)

    history: list[float] = []
    qualified: set[str] = set()
    for day in sorted(by_day):
        day_events = by_day[day]
        if len(history) >= min_history:
            index = round((len(history) - 1) * max(0.0, min(1.0, quantile)))
            threshold = history[index]
            qualified.update(
                event.event_id
                for event in day_events
                if event.signal_value >= threshold
            )
        for event in day_events:
            bisect.insort(history, event.signal_value)
    return qualified


def _condition_filters(events: list[RankSignalEvent]) -> dict[str, Callable[[RankSignalEvent], bool]]:
    top_half_ids = _point_in_time_strength_ids(events, 0.50)
    top_quartile_ids = _point_in_time_strength_ids(events, 0.75)
    return {
        "all": lambda event: True,
        "strength_top50": lambda event: event.event_id in top_half_ids,
        "strength_top25": lambda event: event.event_id in top_quartile_ids,
        "consensus_80": lambda event: _event_metric(event, "consensus") >= 0.80,
        "consensus_90": lambda event: _event_metric(event, "consensus") >= 0.90,
        "authors_4": lambda event: _event_metric(event, "authors") >= 4,
        "consensus80_authors4": lambda event: (
            _event_metric(event, "consensus") >= 0.80
            and _event_metric(event, "authors") >= 4
        ),
    }


def _broad_grid(
    events: list[RankSignalEvent],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    periods: dict[str, tuple[str, str]],
) -> tuple[list[dict[str, Any]], dict[tuple[str, int, int], list[RankSignalEvent]]]:
    grouped: dict[tuple[str, int, int], list[RankSignalEvent]] = collections.defaultdict(list)
    for event in events:
        grouped[(event.strategy, event.rank_band_pct, event.window_days)].append(event)
    rows: list[dict[str, Any]] = []
    for (strategy, rank_band, window), group in sorted(grouped.items()):
        for holding_days in RESEARCH_HOLDING_DAYS:
            for mode in RESEARCH_MODES:
                metrics = _evaluate_scenario(
                    group,
                    price_book,
                    benchmark,
                    periods,
                    holding_days,
                    mode,
                )
                if metrics["full_n_trades"] == 0:
                    continue
                rows.append(
                    {
                        "strategy": strategy,
                        "rank_band_pct": rank_band,
                        "window_days": window,
                        "holding_days": holding_days,
                        "position_mode": mode,
                        "condition": "all",
                        "execution_filter": "unfiltered",
                        **metrics,
                    }
                )
    return rows, grouped


def _candidate_keys(
    rows: list[dict[str, Any]],
    selection_period: str = "full",
) -> set[tuple[str, int, int, int]]:
    output: set[tuple[str, int, int, int]] = set()
    annualized_field = f"{selection_period}_annualized_return"
    trades_field = f"{selection_period}_n_trades"
    days_field = f"{selection_period}_trading_days"
    for strategy in ("top_follow", "bottom_contrarian", "top_bottom_divergence"):
        candidates = [
            row
            for row in rows
            if row["strategy"] == strategy
            and row["position_mode"] == "long_short"
            and row[trades_field] >= (10 if selection_period == "early" else 20)
            and row[days_field] >= (100 if selection_period == "early" else 126)
            and row[annualized_field] is not None
        ]
        candidates.sort(
            key=lambda row: row[annualized_field],
            reverse=True,
        )
        limit = 50 if selection_period == "early" else 30
        for row in candidates[:limit]:
            output.add(
                (
                    str(row["strategy"]),
                    int(row["rank_band_pct"]),
                    int(row["window_days"]),
                    int(row["holding_days"]),
                )
            )
    return output


def _refinement_grid(
    candidate_keys: set[tuple[str, int, int, int]],
    grouped: dict[tuple[str, int, int], list[RankSignalEvent]],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    periods: dict[str, tuple[str, str]],
) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for strategy, rank_band, window, holding_days in sorted(candidate_keys):
        events = grouped[(strategy, rank_band, window)]
        for condition, predicate in _condition_filters(events).items():
            filtered = [event for event in events if predicate(event)]
            if not filtered:
                continue
            for mode in RESEARCH_MODES:
                for execution_filter in EXECUTION_PROFILES:
                    metrics = _evaluate_scenario(
                        filtered,
                        price_book,
                        benchmark,
                        periods,
                        holding_days,
                        mode,
                        execution_filter,
                    )
                    if metrics["full_n_trades"] == 0:
                        continue
                    output.append(
                        {
                            "strategy": strategy,
                            "rank_band_pct": rank_band,
                            "window_days": window,
                            "holding_days": holding_days,
                            "position_mode": mode,
                            "condition": condition,
                            "execution_filter": execution_filter,
                            **metrics,
                        }
                    )
    return output


def _stress_candidates(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    eligible = [
        row
        for row in rows
        if row["execution_filter"] == "price10_adv50m"
        and row["full_n_trades"] >= 20
        and row["early_n_trades"] >= 5
        and row["late_n_trades"] >= 5
        and row["early_annualized_return"] is not None
        and row["late_annualized_return"] is not None
        and row["early_annualized_return"] > 0
        and row["late_annualized_return"] > 0
        and row["full_max_drawdown"] >= -0.50
    ]
    by_full = sorted(
        eligible,
        key=lambda row: row["full_annualized_return"],
        reverse=True,
    )[:25]
    by_split_floor = sorted(
        eligible,
        key=lambda row: min(
            row["early_annualized_return"],
            row["late_annualized_return"],
        ),
        reverse=True,
    )[:25]
    output: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    for row in by_full + by_split_floor:
        key = (
            row["strategy"],
            row["rank_band_pct"],
            row["window_days"],
            row["holding_days"],
            row["position_mode"],
            row["condition"],
            row["execution_filter"],
        )
        if key in seen:
            continue
        seen.add(key)
        output.append(row)
    return output


def _ticker_contributors(
    positions: list[Position],
    price_book: dict[str, PriceSeries],
) -> list[tuple[str, float]]:
    canonical, _ = select_non_overlapping_positions(positions)
    totals: dict[str, float] = collections.defaultdict(float)
    for position in canonical:
        series = price_book[position.ticker]
        entry = series.bars[series.index_by_day[position.entry_day]].open
        exit_price = series.bars[series.index_by_day[position.exit_day]].close
        totals[position.ticker] += (
            position.direction * (exit_price / entry - 1.0) - 0.001
        )
    return sorted(totals.items(), key=lambda item: item[1], reverse=True)


def _stress_grid(
    refined: list[dict[str, Any]],
    grouped: dict[tuple[str, int, int], list[RankSignalEvent]],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    periods: dict[str, tuple[str, str]],
) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    full_start, full_end = periods["full"]
    for candidate in _stress_candidates(refined):
        events = grouped[
            (
                candidate["strategy"],
                candidate["rank_band_pct"],
                candidate["window_days"],
            )
        ]
        predicate = _condition_filters(events)[candidate["condition"]]
        filtered = [event for event in events if predicate(event)]
        positions = _positions(
            filtered,
            price_book,
            candidate["holding_days"],
            candidate["position_mode"],
            candidate["execution_filter"],
        )
        cost_50 = _simulate_period(
            positions,
            price_book,
            benchmark,
            full_start,
            full_end,
            50,
        )
        cost_100 = _simulate_period(
            positions,
            price_book,
            benchmark,
            full_start,
            full_end,
            100,
        )
        lag_stats: dict[int, PortfolioStats | None] = {}
        for lag in (1, 2, 10):
            delayed = _positions(
                filtered,
                price_book,
                candidate["holding_days"],
                candidate["position_mode"],
                candidate["execution_filter"],
                entry_lag_days=lag,
            )
            lag_stats[lag] = _simulate_period(
                delayed,
                price_book,
                benchmark,
                full_start,
                full_end,
            )

        contributors = _ticker_contributors(positions, price_book)
        exclusion_stats: dict[int, PortfolioStats | None] = {}
        for count in (1, 3, 5):
            excluded = {ticker for ticker, _ in contributors[:count]}
            exclusion_stats[count] = _simulate_period(
                [
                    position
                    for position in positions
                    if position.ticker not in excluded
                ],
                price_book,
                benchmark,
                full_start,
                full_end,
            )

        stress_values = [
            candidate["early_annualized_return"],
            candidate["late_annualized_return"],
            cost_50.annualized_return if cost_50 else None,
            lag_stats[2].annualized_return if lag_stats[2] else None,
            (
                exclusion_stats[3].annualized_return
                if exclusion_stats[3]
                else None
            ),
        ]
        stress_floor = min(value for value in stress_values if value is not None)
        output.append(
            {
                **candidate,
                "benchmark_annualized_return": (
                    cost_50.benchmark_annualized_return if cost_50 else None
                ),
                "unique_tickers": len(contributors),
                "top_contributors": ",".join(
                    ticker for ticker, _ in contributors[:5]
                ),
                "annualized_return_50bps": (
                    cost_50.annualized_return if cost_50 else None
                ),
                "annualized_return_100bps": (
                    cost_100.annualized_return if cost_100 else None
                ),
                "annualized_return_lag1": (
                    lag_stats[1].annualized_return if lag_stats[1] else None
                ),
                "annualized_return_lag2": (
                    lag_stats[2].annualized_return if lag_stats[2] else None
                ),
                "annualized_return_lag10": (
                    lag_stats[10].annualized_return if lag_stats[10] else None
                ),
                "annualized_return_ex_top1": (
                    exclusion_stats[1].annualized_return
                    if exclusion_stats[1]
                    else None
                ),
                "annualized_return_ex_top3": (
                    exclusion_stats[3].annualized_return
                    if exclusion_stats[3]
                    else None
                ),
                "annualized_return_ex_top5": (
                    exclusion_stats[5].annualized_return
                    if exclusion_stats[5]
                    else None
                ),
                "stress_floor": stress_floor,
            }
        )
    return output


def _walk_forward_rows(
    refined: list[dict[str, Any]],
    early_candidate_keys: set[tuple[str, int, int, int]],
    grouped: dict[tuple[str, int, int], list[RankSignalEvent]],
    price_book: dict[str, PriceSeries],
    benchmark: PriceSeries,
    periods: dict[str, tuple[str, str]],
) -> list[dict[str, Any]]:
    """Select parameters on early 50bps net returns, then evaluate the late period."""
    eligible = [
        row
        for row in refined
        if (
            row["strategy"],
            row["rank_band_pct"],
            row["window_days"],
            row["holding_days"],
        )
        in early_candidate_keys
        and row["execution_filter"] == "price10_adv50m"
        and row["early_n_trades"] >= 20
        and row["early_trading_days"] >= 100
        and row["early_annualized_return"] is not None
        and row["early_max_drawdown"] is not None
        and row["early_max_drawdown"] >= -0.40
    ]
    early_start, early_end = periods["early"]
    late_start, late_end = periods["late"]
    filtered_cache: dict[tuple[str, int, int, str], list[RankSignalEvent]] = {}
    trained: list[dict[str, Any]] = []
    positions_by_signature: dict[tuple[Any, ...], list[Position]] = {}
    for row in eligible:
        event_key = (
            row["strategy"],
            row["rank_band_pct"],
            row["window_days"],
            row["condition"],
        )
        if event_key not in filtered_cache:
            events = grouped[event_key[:3]]
            predicate = _condition_filters(events)[row["condition"]]
            filtered_cache[event_key] = [
                event for event in events if predicate(event)
            ]
        signature = (
            *event_key,
            row["holding_days"],
            row["position_mode"],
            row["execution_filter"],
        )
        positions = _positions(
            filtered_cache[event_key],
            price_book,
            row["holding_days"],
            row["position_mode"],
            row["execution_filter"],
        )
        positions_by_signature[signature] = positions
        early_cost = _simulate_period(
            positions,
            price_book,
            benchmark,
            early_start,
            early_end,
            50,
        )
        if not early_cost or early_cost.n_trades < 20:
            continue
        trained.append(
            {
                **row,
                "_signature": signature,
                "selection_annualized_return_50bps": early_cost.annualized_return,
                "selection_sharpe_50bps": early_cost.sharpe,
                "selection_max_drawdown_50bps": early_cost.max_drawdown,
            }
        )

    trained.sort(
        key=lambda row: (
            (
                row["selection_annualized_return_50bps"]
                if row["selection_annualized_return_50bps"] is not None
                else -999.0
            ),
            (
                row["selection_sharpe_50bps"]
                if row["selection_sharpe_50bps"] is not None
                else -999.0
            ),
            row["early_n_trades"],
        ),
        reverse=True,
    )
    selected: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    for row in trained:
        signature = (
            row["strategy"],
            row["rank_band_pct"],
            row["window_days"],
            row["holding_days"],
            row["position_mode"],
            row["condition"],
        )
        if signature in seen:
            continue
        seen.add(signature)
        selected.append(row)
        if len(selected) >= 20:
            break

    output: list[dict[str, Any]] = []
    for row in selected:
        positions = positions_by_signature[row["_signature"]]
        late_50 = _simulate_period(
            positions,
            price_book,
            benchmark,
            late_start,
            late_end,
            50,
        )
        late_100 = _simulate_period(
            positions,
            price_book,
            benchmark,
            late_start,
            late_end,
            100,
        )
        event_key = row["_signature"][:4]
        delayed = _positions(
            filtered_cache[event_key],
            price_book,
            row["holding_days"],
            row["position_mode"],
            row["execution_filter"],
            entry_lag_days=2,
        )
        late_delayed_50 = _simulate_period(
            delayed,
            price_book,
            benchmark,
            late_start,
            late_end,
            50,
        )
        output.append(
            {
                "selection_rank": len(output) + 1,
                **{key: value for key, value in row.items() if key != "_signature"},
                "late_excess_vs_benchmark": (
                    row["late_annualized_return"]
                    - row["late_benchmark_annualized_return"]
                    if row["late_annualized_return"] is not None
                    and row["late_benchmark_annualized_return"] is not None
                    else None
                ),
                "late_annualized_return_50bps": (
                    late_50.annualized_return if late_50 else None
                ),
                "late_annualized_return_100bps": (
                    late_100.annualized_return if late_100 else None
                ),
                "late_annualized_return_lag2_50bps": (
                    late_delayed_50.annualized_return
                    if late_delayed_50
                    else None
                ),
            }
        )
    return output


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for column in row:
            if column not in seen:
                columns.append(column)
                seen.add(column)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)
    return len(rows)


def _pct(value: Any) -> str:
    return "-" if value is None else f"{float(value) * 100:.1f}%"


def _table(rows: list[dict[str, Any]]) -> list[str]:
    labels = {
        "top_follow": "跟随头部",
        "bottom_contrarian": "反向底部",
        "top_bottom_divergence": "头尾背离",
    }
    lines = [
        "|策略|分位|窗口|持有|方向|条件|执行过滤|全期年化|前半年|后半年|后半年交易|全期回撤|",
        "|---|---:|---:|---:|---|---|---|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "|{strategy}|{rank}%|{window}D|{hold}D|{mode}|{condition}|{execution}|{full}|"
            "{early}|{late}|{trades}|{drawdown}|".format(
                strategy=labels.get(row["strategy"], row["strategy"]),
                rank=row["rank_band_pct"],
                window=row["window_days"],
                hold=row["holding_days"],
                mode=row["position_mode"],
                condition=row["condition"],
                execution=row.get("execution_filter", "unfiltered"),
                full=_pct(row["full_annualized_return"]),
                early=_pct(row["early_annualized_return"]),
                late=_pct(row["late_annualized_return"]),
                trades=row["late_n_trades"],
                drawdown=_pct(row["full_max_drawdown"]),
            )
        )
    return lines


def _stress_table(rows: list[dict[str, Any]]) -> list[str]:
    labels = {
        "top_follow": "跟随头部",
        "bottom_contrarian": "反向底部",
        "top_bottom_divergence": "头尾背离",
    }
    mode_labels = {
        "long_short": "多空",
        "long_only": "只做多",
        "short_only": "只做空",
    }
    lines = [
        "|策略|方向|分位|窗口|持有|条件|全期|前半|后半|50bps|延迟2D|剔除前三标的|压力下限|交易|回撤|",
        "|---|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "|{strategy}|{mode}|{rank}%|{window}D|{hold}D|{condition}|{full}|"
            "{early}|{late}|{cost}|{lag}|{exclude}|{floor}|{trades}|{drawdown}|".format(
                strategy=labels.get(row["strategy"], row["strategy"]),
                mode=mode_labels.get(row["position_mode"], row["position_mode"]),
                rank=row["rank_band_pct"],
                window=row["window_days"],
                hold=row["holding_days"],
                condition=row["condition"],
                full=_pct(row["full_annualized_return"]),
                early=_pct(row["early_annualized_return"]),
                late=_pct(row["late_annualized_return"]),
                cost=_pct(row["annualized_return_50bps"]),
                lag=_pct(row["annualized_return_lag2"]),
                exclude=_pct(row["annualized_return_ex_top3"]),
                floor=_pct(row["stress_floor"]),
                trades=row["full_n_trades"],
                drawdown=_pct(row["full_max_drawdown"]),
            )
        )
    return lines


def _walk_forward_table(rows: list[dict[str, Any]]) -> list[str]:
    labels = {
        "top_follow": "跟随头部",
        "bottom_contrarian": "反向底部",
        "top_bottom_divergence": "头尾背离",
    }
    mode_labels = {
        "long_short": "多空",
        "long_only": "只做多",
        "short_only": "只做空",
    }
    lines = [
        "|训练排名|策略|方向|分位|窗口|持有|条件|训练期50bps|训练交易|样本外10bps|样本外50bps|样本外100bps|延迟2D+50bps|样本外SPY|样本外交易|样本外回撤|",
        "|---:|---|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "|{rank_no}|{strategy}|{mode}|{band}%|{window}D|{hold}D|{condition}|"
            "{early}|{early_trades}|{late}|{late_50}|{late_100}|{late_lag}|"
            "{benchmark}|{late_trades}|{drawdown}|".format(
                rank_no=row["selection_rank"],
                strategy=labels.get(row["strategy"], row["strategy"]),
                mode=mode_labels.get(row["position_mode"], row["position_mode"]),
                band=row["rank_band_pct"],
                window=row["window_days"],
                hold=row["holding_days"],
                condition=row["condition"],
                early=_pct(row["selection_annualized_return_50bps"]),
                early_trades=row["early_n_trades"],
                late=_pct(row["late_annualized_return"]),
                late_50=_pct(row["late_annualized_return_50bps"]),
                late_100=_pct(row["late_annualized_return_100bps"]),
                late_lag=_pct(row["late_annualized_return_lag2_50bps"]),
                benchmark=_pct(row["late_benchmark_annualized_return"]),
                late_trades=row["late_n_trades"],
                drawdown=_pct(row["late_max_drawdown"]),
            )
        )
    return lines


def _valid_research_row(row: dict[str, Any]) -> bool:
    return (
        row["position_mode"] == "long_short"
        and row["full_n_trades"] >= 20
        and row["early_n_trades"] >= 8
        and row["late_n_trades"] >= 8
        and row["full_trading_days"] >= 126
        and row["early_annualized_return"] is not None
        and row["late_annualized_return"] is not None
        and row["full_max_drawdown"] is not None
        and row["full_max_drawdown"] >= -0.40
    )


def _write_report(
    path: Path,
    broad: list[dict[str, Any]],
    refined: list[dict[str, Any]],
    stress: list[dict[str, Any]],
    walk_forward: list[dict[str, Any]],
    periods: dict[str, tuple[str, str]],
    diagnostics: dict[str, int],
) -> None:
    valid = [row for row in broad if _valid_research_row(row)]
    in_sample = sorted(
        valid,
        key=lambda row: row["full_annualized_return"],
        reverse=True,
    )[:15]
    robust = sorted(
        [
            row
            for row in valid
            if row["early_annualized_return"] > 0
            and row["late_annualized_return"] > 0
        ],
        key=lambda row: row["min_half_annualized_return"],
        reverse=True,
    )[:15]
    early_selected = sorted(
        valid,
        key=lambda row: row["early_annualized_return"],
        reverse=True,
    )[:15]
    refined_valid = [
        row
        for row in refined
        if _valid_research_row(row)
        and row["early_annualized_return"] > 0
        and row["late_annualized_return"] > 0
    ]
    refined_best = sorted(
        refined_valid,
        key=lambda row: row["min_half_annualized_return"],
        reverse=True,
    )[:15]
    liquid_best = sorted(
        [
            row
            for row in refined_valid
            if row.get("execution_filter") == "price10_adv10m"
        ],
        key=lambda row: row["min_half_annualized_return"],
        reverse=True,
    )[:15]
    raw_stress_best = sorted(
        stress,
        key=lambda row: row["full_annualized_return"],
        reverse=True,
    )[:10]
    robust_stress_best = sorted(
        stress,
        key=lambda row: row["stress_floor"],
        reverse=True,
    )[:10]
    best_raw = raw_stress_best[0] if raw_stress_best else None
    best_robust = robust_stress_best[0] if robust_stress_best else None
    best_mode_rows: dict[str, dict[str, Any]] = {}
    if best_robust:
        for row in refined:
            if (
                row["strategy"] == best_robust["strategy"]
                and row["rank_band_pct"] == best_robust["rank_band_pct"]
                and row["window_days"] == best_robust["window_days"]
                and row["holding_days"] == best_robust["holding_days"]
                and row["condition"] == best_robust["condition"]
                and row["execution_filter"] == best_robust["execution_filter"]
            ):
                best_mode_rows[row["position_mode"]] = row
    lines = [
        "# X SV 排名事件宽参数研究",
        "",
        f"- 全期：{periods['full'][0]} 至 {periods['full'][1]}。",
        f"- 前半段：{periods['early'][0]} 至 {periods['early'][1]}。",
        f"- 后半段：{periods['late'][0]} 至 {periods['late'][1]}。",
        f"- 历史时点合格 Call：{diagnostics['ranked_calls']:,} 条；"
        f"事件：{diagnostics['rank_events']:,} 个。",
        "- 所有结果均扣除每笔 10bps 完整往返成本。",
        "- 作者排名只使用 `exit_day < signal_day` 的已结算 Call；"
        "信号强度分位只使用信号日前至少 20 个历史事件。",
        "- 所有事件从信号后的下一交易日开盘入场；成交额过滤只读取入场日前 20 个交易日。",
        "",
        "## 全样本最高年化",
        "",
        "该表用于发现候选，不代表可复制收益。",
        "",
    ]
    lines.extend(_table(in_sample))
    lines.extend(
        [
            "",
            "## 前后半段都为正的稳健候选",
            "",
            "按前后半段较低的年化排序，并要求全期最大回撤不超过 40%。",
            "",
        ]
    )
    lines.extend(_table(robust))
    lines.extend(
        [
            "",
            "## 只按前半段选择后的后半段表现",
            "",
            "这张表更接近时间外检验：参数只按前半段年化排序，右栏展示其后半段结果。",
            "",
        ]
    )
    lines.extend(_table(early_selected))
    lines.extend(
        [
            "",
            "## 事件条件细化后的稳健候选",
            "",
            "条件包括高信号强度、高共识和更多独立作者参与。",
            "",
        ]
    )
    lines.extend(_table(refined_best))
    lines.extend(
        [
            "",
            "## 可交易性过滤后的稳健候选",
            "",
            "要求入场调整价至少 10 美元，且入场前 20 日平均成交额至少 1000 万美元。",
            "",
        ]
    )
    lines.extend(_table(liquid_best))
    lines.extend(
        [
            "",
            "## 全样本高流动性候选压力测试（仅用于发现）",
            "",
            "候选要求入场价至少 10 美元、前 20 日平均成交额至少 5000 万美元；"
            "压力下限取前后半段、50bps 成本、延迟 2 个交易日和剔除前三大收益贡献标的后的最低年化。",
            "该节看过全样本后筛选候选，不属于样本外验证。",
            "",
            "### 原始年化最高",
            "",
        ]
    )
    lines.extend(_stress_table(raw_stress_best))
    lines.extend(
        [
            "",
            "### 压力测试后最高",
            "",
        ]
    )
    lines.extend(_stress_table(robust_stress_best))
    if best_raw and best_robust:
        lines.extend(
            [
                "",
                "### 结论",
                "",
                "- 高流动性候选中的原始最高值是"
                f"`{best_raw['strategy']} / {best_raw['position_mode']} / "
                f"Top-Bottom {best_raw['rank_band_pct']}% / "
                f"{best_raw['window_days']}D 窗口 / {best_raw['holding_days']}D 持有`，"
                f"年化 {_pct(best_raw['full_annualized_return'])}，但压力下限只有 "
                f"{_pct(best_raw['stress_floor'])}。",
                "- 压力测试后的最佳候选是"
                f"`{best_robust['strategy']} / {best_robust['position_mode']} / "
                f"Top-Bottom {best_robust['rank_band_pct']}% / "
                f"{best_robust['window_days']}D 窗口 / {best_robust['holding_days']}D 持有`，"
                f"原始年化 {_pct(best_robust['full_annualized_return'])}，压力下限 "
                f"{_pct(best_robust['stress_floor'])}，涉及 "
                f"{best_robust['unique_tickers']} 个标的。",
                "- 压力测试仍是候选筛选，不是独立样本外证明；报告中的最高年化不得直接作为预期收益。",
            ]
        )
        long_row = best_mode_rows.get("long_only")
        short_row = best_mode_rows.get("short_only")
        if long_row and short_row:
            lines.insert(
                -1,
                "- 同一头部信号拆分后，只做多年化 "
                f"{_pct(long_row['full_annualized_return'])}，只做空年化 "
                f"{_pct(short_row['full_annualized_return'])}；方向收益明显不对称，"
                "不应机械地把头部作者看空事件用于做空。",
            )
    lines.extend(
        [
            "",
            "## 按时间切分的参数选择与样本外结果",
            "",
            f"只使用 {periods['early'][0]} 至 {periods['early'][1]} 的结果选择参数，"
            f"随后在 {periods['late'][0]} 至 {periods['late'][1]} 固定参数验证。"
            "候选执行口径预先固定为股价至少 10 美元、前 20 日平均成交额至少 5000 万美元，"
            "训练期至少 20 笔交易且最大回撤不超过 40%。参数按训练期 50bps 成本后的年化排序，"
            "排序过程不读取样本外收益。",
            "",
        ]
    )
    lines.extend(_walk_forward_table(walk_forward[:15]))
    lines.extend(
        [
            "",
            "该时间切分消除了代码层面的未来参数引用，但后半段此前已被研究人员查看，"
            "因此它是 chronological holdout，不再是完全未触碰的最终验证集。",
        ]
    )
    lines.extend(
        [
            "",
            "## 使用限制",
            "",
            "- 只有约一年历史，前后半段仍处于相近市场制度，不等于真正跨周期样本外验证。",
            "- 网格搜索会放大偶然最优值，应优先看后半段、交易数、回撤和相邻参数是否一致。",
            "- 结果未计入滑点、借券费、融资成本、税费和成交容量。",
            "- 做空候选即使通过成交额过滤，也未验证实际可借券性；高换手策略需优先看 50/100bps 压力结果。",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_x_rank_event_research(
    *,
    db_path: str | Path,
    report_dir: str | Path,
) -> dict[str, int]:
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout=8000")
    try:
        price_book = _load_price_book(con)
        benchmark = price_book.get("SPY")
        if not benchmark:
            raise RuntimeError("SPY price history is required.")
        events, diagnostics = build_rank_signal_events(
            con,
            price_book,
            windows=RESEARCH_WINDOWS,
            rank_bands=RESEARCH_RANK_BANDS,
        )
        periods = _study_periods(events, benchmark)
        broad, grouped = _broad_grid(
            events,
            price_book,
            benchmark,
            periods,
        )
        full_candidate_keys = _candidate_keys(broad, "full")
        early_candidate_keys = _candidate_keys(broad, "early")
        refined = _refinement_grid(
            full_candidate_keys | early_candidate_keys,
            grouped,
            price_book,
            benchmark,
            periods,
        )
        stress = _stress_grid(
            refined,
            grouped,
            price_book,
            benchmark,
            periods,
        )
        walk_forward = _walk_forward_rows(
            refined,
            early_candidate_keys,
            grouped,
            price_book,
            benchmark,
            periods,
        )
    finally:
        con.close()

    root = Path(report_dir)
    broad_rows = _write_csv(root / "x_sv_rank_event_wide_grid.csv", broad)
    refined_rows = _write_csv(root / "x_sv_rank_event_refinements.csv", refined)
    stress_rows = _write_csv(root / "x_sv_rank_event_stress_tests.csv", stress)
    walk_forward_count = _write_csv(
        root / "x_sv_rank_event_walk_forward.csv",
        walk_forward,
    )
    _write_report(
        root / "x_sv_rank_event_research_report.md",
        broad,
        refined,
        stress,
        walk_forward,
        periods,
        diagnostics,
    )
    return {
        **diagnostics,
        "wide_grid_rows": broad_rows,
        "refinement_rows": refined_rows,
        "stress_rows": stress_rows,
        "walk_forward_rows": walk_forward_count,
        "reports": 1,
    }
