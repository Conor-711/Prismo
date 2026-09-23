"""Publish reviewed, real opinion snapshots to private Supabase Storage; never DDL."""
from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
import hashlib
import json
import plistlib
from pathlib import Path
import subprocess
import time
from urllib.parse import urlparse
from uuid import UUID

import httpx

from services.client_api.opinion_trades.context import resolve_context
from services.client_api.opinion_trades.money_catalog import money_sources

PROJECT = 'dzyitinagewdfkzjkuiz'
BUCKET = 'bsmart-feed-catalog'
SOURCE_HOSTS = {'x.com', 'twitter.com', 'youtube.com', 'youtu.be', 'reddit.com', 'xueqiu.com', 'tossinvest.com'}


class Snapshot:
    def __init__(self, root: Path | dict):
        def collection(name):
            return list(root[name]) if isinstance(root, dict) else json.loads((root / f'{name}.json').read_text())
        self.authors = collection('smart-accounts')
        self.evidence = collection('smart-account-evidence')
        self.updates = collection('smart-account-updates')

    def smart_accounts(self):
        return self.authors

    def smart_account_evidence(self, author_id):
        return [o for o in self.evidence if o.get('authorId') == author_id]

    def smart_account_updates(self):
        return self.updates


def representative_opinions(path: Path, authors: list[dict]):
    bundle = plistlib.loads(path.read_bytes())
    if bundle.get('formatVersion') != 2:
        raise ValueError('unsupported_representative_bundle')
    by_id = {a['id']: a for a in authors}
    for story in bundle['stories']:
        author = by_id.get(story['account']['id'])
        if author is None:
            author = story['account']
            authors.append(author)
            by_id[author['id']] = author
        if author['platform'] != story['account']['platform']:
            raise ValueError('unknown_representative_author')
        for call in story['calls']:
            url = call['sourceURL']['relative']
            published = call['publishedAt'].replace(tzinfo=UTC).isoformat()
            yield {'id': str(UUID(call['id'])), 'authorId': author['id'], 'authorName': author['name'],
                   'ticker': story['ticker'], 'companyName': story['ticker'], 'platform': author['platform'],
                   'publishedAt': published, 'direction': call['direction'], 'lifecycle': 'new',
                   'horizon': call.get('horizon', 'unknown'), 'thesis': call.get('summary', ''),
                   'sourceURL': url, 'evidenceURL': url, 'sourcePostId': urlparse(url).path.rstrip('/').split('/')[-1]}


def catalog_digest(opinions):
    digest = hashlib.sha256()
    for key, body in sorted(opinions.items()):
        digest.update(key.encode()); digest.update(body)
    return digest.hexdigest()


def build_catalog(root: Path | dict, representative_stories: Path | None = None):
    source = Snapshot(root)
    if representative_stories is not None:
        existing = {str(UUID(o['id'])) for o in source.evidence + source.updates}
        for item in representative_opinions(representative_stories, source.authors):
            if item['id'] not in existing:
                source.evidence.append(item)
                existing.add(item['id'])
    opinions, skipped = {}, Counter()
    for item in source.evidence + source.updates:
        try:
            source_url = item.get('sourceURL') or item.get('evidenceURL') or ''
            url = urlparse(source_url)
            if url.scheme != 'https' or url.username or not any(
                url.hostname == host or (url.hostname or '').endswith('.' + host) for host in SOURCE_HOSTS
            ) or not item.get('sourcePostId'):
                raise ValueError('missing_public_provenance')
            result = resolve_context(source, UUID(item['id']), item['authorId'], require_top_quartile=False)
            body = json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
            if len(body) > 65536:
                raise ValueError('oversize_opinion')
            opinions[str(UUID(item['id']))] = body
        except (ValueError, KeyError, TypeError) as error:
            skipped[str(error)] += 1
    for item in money_sources(root):
        key = item['id']
        if key in opinions:
            raise ValueError('source_uuid_collision')
        opinions[key] = json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    if not opinions:
        raise ValueError('No eligible real opinions; refusing empty publication')
    return catalog_digest(opinions), opinions, dict(skipped)


