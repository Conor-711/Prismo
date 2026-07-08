"""Compatibility wrapper for global retail quote fetching."""
from __future__ import annotations

from ..platforms.global_retail.quotes import fetch_quotes

__all__ = ["fetch_quotes"]


if __name__ == "__main__":
    fetch_quotes()
