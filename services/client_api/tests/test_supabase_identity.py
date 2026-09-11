import asyncio
import hashlib
import json
from dataclasses import replace
from uuid import uuid4

import httpx
import pytest
from pydantic import ValidationError

from services.client_api.accounts.models import SessionInput
from services.client_api.accounts.oidc import IdentityUnavailable, InvalidIdentity, OIDCVerifier, VerifiedIdentity
from services.client_api.accounts.settings import AccountAuthSettings
from services.client_api.accounts.supabase_identity import SupabaseGoogleIdentity
from services.client_api.tests.test_account_auth import FixedKeys, signing_key, token

SETTINGS = AccountAuthSettings(google_audience="server.google", google_ios_client="ios.google", enabled=True,
    supabase_url="https://abcdefghijklmnopqrst.supabase.co", supabase_publishable_key="sb_publishable_disposable_test_key")
IDENTITY = VerifiedIdentity("google", "provider-subject")
NONCE = "disposable-installation-challenge-123456"


def receipt():
    user = str(uuid4())
    return {"token_type": "bearer", "access_token": "not-used-as-app-session", "refresh_token": "never-persisted",
            "user": {"id": user, "is_anonymous": False, "identities": [
                {"user_id": user, "provider": "google", "identity_data": {"sub": IDENTITY.subject}}]}}


def run(response, *, settings=SETTINGS):
    requests = []
    async def check():
        def respond(request):
            requests.append(request)
            return response
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond),
                headers={"Authorization": "do-not-leak", "Cookie": "do-not-leak", "X-Private": "do-not-leak"},
                auth=("private-user", "private-password"), follow_redirects=True) as client:
            return await SupabaseGoogleIdentity(settings, client).verify(IDENTITY, "transient-google-token", NONCE)
    return asyncio.run(check()), requests


def test_supabase_admits_existing_google_identity_without_changing_wallet_account():
    result, requests = run(httpx.Response(200, json=receipt()))
    assert result == IDENTITY
    assert len(requests) == 1
    request = requests[0]
    assert str(request.url) == SETTINGS.supabase_url + "/auth/v1/token?grant_type=id_token"
    assert request.method == "POST"
    assert request.headers["apikey"] == SETTINGS.supabase_publishable_key
    assert all(name not in request.headers for name in ("authorization", "cookie", "x-private"))
    assert json.loads(request.content) == {"provider": "google", "id_token": "transient-google-token", "nonce": NONCE}


@pytest.mark.parametrize("status,error", [(400, InvalidIdentity), (401, InvalidIdentity), (403, InvalidIdentity),
    (422, InvalidIdentity), (429, IdentityUnavailable), (500, IdentityUnavailable), (302, IdentityUnavailable)])
def test_failed_admission_never_falls_back_to_local_identity(status, error):
    with pytest.raises(error):
        run(httpx.Response(status, json={"error": "do-not-expose-token"}, headers={"Location": "https://wrong.invalid"}))


@pytest.mark.parametrize("change", ["subject", "user", "provider", "anonymous", "missing", "email-only"])
def test_rejects_mismatched_or_user_editable_identity(change):
    body = receipt()
    identity = body["user"]["identities"][0]
    if change == "subject": identity["identity_data"]["sub"] = "somebody-else"
    if change == "user": identity["user_id"] = str(uuid4())
    if change == "provider": identity["provider"] = "apple"
    if change == "anonymous": body["user"]["is_anonymous"] = True
    if change == "missing": del body["user"]["id"]
    if change == "email-only":
        body["user"]["identities"] = []
        body["user"]["user_metadata"] = {"sub": IDENTITY.subject, "email": "same@example.invalid"}
    with pytest.raises(InvalidIdentity):
        run(httpx.Response(200, json=body))


@pytest.mark.parametrize("response", [httpx.Response(200, content=b"x" * 65537, headers={"content-type": "application/json"}),
    httpx.Response(200, text="<html>not auth</html>"),
    httpx.Response(200, content=b'{"user":{},"user":{}}', headers={"content-type": "application/json"})])
def test_bounds_and_validates_supabase_responses(response):
    with pytest.raises((IdentityUnavailable, InvalidIdentity)):
        run(response)


@pytest.mark.parametrize("url,key", [("http://abcdefghijklmnopqrst.supabase.co", SETTINGS.supabase_publishable_key),
    (SETTINGS.supabase_url + ".attacker.invalid", SETTINGS.supabase_publishable_key),
    (SETTINGS.supabase_url + "/redirect", SETTINGS.supabase_publishable_key),
    (SETTINGS.supabase_url, "sb_secret_never-accept-admin-key"), (SETTINGS.supabase_url, "")])
def test_partial_or_unsafe_configuration_disables_signin_without_legacy_fallback(url, key):
    settings = replace(SETTINGS, supabase_url=url, supabase_publishable_key=key)
    assert settings.uses_supabase
    assert not settings.supabase_configured
    assert settings.providers == []
    with pytest.raises(IdentityUnavailable):
        run(httpx.Response(200, json=receipt()), settings=settings)


