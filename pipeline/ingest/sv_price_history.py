"""Compatibility wrapper for Smart Account price-history backfill."""
from __future__ import annotations

from ..platforms.market_data.price_history import main, run

__all__ = ["main", "run"]


if __name__ == "__main__":
    main()
