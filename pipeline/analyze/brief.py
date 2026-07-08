"""Compatibility wrapper for daily brief workflows."""
from __future__ import annotations

from ..domain.market.brief import run_brief

__all__ = ["run_brief"]


if __name__ == "__main__":
    import sys

    run_brief(mock="--mock" in sys.argv)
