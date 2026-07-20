"""Xueqiu author-domain workflows."""
from __future__ import annotations

from pathlib import Path

from .xueqiu_pool import XueqiuPoolSummary, import_discovery_pool


def build_author_pool(
    csv_path: str | Path,
    *,
    pool_version: str,
    target_size: int = 300,
    minimum_size: int = 300,
    min_followers: int = 500,
    min_statuses: int = 300,
) -> XueqiuPoolSummary:
    """Persist a versioned Xueqiu creator pool from a discovery export."""
    return import_discovery_pool(
        csv_path,
        pool_version=pool_version,
        target_size=target_size,
        minimum_size=minimum_size,
        min_followers=min_followers,
        min_statuses=min_statuses,
    )