def service_key():
    result = subprocess.run(['supabase', 'projects', 'api-keys', '--project-ref', PROJECT, '-o', 'json'],
                            capture_output=True, text=True, check=True)
    keys = json.loads(result.stdout)
    return next(k['api_key'] for k in keys if k['name'] == 'service_role')


def storage_client():
    key = service_key()
    return httpx.Client(base_url=f'https://{PROJECT}.supabase.co', timeout=30, follow_redirects=False,
                        headers={'apikey': key, 'Authorization': f'Bearer {key}'})


def check(response):
    if not response.is_success:
        # Never include credentials or full server responses in operator logs.
        raise RuntimeError(f'Supabase operation failed: HTTP {response.status_code}, path={response.request.url.path}')
    return response


def request_with_retry(client, method, path, **kwargs):
    for attempt in range(3):
        try:
            response = client.request(method, path, **kwargs)
            if response.status_code not in (429, 500, 502, 503, 504) or attempt == 2:
                return response
        except httpx.TransportError:
            if attempt == 2:
                raise RuntimeError('Catalog storage request unavailable') from None
        time.sleep(0.5 * (2 ** attempt))


def upload_object(client, path, body):
    # Content-addressed release objects are safe to retry with identical bytes.
    for attempt in range(3):
        try:
            response = client.post(path, content=body, headers={'Content-Type': 'application/json', 'x-upsert': 'true'})
            if response.status_code not in (429, 500, 502, 503, 504) or attempt == 2:
                return check(response)
        except httpx.TransportError:
            if attempt == 2:
                raise RuntimeError('Catalog object upload unavailable') from None
        time.sleep(0.5 * (2 ** attempt))


def retain_previous_catalog(client, opinions):
    response = request_with_retry(client, 'GET', f'/storage/v1/object/{BUCKET}/active.json')
    if response.status_code in (400, 404) and str(response.json().get('statusCode')) == '404':
        return 0
    manifest = check(response).json()
    previous = manifest['release']
    if len(previous) != 64 or any(c not in '0123456789abcdef' for c in previous):
        raise ValueError('invalid_previous_catalog')
    offset, missing = 0, []
    while True:
        rows = check(request_with_retry(client, 'POST', f'/storage/v1/object/list/{BUCKET}', json={
            'prefix': previous + '/', 'offset': offset, 'limit': 1000,
            'sortBy': {'column': 'name', 'order': 'asc'}})).json()
        for row in rows:
            key = str(UUID(row['name'].removesuffix('.json')))
            if key not in opinions:
                missing.append(key)
        if len(rows) < 1000:
            break
        offset += len(rows)
    def download(key):
        data = check(request_with_retry(client, 'GET', f'/storage/v1/object/{BUCKET}/{previous}/{key}.json')).content
        if len(data) > 65536 or str(UUID(json.loads(data)['id'])) != key:
            raise ValueError('invalid_previous_opinion')
        return key, data
    with ThreadPoolExecutor(max_workers=6) as pool:
        opinions.update(pool.map(download, missing))
    return len(missing)


