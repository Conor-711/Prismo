"""Author domain workflows."""

from .xueqiu import build_author_pool as build_xueqiu_author_pool
from .youtube import build_author_pool as build_youtube_author_pool
from .youtube import build_creator_view

build_author_pool = build_youtube_author_pool

__all__ = [
    "build_author_pool",
    "build_creator_view",
    "build_xueqiu_author_pool",
    "build_youtube_author_pool",
]
