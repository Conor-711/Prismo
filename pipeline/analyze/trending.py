"""Compatibility wrapper for market trending workflows."""
from __future__ import annotations

from ..domain.market.trending import run_trending

__all__ = ["run_trending"]


if __name__ == "__main__":
    run_trending()
