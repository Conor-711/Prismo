"""Versioned absolute score for a reproducible follower strategy.

Inputs are net, exposure-matched, point-in-time backtest summaries. This module
does not infer trades from posts or filings and never turns a percentile into a
score. Source-specific adapters must enforce the public-availability rules.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date
from typing import Literal

VERSION = "follow-ability-v1"
ActorKind = Literal["platform", "politician", "celebrity", "insider", "institution"]
Status = Literal[
    "scored", "insufficient_history", "unverified_source", "unaudited_backtest",
    "incomplete_prices", "no_observable_trade",
]
ACTOR_KINDS = {"platform", "politician", "celebrity", "insider", "institution"}


@dataclass(frozen=True)
class FollowPerformance:
    actor_id: str
    actor_kind: ActorKind
    as_of: str
    observed_calendar_days: int
    independent_decision_days: int
    settled_decisions: int
    executable_decisions: int
    priced_decisions: int
    annualized_net_return: float
    annualized_matched_benchmark_return: float
    annualized_volatility: float
    max_drawdown: float
    source_verified: bool
    point_in_time_verified: bool
    execution_costs_included: bool
    benchmark_aligned: bool


@dataclass(frozen=True)
class FollowScore:
    actor_id: str
    actor_kind: ActorKind
    as_of: str
    version: str
    status: Status
    value: float | None
    evidence_weight: float
    annualized_net_return: float
    annualized_excess_return: float
    annualized_volatility: float
    max_drawdown: float
    priced_coverage: float
    independent_decision_days: int


def _validate(row: FollowPerformance) -> None:
    if not row.actor_id or row.actor_kind not in ACTOR_KINDS:
        raise ValueError("Actor identity, kind and as-of date are required")
    try:
        date.fromisoformat(row.as_of)
    except (TypeError, ValueError) as exc:
        raise ValueError("As-of date must be ISO 8601") from exc
    counts = (
        row.observed_calendar_days, row.independent_decision_days,
        row.settled_decisions, row.executable_decisions, row.priced_decisions,
    )
    if any(type(value) is not int for value in counts):
        raise ValueError("Counts must be integers")
    if any(value < 0 for value in counts):
        raise ValueError("Counts cannot be negative")
    if row.independent_decision_days > row.observed_calendar_days:
        raise ValueError("Independent decision days cannot exceed observation days")
    if row.settled_decisions > row.priced_decisions or row.priced_decisions > row.executable_decisions:
        raise ValueError("Settled/priced decisions cannot exceed executable decisions")
    if any(type(value) is not bool for value in (
        row.source_verified, row.point_in_time_verified,
        row.execution_costs_included, row.benchmark_aligned,
    )):
        raise ValueError("Audit attestations must be booleans")
    metrics = (
        row.annualized_net_return, row.annualized_matched_benchmark_return,
        row.annualized_volatility, row.max_drawdown,
    )
    if not all(math.isfinite(value) for value in metrics):
        raise ValueError("Performance metrics must be finite")
    if row.annualized_net_return < -1 or row.annualized_matched_benchmark_return < -1:
        raise ValueError("Annualized total returns cannot be below -100%")
    if row.annualized_volatility < 0 or not -1 <= row.max_drawdown <= 0:
        raise ValueError("Volatility must be nonnegative and drawdown in [-1, 0]")


def score_follow_performance(row: FollowPerformance) -> FollowScore:
    """Score a fixed follower-policy backtest without reference to other actors.

    The result is evidence- and risk-adjusted annualized follower-return
    percentage points, with no artificial score range or cap. Benchmark
    underperformance is a penalty, not a bonus for losing less than a falling
    market. It is not a calibrated forecast of future returns.
    """
    _validate(row)
    coverage = row.priced_decisions / row.executable_decisions if row.executable_decisions else 0.0
    excess = row.annualized_net_return - row.annualized_matched_benchmark_return
    evidence = (
        row.independent_decision_days / (row.independent_decision_days + 20)
        * min(1.0, row.observed_calendar_days / 730)
        * coverage
    )
    if row.settled_decisions == 0 or row.priced_decisions == 0:
        status: Status = "no_observable_trade"
    elif not row.source_verified:
        status: Status = "unverified_source"
    elif not (row.point_in_time_verified and row.execution_costs_included and row.benchmark_aligned):
        status = "unaudited_backtest"
    elif row.actor_kind == "platform" and row.executable_decisions and coverage < 0.8:
        status = "incomplete_prices"
    elif row.actor_kind == "platform" and (
        row.observed_calendar_days < 365
        or row.independent_decision_days < 10
        or row.settled_decisions < 10
    ):
        status = "insufficient_history"
    else:
        status = "scored"

    value = research_score_value(row) if status == "scored" else None

    return FollowScore(
        actor_id=row.actor_id, actor_kind=row.actor_kind, as_of=row.as_of,
        version=VERSION, status=status, value=value, evidence_weight=evidence,
        annualized_net_return=row.annualized_net_return,
        annualized_excess_return=excess,
        annualized_volatility=row.annualized_volatility,
        max_drawdown=row.max_drawdown, priced_coverage=coverage,
        independent_decision_days=row.independent_decision_days,
    )


def research_score_value(row: FollowPerformance) -> float:
    """Formula value for a research candidate, even before audit.

    This is never a publishable Score by itself. Consumers must use
    ``score_follow_performance`` and honor its status before publication.
    """
    _validate(row)
    coverage = row.priced_decisions / row.executable_decisions if row.executable_decisions else 0.0
    evidence = (
        row.independent_decision_days / (row.independent_decision_days + 20)
        * min(1.0, row.observed_calendar_days / 730)
        * coverage
    )
    shortfall = max(0.0, row.annualized_matched_benchmark_return - row.annualized_net_return)
    risk = 0.15 * -row.max_drawdown + 0.05 * max(0.0, row.annualized_volatility - 0.25)
    return 100 * (evidence * (row.annualized_net_return - 0.3 * shortfall) - risk)
