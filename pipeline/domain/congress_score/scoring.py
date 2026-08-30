"""No-lookahead congressional trade settlement and peer scoring."""
from __future__ import annotations

import bisect
import collections
import math
import re
import statistics
from dataclasses import replace
from typing import Iterable

from ...common.congress import CongressDisclosure, CongressMember
from .schema import MemberScore, TradeEvent, TradeOutcome


TICKER_RE = re.compile(r"^[A-Z][A-Z0-9.\-]{0,9}$")
REJECTED_TICKERS = {"US-TBILL", "US-TNOTE", "US-TBOND", "N/A", "NA"}
REJECTED_ASSET_MARKERS = ("option", "bond", "municipal", "cryptocurrency")


def _direction(transaction_type: str) -> str | None:
    value = transaction_type.strip().lower()
    if "purchase" in value or value == "p":
        return "purchase"
    if "sale" in value or value == "s":
        return "sale"
    return None


def is_priceable(disclosure: CongressDisclosure) -> bool:
    ticker = disclosure.ticker or ""
    if not TICKER_RE.fullmatch(ticker) or ticker in REJECTED_TICKERS:
        return False
    asset_type = (disclosure.asset_type or "").lower()
    asset_name = disclosure.asset_name.lower()
    return not any(marker in asset_type or marker in asset_name for marker in REJECTED_ASSET_MARKERS)


def build_trade_events(disclosures: Iterable[CongressDisclosure]) -> list[TradeEvent]:
    """Collapse line items to one member/ticker/date/direction decision."""
    grouped: dict[tuple[str, str, object, str], TradeEvent] = {}
    for disclosure in disclosures:
        direction = _direction(disclosure.transaction_type)
        if direction is None or not is_priceable(disclosure):
            continue
        assert disclosure.ticker is not None
        key = (
            disclosure.member.member_id,
            disclosure.ticker,
            disclosure.transaction_date,
            direction,
        )
        event = grouped.get(key)
        if event is None:
            event = TradeEvent(
                event_id=(
                    f"{disclosure.member.member_id}:{disclosure.transaction_date.isoformat()}:"
                    f"{disclosure.ticker}:{direction}"
                ),
                member=disclosure.member,
                ticker=disclosure.ticker,
                direction=direction,
                transaction_date=disclosure.transaction_date,
                asset_name=disclosure.asset_name,
                asset_type=disclosure.asset_type,
            )
            grouped[key] = event
        event.trade_count += 1
        if disclosure.amount_midpoint is not None:
            event.amount_midpoint += disclosure.amount_midpoint
        if disclosure.filing_date is not None:
            event.filing_dates.append(disclosure.filing_date)
        if disclosure.days_to_file is not None:
            event.disclosure_lags.append(disclosure.days_to_file)
        if disclosure.evidence_url and disclosure.evidence_url not in event.evidence_urls:
            event.evidence_urls.append(disclosure.evidence_url)
        if disclosure.owner and disclosure.owner not in event.owners:
            event.owners.append(disclosure.owner)
    return sorted(grouped.values(), key=lambda event: (event.transaction_date, event.member.name, event.ticker))


def _normalized_prices(
    prices: dict[str, list[tuple[object, float]]],
) -> dict[str, tuple[list[object], list[float]]]:
    normalized: dict[str, tuple[list[object], list[float]]] = {}
    for ticker, rows in prices.items():
        clean = sorted((day, float(close)) for day, close in rows if close is not None and close > 0)
        normalized[ticker] = ([row[0] for row in clean], [row[1] for row in clean])
    return normalized