def test_native_hashed_nonce_is_explicit_and_still_requires_provider_signature(signing_key):
    hashed = hashlib.sha256(NONCE.encode()).hexdigest()
    verifier = OIDCVerifier(SETTINGS, FixedKeys(signing_key))
    assertion = token(signing_key, "google", nonce=hashed)
    result = asyncio.run(verifier.verify("google", assertion, hashed, nonce_is_hashed=True))
    assert result == IDENTITY
    with pytest.raises(InvalidIdentity):
        asyncio.run(verifier.verify("google", assertion, hashed))
    with pytest.raises(InvalidIdentity):
        asyncio.run(verifier.verify("google", token(signing_key, "google", nonce=NONCE), hashed, nonce_is_hashed=True))


def test_nonce_shape_and_logs():
    fields = {"provider": "google", "challengeId": uuid4(), "idToken": "disposable-token" * 4}
    assert NONCE not in repr(SessionInput(**fields, nonce=NONCE))
    assert SETTINGS.supabase_publishable_key not in repr(SETTINGS)
    for nonce in [None, "short", NONCE + "\n", "x" * 129]:
        with pytest.raises(ValidationError):
            SessionInput(**fields, nonce=nonce)
    assert SessionInput(**fields).nonce is None


def test_environment_configuration_and_unchanged_money_gate(monkeypatch):
    monkeypatch.setenv("BSMART_ACCOUNT_AUTH_DEVELOPMENT", "1")
    monkeypatch.setenv("BSMART_GOOGLE_SERVER_CLIENT_ID", SETTINGS.google_audience)
    monkeypatch.setenv("BSMART_GOOGLE_IOS_CLIENT_ID", SETTINGS.google_ios_client)
    monkeypatch.setenv("BSMART_SUPABASE_URL", SETTINGS.supabase_url)
    monkeypatch.setenv("BSMART_SUPABASE_PUBLISHABLE_KEY", SETTINGS.supabase_publishable_key)
    assert AccountAuthSettings.from_environment("test").providers == ["google"]
    assert AccountAuthSettings.from_environment("production").providers == []


def test_http_supabase_login_requires_both_verifiers_and_reuses_existing_account(tmp_path, monkeypatch, signing_key):
    from fastapi import FastAPI
    from services.client_api.accounts.repository import AccountBase, AccountRepository
    from services.client_api.accounts.router import make_account_router
    from services.client_api.accounts.oidc import ProviderKeys
    from types import SimpleNamespace

    accounts = AccountRepository(f"sqlite:///{tmp_path / 'supabase-auth-only.db'}")
    AccountBase.metadata.create_all(accounts.engine)
    installation = uuid4()
    previous = accounts.challenge(installation, "google")
    old = accounts.issue(previous.id, installation, IDENTITY)
    async def key(self, provider, kid):
        return signing_key.public_key()
    monkeypatch.setattr(ProviderKeys, "key", key)
    requests = []
    upstream_status = 200
    def upstream(request):
        requests.append(request)
        return httpx.Response(upstream_status, json=receipt())

    async def check():
        nonlocal upstream_status
        async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as supabase:
            app = FastAPI()
            app.include_router(make_account_router(SETTINGS, accounts, supabase,
                lambda: SimpleNamespace(installation_id=installation)))
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
                config = (await client.get("/v1/auth/configuration")).json()
                assert config == {"providers": ["google"], "depositsEnabled": False, "tradingEnabled": False}
                challenge = (await client.post("/v1/auth/challenges", json={"provider": "google"})).json()
                hashed = hashlib.sha256(challenge["nonce"].encode()).hexdigest()
                assert challenge["providerNonce"] == hashed
                body = {"provider": "google", "challengeId": challenge["id"],
                        "idToken": token(signing_key, "google", nonce=hashed)}
                assert (await client.post("/v1/auth/sessions", json=body)).status_code == 401
                assert (await client.post("/v1/auth/sessions", json={**body, "nonce": NONCE})).status_code == 401
                assert not requests
                body["nonce"] = challenge["nonce"]
                wrong = {**body, "idToken": token(signing_key, "google", nonce=hashed, azp="another-ios-app")}
                assert (await client.post("/v1/auth/sessions", json=wrong)).status_code == 401
                assert not requests
                upstream_status = 503
                assert (await client.post("/v1/auth/sessions", json=body)).status_code == 503
                assert accounts.authenticate(old.accessToken) is not None
                upstream_status = 200
                success = await client.post("/v1/auth/sessions", json=body)
                assert success.status_code == 200
                assert success.json()["account"]["id"] == str(old.account.id)
                assert "never-persisted" not in success.text and body["idToken"] not in success.text
                before = len(requests)
                assert (await client.post("/v1/auth/sessions", json=body)).status_code == 401
                assert len(requests) == before
                headers = {"Authorization": "Bearer " + success.json()["accessToken"]}
                assert (await client.get("/v1/auth/account", headers=headers)).status_code == 200
                deletion = {"id": str(uuid4()), "statusToken": "disposable-ticket" * 4,
                            "confirmDeletion": True, "walletRecoveryConfirmed": True}
                assert (await client.post("/v1/auth/account/deletions", json=deletion, headers=headers)).status_code == 503
                assert (await client.get("/v1/auth/account", headers=headers)).status_code == 200
                assert (await client.delete("/v1/auth/sessions/current", headers=headers)).status_code == 204
                assert (await client.get("/v1/auth/account", headers=headers)).status_code == 401
    try:
        asyncio.run(check())
    finally:
        accounts.engine.dispose()
