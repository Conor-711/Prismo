"""Stable value objects for Smart Account follow-strategy research."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class FollowCall:
    candidate_id: str
    source: str
    investor_id: str
    ticker: str
    created_at: str
    direction: str
    lifecycle: str
    affected_direction: str
    horizon_sessions: int
    thesis: str = ""
    evidence_url: str = ""

    @property
    def signal_day(self) -> str:
        return self.created_at[:10]


@dataclass(frozen=True)
class ScheduledCall:
    call: FollowCall
    execution_day: str
    expiry_day: str | None


@dataclass(frozen=True)
class FollowTrade:
    source: str
    investor_id: str
    ticker: str
    direction: str
    entry_candidate_id: str
    entry_day: str
    entry_price: float
    exit_candidate_id: str
    exit_day: str
    exit_price: float
    exit_timing: str
    exit_reason: str
    gross_return: float
    net_return: float
    signal_updates: int
    thesis: str
    evidence_url: str


@dataclass(frozen=True)
class FollowStats:
    start_day: str
    end_day: str
    trading_days: int
    active_days: int
    signal_count: int
    trade_count: int
    long_trades: int
    short_trades: int
    exposure_pct: float
    average_active_positions: float
    turnover_sides: float
    total_return: float
    annualized_return: float | None
    benchmark_total_return: float
    benchmark_annualized_return: float | None
    annualized_excess_return: float | None
    annualized_volatility: float | None
    sharpe: float | None
    max_drawdown: float
    trade_hit_rate: float | None
    average_trade_return: float | None
    same_direction_updates: int
    reversals: int
    explicit_exits: int
    price_history_end_exits: int
    skipped_no_price: int