def settle_trade_events(
    events: Iterable[TradeEvent],
    prices: dict[str, list[tuple[object, float]]],
    *,
    horizons: tuple[int, ...] = (20, 60),
    benchmark: str = "SPY",
) -> list[TradeOutcome]:
    """Enter at the next session close and settle after N further sessions."""
    series = _normalized_prices(prices)
    benchmark_series = series.get(benchmark)
    if benchmark_series is None:
        raise ValueError(f"missing benchmark price series: {benchmark}")
    benchmark_days, benchmark_closes = benchmark_series
    benchmark_by_day = dict(zip(benchmark_days, benchmark_closes))
    outcomes: list[TradeOutcome] = []
    for event in events:
        ticker_series = series.get(event.ticker)
        if ticker_series is None:
            continue
        days, closes = ticker_series
        entry_index = bisect.bisect_right(days, event.transaction_date)
        if entry_index >= len(days):
            continue
        entry_date = days[entry_index]
        entry_price = closes[entry_index]
        benchmark_entry = benchmark_by_day.get(entry_date)
        if benchmark_entry is None:
            continue
        for horizon in horizons:
            exit_index = entry_index + horizon
            if exit_index >= len(days):
                continue
            exit_date = days[exit_index]
            benchmark_exit = benchmark_by_day.get(exit_date)
            if benchmark_exit is None:
                continue
            asset_return = (closes[exit_index] / entry_price - 1.0) * 100.0
            benchmark_return = (benchmark_exit / benchmark_entry - 1.0) * 100.0
            raw_excess = asset_return - benchmark_return
            directional_excess = raw_excess if event.direction == "purchase" else -raw_excess
            outcomes.append(
                TradeOutcome(
                    event_id=event.event_id,
                    member=event.member,
                    ticker=event.ticker,
                    direction=event.direction,
                    transaction_date=event.transaction_date,
                    entry_date=entry_date,
                    exit_date=exit_date,
                    horizon=horizon,
                    asset_return=asset_return,
                    benchmark_return=benchmark_return,
                    directional_excess=directional_excess,
                    trade_count=event.trade_count,
                    amount_midpoint=event.amount_midpoint,
                    evidence_urls=tuple(event.evidence_urls),
                )
            )
    return outcomes


def _winsor(value: float, limit: float = 50.0) -> float:
    return max(-limit, min(limit, value))


def _day_values(outcomes: Iterable[TradeOutcome]) -> list[float]:
    by_day: dict[object, list[float]] = collections.defaultdict(list)
    for outcome in outcomes:
        by_day[outcome.transaction_date].append(_winsor(outcome.directional_excess))
    return [statistics.fmean(values) for _, values in sorted(by_day.items())]


def _summary(values: list[float]) -> tuple[int, float | None, float | None, float | None]:
    if not values:
        return 0, None, None, None
    return (
        len(values),
        sum(value > 0 for value in values) / len(values),
        statistics.fmean(values),
        statistics.median(values),
    )


def _horizon_signal(values: list[float], *, prior_days: int = 5) -> float | None:
    if not values:
        return None
    mean = statistics.fmean(values)
    dispersion = statistics.pstdev(values) if len(values) > 1 else 10.0
    dispersion = max(5.0, dispersion)
    shrunk_mean = mean * len(values) / (len(values) + prior_days)
    posterior_hit = (sum(value > 0 for value in values) + 2.0) / (len(values) + 4.0)
    return shrunk_mean / dispersion + 0.35 * ((posterior_hit - 0.5) / 0.10)


def _percentile_scores(values: list[tuple[str, float]]) -> dict[str, float]:
    ordered = sorted(values, key=lambda pair: (pair[1], pair[0]))
    if len(ordered) == 1:
        return {ordered[0][0]: 50.0}
    result: dict[str, float] = {}
    index = 0
    while index < len(ordered):
        end = index + 1
        while end < len(ordered) and math.isclose(ordered[end][1], ordered[index][1], abs_tol=1e-12):
            end += 1
        average_rank = (index + end - 1) / 2.0
        score = 100.0 * average_rank / (len(ordered) - 1)
        for member_id, _ in ordered[index:end]:
            result[member_id] = score
        index = end
    return result