def publish(root: Path | dict, version: str, apply: bool, representative_stories: Path | None = None):
    release, opinions, skipped = build_catalog(root, representative_stories)
    tickers = sorted({json.loads(body)['ticker'] for body in opinions.values()})
    report = {'release': release, 'opinions': len(opinions), 'tickers': tickers, 'skipped': skipped,
              'sourceVersion': version, 'status': 'ready'}
    if not apply:
        return report
    with storage_client() as client:
        buckets = check(request_with_retry(client, 'GET', '/storage/v1/bucket')).json()
        bucket = next((b for b in buckets if b['id'] == BUCKET), None)
        if bucket is None:
            check(client.post('/storage/v1/bucket', json={'id': BUCKET, 'name': BUCKET, 'public': False,
                                                        'file_size_limit': 65536, 'allowed_mime_types': ['application/json']}))
        elif bucket.get('public'):
            raise RuntimeError('Catalog bucket must be private')

        if version.startswith('content:'):
            active = request_with_retry(client, 'GET', f'/storage/v1/object/{BUCKET}/active.json')
            if active.is_success:
                manifest = active.json()
                if (manifest.get('schema') == 1 and manifest.get('sourceVersion') == version
                        and isinstance(manifest.get('count'), int)
                        and isinstance(manifest.get('release'), str)
                        and len(manifest['release']) == 64
                        and all(c in '0123456789abcdef' for c in manifest['release'])):
                    report.update(status='already-published', release=manifest['release'],
                                  opinions=manifest['count'])
                    return report
            elif active.status_code not in (400, 404):
                check(active)

        retained = retain_previous_catalog(client, opinions)
        release = catalog_digest(opinions)
        report.update(release=release, opinions=len(opinions), retained=retained)
        previous = check(request_with_retry(client, 'GET', f'/storage/v1/object/{BUCKET}/active.json')).json()
        if previous.get('release') != release:
            def upload(entry):
                key, body = entry
                path = f'/storage/v1/object/{BUCKET}/{release}/{key}.json'
                upload_object(client, path, body)

            with ThreadPoolExecutor(max_workers=6) as pool:
                list(pool.map(upload, opinions.items()))
        # Activate only after every immutable opinion object is available.
        manifest = {'schema': 1, 'release': release, 'sourceVersion': version,
                    'publishedAt': datetime.now(UTC).isoformat(), 'count': len(opinions)}
        check(request_with_retry(client, 'POST', f'/storage/v1/object/{BUCKET}/active.json',
                                 json=manifest, headers={'x-upsert': 'true'}))
        report['status'] = 'published'
    return report


def sync_active_content(engine, *, apply: bool = False):
    from sqlalchemy.orm import Session
    from services.client_api.content_release.models import Active
    from services.client_api.content_release.publisher import read_collections

    with Session(engine) as session:
        active = session.get(Active, 'production')
        if active is None:
            raise ValueError('No active content release')
        revision = active.revision
        collections = read_collections(session, revision)
    if apply:
        with Session(engine) as session:
            if session.get(Active, 'production').revision != revision:
                raise RuntimeError('Content changed during catalog preparation; retry the current revision')
    stories = Path(__file__).resolve().parents[3] / 'ios/BSmart/Resources/representative-stories.plist'
    report = publish(collections, f'content:{revision}', apply, stories)
    if apply:
        with Session(engine) as session:
            if session.get(Active, 'production').revision != revision:
                raise RuntimeError('Content changed during catalog publication; retry the current revision')
    report['contentRevision'] = revision
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--source-dir', type=Path)
    source.add_argument('--active-content', action='store_true')
    parser.add_argument('--source-version')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--representative-stories', type=Path,
                        default=Path(__file__).resolve().parents[3] / 'ios/BSmart/Resources/representative-stories.plist')
    args = parser.parse_args()
    if args.active_content:
        from sqlalchemy import create_engine
        from services.client_api.config import normalize_database_url
        from services.client_api.content_release.__main__ import publication_database_url
        url = publication_database_url()
        if not url.startswith(('postgresql', 'postgres://')):
            parser.error('Set protected BSMART_CONTENT_DATABASE_URL')
        engine = create_engine(normalize_database_url(url), pool_pre_ping=True,
                               connect_args={'connect_timeout': 10, 'prepare_threshold': None,
                                             'options': '-c statement_timeout=30000'})
        try:
            report = sync_active_content(engine, apply=args.apply)
        finally:
            engine.dispose()
    else:
        if not args.source_version:
            parser.error('--source-version is required with --source-dir')
        report = publish(args.source_dir, args.source_version, args.apply, args.representative_stories)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
