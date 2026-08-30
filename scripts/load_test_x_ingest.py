#!/usr/bin/env python3
"""Local 5x-peak ingestion benchmark without provider or model calls."""
from __future__ import annotations

import argparse
import sys
import tempfile
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from pipeline.common.models import XRealtimeSubscription
from pipeline.platforms.x.realtime.normalizer import NormalizedPost
from pipeline.platforms.x.realtime.repository import XRealtimeRepository


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--messages", type=int, default=8_000)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="bsmart-x-load-") as folder:
        repository = XRealtimeRepository(f"sqlite:///{Path(folder) / 'load.db'}")
        repository.initialize()
        with repository.sessions() as session, session.begin():
            for index in range(67):
                session.add(
                    XRealtimeSubscription(
                        author_id=f"author-{index}",
                        handle=f"author{index}",
                        display_name=f"Author {index}",
                        author_score=100,
                        platform_percentile=(index + 1) / 268,
                        pool_version="load-test",
                        active=True,
                    )
                )
        started = time.perf_counter()
        batch = []
        now = datetime.now(UTC).replace(tzinfo=None)
        inserted = 0
        for index in range(args.messages):
            author = index % 67
            batch.append(
                NormalizedPost(
                    post_id=str(10_000_000 + index),
                    author_id=f"author-{author}",
                    author_handle=f"author{author}",
                    author_name=f"Author {author}",
                    author_avatar_url=None,
                    author_followers_count=None,
                    author_verified=None,
                    source_url=f"https://x.com/author{author}/status/{10_000_000 + index}",
                    original_text=f"Watching $NVDA setup {index}.",
                    language="en",
                    post_type="original",
                    is_reply=False,
                    is_quote=False,
                    is_retweet=False,
                    parent_post_id=None,
                    conversation_id=None,
                    like_count=0,
                    reply_count=0,
                    retweet_count=0,
                    quote_count=0,
                    view_count=0,
                    bookmark_count=0,
                    published_at=now - timedelta(seconds=index),
                    raw_payload={"id": str(10_000_000 + index)},
                )
            )
            if len(batch) == 500:
                inserted += repository.ingest(batch, delivery_source="load-test").inserted
                batch.clear()
        if batch:
            inserted += repository.ingest(batch, delivery_source="load-test").inserted
        elapsed = time.perf_counter() - started
        print(
            f"messages={args.messages} inserted={inserted} elapsed={elapsed:.3f}s "
            f"rate={inserted / max(elapsed, 0.001):.1f}/s"
        )


if __name__ == "__main__":
    main()
