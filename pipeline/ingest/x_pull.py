"""Compatibility wrapper for pulling X/Twitter opinions into the local snapshot."""
from __future__ import annotations

from ..platforms.x.cloud_pull import main

__all__ = ["main"]


if __name__ == "__main__":
    main()
