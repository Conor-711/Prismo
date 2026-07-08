"""Compatibility wrapper for content translation workflows."""
from __future__ import annotations

from ..domain.translations.legacy import (
    main,
    run,
    translate_analysis,
    translate_comments,
    translate_posts,
    translate_texts,
)

__all__ = [
    "main",
    "run",
    "translate_analysis",
    "translate_comments",
    "translate_posts",
    "translate_texts",
]


if __name__ == "__main__":
    main()
