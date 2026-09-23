from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import uuid4

import pytest

from services.client_api.opinion_trades.context import make_feed_context_router, resolve_context
from fastapi import FastAPI
from fastapi.testclient import TestClient


def catalog(percentile=.1, **changes):
    key = uuid4()
    opinion = dict(id=str(key), authorId='author', ticker='NVDA', platform='x',
                   publishedAt=datetime.now(UTC).isoformat(), originalText='x' * 2000)
    opinion.update(changes)
    return key, SimpleNamespace(
        smart_accounts=lambda: [dict(id='author', platform='x', platformPercentile=percentile, score=110)],
        smart_account_evidence=lambda _: [opinion], smart_account_updates=lambda: [])


def test_context_uses_server_author_rank_and_bounded_excerpt():
    key, models = catalog()
    result = resolve_context(models, key, 'author')
    assert result['score'] == 110 and result['platformPercentile'] == .1
    assert len(result['originalText']) == 1500


@pytest.mark.parametrize('rank', [None, True, float('nan'), .26, -.1])
def test_ineligible_ranks_rejected(rank):
    key, models = catalog(rank)
    with pytest.raises(ValueError):
        resolve_context(models, key, 'author')


def test_wrong_author_and_future_opinions_rejected():
    key, models = catalog(publishedAt=(datetime.now(UTC) + timedelta(days=1)).isoformat())
    with pytest.raises(ValueError):
        resolve_context(models, key, 'author')
    key, models = catalog()
    with pytest.raises(ValueError):
        resolve_context(models, key, 'different-author')


def test_catalog_requires_dedicated_service_secret(monkeypatch):
    key, models = catalog()
    app = FastAPI()
    app.include_router(make_feed_context_router(models))
    client = TestClient(app)
    url = f'/v1/opinions/{key}/feed-context?authorId=author'
    monkeypatch.delenv('BSMART_FEED_CATALOG_TOKEN', raising=False)
    assert client.get(url).status_code == 503
    monkeypatch.setenv('BSMART_FEED_CATALOG_TOKEN', 'disposable-test-catalog-secret-12345')
    assert client.get(url).status_code == 401
    assert client.get(url, headers={'Authorization': 'Bearer user-session'}).status_code == 401
    response = client.get(url, headers={'Authorization': 'Bearer disposable-test-catalog-secret-12345'})
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
