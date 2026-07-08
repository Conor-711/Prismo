"""KOL jobs."""

from .workflows import (
    classify_viewpoints,
    extract_judgments,
    refine_opinions,
    score_quality,
    score_relevance,
    synthesize_arguments,
    translate_opinions,
)

__all__ = [
    "classify_viewpoints",
    "extract_judgments",
    "refine_opinions",
    "score_quality",
    "score_relevance",
    "synthesize_arguments",
    "translate_opinions",
]

