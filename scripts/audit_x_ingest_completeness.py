#!/usr/bin/env python3
"""Compare provider search results with stored realtime X post IDs."""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from pipeline.platforms.x.realtime.normalizer import normalize_delivery
from pipeline.platforms.x.realtime.repository import XRealtimeRepository
from pipeline.platforms.x.realtime.twitterapi_io import TwitterAPIIOProvider


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hours", type=int, default=24)
    parser.add_argument("--minimum", type=float, default=0.99)
    parser.add_argument("--max-requests-per-rule", type=int, default=80)
    arguments = parser.parse_args()
    api_key = os.environ.get("TWITTERAPI_IO_KEY", "").strip()
    if not api_key:
        raise SystemExit("TWITTERAPI_IO_KEY is required")
    database_url = os.environ.get(
        "BSMART_X_DATABASE_URL",
        os.environ.get("DATABASE_URL", "sqlite:///./data/x_realtime.db"),
    )
    repository = XRealtimeRepository(database_url)
    provider = TwitterAPIIOProvider(
        api_key,
        base_url=os.environ.get("TWITTERAPI_IO_BASE_URL", "https://api.twitterapi.io"),
    )
    try:
        until = datetime.now(UTC)
        since = until - timedelta(hours=max(1, arguments.hours))
        active_author_ids = {
            item.author_id for item in repository.active_subscriptions()
        }
        expected: set[str] = set()
        failed_rules: list[str] = []
        for rule in repository.list_rules():
            if rule.state != "active":
                continue
            try:
                payloads = provider.search_recent(
                    query=rule.value,
                    since=since,
                    until=until,
                    max_pages=arguments.max_requests_per_rule,
                )
                _, posts = normalize_delivery({"tweets": payloads, "tag": rule.tag})
                expected.update(
                    post.post_id for post in posts if post.author_id in active_author_ids
                )
            except Exception as exc:  # noqa: BLE001 - report every failed rule together
                failed_rules.append(f"{rule.rule_key}:{exc}")
        stored = repository.existing_post_ids(expected)
        missing = sorted(expected - stored)
        completeness = len(stored) / max(1, len(expected))
        report = {
            "windowStart": since.isoformat(),
            "windowEnd": until.isoformat(),
            "providerPosts": len(expected),
            "storedPosts": len(stored),
            "missingPosts": len(missing),
            "completeness": round(completeness, 6),
            "minimum": arguments.minimum,
            "failedRules": failed_rules,
            "missingPostIds": missing[:100],
            "health": repository.health_snapshot(),
        }
        print(json.dumps(report, ensure_ascii=False, indent=2))
        if failed_rules or completeness < arguments.minimum:
            raise SystemExit(1)
    finally:
        repository.dispose()


if __name__ == "__main__":
    main()
