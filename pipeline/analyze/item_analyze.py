"""Compatibility wrapper for Reddit item analysis."""
from __future__ import annotations

from ..domain.opinions.item_analysis import run_analyze

__all__ = ["run_analyze"]


if __name__ == "__main__":
    import sys

    run_analyze(mock="--mock" in sys.argv, qwen="--qwen" in sys.argv)
