"""Leakage-free backtest for the Smart Consensus and Smart Alpha product signals."""
from __future__ import annotations

import bisect
import csv
import math
import random
import sqlite3
import statistics
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable, Sequence


CONSENSUS_LIFECYCLES = {
    "open_call",
    "reinforce_call",
    "close_prior_call",
    "invalidate_prior_call",
    "reverse_call",
}
ALPHA_LIFECYCLES = {"open_call", "reinforce_call", "reverse_call"}
UNKNOWN_HORIZONS = {"", "unknown", "unspecified", "n/a", "na", "none"}


@dataclass(frozen=True)
class PointInTimeCall:
    candidate_id: str
    ticker: str
    source: str
    investor_id: str
    created_at: str
    day: str
    direction: str
    lifecycle: str
    call_weight: float
    target_price: float | None
    invalidation: str
    horizon: str
    evidence_url: str
    platform_sv: float
    platform_rank: int
    platform_population: int
    platform_percentile: float

    @property
    def author_key(self) -> str:
        return f"{self.source}:{self.investor_id}".lower()


@dataclass(frozen=True)
class ProductSignalEvent:
    event_id: str
    signal_type: str
    ticker: str
    signal_day: str
    occurred_at: str
    direction: str
    source_count: int
    bullish_count: int
    bearish_count: int
    agreement: float
    priority: float
    author_keys: str
    candidate_ids: str
    best_platform_rank: int
    best_platform_population: int
    overlaps_consensus: int


@dataclass(frozen=True)
class AdjustedPriceBar:
    day: str
    open: float
    high: float
    low: float
    close: float


@dataclass(frozen=True)
class PriceSeries:
    bars: tuple[AdjustedPriceBar, ...]
    days: tuple[str, ...]
    index_by_day: dict[str, int]


@dataclass(frozen=True)
class SignalOutcome:
    event_id: str
    signal_type: str
    ticker: str
    signal_day: str
    direction: str
    source_count: int
    agreement: float
    priority: float
    overlaps_consensus: int
    horizon_sessions: int
    entry_day: str
    exit_day: str
    entry_price: float
    exit_price: float
    raw_return: float
    benchmark_return: float | None
    directional_return: float
    directional_excess: float | None
    directional_return_net_10bps: float
    raw_match: int
    excess_match: int | None
    net_match_10bps: int
    max_favorable_excursion: float
    max_adverse_excursion: float


def _parse_day(value: str) -> date:
    return date.fromisoformat(value[:10])


def _iter_days(start_day: str, end_day: str) -> Iterable[str]:
    current = _parse_day(start_day)
    end = _parse_day(end_day)
    while current <= end:
        yield current.isoformat()
        current += timedelta(days=1)


def _rank_cutoff(population: int, share: float) -> int:
    return max(1, math.ceil(max(population, 1) * share))


def _is_top(call: PointInTimeCall, share: float) -> bool:
    return call.platform_rank <= _rank_cutoff(call.platform_population, share)


