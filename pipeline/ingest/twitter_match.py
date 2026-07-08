"""Compatibility wrapper for X/Twitter topic matching."""
from __future__ import annotations

from ..platforms.x.ticker_match import (
    Index,
    load_index,
    match_tweet,
    run,
    tokenize,
)

__all__ = ["Index", "load_index", "match_tweet", "run", "tokenize"]


if __name__ == "__main__":
    run()
