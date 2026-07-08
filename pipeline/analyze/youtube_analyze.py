"""Compatibility wrapper for YouTube opinion analysis."""
from __future__ import annotations

from ..domain.opinions.youtube_analysis import gen_fulltext, tag, tag_text

__all__ = ["gen_fulltext", "tag", "tag_text"]


if __name__ == "__main__":
    tag(mock=True)
