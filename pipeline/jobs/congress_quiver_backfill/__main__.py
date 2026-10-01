from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path

from .capture import capture


def main() -> None:
    parser = argparse.ArgumentParser(description="Backfill licensed congressional trades")
    parser.add_argument("--since", type=dt.date.fromisoformat, required=True)
    parser.add_argument("--until", type=dt.date.fromisoformat, required=True)
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--max-members", type=int, default=None)
    parser.add_argument("--delay", type=float, default=0.75)
    parser.add_argument("--refresh", action="store_true", help="Re-fetch members already captured in this window")
    args = parser.parse_args()
    if args.since > args.until or args.delay < 0:
        parser.error("invalid date window or delay")
    if args.max_members is not None and args.max_members < 1:
        parser.error("--max-members must be positive")
    result = capture(
        since=args.since,
        until=args.until,
        db_path=args.db,
        report_path=args.report,
        max_members=args.max_members,
        delay=args.delay,
        refresh=args.refresh,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