def build_member_scores(
    *,
    members: Iterable[CongressMember],
    disclosures: Iterable[CongressDisclosure],
    events: Iterable[TradeEvent],
    outcomes: Iterable[TradeOutcome],
    min_purchase_days: int = 5,
) -> list[MemberScore]:
    members = list(members)
    disclosures = list(disclosures)
    events = list(events)
    outcomes = list(outcomes)
    disclosures_by_member: dict[str, list[CongressDisclosure]] = collections.defaultdict(list)
    events_by_member: dict[str, list[TradeEvent]] = collections.defaultdict(list)
    outcomes_by_member: dict[str, list[TradeOutcome]] = collections.defaultdict(list)
    for disclosure in disclosures:
        disclosures_by_member[disclosure.member.member_id].append(disclosure)
    for event in events:
        events_by_member[event.member.member_id].append(event)
    for outcome in outcomes:
        outcomes_by_member[outcome.member.member_id].append(outcome)

    rows: list[MemberScore] = []
    qualified_composites: list[tuple[str, float]] = []
    for member in members:
        member_id = member.member_id
        raw = disclosures_by_member.get(member_id, [])
        member_events = events_by_member.get(member_id, [])
        member_outcomes = outcomes_by_member.get(member_id, [])
        purchase_20 = [o for o in member_outcomes if o.direction == "purchase" and o.horizon == 20]
        purchase_60 = [o for o in member_outcomes if o.direction == "purchase" and o.horizon == 60]
        sale_20 = [o for o in member_outcomes if o.direction == "sale" and o.horizon == 20]
        purchase_values_20 = _day_values(purchase_20)
        purchase_values_60 = _day_values(purchase_60)
        sale_values_20 = _day_values(sale_20)
        days_20, hit_20, avg_20, median_20 = _summary(purchase_values_20)
        days_60, hit_60, avg_60, median_60 = _summary(purchase_values_60)
        sale_days, sale_hit, sale_avg, _ = _summary(sale_values_20)
        signal_20 = _horizon_signal(purchase_values_20)
        signal_60 = _horizon_signal(purchase_values_60)
        if signal_20 is not None and signal_60 is not None and days_60 >= 3:
            composite = 0.65 * signal_20 + 0.35 * signal_60
            horizon_factor = 1.0
        else:
            composite = signal_20
            horizon_factor = 0.85
        status = "ranked" if days_20 >= min_purchase_days and composite is not None else (
            "observation" if days_20 > 0 else "unscored"
        )
        if status == "ranked" and composite is not None:
            qualified_composites.append((member_id, composite))
        lags = [d.days_to_file for d in raw if d.days_to_file is not None]
        late_values = [d.is_late for d in raw if d.is_late is not None]
        ticker_counts = collections.Counter(event.ticker for event in member_events)
        evidence_url = next((event.evidence_urls[0] for event in member_events if event.evidence_urls), None)
        resolved_ids = {outcome.event_id for outcome in member_outcomes}
        confidence = 100.0 * math.sqrt(days_20 / (days_20 + 20.0)) * horizon_factor if days_20 else 0.0
        rows.append(
            MemberScore(
                member=member,
                status=status,
                confidence=confidence,
                raw_disclosures=len(raw),
                eligible_events=len(member_events),
                price_resolved_events=len(resolved_ids),
                purchase_events_20d=len(purchase_20),
                purchase_days_20d=days_20,
                purchase_hit_rate_20d=hit_20,
                purchase_avg_excess_20d=avg_20,
                purchase_median_excess_20d=median_20,
                purchase_events_60d=len(purchase_60),
                purchase_days_60d=days_60,
                purchase_hit_rate_60d=hit_60,
                purchase_avg_excess_60d=avg_60,
                purchase_median_excess_60d=median_60,
                sale_events_20d=len(sale_20),
                sale_days_20d=sale_days,
                sale_avoidance_hit_rate_20d=sale_hit,
                sale_avoidance_avg_excess_20d=sale_avg,
                median_disclosure_lag_days=statistics.median(lags) if lags else None,
                late_filing_rate=(sum(bool(value) for value in late_values) / len(late_values)) if late_values else None,
                top_tickers=[ticker for ticker, _ in ticker_counts.most_common(5)],
                evidence_url=evidence_url,
                composite=composite,
            )
        )

    percentile_by_member = _percentile_scores(qualified_composites)
    for row in rows:
        if row.status == "ranked":
            row.score = percentile_by_member[row.member.member_id]
    ranked = sorted(
        (row for row in rows if row.status == "ranked"),
        key=lambda row: (-(row.score or 0.0), -row.confidence, row.member.name),
    )
    for rank, row in enumerate(ranked, start=1):
        row.rank = rank
    return sorted(
        rows,
        key=lambda row: (
            0 if row.status == "ranked" else 1 if row.status == "observation" else 2,
            row.rank or 10**9,
            -row.purchase_days_20d,
            row.member.name,
        ),
    )
