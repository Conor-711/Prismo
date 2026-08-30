"""Compatibility wrapper for Smart Account v0 scoring."""
from __future__ import annotations

from ..domain.smart_voice.v0_impl import main, run

__all__ = ["main", "run"]


if __name__ == "__main__":
    main()
