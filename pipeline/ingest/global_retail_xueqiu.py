"""Compatibility wrapper for browser-exported Xueqiu imports."""
from __future__ import annotations

from ..platforms.global_retail.xueqiu_export import DEFAULT_PATH, ingest

__all__ = ["DEFAULT_PATH", "ingest"]


if __name__ == "__main__":
    import sys

    ingest(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PATH)
