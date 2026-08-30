"""Compatibility wrapper for Smart Account X sentiment scoring."""
from __future__ import annotations

from ..domain.smart_voice.tweet_sentiment import MEGACAP, main, megacap_regex, score

__all__ = ["MEGACAP", "main", "megacap_regex", "score"]


if __name__ == "__main__":
    main()
