"""KOL job-level workflows."""
from __future__ import annotations

from ...domain.opinions.kol import (
    classify_viewpoints as classify_viewpoints_domain,
    refine_opinions as refine_opinions_domain,
    score_quality as score_quality_domain,
    score_relevance as score_relevance_domain,
    synthesize_arguments as synthesize_arguments_domain,
    translate_opinions as translate_opinions_domain,
)
from ...domain.target_prices.kol import extract_judgments as extract_judgments_domain


def refine_opinions(
    *,
    sources: list[str] | None,
    per_source: int,
    only: list[str] | None,
    force: bool,
    workers: int,
    since_days: int,
) -> int:
    """Distill cross-platform KOL posts into opinion records."""
    return refine_opinions_domain(
        sources=sources,
        per_source=per_source,
        only=only,
        force=force,
        workers=workers,
        since_days=since_days,
    )


def classify_viewpoints(
    *,
    only: list[str] | None,
    force: bool,
    workers: int,
    reclassify_other: bool,
) -> int:
    """Classify KOL opinions into viewpoint buckets."""
    return classify_viewpoints_domain(
        only=only,
        force=force,
        workers=workers,
        reclassify_other=reclassify_other,
    )


def extract_judgments(
    *,
    sources: list[str] | None,
    per_source: int,
    only: list[str] | None,
    force: bool,
    workers: int,
    since_days: int,
) -> int:
    """Extract target prices and operation horizons from KOL posts."""
    return extract_judgments_domain(
        sources=sources,
        per_source=per_source,
        only=only,
        force=force,
        workers=workers,
        since_days=since_days,
    )


def synthesize_arguments(*, only: list[str] | None, force: bool, workers: int) -> int:
    """Synthesize arguments by ticker/viewpoint/stance."""
    return synthesize_arguments_domain(only=only, force=force, workers=workers)


def translate_opinions(
    *,
    sources: list[str] | None,
    per_source: int,
    only: list[str] | None,
    force: bool,
    workers: int,
    since_days: int,
) -> int:
    """Translate original KOL posts faithfully."""
    return translate_opinions_domain(
        sources=sources,
        per_source=per_source,
        only=only,
        force=force,
        workers=workers,
        since_days=since_days,
    )


def score_relevance(
    *,
    sources: list[str] | None,
    per_source: int,
    only: list[str] | None,
    force: bool,
    workers: int,
    since_days: int,
    include_youtube: bool,
) -> int:
    """Score ticker relevance for KOL posts and videos."""
    return score_relevance_domain(
        sources=sources,
        per_source=per_source,
        only=only,
        force=force,
        workers=workers,
        since_days=since_days,
        include_youtube=include_youtube,
    )


def score_quality(
    *,
    sources: list[str] | None,
    per_source: int,
    only: list[str] | None,
    force: bool,
    workers: int,
    since_days: int,
    include_youtube: bool,
) -> int:
    """Score intrinsic investment-analysis quality."""
    return score_quality_domain(
        sources=sources,
        per_source=per_source,
        only=only,
        force=force,
        workers=workers,
        since_days=since_days,
        include_youtube=include_youtube,
    )

