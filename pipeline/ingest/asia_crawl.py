"""Compatibility wrapper for global retail Asia source fetchers."""
from __future__ import annotations

from ..platforms.global_retail.asia_sources import (
    fetch_naver_discussion,
    fetch_ptt_stock,
    fetch_yahoo_jp,
)

__all__ = ["fetch_naver_discussion", "fetch_ptt_stock", "fetch_yahoo_jp"]
