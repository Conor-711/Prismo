"""Compatibility wrapper for the resumable Xueqiu platform pipeline."""
from __future__ import annotations

from ..platforms.xueqiu.pipeline import (
    backfill,
    enrich_authors,
    expand_related,
    incremental,
    plan_jobs,
    run_jobs,
    status,
    sync_to_gr_post,
)

__all__ = [
    "backfill",
    "enrich_authors",
    "expand_related",
    "incremental",
    "plan_jobs",
    "run_jobs",
    "status",
    "sync_to_gr_post",
]
