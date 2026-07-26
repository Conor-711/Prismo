"""Point-in-time-safe time decay for Smart Voice evidence."""
from __future__ import annotations

import datetime as dt
import math
from dataclasses import dataclass, field
from typing import Mapping


TIME_DECAY_VERSION = "sv-time-decay-v1"


@dataclass(frozen=True)
class SVTimeDecayConfig:
    """Decay settled evidence according to the call's investment horizon."""

    half_life_days_by_horizon: Mapping[str, float] = field(
        default_factory=lambda: {
            "1D": 45.0,
            "5D": 60.0,
            "20D": 120.0,
            "60D": 240.0,
            "90D": 360.0,
            "180D": 540.0,
        }
    )
    default_half_life_days: float = 180.0

    def half_life_days(self, horizon: object) -> float:
        value = self.half_life_days_by_horizon.get(str(horizon or "").upper())
        return max(1.0, float(value or self.default_half_life_days))


DEFAULT_TIME_DECAY_CONFIG = SVTimeDecayConfig()


def parse_day(value: object) -> dt.date | None:
    if isinstance(value, dt.datetime):
        return value.date()
    if isinstance(value, dt.date):
        return value
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return dt.date.fromisoformat(text[:10])
    except ValueError:
        return None


def evidence_age_days(exit_day: object, as_of_day: object) -> int | None:
    exit_date = parse_day(exit_day)
    as_of_date = parse_day(as_of_day)
    if exit_date is None or as_of_date is None:
        return None
    return max(0, (as_of_date - exit_date).days)


def evidence_is_available(exit_day: object, as_of_day: object) -> bool:
    """Treat ``as_of_day`` as the start of day, before that day's close."""

    exit_date = parse_day(exit_day)
    as_of_date = parse_day(as_of_day)
    return bool(exit_date and as_of_date and exit_date < as_of_date)


def evidence_decay_weight(
    exit_day: object,
    horizon: object,
    as_of_day: object,
    config: SVTimeDecayConfig = DEFAULT_TIME_DECAY_CONFIG,
) -> float:
    age_days = evidence_age_days(exit_day, as_of_day)
    if age_days is None:
        return 1.0
    return math.pow(0.5, age_days / config.half_life_days(horizon))
