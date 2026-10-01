"""Lightweight entrypoint that does not load unrelated pipeline commands."""
from __future__ import annotations

import argparse
from pathlib import Path

from .workflows import capture_trades


def main() -> None:
    root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description="Capture Disclosed Capitol congressional trades")
    parser.add_argument("--since")
    parser.add_argument("--until")
    parser.add_argument("--page-size", type=int, default=50)
    parser.add_argument("--max-pages", type=int, default=1)
    parser.add_argument("--credit-budget", type=int, default=100)
    parser.add_argument(
        "--output", type=Path,
        default=root / "data" / "exports" / "congress" / "disclosed_capitol.json",
    )
    args = parser.parse_args()
    snapshot = capture_trades(
        root=root, output=args.output, since=args.since, until=args.until,
        page_size=args.page_size, max_pages=args.max_pages, credit_budget=args.credit_budget,
    )
    print(
        f"fetched={snapshot['fetched_count']} total={snapshot['total_count']} "
        f"pages={snapshot['pages_fetched']} "
        f"possibly_truncated={snapshot['possibly_truncated']} output={args.output}"
    )
    if snapshot["possibly_truncated"]:
        print("Warning: page cap reached; widen --max-pages or narrow the date window.")


if __name__ == "__main__":
    main()
