"""Shared helpers for CLI command adapters."""
from __future__ import annotations

from collections.abc import Iterable


def csv_values(
    value: str | None,
    *,
    upper: bool = False,
    as_set: bool = False,
) -> list[str] | set[str] | None:
    """Parse a comma-separated CLI option into normalized values."""
    if not value:
        return None

    values: Iterable[str] = (part.strip() for part in value.split(","))
    parsed = [item.upper() if upper else item for item in values if item]
    if as_set:
        return set(parsed)
    return parsed

