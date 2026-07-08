"""Compatibility wrapper for ticker catalog seeding."""
from __future__ import annotations

from ..domain.tickers.seeding import (
    SEC_URL,
    fetch_sec_tickers,
    load_fallback,
    seed_cn_hk,
    seed_tickers,
)

__all__ = ["SEC_URL", "fetch_sec_tickers", "load_fallback", "seed_cn_hk", "seed_tickers"]


if __name__ == "__main__":
    import sys

    seed_tickers(use_fallback="--fallback" in sys.argv)
