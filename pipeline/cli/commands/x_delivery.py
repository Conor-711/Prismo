"""Thin entry points for the three-hour package delivery queue."""
import json
from ...jobs.x_delivery import enqueue, retry, run


def register_commands(subparsers, root):
    parser = subparsers.add_parser('x-delivery', help='Enqueue or process completed X packages')
    parser.add_argument('--inbox', default=str(root / 'data/inbox/x'))
    parser.add_argument('--package')
    parser.add_argument('--workers', type=int, default=2)
    parser.add_argument('--max-calls', type=int, default=1000)
    parser.add_argument('--skip-translation', action='store_true')
    parser.add_argument('--retry-package')
    parser.add_argument('--retry-reason')
    def execute(args):
        if args.retry_package:
            result = retry(args.inbox, args.retry_package, args.retry_reason or '')
        elif args.package:
            result = enqueue(args.package, args.inbox, workers=args.workers, max_calls=args.max_calls,
                             skip_translation=args.skip_translation)
        else:
            result = run(args.inbox)
        print(json.dumps(result, ensure_ascii=False))
        if not args.package and not args.retry_package and result.get('status') in {'retry', 'needs_attention', 'busy'}:
            raise SystemExit(1)
    parser.set_defaults(func=execute)
