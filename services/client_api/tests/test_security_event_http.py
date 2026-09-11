import asyncio
import json
from contextlib import asynccontextmanager
from dataclasses import replace
from datetime import UTC, datetime, timedelta

import httpx
import jwt
import pytest
from fastapi import FastAPI
from sqlalchemy import event as sql_event, func, select
from sqlalchemy.exc import OperationalError

from services.client_api.accounts.repository import AccountBase, AccountRepository, SecurityEventRecord
from services.client_api.accounts.router import make_account_router
from services.client_api.tests.test_security_event_repository import login
from services.client_api.tests.test_security_event_verifier import SETTINGS, claims, event_key, signed


@pytest.fixture
def accounts(tmp_path):
    repository = AccountRepository(f"sqlite:///{tmp_path / 'security-http.db'}")
    AccountBase.metadata.create_all(repository.engine)
    yield repository
    repository.engine.dispose()


@asynccontextmanager
async def receiver(accounts, key, settings=SETTINGS, metadata_status=200):
    jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key()))
    jwk.update(kid="event-key", use="sig", alg="RS256")
    def metadata(request):
        if metadata_status != 200:
            return httpx.Response(metadata_status)
        if str(request.url) == "https://accounts.google.com/.well-known/risc-configuration":
            return httpx.Response(200, json={"issuer": "https://accounts.google.com",
                                            "jwks_uri": "https://www.googleapis.com/oauth2/v3/certs"})
        assert str(request.url) in {"https://appleid.apple.com/auth/keys", "https://www.googleapis.com/oauth2/v3/certs"}
        return httpx.Response(200, json={"keys": [jwk]})
    def require_installation():
        pytest.fail("Provider notification must not trust an installation bearer")
    async with httpx.AsyncClient(transport=httpx.MockTransport(metadata)) as provider_client:
        app = FastAPI()
        app.include_router(make_account_router(settings, accounts, provider_client, require_installation))
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="https://account.test") as client:
            yield client


def payload(provider, token):
    if provider == "apple":
        return {"content": json.dumps({"payload": token}), "headers": {"Content-Type": "application/json"}}
    return {"content": token, "headers": {"Content-Type": "application/secevent+jwt"}}


@pytest.mark.parametrize("provider,success", [("apple", 200), ("google", 202)])
def test_signed_delivery_commits_before_ack_duplicate_is_harmless_and_new_login_survives(accounts, event_key, provider, success):
    now = datetime.now(UTC)
    _, old = login(accounts, now - timedelta(minutes=5), provider=provider)
    _, fresh = login(accounts, now - timedelta(seconds=20), provider=provider)
    token = signed(event_key, claims(provider))
    async def check():
        async with receiver(accounts, event_key) as client:
            path = f"/v1/auth/security-events/{provider}"
            for _ in range(2):
                response = await client.post(path, **payload(provider, token))
                assert response.status_code == success and response.content == b""
                assert response.headers["cache-control"] == "no-store"
                assert accounts.authenticate(old.accessToken) is None
                assert accounts.authenticate(fresh.accessToken) == fresh.account
            # Verification is independent of bearer headers; an invalid signature cannot be authorized by one.
            request = payload(provider, token[:-12] + "AAAAAAAAAAAA")
            request["headers"]["Authorization"] = f"Bearer {fresh.accessToken}"
            rejected = await client.post(path, **request)
            assert rejected.status_code == 400 and token not in rejected.text
            assert accounts.authenticate(fresh.accessToken) == fresh.account
            with accounts.sessions() as db:
                assert db.scalar(select(func.count()).select_from(SecurityEventRecord)) == 1
    asyncio.run(check())


@pytest.mark.parametrize("provider", ["apple", "google"])
def test_commit_failure_returns_retryable_error_and_rolls_back_revocation(accounts, event_key, provider):
    _, original = login(accounts, datetime.now(UTC) - timedelta(minutes=5), provider=provider)
    token = signed(event_key, claims(provider))
    def fail_commit(connection):
        raise OperationalError("commit", {}, RuntimeError("private-database-error"))
    async def check():
        async with receiver(accounts, event_key) as client:
            sql_event.listen(accounts.engine, "commit", fail_commit)
            try:
                response = await client.post(f"/v1/auth/security-events/{provider}", **payload(provider, token))
                assert response.status_code == 503
                assert response.headers["cache-control"] == "no-store"
                assert "private-database-error" not in response.text and token not in response.text
            finally:
                sql_event.remove(accounts.engine, "commit", fail_commit)
            assert accounts.authenticate(original.accessToken) == original.account
            with accounts.sessions() as db:
                assert db.scalar(select(func.count()).select_from(SecurityEventRecord)) == 0
            response = await client.post(f"/v1/auth/security-events/{provider}", **payload(provider, token))
            assert response.status_code == (200 if provider == "apple" else 202)
            assert accounts.authenticate(original.accessToken) is None
    asyncio.run(check())


@pytest.mark.parametrize("provider", ["apple", "google"])
@pytest.mark.parametrize("unavailable", ["disabled", "metadata"])
def test_disabled_or_unavailable_keys_do_not_acknowledge(accounts, event_key, provider, unavailable):
    async def check():
        settings = replace(SETTINGS, enabled=False) if unavailable == "disabled" else SETTINGS
        async with receiver(accounts, event_key, settings, metadata_status=503) as client:
            response = await client.post(f"/v1/auth/security-events/{provider}",
                                         **payload(provider, signed(event_key, claims(provider))))
            assert response.status_code == 503 and response.headers["cache-control"] == "no-store"
            with accounts.sessions() as db:
                assert db.scalar(select(func.count()).select_from(SecurityEventRecord)) == 0
    asyncio.run(check())


@pytest.mark.parametrize("provider,content,mime,encoding,status", [
    ("apple", '{"payload":"sensitive","payload":"duplicate"}', "application/json", "identity", 400),
    ("apple", '{"payload":"sensitive","privateKey":"reject"}', "application/json", "identity", 400),
    ("apple", '{"payload":null}', "application/json", "identity", 400),
    ("apple", '[' * 1800 + ']' * 1800, "application/json", "identity", 400),
    ("apple", '{"payload":NaN}', "application/json", "identity", 400),
    ("apple", 'x' * 20481, "application/json", "identity", 413),
    ("google", 'x' * 20481, "application/secevent+jwt", "identity", 413),
    ("google", 'x' * 16385, "application/secevent+jwt", "identity", 400),
    ("google", b'\xff' * 32, "application/secevent+jwt", "identity", 400),
    ("google", "sensitive", "application/json", "identity", 415),
    ("apple", "sensitive", "text/plain", "identity", 415),
    ("google", "sensitive", "application/secevent+jwt", "gzip", 415),
])
def test_untrusted_requests_are_bounded_redacted_and_no_store(accounts, event_key, provider, content, mime, encoding, status):
    async def check():
        async with receiver(accounts, event_key) as client:
            response = await client.post(f"/v1/auth/security-events/{provider}", content=content,
                headers={"Content-Type": mime, "Content-Encoding": encoding})
            assert response.status_code == status and response.headers["cache-control"] == "no-store"
            assert "sensitive" not in response.text and "privateKey" not in response.text
            with accounts.sessions() as db:
                assert db.scalar(select(func.count()).select_from(SecurityEventRecord)) == 0
    asyncio.run(check())
