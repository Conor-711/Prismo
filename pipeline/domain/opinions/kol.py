"""KOL opinion-domain workflows."""
from __future__ import annotations


def refine_opinions(
    *,
    sources: list[str] | None,
    per_source: int,
    only: list[str] | None,
    force: bool,
    workers: int,
    since_days: int,
) -> int:
    """Distill cross-platform KOL source posts into bilingual opinion records."""
    from .kol_refine import refine

    return refine(
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
    sources: list[str] | None,
    since_days: int | None,
    force: bool,
    workers: int,
    reclassify_other: bool,
) -> int:
    """Classify KOL opinions into viewpoint buckets."""
    from .kol_viewpoint import classify

    return classify(
        only=only,
        sources=sources,
        since_days=since_days,
        force=force,
        workers=workers,
        reclassify_other=reclassify_other,
    )


def synthesize_arguments(*, only: list[str] | None, force: bool, workers: int) -> int:
    """Synthesize KOL arguments by ticker, viewpoint and stance."""
    from .kol_argument import synthesize

    return synthesize(only=only, force=force, workers=workers)


def translate_opinions(
    *,
    sources: list[str] | None,
    per_source: int,
    only: list[str] | None,
    force: bool,
    workers: int,
    since_days: int,
) -> int:
    """Translate original KOL posts faithfully without summarization."""
    from .kol_translate import translate

    return translate(
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
    """Score ticker relevance for displayed KOL posts and videos."""
    from .kol_relevance import score

    return score(
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
    """Score intrinsic investment-analysis quality for KOL posts and videos."""
    from .kol_quality import score

    return score(
        sources=sources,
        per_source=per_source,
        only=only,
        force=force,
        workers=workers,
        since_days=since_days,
        include_youtube=include_youtube,
    )
