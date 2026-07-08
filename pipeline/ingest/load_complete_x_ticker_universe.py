"""Compatibility wrapper for loading the complete local X/Twitter universe."""
from __future__ import annotations

from ..platforms.x.complete_universe import main

__all__ = ["main"]


if __name__ == "__main__":
    main()
