"""Provider-neutral realtime X ingestion primitives."""

from .normalizer import NormalizedPost, normalize_delivery, normalize_tweet
from .provider import TweetProvider
from .rules import DesiredRule, build_rules

__all__ = [
    "DesiredRule",
    "NormalizedPost",
    "TweetProvider",
    "build_rules",
    "normalize_delivery",
    "normalize_tweet",
]
