"""Compatibility wrapper for the YouTube channel refresh entrypoint."""
from __future__ import annotations

from ..platforms.youtube.channels import main

__all__ = ["main"]


if __name__ == "__main__":
    main()
