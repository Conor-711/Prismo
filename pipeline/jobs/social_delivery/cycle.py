"""Shared scheduled cycle; bounded sources run serially against one local DB."""
import os
from ..x_delivery import ROOT, command, run as run_x
from ..telegram_x_delivery import cleanup as cleanup_telegram, sync as sync_telegram
from . import run as run_social


def run():
    social = run_social()
    try:
        telegram = sync_telegram()
    except Exception as error:
        telegram = {'status': 'retry', 'errorType': type(error).__name__}
    # 2 * (25-minute analysis + 10-minute publish + 10-minute verify)
    # plus X (35 + 10 + 10 minutes) fits within the 3-hour interval.
    previous = os.environ.get('BSMART_X_DELIVERY_TIMEOUT')
    os.environ['BSMART_X_DELIVERY_TIMEOUT'] = '2100'
    try:
        x = run_x(ROOT / 'data/inbox/x')
    finally:
        if previous is None:
            os.environ.pop('BSMART_X_DELIVERY_TIMEOUT', None)
        else:
            os.environ['BSMART_X_DELIVERY_TIMEOUT'] = previous
    result = {'social': social, 'telegram': telegram, 'x': x}
    try:
        result['telegramCleanup'] = cleanup_telegram()
    except Exception as error:
        result['telegramCleanup'] = {'status': 'needs_attention', 'errorType': type(error).__name__}
    published = any(item.get('status') == 'verified' for item in social.get('sources', []))
    published = published or x.get('status') == 'verified'
    if published:
        try:
            command([str(ROOT / 'services/client_api/.venv/bin/python'), '-m',
                     'services.client_api.content_release.retention', '--apply'],
                    ROOT / 'data/runtime/social-delivery/retention.log', timeout=600)
            result['retention'] = {'status': 'checked'}
        except Exception as error:
            result['retention'] = {'status': 'needs_attention', 'errorType': type(error).__name__}
    statuses = [social.get('status'), telegram.get('status'), x.get('status'),
                result.get('telegramCleanup', {}).get('status'), result.get('retention', {}).get('status')]
    statuses.extend(item.get('status') for item in social.get('sources', []))
    result['status'] = ('needs_attention' if 'needs_attention' in statuses else
                        'retry' if any(status in {'retry', 'busy'} for status in statuses) else
                        'verified' if published else 'idle')
    return result
