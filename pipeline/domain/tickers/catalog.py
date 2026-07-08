"""Ticker catalog and mention-extraction workflows."""
from __future__ import annotations


def seed_us_tickers(*, use_fallback: bool) -> int:
    """Seed US ticker universe."""
    from .seeding import seed_tickers

    return seed_tickers(use_fallback=use_fallback)


def seed_cn_hk_tickers() -> int:
    """Seed China/Hong Kong ticker universe."""
    from .seeding import seed_cn_hk

    return seed_cn_hk()


def extract_mentions(*, reextract: bool) -> int:
    """Extract ticker mentions for posts."""
    from .extraction import extract_for_posts

    return extract_for_posts(reextract=reextract)
