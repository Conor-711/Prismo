"""Global retail platform operations."""
from __future__ import annotations


def crawl_regional_discussions(
    *,
    per_board: int,
    since_days: int,
    regions: set[str] | None,
    only: list[str] | None,
) -> dict:
    """Fetch JP/KR/TW regional retail discussions."""
    from .regional import crawl

    return crawl(per_board=per_board, since_days=since_days, regions=regions, only=only)


def import_xueqiu_export(*, path: str, since_days: int) -> dict:
    """Import browser-exported Xueqiu discussions into global retail posts."""
    from .xueqiu_export import ingest

    return ingest(path=path, since_days=since_days)


def fetch_quotes() -> dict:
    """Fetch latest global retail ticker quotes."""
    from .quotes import fetch_quotes as run

    return run()
