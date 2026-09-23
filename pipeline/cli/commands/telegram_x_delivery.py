"""Telegram channel intake commands."""
import json

from ...jobs.telegram_x_delivery import cutover, retry, sync


def register_commands(subparsers, root):
    parser = subparsers.add_parser('telegram-x-sync', help='Download and queue one channel X package')
    parser.set_defaults(func=lambda args: print(json.dumps(sync(), ensure_ascii=False)))

    resume = subparsers.add_parser('telegram-x-retry', help='Retry a reviewed blocked Telegram update')
    resume.set_defaults(func=lambda args: print(json.dumps(retry(), ensure_ascii=False)))

    cutover_parser = subparsers.add_parser('telegram-bot-api-cutover',
                                          help='Log out the hosted Bot API before local large-file service use')

    cutover_parser.set_defaults(func=lambda args: print(json.dumps(cutover())))
