"""Compatibility wrapper for ticker extraction."""
from __future__ import annotations

from ..common.ticker_extraction import (
    ALIASES,
    BARE_RE,
    CASHTAG_RE,
    CN_CODE_RE,
    TickerDict,
    extract_for_posts,
    extract_mentions,
    load_stoplist,
    load_ticker_dict,
    load_ticker_dict_from_fallback,
)

__all__ = [
    "ALIASES",
    "BARE_RE",
    "CASHTAG_RE",
    "CN_CODE_RE",
    "TickerDict",
    "extract_for_posts",
    "extract_mentions",
    "load_stoplist",
    "load_ticker_dict",
    "load_ticker_dict_from_fallback",
]


if __name__ == "__main__":
    import sys

    extract_for_posts(reextract="--reextract" in sys.argv)
