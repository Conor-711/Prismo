from __future__ import annotations

from pathlib import Path

from ...jobs.congress_capture import capture_trades
from ...jobs.congress_score import DEFAULT_DATASET_URL, run_congress_score


def cmd_congress_fetch(args) -> None:
    root = Path(__file__).resolve().parents[3]
    output = Path(args.output).expanduser().resolve()
    snapshot = capture_trades(
        root=root, output=output, since=args.since, until=args.until,
        page_size=args.page_size, max_pages=args.max_pages, credit_budget=args.credit_budget,
    )
    print(
        f"fetched={snapshot['fetched_count']} total={snapshot['total_count']} "
        f"pages={snapshot['pages_fetched']} "
        f"possibly_truncated={snapshot['possibly_truncated']} output={output}"
    )
    if snapshot["possibly_truncated"]:
        print("Warning: page cap reached; rerun with a larger --max-pages or a narrower date window.")


def cmd_congress_score(args) -> None:
    run_congress_score(
        as_of=args.as_of,
        lookback_days=args.lookback_days,
        output_dir=args.output,
        db_path=args.db,
        source_zip=args.source_zip,
        source_url=args.source_url,
        refresh_source=args.refresh_source,
        min_purchase_days=args.min_purchase_days,
        workers=args.workers,
        refresh_prices=args.refresh_prices,
    )


def register_commands(sub, root) -> None:
    fetch_parser = sub.add_parser(
        "congress-fetch",
        help="Capture Disclosed Capitol trades into a local, incrementally updated snapshot.",
    )
    fetch_parser.add_argument("--since", help="Inclusive start date; defaults to 30 days or a 7-day overlap.")
    fetch_parser.add_argument("--until", help="Inclusive end date; defaults to today UTC.")
    fetch_parser.add_argument("--page-size", type=int, default=50)
    fetch_parser.add_argument("--max-pages", type=int, default=1)
    fetch_parser.add_argument("--credit-budget", type=int, default=100)
    fetch_parser.add_argument(
        "--output", default=str(root / "data" / "exports" / "congress" / "disclosed_capitol.json")
    )
    fetch_parser.set_defaults(func=cmd_congress_fetch)

    parser = sub.add_parser(
        "congress-score",
        help="Score one year of House and Senate STOCK Act transactions.",
    )
    parser.add_argument("--as-of", help="Inclusive as-of date; defaults to the previous UTC day.")
    parser.add_argument("--lookback-days", type=int, default=365)
    parser.add_argument("--output", default=str(root / "data" / "exports" / "congress_score"))
    parser.add_argument("--db", default=str(root / "data" / "dev.db"))
    parser.add_argument("--source-zip")
    parser.add_argument("--source-url", default=DEFAULT_DATASET_URL)
    parser.add_argument("--refresh-source", action="store_true")
    parser.add_argument("--refresh-prices", action="store_true")
    parser.add_argument("--min-purchase-days", type=int, default=5)
    parser.add_argument("--workers", type=int, default=20)
    parser.set_defaults(func=cmd_congress_score)
