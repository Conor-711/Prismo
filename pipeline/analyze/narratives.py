"""Compatibility wrapper for legacy narrative clustering."""
from __future__ import annotations

from ..domain.narratives.legacy import (
    build_legacy_narratives,
    run_narratives,
)

__all__ = ["build_legacy_narratives", "run_narratives"]


if __name__ == "__main__":
    import sys

    run_narratives(mock="--mock" in sys.argv)
