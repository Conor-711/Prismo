"""Compatibility wrapper for market rollup workflows."""
from __future__ import annotations

from ..domain.market.rollups import run_rollups

__all__ = ["run_rollups"]


if __name__ == "__main__":
    run_rollups()