def load_point_in_time_calls(
    connection: sqlite3.Connection,
    *,
    start_day: str,
    end_day: str,
    sources: Sequence[str] = ("x", "youtube", "reddit", "xueqiu"),
) -> list[PointInTimeCall]:
    """Load calls joined only to the ranking snapshot known on publication day."""
    connection.row_factory = sqlite3.Row
    slots = ",".join("?" for _ in sources)
    rows = connection.execute(
        f"""
        SELECT c.candidate_id,
               upper(c.ticker) AS ticker,
               c.source,
               c.investor_id,
               c.created_at,
               substr(c.created_at, 1, 10) AS day,
               c.direction,
               c.lifecycle_action,
               COALESCE(c.call_weight, 0) AS call_weight,
               c.target_price,
               COALESCE(c.invalidation_condition, '') AS invalidation,
               COALESCE(NULLIF(c.horizon_bucket, ''), 'unknown') AS horizon,
               COALESCE(candidate.url, '') AS evidence_url,
               a.platform_sv,
               a.platform_rank_no,
               a.platform_population,
               a.platform_percentile
          FROM sv_call c
          JOIN sv_investor_score_asof a
            ON a.asof_day = substr(c.created_at, 1, 10)
           AND a.investor_id = c.investor_id
           AND a.source = c.source
          LEFT JOIN sv_call_candidate candidate
            ON candidate.candidate_id = c.candidate_id
         WHERE c.is_actionable_call = 1
           AND c.direction IN ('bull', 'bear')
           AND c.lifecycle_action IN ({','.join('?' for _ in CONSENSUS_LIFECYCLES)})
           AND c.source IN ({slots})
           AND a.platform_qualified = 1
           AND a.platform_rank_no IS NOT NULL
           AND a.platform_population >= 10
           AND substr(c.created_at, 1, 10) BETWEEN ? AND ?
         ORDER BY c.created_at, c.candidate_id
        """,
        [*sorted(CONSENSUS_LIFECYCLES), *sources, start_day, end_day],
    ).fetchall()
    return [
        PointInTimeCall(
            candidate_id=str(row["candidate_id"]),
            ticker=str(row["ticker"]),
            source=str(row["source"]),
            investor_id=str(row["investor_id"]),
            created_at=str(row["created_at"]),
            day=str(row["day"]),
            direction=str(row["direction"]),
            lifecycle=str(row["lifecycle_action"]),
            call_weight=float(row["call_weight"] or 0),
            target_price=(None if row["target_price"] is None else float(row["target_price"])),
            invalidation=str(row["invalidation"] or ""),
            horizon=str(row["horizon"] or "unknown"),
            evidence_url=str(row["evidence_url"] or ""),
            platform_sv=float(row["platform_sv"] or 0),
            platform_rank=int(row["platform_rank_no"]),
            platform_population=int(row["platform_population"]),
            platform_percentile=float(row["platform_percentile"] or 0) / 100.0,
        )
        for row in rows
    ]


def _window_calls(
    calls: Sequence[PointInTimeCall],
    *,
    as_of_day: str,
    lookback_days: int,
) -> list[PointInTimeCall]:
    as_of = _parse_day(as_of_day)
    cutoff = as_of - timedelta(days=lookback_days)
    return [call for call in calls if cutoff <= _parse_day(call.day) <= as_of]


def _latest_by_author(calls: Iterable[PointInTimeCall]) -> list[PointInTimeCall]:
    latest: dict[str, PointInTimeCall] = {}
    for call in calls:
        previous = latest.get(call.author_key)
        marker = (call.created_at, call.candidate_id)
        if previous is None or marker > (previous.created_at, previous.candidate_id):
            latest[call.author_key] = call
    return list(latest.values())


def _consensus_packages(
    calls: Sequence[PointInTimeCall],
    *,
    as_of_day: str,
    lookback_days: int,
    maximum_packages: int,
    maximum_accounts: int,
) -> list[tuple[str, list[PointInTimeCall]]]:
    eligible = [
        call
        for call in _window_calls(calls, as_of_day=as_of_day, lookback_days=lookback_days)
        if call.lifecycle in CONSENSUS_LIFECYCLES and _is_top(call, 0.25)
    ]
    grouped: dict[str, list[PointInTimeCall]] = defaultdict(list)
    for call in eligible:
        grouped[call.ticker].append(call)

    packages: list[tuple[str, list[PointInTimeCall]]] = []
    for ticker, ticker_calls in grouped.items():
        distinct = _latest_by_author(ticker_calls)
        distinct.sort(
            key=lambda call: (
                call.created_at,
                call.platform_sv,
                call.call_weight,
                call.candidate_id,
            ),
            reverse=True,
        )
        selected = distinct[:maximum_accounts]
        if len(selected) >= 2:
            packages.append((ticker, selected))
    packages.sort(
        key=lambda item: (
            max(call.created_at for call in item[1]),
            len(item[1]),
            item[0],
        ),
        reverse=True,
    )
    return packages[:maximum_packages]


def _direction(calls: Sequence[PointInTimeCall]) -> tuple[str, int, int, float]:
    bulls = sum(call.direction == "bull" for call in calls)
    bears = sum(call.direction == "bear" for call in calls)
    if bulls == bears:
        direction = "mixed"
    else:
        direction = "bull" if bulls > bears else "bear"
    agreement = max(bulls, bears) / max(1, len(calls))
    return direction, bulls, bears, agreement


