"""Operator-only Feed readiness check. No identities, tokens, DDL or trades printed."""
import argparse
from datetime import UTC, datetime
import json

import httpx

from services.client_api.opinion_trades.publish_catalog import BUCKET, PROJECT, check, storage_client


def inspect(run_worker=False):
    base = f'https://{PROJECT}.supabase.co'
    result = {}
    with httpx.Client(timeout=15, follow_redirects=False) as public:
        for path in ['', '/reconcile']:
            r = public.post(base + '/functions/v1/bsmart-feed' + path, json={})
            result['auth' + (path or '/feed')] = r.status_code
            if r.status_code != 401:
                raise RuntimeError('Missing function or invalid authentication boundary')
        private = public.get(base + f'/storage/v1/object/public/{BUCKET}/active.json')
        if private.is_success:
            raise RuntimeError('Private catalog is publicly exposed')
    with storage_client() as client:
        result['database'] = check(client.post('/rest/v1/rpc/bsmart_feed_status', json={})).json()
        bucket = check(client.get(f'/storage/v1/bucket/{BUCKET}')).json()
        if bucket.get('public'):
            raise RuntimeError('Catalog bucket is public')
        result['catalog'] = check(client.get(f'/storage/v1/object/authenticated/{BUCKET}/active.json')).json()
        r = client.get(f'/storage/v1/object/authenticated/{BUCKET}/worker-status.json')
        result['worker'] = check(r).json()
        checked_at = datetime.fromisoformat(result['worker']['checkedAt'].replace('Z', '+00:00'))
        result['workerAgeSeconds'] = round((datetime.now(UTC) - checked_at).total_seconds())
        result['ready'] = bool(result['database']['scheduled'] and result['catalog']['count'] > 0
                               and 0 <= result['workerAgeSeconds'] < 300 and result['worker']['failed'] == 0)
        if run_worker:
            result['queuedRequest'] = check(client.post('/rest/v1/rpc/bsmart_feed_run_worker', json={})).json()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reconcile', action='store_true')
    args = parser.parse_args()
    print(json.dumps(inspect(args.reconcile), indent=2))


if __name__ == '__main__':
    main()
