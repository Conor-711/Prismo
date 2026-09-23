import json
import plistlib
from datetime import datetime
from pathlib import Path

import pytest
import httpx

from services.client_api.opinion_trades.publish_catalog import build_catalog, publish, sync_active_content
from services.client_api.opinion_trades.publish_catalog import upload_object, retain_previous_catalog, request_with_retry


def test_representative_chart_nodes_are_in_catalog_without_inventing_original_text(tmp_path):
    write_source(tmp_path)
    author = {'id': 'author', 'name': 'Author', 'platform': 'X', 'score': 999, 'platformPercentile': .01}
    call = {'id': '00000000-0000-4000-8000-000000000456', 'publishedAt': datetime(2026, 1, 1),
            'direction': 'bullish', 'summary': 'Memory demand supports SNDK.',
            'sourceURL': {'relative': 'https://x.com/author/status/456'}}
    path = tmp_path / 'stories.plist'
    path.write_bytes(plistlib.dumps({'formatVersion': 2, 'stories': [
        {'account': author, 'ticker': 'SNDK', 'calls': [call, call]}]}))
    _, items, skipped = build_catalog(tmp_path, path)
    assert len(items) == 2 and not skipped
    result = json.loads(items[call['id']])
    assert result['ticker'] == 'SNDK' and result['sourcePostId'] == '456'
    assert result['score'] == 105 and result['platformPercentile'] == .8
    assert 'originalText' not in result


def test_new_release_retains_old_app_opinions(tmp_path):
    old_id = '00000000-0000-4000-8000-000000000789'
    old = json.dumps({'id': old_id}).encode()
    def handle(req):
        if req.url.path.endswith('/active.json'):
            return httpx.Response(200, json={'release': 'a' * 64})
        if '/list/' in req.url.path:
            return httpx.Response(200, json=[{'name': old_id + '.json'}])
        return httpx.Response(200, content=old)
    with httpx.Client(base_url='https://example.com', transport=httpx.MockTransport(handle)) as client:
        items = {'new': b'{}'}
        assert retain_previous_catalog(client, items) == 1
        assert items[old_id] == old and items['new'] == b'{}'


def test_old_catalog_permission_error_must_not_activate_an_incomplete_release():
    with httpx.Client(base_url='https://example.com', transport=httpx.MockTransport(
            lambda _: httpx.Response(400, json={'statusCode': '403'}))) as client:
        with pytest.raises(RuntimeError):
            retain_previous_catalog(client, {})


def write_source(root: Path, percentile=.8, url='https://x.com/author/status/123'):
    author = {'id': 'author', 'name': 'Author', 'platformPercentile': percentile, 'platform': 'X', 'score': 105}
    opinion = {'id': '00000000-0000-4000-8000-000000000123', 'authorId': 'author',
               'platform': 'X', 'ticker': 'NVDA', 'publishedAt': '2026-01-01T00:00:00Z',
               'sourcePostId': '123', 'sourceURL': url, 'originalText': 'a' * 2000}
    for name, items in [('smart-accounts', [author]), ('smart-account-evidence', [opinion]), ('smart-account-updates', [])]:
        (root / f'{name}.json').write_text(json.dumps(items))


def test_catalog_includes_non_top_quartile_opinions_but_uses_authoritative_rank(tmp_path):
    write_source(tmp_path)
    release, items, skipped = build_catalog(tmp_path)
    assert len(release) == 64 and len(items) == 1 and not skipped
    opinion = json.loads(next(iter(items.values())))
    assert opinion['platformPercentile'] == .8 and opinion['score'] == 105
    assert len(opinion['originalText']) == 1500
    assert build_catalog(tmp_path)[0] == release


def test_catalog_builds_from_active_collections_without_mutating_them(tmp_path):
    write_source(tmp_path)
    collections = {name: json.loads((tmp_path / f'{name}.json').read_text()) for name in (
        'smart-accounts', 'smart-account-evidence', 'smart-account-updates')}
    original_author_count = len(collections['smart-accounts'])
    release, items, skipped = build_catalog(collections)
    assert len(release) == 64 and not skipped
    assert '00000000-0000-4000-8000-000000000123' in items
    assert len(collections['smart-accounts']) == original_author_count


def test_sync_uses_active_content_revision(monkeypatch, tmp_path):
    from sqlalchemy import create_engine
    from sqlalchemy.orm import Session
    from services.client_api.content_release.models import Base, Active, Release, Page

    engine = create_engine(f'sqlite:///{tmp_path / "content.db"}')
    Base.metadata.create_all(engine)
    write_source(tmp_path)
    with Session(engine) as session, session.begin():
        session.add(Release(revision='current', manifest={'collections': {}}, provenance={}))
        session.add(Active(channel='production', revision='current'))
        for name in ('smart-accounts', 'smart-account-evidence', 'smart-account-updates'):
            items = json.loads((tmp_path / f'{name}.json').read_text())
            session.add(Page(revision='current', collection=name, owner='_', page=0,
                             payload={'revision': 'current', 'page': 0, 'items': items}))
    seen = {}
    def fake_publish(collections, version, apply, stories):
        seen.update(version=version, apply=apply, opinion=collections['smart-account-evidence'][0]['id'])
        return {'status': 'ready'}
    monkeypatch.setattr('services.client_api.opinion_trades.publish_catalog.publish', fake_publish)
    report = sync_active_content(engine, apply=False)
    assert report['contentRevision'] == 'current'
    assert seen == {'version': 'content:current', 'apply': False,
                    'opinion': '00000000-0000-4000-8000-000000000123'}
    engine.dispose()