def _event(
    *,
    signal_type: str,
    ticker: str,
    day: str,
    calls: Sequence[PointInTimeCall],
    priority: float,
    overlaps_consensus: bool,
) -> ProductSignalEvent:
    ordered = sorted(calls, key=lambda call: (call.created_at, call.candidate_id), reverse=True)
    direction, bulls, bears, agreement = _direction(ordered)
    signature = "+".join(sorted(call.candidate_id for call in ordered))
    return ProductSignalEvent(
        event_id=f"{signal_type}:{ticker}:{day}:{signature}",
        signal_type=signal_type,
        ticker=ticker,
        signal_day=day,
        occurred_at=max(call.created_at for call in ordered),
        direction=direction,
        source_count=len(ordered),
        bullish_count=bulls,
        bearish_count=bears,
        agreement=agreement,
        priority=priority,
        author_keys="|".join(sorted(call.author_key for call in ordered)),
        candidate_ids="|".join(sorted(call.candidate_id for call in ordered)),
        best_platform_rank=min(call.platform_rank for call in ordered),
        best_platform_population=max(call.platform_population for call in ordered),
        overlaps_consensus=int(overlaps_consensus),
    )


def build_consensus_events(
    calls: Sequence[PointInTimeCall],
    *,
    start_day: str,
    end_day: str,
    lookback_days: int = 30,
    maximum_packages: int = 10,
    maximum_accounts: int = 5,
) -> list[ProductSignalEvent]:
    """Emit a signal only when a fresh call changes a visible consensus package."""
    by_day: dict[str, list[PointInTimeCall]] = defaultdict(list)
    for call in calls:
        by_day[call.day].append(call)
    previous_signatures: dict[str, str] = {}
    events: list[ProductSignalEvent] = []
    for day in _iter_days(start_day, end_day):
        packages = _consensus_packages(
            calls,
            as_of_day=day,
            lookback_days=lookback_days,
            maximum_packages=maximum_packages,
            maximum_accounts=maximum_accounts,
        )
        visible: dict[str, str] = {}
        fresh_tickers = {call.ticker for call in by_day.get(day, [])}
        for ticker, selected in packages:
            signature = "|".join(sorted(call.candidate_id for call in selected))
            visible[ticker] = signature
            if ticker not in fresh_tickers or previous_signatures.get(ticker) == signature:
                continue
            events.append(
                _event(
                    signal_type="smart_consensus",
                    ticker=ticker,
                    day=day,
                    calls=selected,
                    priority=max(call.platform_sv for call in selected),
                    overlaps_consensus=False,
                )
            )
        previous_signatures = visible
    return events


def _alpha_priority(call: PointInTimeCall, *, as_of_day: str, lookback_days: int) -> float:
    quality = 1 - min(max(call.platform_percentile, 0), 1)
    lifecycle = {
        "reverse_call": 1.0,
        "open_call": 0.92,
        "reinforce_call": 0.82,
    }.get(call.lifecycle, 0.4)
    specificity = sum(
        (
            call.target_price is not None,
            bool(call.invalidation.strip()),
            call.horizon.strip().lower() not in UNKNOWN_HORIZONS,
        )
    ) / 3.0
    age = max((_parse_day(as_of_day) - _parse_day(call.day)).days, 0)
    recency = max(0.0, 1 - age / max(lookback_days, 1))
    return quality * 0.45 + lifecycle * 0.25 + specificity * 0.15 + recency * 0.15


def _alpha_candidates(
    calls: Sequence[PointInTimeCall],
    *,
    as_of_day: str,
    lookback_days: int,
    maximum_source_count: int,
    excluded_tickers: set[str],
) -> list[tuple[str, list[PointInTimeCall], float]]:
    eligible = [
        call
        for call in _window_calls(calls, as_of_day=as_of_day, lookback_days=lookback_days)
        if call.lifecycle in ALPHA_LIFECYCLES
        and call.evidence_url
        and _is_top(call, 0.10)
        and call.ticker not in excluded_tickers
    ]
    grouped: dict[str, list[PointInTimeCall]] = defaultdict(list)
    for call in eligible:
        grouped[call.ticker].append(call)
    candidates: list[tuple[str, list[PointInTimeCall], float]] = []
    for ticker, ticker_calls in grouped.items():
        distinct = _latest_by_author(ticker_calls)
        if not distinct or len(distinct) > maximum_source_count:
            continue
        distinct.sort(
            key=lambda call: (
                _alpha_priority(call, as_of_day=as_of_day, lookback_days=lookback_days),
                call.created_at,
                call.candidate_id,
            ),
            reverse=True,
        )
        priority = _alpha_priority(distinct[0], as_of_day=as_of_day, lookback_days=lookback_days)
        candidates.append((ticker, distinct, priority))
    candidates.sort(
        key=lambda item: (item[2], max(call.created_at for call in item[1]), item[0]),
        reverse=True,
    )
    return candidates


