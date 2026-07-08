"""Smart Voice job-level workflows."""
from __future__ import annotations

from ...domain.smart_voice import signals
from ...domain.smart_voice.v0 import run_sv_v0 as run_sv_v0_domain
from ...platforms.market_data import backfill_price_history as backfill_price_history_platform
from ...platforms.x import match_tweet_topics


def score_x_sentiment(
    *,
    batch_size: int,
    workers: int,
    only_new: bool,
    limit: int | None,
) -> int:
    """Score X tweet sentiment for Smart Voice rollups."""
    return signals.score_x_sentiment(
        batch_size=batch_size,
        workers=workers,
        only_new=only_new,
        limit=limit,
    )


def match_x_topics(*, page: int, batch: int) -> None:
    """Rebuild X tweet ticker/topic matches."""
    match_tweet_topics(page=page, batch=batch)


def rollup_kol_sentiment() -> int:
    """Build KOL daily net sentiment."""
    return signals.rollup_kol_sentiment()


def rollup_kol_volume() -> int:
    """Build KOL daily discussion volume."""
    return signals.rollup_kol_volume()


def rollup_retail_sentiment() -> int:
    """Build retail daily net sentiment."""
    return signals.rollup_retail_sentiment()


def rollup_retail_volume() -> int:
    """Build retail daily discussion volume."""
    return signals.rollup_retail_volume()


def rollup_retail_newcomers() -> int:
    """Build retail daily newcomer counts."""
    return signals.rollup_retail_newcomers()


def rollup_kol_newcomers() -> int:
    """Build KOL daily newcomer counts."""
    return signals.rollup_kol_newcomers()


def build_overall_signals(
    *,
    ticker: str,
    kol_file: str,
    window: int,
    look: int,
    aspect_days: int,
    cap: int,
    skill_dir: str,
    recent_days: int,
    prior_days: int,
) -> None:
    """Build ticker detail derived Smart Voice signals."""
    signals.build_overall_signals(
        ticker=ticker,
        kol_file=kol_file,
        window=window,
        look=look,
        aspect_days=aspect_days,
        cap=cap,
        skill_dir=skill_dir,
        recent_days=recent_days,
        prior_days=prior_days,
    )


def backfill_price_history(
    *,
    db: str,
    start: str,
    end: str | None,
    top_n: int,
    min_count: int,
    tweet_dirs: list[str] | None,
    only: str,
    sleep: float,
    workers: int,
    limit: int,
) -> None:
    """Backfill daily market prices required by Smart Voice settlement."""
    backfill_price_history_platform(
        db=db,
        start=start,
        end=end,
        top_n=top_n,
        min_count=min_count,
        tweet_dirs=tweet_dirs,
        only=only,
        sleep=sleep,
        workers=workers,
        limit=limit,
    )


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
    """Run Smart Voice v0 scoring through the job boundary."""
    run_sv_v0_domain(
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
        tweet_dirs=tweet_dirs,
        reddit_author_limit=reddit_author_limit,
        reddit_since_days=reddit_since_days,
        reddit_min_author_posts=reddit_min_author_posts,
        youtube_min_subs=youtube_min_subs,
        youtube_since_days=youtube_since_days,
        force=force,
    )
