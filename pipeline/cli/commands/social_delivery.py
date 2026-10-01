"""CLI for scheduled public-source refresh."""
import json
from pathlib import Path
from ...jobs.social_delivery import run
from ...jobs.social_delivery.cycle import run as run_cycle


def _run_cycle(_args):
    result = run_cycle()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if result['status'] in {'retry', 'needs_attention'}:
        raise SystemExit(1)


def register_commands(subparsers, root):
    parser = subparsers.add_parser('social-delivery', help='Collect, process and publish YouTube/Reddit updates')
    parser.add_argument('--source', choices=['all', 'youtube', 'reddit'], default='all')
    parser.add_argument('--lookback-hours', type=int, help='Explicit Reddit backfill, 1..168 hours; use a separate run directory')
    parser.add_argument('--run-dir', type=Path, help='Separate checkpoint directory for a manual backfill')
    def execute(args):
        if args.lookback_hours is not None and args.run_dir is None:
            parser.error('--lookback-hours requires --run-dir')
        options = {'root': args.run_dir} if args.run_dir is not None else {}
        print(json.dumps(run(source=args.source, lookback_hours=args.lookback_hours, **options),
                         ensure_ascii=False, indent=2))
    parser.set_defaults(func=execute)

    cycle = subparsers.add_parser('content-delivery', help='Run the scheduled three-source content cycle')
    cycle.set_defaults(func=_run_cycle)