def build_alpha_events(
    calls: Sequence[PointInTimeCall],
    *,
    start_day: str,
    end_day: str,
    consensus_events: Sequence[ProductSignalEvent] = (),
    lookback_days: int = 30,
    maximum_source_count: int = 2,
) -> list[ProductSignalEvent]:
    """Build both the exact UI winner and a consensus-excluded Alpha audit variant."""
    by_day: dict[str, list[PointInTimeCall]] = defaultdict(list)
    for call in calls:
        by_day[call.day].append(call)
    consensus_tickers_by_day: dict[str, set[str]] = defaultdict(set)
    for event in consensus_events:
        consensus_tickers_by_day[event.signal_day].add(event.ticker)

    previous: dict[str, str] = {}
    events: list[ProductSignalEvent] = []
    for day in _iter_days(start_day, end_day):
        fresh_tickers = {call.ticker for call in by_day.get(day, [])}
        active_consensus = {
            ticker
            for ticker, _ in _consensus_packages(
                calls,
                as_of_day=day,
                lookback_days=lookback_days,
                maximum_packages=10_000,
                maximum_accounts=5,
            )
        }
        variants = (
            ("smart_alpha_ui", set()),
            ("smart_alpha_pure", active_consensus),
        )
        for signal_type, excluded in variants:
            candidates = _alpha_candidates(
                calls,
                as_of_day=day,
                lookback_days=lookback_days,
                maximum_source_count=maximum_source_count,
                excluded_tickers=excluded,
            )
            if not candidates:
                previous.pop(signal_type, None)
                continue
            ticker, selected, priority = candidates[0]
            signature = f"{ticker}:" + "|".join(sorted(call.candidate_id for call in selected))
            if ticker in fresh_tickers and previous.get(signal_type) != signature:
                events.append(
                    _event(
                        signal_type=signal_type,
                        ticker=ticker,
                        day=day,
                        calls=selected,
                        priority=priority,
                        overlaps_consensus=ticker in active_consensus,
                    )
                )
            previous[signal_type] = signature
    return events


def load_price_book(
    connection: sqlite3.Connection,
    tickers: Iterable[str],
) -> dict[str, PriceSeries]:
    connection.row_factory = sqlite3.Row
    normalized = sorted({ticker.upper() for ticker in tickers} | {"SPY"})
    slots = ",".join("?" for _ in normalized)
    rows = connection.execute(
        f"""SELECT upper(ticker) AS ticker, day, open, high, low, close, adj_close
              FROM price_daily
             WHERE upper(ticker) IN ({slots})
               AND open > 0 AND close > 0
             ORDER BY ticker, day""",
        normalized,
    ).fetchall()
    grouped: dict[str, list[AdjustedPriceBar]] = defaultdict(list)
    for row in rows:
        close = float(row["close"])
        factor = float(row["adj_close"] or close) / close if close else 1.0
        grouped[str(row["ticker"])].append(
            AdjustedPriceBar(
                day=str(row["day"]),
                open=float(row["open"]) * factor,
                high=float(row["high"] or row["close"]) * factor,
                low=float(row["low"] or row["close"]) * factor,
                close=close * factor,
            )
        )
    return {
        ticker: PriceSeries(
            bars=tuple(bars),
            days=tuple(bar.day for bar in bars),
            index_by_day={bar.day: index for index, bar in enumerate(bars)},
        )
        for ticker, bars in grouped.items()
    }


