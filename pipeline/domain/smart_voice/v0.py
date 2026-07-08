"""Smart Voice v0 scoring workflow adapter."""
from __future__ import annotations

import argparse


def run_sv_v0(
    *,
    stage: str,
    source: str,
    candidate_limit: int,
    extract_limit: int,
    extract_mode: str,
    per_author_min: int,
    per_author_max: int,
    min_score: float,
    workers: int,
    only: str,
    tweet_dirs: list[str] | None,
    reddit_author_limit: int,
    reddit_since_days: int,
    reddit_min_author_posts: int,
    youtube_min_subs: int,
    youtube_since_days: int,
    force: bool,
) -> None:
    """Run the legacy Smart Voice v0 scorer through the domain boundary."""
    from .v0_impl import run

    run(
        argparse.Namespace(
            stage=stage,
            source=source,
            candidate_limit=candidate_limit,
            extract_limit=extract_limit,
            extract_mode=extract_mode,
            per_author_min=per_author_min,
            per_author_max=per_author_max,
            min_score=min_score,
            workers=workers,
            only=only,
            tweet_dir=tweet_dirs or [],
            reddit_author_limit=reddit_author_limit,
            reddit_since_days=reddit_since_days,
            reddit_min_author_posts=reddit_min_author_posts,
            youtube_min_subs=youtube_min_subs,
            youtube_since_days=youtube_since_days,
            force=force,
        )
    )
