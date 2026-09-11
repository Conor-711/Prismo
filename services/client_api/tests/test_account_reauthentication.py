import asyncio
from datetime import UTC, datetime
from uuid import uuid4

import httpx
import pytest
from pydantic import ValidationError
from sqlalchemy import func, select

from services.client_api.accounts.apple_repository import AppleGrantRepository
from services.client_api.accounts.models import SessionInput
from services.client_api.accounts.oidc import OIDCVerifier, VerifiedIdentity
from services.client_api.accounts.repository import AccountRecord, ChallengeRejected
from services.client_api.tests.apple_test_support import REFRESH, apple_settings
from services.client_api.tests.deletion_test_support import accounts, login, accept
from services.client_api.tests.test_account_deletion_http import application, register


def reauthenticate(accounts, installation, expected, provider="google", subject="disposable-owner"):
    identity = VerifiedIdentity(provider, subject, datetime.now(UTC))
    challenge = accounts.challenge(installation, provider)
    if provider == "apple":
        settings = apple_settings()
        grants = AppleGrantRepository(accounts)
        claim = grants.claim(challenge.id, installation, identity, settings.client_id)
        return grants.finish(claim, REFRESH, settings.cipher, expected)
    return accounts.issue(challenge.id, installation, identity, expected)


@pytest.mark.parametrize("provider", ["google", "apple"])
def test_reauthentication_reuses_only_matching_existing_account(accounts, provider):
    installation, original = login(accounts, provider=provider)
    refreshed = reauthenticate(accounts, installation, original.account.id, provider)
    assert refreshed.account == original.account
    assert accounts.authenticate(original.accessToken) is None
    assert accounts.authenticate(refreshed.accessToken) == original.account
    with accounts.sessions() as db:
        assert db.scalar(select(func.count()).select_from(AccountRecord)) == 1


@pytest.mark.parametrize("provider", ["google", "apple"])
def test_unknown_id_or_wrong_provider_subject_never_creates_or_replaces_account(accounts, provider):
    installation, original = login(accounts, provider=provider)
    for expected, subject in [(uuid4(), "disposable-owner"), (original.account.id, "different-user")]:
        with pytest.raises(ChallengeRejected):
            reauthenticate(accounts, installation, expected, provider, subject)
    assert accounts.authenticate(original.accessToken) == original.account
    with accounts.sessions() as db:
        assert db.scalar(select(func.count()).select_from(AccountRecord)) == 1


@pytest.mark.parametrize("provider", ["google", "apple"])
def test_pending_and_deleted_account_cannot_be_recreated_by_reauthentication(accounts, provider):
    settings = apple_settings() if provider == "apple" else None
    installation, original = login(accounts, provider=provider, settings=settings)
    work, request, _ = accept(accounts, original, settings=settings)
    with pytest.raises(ChallengeRejected):
        reauthenticate(accounts, installation, original.account.id, provider)
    lease = work.claim(request.id)
    work.complete(lease)
    with pytest.raises(ChallengeRejected):
        reauthenticate(accounts, installation, original.account.id, provider)
    with accounts.sessions() as db:
        assert db.scalar(select(func.count()).select_from(AccountRecord)) == 0


def test_expected_account_is_optional_but_null_or_invalid_is_rejected():
    body = dict(challengeId=uuid4(), provider="google", idToken="disposable-id" * 8)
    assert SessionInput(**body).expectedAccountId is None
    for value in [None, "bad", 123, ""]:
        with pytest.raises(ValidationError):
            SessionInput(**body, expectedAccountId=value)


def test_http_forwards_existing_identity_constraint_without_exposing_existence(accounts, monkeypatch):
    app = application(accounts, monkeypatch)
    installation, original = login(accounts)

    async def verify(*_):
        return VerifiedIdentity("google", "disposable-owner", datetime.now(UTC))
    monkeypatch.setattr(OIDCVerifier, "verify", verify)

    async def check():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
                auth = await register(client, installation)
                for expected, status in [(uuid4(), 401), (original.account.id, 200)]:
                    challenge = await client.post("/v1/auth/challenges", headers=auth, json={"provider": "google"})
                    response = await client.post("/v1/auth/sessions", headers=auth, json={
                        "provider": "google", "idToken": "disposable-id" * 8,
                        "challengeId": challenge.json()["id"], "expectedAccountId": str(expected)})
                    assert response.status_code == status
                    assert response.headers["cache-control"] == "no-store"
                    if status == 200:
                        assert response.json()["account"]["id"] == str(original.account.id)
                    else:
                        assert str(expected) not in response.text
    asyncio.run(check())