def _benchmark_return(
    benchmark: PriceSeries | None,
    entry_day: str,
    exit_day: str,
) -> float | None:
    if benchmark is None:
        return None
    entry_index = benchmark.index_by_day.get(entry_day)
    exit_index = benchmark.index_by_day.get(exit_day)
    if entry_index is None or exit_index is None:
        return None
    entry = benchmark.bars[entry_index].open
    exit_price = benchmark.bars[exit_index].close
    return exit_price / entry - 1 if entry > 0 else None


def calculate_outcomes(
    events: Sequence[ProductSignalEvent],
    price_book: dict[str, PriceSeries],
    *,
    horizons: Sequence[int] = (1, 5, 20, 60),
) -> list[SignalOutcome]:
    outcomes: list[SignalOutcome] = []
    benchmark = price_book.get("SPY")
    for event in events:
        if event.direction not in {"bull", "bear"}:
            continue
        series = price_book.get(event.ticker)
        if series is None:
            continue
        entry_index = bisect.bisect_right(series.days, event.signal_day)
        if entry_index >= len(series.bars):
            continue
        entry = series.bars[entry_index]
        sign = 1.0 if event.direction == "bull" else -1.0
        for horizon in horizons:
            exit_index = entry_index + int(horizon) - 1
            if exit_index >= len(series.bars):
                continue
            exit_bar = series.bars[exit_index]
            raw_return = exit_bar.close / entry.open - 1
            directional_return = sign * raw_return
            benchmark_return = _benchmark_return(benchmark, entry.day, exit_bar.day)
            directional_excess = (
                None if benchmark_return is None else sign * (raw_return - benchmark_return)
            )
            path = series.bars[entry_index : exit_index + 1]
            if event.direction == "bull":
                favorable = max(bar.high / entry.open - 1 for bar in path)
                adverse = min(bar.low / entry.open - 1 for bar in path)
            else:
                favorable = max(1 - bar.low / entry.open for bar in path)
                adverse = min(1 - bar.high / entry.open for bar in path)
            outcomes.append(
                SignalOutcome(
                    event_id=event.event_id,
                    signal_type=event.signal_type,
                    ticker=event.ticker,
                    signal_day=event.signal_day,
                    direction=event.direction,
                    source_count=event.source_count,
                    agreement=event.agreement,
                    priority=event.priority,
                    overlaps_consensus=event.overlaps_consensus,
                    horizon_sessions=int(horizon),
                    entry_day=entry.day,
                    exit_day=exit_bar.day,
                    entry_price=entry.open,
                    exit_price=exit_bar.close,
                    raw_return=raw_return,
                    benchmark_return=benchmark_return,
                    directional_return=directional_return,
                    directional_excess=directional_excess,
                    directional_return_net_10bps=directional_return - 0.001,
                    raw_match=int(directional_return > 0),
                    excess_match=(None if directional_excess is None else int(directional_excess > 0)),
                    net_match_10bps=int(directional_return - 0.001 > 0),
                    max_favorable_excursion=favorable,
                    max_adverse_excursion=adverse,
                )
            )
    return outcomes


def select_non_overlapping(outcomes: Sequence[SignalOutcome]) -> list[SignalOutcome]:
    selected: list[SignalOutcome] = []
    last_exit: dict[tuple[str, str, int], str] = {}
    for outcome in sorted(
        outcomes,
        key=lambda item: (item.entry_day, item.signal_type, item.ticker, item.event_id),
    ):
        key = (outcome.signal_type, outcome.ticker, outcome.horizon_sessions)
        if last_exit.get(key, "") >= outcome.entry_day:
            continue
        selected.append(outcome)
        last_exit[key] = outcome.exit_day
    return selected


def _wilson_interval(hits: int, count: int, z: float = 1.96) -> tuple[float | None, float | None]:
    if count <= 0:
        return None, None
    p = hits / count
    denominator = 1 + z * z / count
    center = (p + z * z / (2 * count)) / denominator
    margin = z * math.sqrt((p * (1 - p) + z * z / (4 * count)) / count) / denominator
    return center - margin, center + margin


