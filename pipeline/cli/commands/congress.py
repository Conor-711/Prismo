from __future__ import annotations

from ...jobs.congress_score import DEFAULT_DATASET_URL, run_congress_score


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
