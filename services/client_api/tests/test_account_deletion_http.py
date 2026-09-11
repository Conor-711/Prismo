import asyncio
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx
from sqlalchemy import update
from sqlalchemy.exc import OperationalError

from services.client_api.accounts.apple_revocation import AppleTokenRevocation
from services.client_api.accounts.deletion_repository import DeletionRecord
from services.client_api.accounts.deletion_work import AccountDeletionWorkRepository
from services.client_api.accounts.oidc import IdentityUnavailable
from services.client_api.config import ClientAPISettings, REPO_ROOT
from services.client_api.main import create_app
from services.client_api.tests.apple_test_support import configure_apple_files
from services.client_api.tests.deletion_test_support import accounts, login, payload


def application(accounts, monkeypatch):
    monkeypatch.setenv("BSMART_ACCOUNT_AUTH_DEVELOPMENT", "1")
    monkeypatch.setenv("BSMART_GOOGLE_SERVER_CLIENT_ID", "server.google")
    monkeypatch.setenv("BSMART_GOOGLE_IOS_CLIENT_ID", "ios.google")
    return create_app(ClientAPISettings(environment="test", database_url=str(accounts.engine.url),
        read_model_mode="fixture", fixture_root=REPO_ROOT / "contracts/fixtures"))


async def register(client, installation):
    result = await client.post("/v1/installations", json={"installationId": str(installation),
        "platform": "ios", "appVersion": "1.0", "locale": "en_US", "timeZone": "UTC"})
    assert result.status_code == 201
    return {"Authorization": f"Bearer {result.json()['accessToken']}"}


def body(request):
    return {**request.model_dump(mode="json"), "statusToken": request.statusToken.get_secret_value()}


def test_deletion_http_complete_ticket_auth_isolation_and_redacted_validation(accounts, monkeypatch):
    app = application(accounts, monkeypatch)
    installation, original = login(accounts)
    request = payload()
    async def check():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
                device = await register(client, installation)
                other = await register(client, uuid4())
                account = {"Authorization": f"Bearer {original.accessToken}"}
                path = f"/v1/auth/account/deletions/{request.id}/status"
                ticket = {"statusToken": request.statusToken.get_secret_value()}
                for invalid in [{**body(request), "privateKey": "never-accept"}, {**body(request), "confirmDeletion": 1},
                                {**body(request), "statusToken": "sensitive-short"}]:
                    rejected = await client.post("/v1/auth/account/deletions", json=invalid, headers=account)
                    assert rejected.status_code == 422 and rejected.headers["cache-control"] == "no-store"
                    assert "never-accept" not in rejected.text and "sensitive-short" not in rejected.text
                for invalid_auth in [{}, device, {"Authorization": f"Bearer {original.refreshToken}"}]:
                    assert (await client.post("/v1/auth/account/deletions", json=body(request), headers=invalid_auth)).status_code == 401
                assert (await client.post(path, json=ticket, headers=device)).status_code == 404
                accepted = await client.post("/v1/auth/account/deletions", json=body(request), headers=account)
                assert accepted.status_code == 202 and accepted.headers["cache-control"] == "no-store"
                assert accepted.json()["status"] == "pending"
                assert set(accepted.json()) == {"id", "status", "requestedAt", "completedAt", "retryAfterSeconds"}
                assert original.accessToken not in accepted.text and ticket["statusToken"] not in accepted.text
                assert (await client.get("/v1/auth/account", headers=account)).status_code == 401
                assert (await client.post("/v1/auth/account/deletions", json=body(request), headers=account)).status_code == 401
                for auth in [{}, account]:
                    assert (await client.post(path, json=ticket, headers=auth)).status_code == 401
                assert (await client.post(path, json=ticket, headers=other)).status_code == 404
                assert (await client.post(path, json={"statusToken": "wrong" * 12}, headers=device)).status_code == 404
                for _ in range(2):
                    result = await client.post(path, json=ticket, headers=device)
                    assert result.status_code == 200 and result.headers["cache-control"] == "no-store"
                    assert result.json()["status"] == "completed" and result.json()["retryAfterSeconds"] == 0
                    assert result.json()["completedAt"] is not None
                # A status ticket is never a replacement account bearer.
                assert (await client.get("/v1/auth/wallet", headers={"Authorization": f"Bearer {ticket['statusToken']}"})).status_code == 401
    asyncio.run(check())


def test_lost_acceptance_response_recovers_by_ticket_after_original_session_revoked(accounts, monkeypatch):
    app = application(accounts, monkeypatch)
    installation, original = login(accounts)
    request = payload()
    async def check():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
                device = await register(client, installation)
                with monkeypatch.context() as patch:
                    def unavailable(*_):
                        raise OperationalError("sensitive-query", {}, RuntimeError("sensitive-server"))
                    patch.setattr(AccountDeletionWorkRepository, "claim", unavailable)
                    response = await client.post("/v1/auth/account/deletions", json=body(request),
                        headers={"Authorization": f"Bearer {original.accessToken}"})
                    assert response.status_code == 503 and "sensitive" not in response.text
                assert accounts.authenticate(original.accessToken) is None
                result = await client.post(f"/v1/auth/account/deletions/{request.id}/status",
                    json={"statusToken": request.statusToken.get_secret_value()}, headers=device)
                assert result.status_code == 200 and result.json()["status"] == "completed"
    asyncio.run(check())


def test_apple_provider_outage_stays_pending_until_confirmed_revocation(accounts, monkeypatch, tmp_path):
    settings, _, _ = configure_apple_files(monkeypatch, tmp_path)
    app = application(accounts, monkeypatch)
    installation, original = login(accounts, provider="apple", settings=settings)
    request, calls = payload(), []
    async def revoke(_, token):
        calls.append(token)
        if len(calls) == 1:
            raise IdentityUnavailable()
    monkeypatch.setattr(AppleTokenRevocation, "revoke", revoke)
    async def check():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
                device = await register(client, installation)
                accepted = await client.post("/v1/auth/account/deletions", json=body(request),
                    headers={"Authorization": f"Bearer {original.accessToken}"})
                assert accepted.status_code == 202
                path = f"/v1/auth/account/deletions/{request.id}/status"
                ticket = {"statusToken": request.statusToken.get_secret_value()}
                pending = await client.post(path, json=ticket, headers=device)
                assert pending.json()["status"] == "pending" and len(calls) == 1
                with accounts.sessions.begin() as db:
                    db.execute(update(DeletionRecord).values(next_attempt_at=datetime.now(UTC) - timedelta(seconds=1)))
                result = await client.post(path, json=ticket, headers=device)
                assert result.json()["status"] == "completed" and len(calls) == 2
    asyncio.run(check())


def test_stale_authentication_returns_reauthentication_without_mutation(accounts, monkeypatch):
    app = application(accounts, monkeypatch)
    _, original = login(accounts, issued_at=datetime.now(UTC) - timedelta(minutes=6))
    async def check():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
                response = await client.post("/v1/auth/account/deletions", json=body(payload()),
                    headers={"Authorization": f"Bearer {original.accessToken}"})
                assert response.status_code == 409 and response.headers["cache-control"] == "no-store"
                assert accounts.authenticate(original.accessToken) == original.account
    asyncio.run(check())
