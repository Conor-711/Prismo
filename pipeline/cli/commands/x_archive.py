"""CLI for additive local roster imports."""
from ...jobs.x_archive import run


def register_commands(sub, root) -> None:
    parser = sub.add_parser("x-import-archive")
    parser.add_argument("--tweet-dir", action="append", required=True)
    parser.add_argument("--report", default=str(root / "data/runtime/x-archive-import.json"))
    parser.add_argument("--dry-run", action="store_true")
    parser.set_defaults(func=lambda args: run(
        tweet_dirs=args.tweet_dir, report=args.report, dry_run=args.dry_run,
    ))
