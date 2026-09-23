"""CLI for scheduled public-source refresh."""
import json
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
    parser.set_defaults(func=lambda args: print(json.dumps(run(source=args.source), ensure_ascii=False, indent=2)))

    cycle = subparsers.add_parser('content-delivery', help='Run the scheduled three-source content cycle')
    cycle.set_defaults(func=_run_cycle)
