"""Compatibility wrapper for Reddit post refresh."""
from __future__ import annotations

from ..platforms.reddit.refresh import refresh_recent

__all__ = ["refresh_recent"]


if __name__ == "__main__":
    refresh_recent()
