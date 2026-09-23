"""Daily package command; orchestration lives in jobs."""
from ...jobs.x_daily import run


def register_commands(subparsers, root):
    parser = subparsers.add_parser("x-daily", help="Inspect/process/publish a daily X archive")
    parser.add_argument("--package", required=True)
    parser.add_argument("--database", default=str(root / "data/dev.db"))
    parser.add_argument("--output", default=str(root / "data/runtime/x-daily"))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--skip-translation", action="store_true", help="Keep original text; do not generate full-text translations")
    parser.add_argument("--reading-package-only", action="store_true", help="Do not backfill reading content outside the supplied package")
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--max-calls", type=int, default=1000)
    parser.set_defaults(func=lambda args: run(package=args.package, database=args.database,
        output=args.output, apply=args.apply, publish=args.publish, workers=args.workers,
        max_calls=args.max_calls, skip_translation=args.skip_translation,
        reading_package_only=args.reading_package_only))
