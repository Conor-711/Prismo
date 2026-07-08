"""Narrative rotation job workflows."""
from __future__ import annotations

from typing import Any

from ...domain.narratives import build_rotation


def build_narrative_rotation(
    *,
    db_path: str,
    out_path: str,
    window_days: int,
    recent_days: int,
) -> dict[str, Any]:
    """Build the fixed-taxonomy cross-community narrative rotation export."""
    return build_rotation(
        db_path=db_path,
        out_path=out_path,
        window_days=window_days,
        recent_days=recent_days,
    )
