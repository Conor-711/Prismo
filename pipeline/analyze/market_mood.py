"""Compatibility wrapper for market mood workflows."""
from __future__ import annotations

from ..domain.market.mood import mood_label, run_market_mood

__all__ = ["mood_label", "run_market_mood"]


if __name__ == "__main__":
    run_market_mood()
