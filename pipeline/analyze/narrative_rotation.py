"""Compatibility wrapper for fixed-taxonomy narrative rotation."""
from __future__ import annotations

from ..domain.narratives.rotation import (
    CATEGORIES,
    OUT,
    SOURCE_LABELS,
    build,
    build_rotation,
    main,
)

__all__ = ["CATEGORIES", "OUT", "SOURCE_LABELS", "build", "build_rotation", "main"]


if __name__ == "__main__":
    main()
