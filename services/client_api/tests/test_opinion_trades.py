from dataclasses import replace
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from uuid import uuid4

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from services.client_api.opinion_trades.repository import ConfirmedOpinionFill, OpinionTradeRepository, TradeBase
from services.client_api.opinion_trades.router import make_opinion_trade_router
from services.client_api.accounts.repository import AccountBase, AccountRecord, ProviderSubjectRecord
from services.client_api.accounts.security_event_models import subject_key


@pytest.fixture
def repo():
    value = OpinionTradeRepository("sqlite:///:memory:")
    AccountBase.metadata.create_all(value.engine)
    TradeBase.metadata.create_all(value.engine)  # Disposable in-memory test DB only.
    yield value
    value.engine.dispose()


def fill(**changes):
    value = ConfirmedOpinionFill("hyperliquid", str(uuid4()), uuid4(), uuid4(), str(uuid4()),
                                 "NVDA", "long", datetime.now(UTC) - timedelta(seconds=10),
                                 Decimal("1"), True, True)
    return replace(value, **changes)


def register(repo, *items):
    with repo.sessions.begin() as db:
        for identifier in {str(item.account_id) for item in items}:
            db.add(AccountRecord(id=identifier, provider="google", subject=identifier, created_at=datetime.now(UTC)))
            db.add(ProviderSubjectRecord(id=subject_key("google", identifier), provider="google", state="active"))


def test_unique_people_latest_direction_order_and_privacy(repo):
    first = fill()
    second = fill(opinion_id=first.opinion_id, traded_at=first.traded_at - timedelta(days=1))
    private = fill(opinion_id=first.opinion_id)
    register(repo, first, second, private)
    for item in (first, second, private):
        assert repo.record_confirmed(item)
    repo.update_public_profile(first.account_id, nickname="Casey", avatar_url=None, visible=True)
    repo.update_public_profile(second.account_id, nickname="Morgan", avatar_url=None, visible=True)
    repo.record_confirmed(replace(first, fill_id=str(uuid4()), order_id=str(uuid4()), side="short",
                                  traded_at=first.traded_at + timedelta(seconds=1)))
    page = repo.page(first.opinion_id, limit=1)
    assert (page["totalTraders"], page["publicTraders"], page["nextOffset"]) == (3, 2, 1)
    assert page["traders"][0]["nickname"] == "Casey"
    assert page["traders"][0]["side"] == "short"
    assert set(page["traders"][0]) == {"id", "nickname", "avatarURL", "side", "tradedAt"}
    assert str(first.account_id) not in str(page)
    assert repo.page(first.opinion_id, offset=1, limit=1)["traders"][0]["nickname"] == "Morgan"
    assert repo.page(uuid4())["totalTraders"] == 0
    repo.update_public_profile(first.account_id, nickname="Casey", avatar_url=None, visible=False)
    page = repo.page(first.opinion_id)
    assert page["totalTraders"] == 3
    assert page["publicTraders"] == 1
    assert all(row["nickname"] != "Casey" for row in page["traders"])


def test_idempotent_fill_and_conflict_rejected(repo):
    item = fill()
    register(repo, item)
    assert repo.record_confirmed(item)
    assert not repo.record_confirmed(item)
    for changes in ({"opinion_id": uuid4()}, {"account_id": uuid4()}, {"side": "short"}):
        with pytest.raises(ValueError):
            repo.record_confirmed(replace(item, **changes))
    assert repo.page(item.opinion_id)["totalTraders"] == 1


@pytest.mark.parametrize("changes", [
    {"venue": "paper"}, {"mainnet": False}, {"final": False},
    {"quantity": Decimal(0)}, {"quantity": Decimal("NaN")}, {"side": "buy"},
    {"traded_at": datetime.now(UTC) + timedelta(days=1)},
])
def test_ineligible_execution_never_counts(repo, changes):
    item = fill(**changes)
    with pytest.raises(ValueError):
        repo.record_confirmed(item)
    assert repo.page(item.opinion_id)["totalTraders"] == 0


def test_private_by_default_and_unapproved_avatar_rejected(repo):
    item = fill()
    register(repo, item)
    repo.record_confirmed(item)
    assert repo.page(item.opinion_id)["traders"] == []
    with pytest.raises(ValueError):
        repo.update_public_profile(item.account_id, nickname="Casey", avatar_url="http://127.0.0.1/a", visible=True)
    assert repo.page(item.opinion_id)["publicTraders"] == 0


def test_source_off_returns_unavailable_not_zero():
    app = FastAPI()
    app.include_router(make_opinion_trade_router(lambda: object(), None))
    with TestClient(app) as client:
        response = client.get(f"/v1/opinions/{uuid4()}/traders")
        assert response.status_code == 503
        assert response.headers["cache-control"] == "no-store"
        assert "totalTraders" not in response.json()
        assert client.post(f"/v1/opinions/{uuid4()}/traders", json={"filled": True}).status_code == 405


def test_read_requires_authentication():
    def denied():
        raise HTTPException(401)
    app = FastAPI()
    app.include_router(make_opinion_trade_router(denied, None))
    with TestClient(app) as client:
        assert client.get(f"/v1/opinions/{uuid4()}/traders").status_code == 401
