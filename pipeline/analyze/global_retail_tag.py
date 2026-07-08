"""Compatibility wrapper for global retail sentiment tagging."""
from __future__ import annotations

from ..domain.global_retail.tag import tag_all

__all__ = ["tag_all"]


if __name__ == "__main__":
    tag_all()
