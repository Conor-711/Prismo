"""Data contracts for congressional investment scoring."""
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field

from ...common.congress import CongressMember


@dataclass
class TradeEvent:
    event_id: str
    member: CongressMember
    ticker: str
    direction: str
    transaction_date: dt.date
    asset_name: str
    asset_type: str | None
    trade_count: int = 0
    amount_midpoint: float = 0.0
    filing_dates: list[dt.date] = field(default_factory=list)
    disclosure_lags: list[int] = field(default_factory=list)
    evidence_urls: list[str] = field(default_factory=list)
    owners: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class TradeOutcome:
    event_id: str
    member: CongressMember
    ticker: str
    direction: str
    transaction_date: dt.date
    entry_date: dt.date
    exit_date: dt.date
    horizon: int
    asset_return: float
    benchmark_return: float
    directional_excess: float
    trade_count: int
    amount_midpoint: float
    evidence_urls: tuple[str, ...]


@dataclass
class MemberScore:
    member: CongressMember
    status: str
    rank: int | None = None
    score: float | None = None
    confidence: float = 0.0
    raw_disclosures: int = 0
    eligible_events: int = 0
    price_resolved_events: int = 0
    purchase_events_20d: int = 0
    purchase_days_20d: int = 0
    purchase_hit_rate_20d: float | None = None
    purchase_avg_excess_20d: float | None = None
    purchase_median_excess_20d: float | None = None
    purchase_events_60d: int = 0
    purchase_days_60d: int = 0
    purchase_hit_rate_60d: float | None = None
    purchase_avg_excess_60d: float | None = None
    purchase_median_excess_60d: float | None = None
    sale_events_20d: int = 0
    sale_days_20d: int = 0
    sale_avoidance_hit_rate_20d: float | None = None
    sale_avoidance_avg_excess_20d: float | None = None
    median_disclosure_lag_days: float | None = None
    late_filing_rate: float | None = None
    top_tickers: list[str] = field(default_factory=list)
    evidence_url: str | None = None
    composite: float | None = None
