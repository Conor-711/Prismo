"""Toss community platform operations."""
from __future__ import annotations


def crawl_community(
    *,
    days: int,
    only: list[str] | None,
    max_pages: int,
    sleep: float,
    commit_pages: int,
    resume: bool,
) -> int:
    """Fetch Toss stock-community posts into global retail posts."""
    from .community import crawl

    return crawl(
        days=days,
        only=only,
        max_pages=max_pages,
        sleep=sleep,
        commit_pages=commit_pages,
        resume=resume,
    )