def _cluster_bootstrap_mean(
    rows: Sequence[SignalOutcome],
    field: str,
    *,
    iterations: int = 2000,
    seed: int = 7,
) -> tuple[float | None, float | None]:
    clusters: dict[str, list[SignalOutcome]] = defaultdict(list)
    for row in rows:
        if getattr(row, field) is not None:
            clusters[row.ticker].append(row)
    keys = sorted(clusters)
    if not keys:
        return None, None
    rng = random.Random(seed)
    samples: list[float] = []
    for _ in range(iterations):
        selected = [rng.choice(keys) for _ in keys]
        values = [float(getattr(row, field)) for key in selected for row in clusters[key]]
        if values:
            samples.append(statistics.fmean(values))
    if not samples:
        return None, None
    samples.sort()
    return samples[int(0.025 * (len(samples) - 1))], samples[int(0.975 * (len(samples) - 1))]


def summarize_outcomes(outcomes: Sequence[SignalOutcome]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    canonical = select_non_overlapping(outcomes)
    for sample_name, sample in (("all_events", outcomes), ("non_overlapping", canonical)):
        grouped: dict[tuple[str, int], list[SignalOutcome]] = defaultdict(list)
        for outcome in sample:
            grouped[(outcome.signal_type, outcome.horizon_sessions)].append(outcome)
        for (signal_type, horizon), values in sorted(grouped.items()):
            raw_values = [item.directional_return for item in values]
            excess_values = [item.directional_excess for item in values if item.directional_excess is not None]
            hit_low, hit_high = _wilson_interval(sum(item.raw_match for item in values), len(values))
            excess_ci_low, excess_ci_high = _cluster_bootstrap_mean(values, "directional_excess")
            rows.append(
                {
                    "sample": sample_name,
                    "signal_type": signal_type,
                    "horizon_sessions": horizon,
                    "n": len(values),
                    "benchmark_n": len(excess_values),
                    "tickers": len({item.ticker for item in values}),
                    "bullish": sum(item.direction == "bull" for item in values),
                    "bearish": sum(item.direction == "bear" for item in values),
                    "raw_match_rate": statistics.fmean(item.raw_match for item in values),
                    "raw_match_ci_low": hit_low,
                    "raw_match_ci_high": hit_high,
                    "excess_match_rate": (
                        statistics.fmean(item.excess_match for item in values if item.excess_match is not None)
                        if excess_values
                        else None
                    ),
                    "net_match_rate_10bps": statistics.fmean(item.net_match_10bps for item in values),
                    "mean_directional_return": statistics.fmean(raw_values),
                    "median_directional_return": statistics.median(raw_values),
                    "mean_directional_excess": statistics.fmean(excess_values) if excess_values else None,
                    "median_directional_excess": statistics.median(excess_values) if excess_values else None,
                    "mean_excess_ci_low": excess_ci_low,
                    "mean_excess_ci_high": excess_ci_high,
                    "mean_mfe": statistics.fmean(item.max_favorable_excursion for item in values),
                    "mean_mae": statistics.fmean(item.max_adverse_excursion for item in values),
                    "overlap_consensus_rate": statistics.fmean(item.overlaps_consensus for item in values),
                }
            )
    return rows


def _subgroup_metrics(
    values: Sequence[SignalOutcome],
    *,
    sample_name: str,
    signal_type: str,
    horizon: int,
    dimension: str,
    bucket: str,
) -> dict[str, object]:
    excess_values = [item.directional_excess for item in values if item.directional_excess is not None]
    hit_low, hit_high = _wilson_interval(sum(item.raw_match for item in values), len(values))
    excess_ci_low, excess_ci_high = _cluster_bootstrap_mean(values, "directional_excess")
    return {
        "sample": sample_name,
        "signal_type": signal_type,
        "horizon_sessions": horizon,
        "dimension": dimension,
        "bucket": bucket,
        "n": len(values),
        "benchmark_n": len(excess_values),
        "tickers": len({item.ticker for item in values}),
        "raw_match_rate": statistics.fmean(item.raw_match for item in values),
        "raw_match_ci_low": hit_low,
        "raw_match_ci_high": hit_high,
        "net_match_rate_10bps": statistics.fmean(item.net_match_10bps for item in values),
        "mean_directional_return": statistics.fmean(item.directional_return for item in values),
        "median_directional_return": statistics.median(item.directional_return for item in values),
        "mean_directional_excess": statistics.fmean(excess_values) if excess_values else None,
        "median_directional_excess": statistics.median(excess_values) if excess_values else None,
        "mean_excess_ci_low": excess_ci_low,
        "mean_excess_ci_high": excess_ci_high,
    }


def summarize_subgroups(
    outcomes: Sequence[SignalOutcome],
    *,
    start_day: str | None = None,
    end_day: str | None = None,
) -> list[dict[str, object]]:
    """Expose stability checks that can invalidate an attractive aggregate result."""
    if not outcomes:
        return []
    first_day = _parse_day(start_day) if start_day else min(_parse_day(item.signal_day) for item in outcomes)
    last_day = _parse_day(end_day) if end_day else max(_parse_day(item.signal_day) for item in outcomes)
    midpoint = first_day + (last_day - first_day) / 2
    midpoint_day = midpoint.isoformat()
    rows: list[dict[str, object]] = []
    canonical = select_non_overlapping(outcomes)
    for sample_name, sample in (("all_events", outcomes), ("non_overlapping", canonical)):
        base: dict[tuple[str, int], list[SignalOutcome]] = defaultdict(list)
        for outcome in sample:
            base[(outcome.signal_type, outcome.horizon_sessions)].append(outcome)
        for (signal_type, horizon), values in sorted(base.items()):
            dimensions = {
                "direction": lambda item: item.direction,
                "source_count": lambda item: str(item.source_count) if item.source_count < 5 else "5+",
                "agreement": lambda item: "unanimous" if math.isclose(item.agreement, 1.0) else "split",
                "period": lambda item: (
                    f"first_half_through_{midpoint_day}"
                    if item.signal_day <= midpoint_day
                    else f"second_half_after_{midpoint_day}"
                ),
                "consensus_overlap": lambda item: "overlap" if item.overlaps_consensus else "standalone",
            }
            for dimension, classifier in dimensions.items():
                grouped: dict[str, list[SignalOutcome]] = defaultdict(list)
                for value in values:
                    grouped[classifier(value)].append(value)
                for bucket, bucket_values in sorted(grouped.items()):
                    rows.append(
                        _subgroup_metrics(
                            bucket_values,
                            sample_name=sample_name,
                            signal_type=signal_type,
                            horizon=horizon,
                            dimension=dimension,
                            bucket=bucket,
                        )
                    )
    return rows


def write_dataclass_csv(path: Path, values: Sequence[object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not values:
        path.write_text("", encoding="utf-8")
        return
    rows = [asdict(value) for value in values]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_dict_csv(path: Path, values: Sequence[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not values:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(values[0]))
        writer.writeheader()
        writer.writerows(values)


def database_coverage(connection: sqlite3.Connection) -> dict[str, object]:
    connection.row_factory = sqlite3.Row
    calls = connection.execute(
        "SELECT COUNT(*) n, MIN(created_at) first_day, MAX(created_at) last_day FROM sv_call"
    ).fetchone()
    scores = connection.execute(
        """SELECT COUNT(*) n, COUNT(DISTINCT asof_day) days,
                  MIN(asof_day) first_day, MAX(asof_day) last_day
             FROM sv_investor_score_asof"""
    ).fetchone()
    prices = connection.execute(
        """SELECT COUNT(*) n, COUNT(DISTINCT ticker) tickers,
                  MIN(day) first_day, MAX(day) last_day
             FROM price_daily"""
    ).fetchone()
    benchmark_prices = connection.execute(
        "SELECT COUNT(*) n, MIN(day) first_day, MAX(day) last_day FROM price_daily WHERE upper(ticker)='SPY'"
    ).fetchone()
    wallet_scores = connection.execute(
        """SELECT COUNT(*) n, COUNT(DISTINCT as_of_day) days,
                  MIN(as_of_day) first_day, MAX(as_of_day) last_day
             FROM hl_wallet_score"""
    ).fetchone()
    wallet_fills = connection.execute(
        """SELECT COUNT(*) n, COUNT(DISTINCT address) addresses,
                  MIN(created_day) first_day, MAX(created_day) last_day
             FROM hl_fill"""
    ).fetchone()
    return {
        "calls": dict(calls),
        "scores": dict(scores),
        "prices": dict(prices),
        "benchmark_prices": dict(benchmark_prices),
        "wallet_scores": dict(wallet_scores),
        "wallet_fills": dict(wallet_fills),
    }
