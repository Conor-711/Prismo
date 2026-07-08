"""Compatibility wrapper for Toss community crawling."""
from __future__ import annotations

from ..platforms.toss.community import crawl, crawl_stock

__all__ = ["crawl", "crawl_stock"]


if __name__ == "__main__":
    crawl()
