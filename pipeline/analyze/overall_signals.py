"""Compatibility wrapper for Smart Account overall ticker signals."""
from __future__ import annotations

from ..domain.smart_voice.overall_signals import main, run

__all__ = ["main", "run"]


if __name__ == "__main__":
    main()
