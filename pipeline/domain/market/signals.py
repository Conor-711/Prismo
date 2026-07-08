"""Market-level signal workflows."""
from __future__ import annotations


def build_rollups(*, market: str) -> int:
    """Build ticker rollups for a market."""
    from .rollups import run_rollups

    return run_rollups(market=market)


def build_mood(*, market: str) -> dict:
    """Build market mood for a market."""
    from .mood import run_market_mood

    return run_market_mood(market=market)


def build_trending(*, market: str) -> int:
    """Build trending tickers for a market."""
    from .trending import run_trending

    return run_trending(market=market)


def build_brief(*, mock: bool) -> str:
    """Build market brief."""
    from .brief import run_brief

    return run_brief(mock=mock)
