"""Content translation workflows."""
from __future__ import annotations


def translate_legacy_content(*, only: set[str], limit: int | None) -> None:
    """Translate legacy Reddit posts, analyses, and comments."""
    from .legacy import run

    run(only, limit)
