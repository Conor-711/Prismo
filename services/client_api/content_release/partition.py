"""Checked platform deltas; preserve history and every unrelated source."""
import hashlib
import json
from datetime import datetime, timedelta, timezone

from .contract import date, digest, validators
from ..smart_account_signals import build_portfolio_signals

NAMES = ('smart-accounts', 'smart-account-updates', 'smart-account-evidence')
PLATFORMS = {'youtube': 'YouTube', 'reddit': 'Reddit'}


def load_partition(directory):
    raw = (directory / 'platform-manifest.json').read_bytes()
    manifest = json.loads(raw)
    source = manifest.get('platform')
    if source not in PLATFORMS or manifest.get('status') != 'ready' or manifest.get('version') != 1:
        raise ValueError('Invalid platform release')
    if set(manifest.get('collections', {})) != set(NAMES) or manifest.get('crawlComplete') is not True:
        raise ValueError('Incomplete platform release')
    window_from, window_through = date(manifest['crawlFrom']), date(manifest['crawlThrough'])
    if window_from > window_through or window_through - window_from > timedelta(days=7):
        raise ValueError('Invalid crawl window')
    if window_through < datetime.now(timezone.utc) - timedelta(hours=12):
        raise ValueError('Crawl window is stale')
    if manifest.get('sourceThrough') and not window_from <= date(manifest['sourceThrough']) <= window_through:
        raise ValueError('Source date outside crawl window')
    collections = {}
    for name in NAMES:
        content = (directory / (name + '.json')).read_bytes()
        entry = manifest['collections'][name]
        items = json.loads(content)
        if hashlib.sha256(content).hexdigest() != entry['sha256'] or not isinstance(items, list) or len(items) != entry['count']:
            raise ValueError('Platform checksum/count mismatch')
        ids = set()
        for item in items:
            validators()[name].validate(item)
            if item['platform'] != PLATFORMS[source] or item['id'] in ids:
                raise ValueError('Mixed platform or duplicate identity')
            author = item['id'] if name == 'smart-accounts' else item['authorId']
            if not author.startswith(source + ':'):
                raise ValueError('Invalid platform author identity')
            ids.add(item['id'])
        collections[name] = items
    authors = {r['id'] for r in collections['smart-accounts']}
    if not authors or any(r['authorId'] not in authors for n in NAMES[1:] for r in collections[n]):
        raise ValueError('Missing platform authors')
    collections['portfolio-signals'] = build_portfolio_signals(collections['smart-account-updates'])
    return collections, manifest, digest({'manifest': manifest, 'collections': collections})


def merge_partition(collections, metadata, incoming, source):
    now = datetime.now(timezone.utc)
    checked = date(source['asOf'])
    if checked < now - timedelta(hours=6):
        raise ValueError('Platform collection check is stale')
    if source.get('sourceThrough'):
        date(source['sourceThrough'])  # No posts is valid; never invent a recent publication date.
    updated, timestamps = dict(collections), dict(metadata)
    for name, items in incoming.items():
        existing = {row['id']: row for row in collections[name]}
        # IDs may only overwrite rows from this source (signals have no platform field).
        for row in items:
            old = existing.get(row['id'])
            if old and name != 'portfolio-signals' and old.get('platform') != PLATFORMS[source['platform']]:
                raise ValueError('Cross-platform identity collision')
            existing[row['id']] = row
        updated[name] = list(existing.values())
        field = 'occurredAt' if name == 'portfolio-signals' else 'publishedAt'
        dates = [date(row[field]) for row in updated[name] if row.get(field)]
        timestamps[name] = {'checkedAt': max(date(metadata[name]['checkedAt']), checked).isoformat(),
                            'latestContentAt': max(dates).isoformat() if dates else metadata[name].get('latestContentAt')}
    return updated, timestamps
