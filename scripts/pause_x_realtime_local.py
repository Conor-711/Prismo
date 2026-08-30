#!/usr/bin/env python3
"""Pause provider rules owned by the local X realtime database."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from dotenv import load_dotenv


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from pipeline.platforms.x.realtime.repository import XRealtimeRepository
from pipeline.platforms.x.realtime.twitterapi_io import TwitterAPIIOProvider


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database-url", required=True)
    return parser.parse_args()


def main() -> None:
    args = _arguments()
    load_dotenv(ROOT / ".env")
    load_dotenv(ROOT / ".env.x-realtime.local", override=True)
    api_key = os.environ.get("TWITTERAPI_IO_KEY", "").strip()
    if not api_key:
        raise SystemExit("TWITTERAPI_IO_KEY is missing from .env.x-realtime.local")

    repository = XRealtimeRepository(args.database_url)
    provider = TwitterAPIIOProvider(api_key)
    paused = 0
    try:
        provider_rules = {rule.rule_id: rule for rule in provider.list_rules()}
        for rule in repository.list_rules():
            current = provider_rules.get(rule.provider_rule_id or "")
            if rule.state not in {"active", "retiring"} or current is None or not current.active:
                continue
            provider.deactivate_rule(
                rule_id=current.rule_id,
                tag=current.tag,
                value=current.value,
                interval_seconds=current.interval_seconds,
            )
            paused += 1
    finally:
        repository.dispose()
    print(f"Paused {paused} local TwitterAPI.io rule(s).")


if __name__ == "__main__":
    main()
