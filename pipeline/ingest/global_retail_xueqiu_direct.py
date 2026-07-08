"""Compatibility wrapper for direct Xueqiu crawling."""
from __future__ import annotations

from ..platforms.xueqiu.direct import DEFAULT_OUT, _fetch_page, _ms_to_dt, _row, crawl

__all__ = ["DEFAULT_OUT", "_fetch_page", "_ms_to_dt", "_row", "crawl"]


if __name__ == "__main__":
    crawl()
