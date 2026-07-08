"""Compatibility wrapper for bundled sample-data loading."""
from __future__ import annotations

from ..platforms.local.sample_data import load_sample

__all__ = ["load_sample"]


if __name__ == "__main__":
    load_sample()
