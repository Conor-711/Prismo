"""Compatibility wrapper for the YouTube video discovery entrypoint."""
from __future__ import annotations

from ..platforms.youtube.discovery import crawl

__all__ = ["crawl"]


if __name__ == "__main__":
    crawl(mock=True)
