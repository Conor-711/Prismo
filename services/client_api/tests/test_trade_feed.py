from dataclasses import replace
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from services.client_api.opinion_trades.feed import TradeFeedRepository
from services.client_api.opinion_trades.feed_router import make_trade_feed_router
from services.client_api.read_models import FixtureReadModelRepository
from services.client_api.tests.test_opinion_trades import fill, register
from services.client_api.opinion_trades.repository import OpinionTradeRepository, TradeBase
from services.client_api.accounts.repository import AccountBase
from pathlib import Path


@pytest.fixture
def repo():
    value = OpinionTradeRepository('sqlite:///:memory:')
    value.engine.dispose()
    value.engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    value.sessions = sessionmaker(value.engine)
    AccountBase.metadata.create_all(value.engine)
    TradeBase.metadata.create_all(value.engine)  # Shared disposable in-memory HTTP test DB only.
    yield value
    value.engine.dispose()


@pytest.fixture
def setup(repo):
    catalog = FixtureReadModelRepository(Path(__file__).resolve().parents[3] / 'contracts/fixtures')
    feed = TradeFeedRepository(repo, catalog)
    authors = {a['id']: a for a in catalog.smart_accounts()}
    opinion = next(o for o in catalog.smart_account_updates()
                   if o['ticker'] == 'NVDA' and authors.get(o['authorId'], {}).get('platformPercentile', 1) <= .25)
    now = datetime.now(UTC)
    feed.register_opinion(UUID(opinion['id']), opinion['authorId'], now=now-timedelta(minutes=5))
    execution = fill(opinion_id=UUID(opinion['id']), traded_at=now-timedelta(minutes=1),
                     notional_usd=Decimal('40.25'), market_coin='xyz:NVDA')
    register(repo, execution)
    return repo, feed, execution


def test_only_separately_consented_verified_amounts_appear(setup):
    repo, feed, execution = setup
    repo.record_confirmed(execution)
    repo.update_public_profile(execution.account_id, nickname='Casey', avatar_url=None, visible=True)
    assert feed.page()['items'] == []  # Existing trader-list consent is insufficient.
    repo.update_public_profile(execution.account_id, nickname='Casey', avatar_url=None, visible=True, feed_visible=True)
    page = feed.page()
    row = page['items'][0]
    assert row['notionalUSD'] == '40.25'
    assert row['marketCoin'] == 'xyz:NVDA'
    assert row['trader']['nickname'] == 'Casey'
    assert str(execution.account_id) not in str(page)
    assert execution.fill_id not in str(page)
    assert execution.order_id not in str(page)
    public_id = UUID(row['trader']['id'])
    assert feed.profile(public_id)['nickname'] == 'Casey'
    repo.update_public_profile(execution.account_id, nickname='Casey', avatar_url=None, visible=True, feed_visible=False)
    assert feed.page()['items'] == []
    assert feed.profile(public_id) is None
    assert repo.page(execution.opinion_id)['totalTraders'] == 1


def test_partial_fills_aggregate_once_and_multiple_orders_remain_distinct(setup):
    repo, feed, execution = setup
    repo.update_public_profile(execution.account_id, nickname='Casey', avatar_url=None, visible=True, feed_visible=True)
    repo.record_confirmed(execution)
    old = feed.page()['items'][0]
    extra = replace(execution, fill_id=str(uuid4()), notional_usd=Decimal('59.75'),
                    traded_at=execution.traded_at+timedelta(seconds=2))
    repo.record_confirmed(extra)
    assert not repo.record_confirmed(extra)
    merged = feed.page()['items'][0]
    assert Decimal(merged['notionalUSD']) == 100
    assert (merged['id'], merged['executedAt']) == (old['id'], old['executedAt'])
    newer = replace(extra, fill_id=str(uuid4()), order_id=str(uuid4()), side='short')
    repo.record_confirmed(newer)
    first = feed.page(limit=1)
    assert first['items'][0]['side'] == 'short' and first['nextOffset'] == 1
    assert feed.page(offset=1, limit=1)['items'][0]['id'] == old['id']
    assert feed.page(offset=2)['items'] == []


