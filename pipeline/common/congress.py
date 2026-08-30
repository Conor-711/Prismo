"""Platform-neutral contracts for U.S. congressional disclosures."""
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass


@dataclass(frozen=True)
class CongressMember:
    member_id: str
    name: str
    chamber: str
    party: str | None
    state: str | None
    office: str | None
    photo_url: str | None


@dataclass(frozen=True)
class CongressDisclosure:
    trade_id: str
    member: CongressMember
    source_id: str
    transaction_date: dt.date
    filing_date: dt.date | None
    notification_date: dt.date | None
    owner: str | None
    ticker: str | None
    asset_name: str
    asset_type: str | None
    transaction_type: str
    amount_low: int | None
    amount_high: int | None
    days_to_file: int | None
    is_late: bool | None
    filing_type: str | None
    evidence_url: str | None

    @property
    def amount_midpoint(self) -> float | None:
        if self.amount_low is None or self.amount_high is None:
            return None
        return (self.amount_low + self.amount_high) / 2.0