def test_catalog_retry_skips_upload_for_same_content_revision(tmp_path, monkeypatch):
    write_source(tmp_path)
    version = 'content:' + 'a' * 64
    requests = []
    def handle(request):
        requests.append((request.method, request.url.path))
        if request.url.path == '/storage/v1/bucket':
            return httpx.Response(200, json=[{'id': 'bsmart-feed-catalog', 'public': False}])
        if request.url.path.endswith('/active.json'):
            return httpx.Response(200, json={'schema': 1, 'release': 'b' * 64,
                                              'sourceVersion': version, 'count': 7})
        return httpx.Response(500)
    client = httpx.Client(base_url='https://example.com', transport=httpx.MockTransport(handle))
    monkeypatch.setattr('services.client_api.opinion_trades.publish_catalog.storage_client', lambda: client)
    report = publish(tmp_path, version, True)
    assert report['status'] == 'already-published' and report['opinions'] == 7
    assert requests == [('GET', '/storage/v1/bucket'),
                        ('GET', '/storage/v1/object/bsmart-feed-catalog/active.json')]
    client.close()


def test_media_only_revision_reuses_identical_catalog_objects(tmp_path, monkeypatch):
    write_source(tmp_path)
    release = build_catalog(tmp_path)[0]
    seen = []

    def handle(request):
        seen.append((request.method, request.url.path))
        if request.url.path == '/storage/v1/bucket':
            return httpx.Response(200, json=[{'id': 'bsmart-feed-catalog', 'public': False}])
        if request.url.path.endswith('/active.json'):
            if request.method == 'GET':
                return httpx.Response(200, json={'schema': 1, 'release': release,
                                                  'sourceVersion': 'content:old', 'count': 1})
            return httpx.Response(200)
        if '/list/' in request.url.path:
            return httpx.Response(200, json=[])
        return httpx.Response(500)

    client = httpx.Client(base_url='https://example.com', transport=httpx.MockTransport(handle))
    monkeypatch.setattr('services.client_api.opinion_trades.publish_catalog.storage_client', lambda: client)
    result = publish(tmp_path, 'content:new', True)
    assert result['status'] == 'published' and result['release'] == release
    assert not any(path.endswith('.json') and path != '/storage/v1/object/bsmart-feed-catalog/active.json'
                   for method, path in seen if method == 'POST')


def test_catalog_read_retries_transient_transport_error(monkeypatch):
    monkeypatch.setattr('services.client_api.opinion_trades.publish_catalog.time.sleep', lambda _: None)
    attempts = 0

    def handle(request):
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise httpx.ReadError('temporary disconnect')
        return httpx.Response(200, json={})

    with httpx.Client(base_url='https://example.com', transport=httpx.MockTransport(handle)) as client:
        assert request_with_retry(client, 'GET', '/storage/v1/bucket').status_code == 200
    assert attempts == 2


@pytest.mark.parametrize('url', ['https://example.com/fake', 'https://x.com.evil.test/status/123', 'http://x.com/status/123'])
def test_catalog_refuses_missing_public_provenance(tmp_path, url):
    write_source(tmp_path, url=url)
    with pytest.raises(ValueError, match='No eligible real opinions'):
        build_catalog(tmp_path)


def test_money_catalog_requires_reviewed_account_and_keeps_source_out_of_social_ranking(tmp_path):
    write_source(tmp_path)
    address = '0x' + 'ab' * 20
    money = {'id': address, 'address': address, 'source': 'hyperdash'}
    movement = {'id': '00000000-0000-4000-8000-000000000456', 'accountId': address,
                'ticker': 'NVDA', 'market': 'xyz:NVDA', 'observedAt': '2026-01-01T00:00:00Z',
                'evidenceURL': f'https://hyperdash.com/trader/{address}'}
    (tmp_path / 'smart-money.json').write_text(json.dumps([money]))
    path = tmp_path / 'smart-money-movements.json'
    path.write_text(json.dumps([movement]))
    _, items, _ = build_catalog(tmp_path)
    result = json.loads(items[movement['id']])
    assert result['sourceKind'] == 'money' and result['authorId'] == address
    assert result['marketCoin'] == 'xyz:NVDA' and 'platformPercentile' not in result
    for patch in [{'accountId': 'unknown'}, {'evidenceURL': 'https://hyperdash.com/trader/other'},
                  {'observedAt': '2099-01-01T00:00:00Z'}]:
        path.write_text(json.dumps([{**movement, **patch}]))
        assert movement['id'] not in build_catalog(tmp_path)[1]


def test_catalog_object_retries_identical_bytes_but_not_permission_errors(monkeypatch):
    monkeypatch.setattr('services.client_api.opinion_trades.publish_catalog.time.sleep', lambda _: None)
    seen = []
    def handle(request):
        seen.append(request.content)
        return httpx.Response(503 if len(seen) == 1 else 200)
    with httpx.Client(base_url='https://example.com', transport=httpx.MockTransport(handle)) as client:
        upload_object(client, '/immutable/source.json', b'{}')
    assert seen == [b'{}', b'{}']
    seen.clear()
    def deny(request):
        seen.append(request.content)
        return httpx.Response(403)
    with httpx.Client(base_url='https://example.com', transport=httpx.MockTransport(deny)) as client:
        with pytest.raises(RuntimeError, match='HTTP 403'):
            upload_object(client, '/immutable/source.json', b'{}')
    assert len(seen) == 1
