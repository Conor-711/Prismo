"""Compatibility wrapper for global retail regional crawling."""
from __future__ import annotations

from ..platforms.global_retail.regional import crawl, crawl_tw, load_targets

__all__ = ["crawl", "crawl_tw", "load_targets"]


if __name__ == "__main__":
    crawl()
