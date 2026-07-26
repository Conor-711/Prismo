"""Smart Voice job-level workflows."""
from __future__ import annotations

from ...domain.smart_voice import signals
from ...domain.smart_voice.indicator_backtest import build_sv_indicator_backtest as build_sv_indicator_backtest_domain
from ...domain.smart_voice.indicator_backtest_reporting import export_sv_indicator_backtest_reports as export_sv_indicator_backtest_reports_domain
from ...domain.smart_voice.portfolio_backtest import build_x_sv_portfolio_backtest as build_x_sv_portfolio_backtest_domain
from ...domain.smart_voice.rank_event_research import build_x_rank_event_research as build_x_rank_event_research_domain
from ...domain.smart_voice.segment_backtest import build_sv_segment_backtest as build_sv_segment_backtest_domain
from ...domain.smart_voice.v0 import run_sv_v0 as run_sv_v0_domain
from ...domain.smart_voice.ticker_signals import build_ticker_sv_signals as build_ticker_sv_signals_domain
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
    xueqiu_pool_version: str,
    xueqiu_since_days: int,
    xueqiu_allow_partial: bool,
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
        xueqiu_pool_version=xueqiu_pool_version,
        xueqiu_since_days=xueqiu_since_days,
        xueqiu_allow_partial=xueqiu_allow_partial,
        force=force,
    )


def build_ticker_sv_signals(
    *,
    db_path: str,
    only: list[str] | None,
    window_days: int,
    min_authors: int,
    consensus_threshold: float,
    effective_voice_threshold: float,
) -> dict[str, int]:
    """Build point-in-time ticker SV clusters and their forward backtests."""
    return build_ticker_sv_signals_domain(
        db_path=db_path,
        only=only,
        window_days=window_days,
        min_authors=min_authors,
        consensus_threshold=consensus_threshold,
        effective_voice_threshold=effective_voice_threshold,
    )


def build_sv_indicator_backtest(
    *,
    db_path: str,
    report_path: str,
    only: list[str] | None,
    windows: tuple[int, ...],
    source_scopes: tuple[str, ...],
) -> dict[str, int]:
    """Backtest Smart Voice discovery indicators through the job boundary."""
    return build_sv_indicator_backtest_domain(
        db_path=db_path,
        report_path=report_path,
        only=only,
        windows=windows,
        source_scopes=source_scopes,
    )


def export_sv_indicator_backtest_reports(
    *,
    db_path: str,
    report_dir: str,
) -> dict[str, int]:
    """Export detailed event, evidence, and robustness files without rebuilding signals."""
    return export_sv_indicator_backtest_reports_domain(db_path=db_path, report_dir=report_dir)


def build_sv_segment_backtest(
    *,
    db_path: str,
    report_path: str,
    only: list[str] | None,
    windows: tuple[int, ...],
    sources: tuple[str, ...],
    segment_types: tuple[str, ...],
    rank_bands: tuple[str, ...],
    min_authors: int,
    consensus_threshold: float,
    effective_voice_threshold: float,
    segment_min_n_eff: float,
    segment_min_settled_calls: int,
) -> dict[str, int]:
    """Backtest vertical concentration using historical sub-SV ranks."""
    return build_sv_segment_backtest_domain(
        db_path=db_path,
        report_path=report_path,
        only=only,
        windows=windows,
        sources=sources,
        segment_types=segment_types,
        rank_bands=rank_bands,
        min_authors=min_authors,
        consensus_threshold=consensus_threshold,
        effective_voice_threshold=effective_voice_threshold,
        segment_min_n_eff=segment_min_n_eff,
        segment_min_settled_calls=segment_min_settled_calls,
    )


def build_x_sv_portfolio_backtest(
    *,
    db_path: str,
    report_dir: str,
    windows: tuple[int, ...],
    holding_days: tuple[int, ...],
    position_modes: tuple[str, ...],
) -> dict[str, int]:
    """Build annualized X-only SV signal and author portfolios."""
    return build_x_sv_portfolio_backtest_domain(
        db_path=db_path,
        report_dir=report_dir,
        windows=windows,
        holding_days=holding_days,
        position_modes=position_modes,
    )


def build_x_rank_event_research(
    *,
    db_path: str,
    report_dir: str,
) -> dict[str, int]:
    """Search and split-test X SV rank-event strategy parameters."""
    return build_x_rank_event_research_domain(
        db_path=db_path,
        report_dir=report_dir,
    )
