"""Compatibility wrapper for short-window market price loading."""
from __future__ import annotations

from ..platforms.market_data.short_window_prices import fetch, main

__all__ = ["fetch", "main"]


if __name__ == "__main__":
    main()