def test_no_amount_no_context_and_retroactive_context_excluded(setup):
    repo, feed, execution = setup
    repo.update_public_profile(execution.account_id, nickname='Casey', avatar_url=None, visible=True, feed_visible=True)
    repo.record_confirmed(replace(execution, notional_usd=None, market_coin=None))
    repo.record_confirmed(replace(execution, fill_id=str(uuid4()), order_id=str(uuid4()), opinion_id=uuid4()))
    repo.record_confirmed(replace(execution, fill_id=str(uuid4()), order_id=str(uuid4()),
                                  traded_at=execution.traded_at-timedelta(days=1)))
    assert feed.page()['items'] == []


def test_profile_filter_withdrawal_and_account_deletion(setup):
    repo, feed, execution = setup
    other = replace(execution, fill_id=str(uuid4()), order_id=str(uuid4()), account_id=uuid4())
    register(repo, other)
    for item in (execution, other):
        repo.update_public_profile(item.account_id, nickname='Public', avatar_url=None, visible=True, feed_visible=True)
        repo.record_confirmed(item)
    page = feed.page()
    public_id = UUID(page['items'][0]['trader']['id'])
    assert len(feed.page(profile_id=public_id)['items']) == 1
    with repo.sessions.begin() as db:
        repo.delete_account_data(db, execution.account_id)
    assert len(feed.page()['items']) == 1
    feed.withdraw_opinion(execution.opinion_id)
    assert feed.page()['items'] == []


def test_rank_and_author_provenance_checked_from_catalog(setup):
    _, feed, execution = setup
    with pytest.raises(ValueError):
        feed.register_opinion(execution.opinion_id, 'invented-author')
    with pytest.raises(ValueError):
        feed.register_opinion(uuid4(), feed.read_models.smart_accounts()[0]['id'])
    catalog = feed.read_models
    author_id = next(o['authorId'] for o in catalog.smart_account_updates()
                     if o['id'] == str(execution.opinion_id))
    class LowRankCatalog:
        def smart_accounts(self):
            return [dict(a, platformPercentile=.5) for a in catalog.smart_accounts()]
    with pytest.raises(ValueError, match='Top 25%'):
        TradeFeedRepository(feed.ledger, LowRankCatalog()).register_opinion(execution.opinion_id, author_id)


def test_conflicting_order_and_amount_cannot_silently_change(setup):
    repo, _, execution = setup
    repo.record_confirmed(execution)
    for changes in ({'notional_usd': Decimal('50')}, {'side':'short'}, {'market_coin':'other:NVDA'}):
        with pytest.raises(ValueError):
            repo.record_confirmed(replace(execution, **changes))
    with pytest.raises(ValueError):
        repo.record_confirmed(replace(execution, fill_id=str(uuid4()), opinion_id=uuid4()))


def test_routes_fail_closed_and_require_auth():
    app = FastAPI()
    app.include_router(make_trade_feed_router(lambda: object(), None))
    with TestClient(app) as client:
        for path in ('/v1/trade-feed', f'/v1/public-traders/{uuid4()}'):
            response = client.get(path)
            assert response.status_code == 503 and response.headers['cache-control'] == 'no-store'
            assert client.post(path, json={'filled': True}).status_code == 405
        assert client.get('/v1/trade-feed?limit=100').status_code == 422
    def denied():
        raise HTTPException(401)
    app = FastAPI()
    app.include_router(make_trade_feed_router(denied, None))
    with TestClient(app) as client:
        assert client.get('/v1/trade-feed').status_code == 401


def test_http_feed_and_profile_reflect_revoked_consent(setup):
    repo, feed, execution = setup
    repo.record_confirmed(execution)
    repo.update_public_profile(execution.account_id, nickname='Casey', avatar_url=None, visible=True, feed_visible=True)
    app = FastAPI()
    app.include_router(make_trade_feed_router(lambda: object(), feed))
    with TestClient(app) as client:
        response = client.get('/v1/trade-feed')
        assert response.status_code == 200 and response.headers['cache-control'] == 'no-store'
        item = response.json()['items'][0]
        profile_id = item['trader']['id']
        assert item['opinion']['id'] == str(execution.opinion_id)
        assert client.get(f'/v1/public-traders/{profile_id}').json() == item['trader']
        assert len(client.get(f'/v1/trade-feed?profileId={profile_id}').json()['items']) == 1
        repo.update_public_profile(execution.account_id, nickname='Casey', avatar_url=None, visible=False)
        assert client.get('/v1/trade-feed').json()['items'] == []
        response = client.get(f'/v1/public-traders/{profile_id}')
        assert response.status_code == 404 and response.headers['cache-control'] == 'no-store'
