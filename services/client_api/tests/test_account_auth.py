import asyncio
import hashlib
import json
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from sqlalchemy import select, update

from services.client_api.accounts.oidc import (
    IdentityUnavailable, InvalidIdentity, OIDCVerifier, ProviderKeys, VerifiedIdentity,
)
from services.client_api.accounts.repository import (
    AccountBase, AccountRecord, AccountRepository, ChallengeRecord, ChallengeRejected, ChallengeThrottled,
)
from services.client_api.accounts.settings import AccountAuthSettings

SETTINGS = AccountAuthSettings("today.bsmart.ios", "server.google", "ios.google", True)
NONCE = "only-this-single-use-challenge-nonce"
NONCE_HASH = hashlib.sha256(NONCE.encode()).hexdigest()


@pytest.fixture(scope="module")
def signing_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def token(key, provider="apple", **changes):
    now = int(time.time())
    claims = dict(iss="https://appleid.apple.com", sub="provider-subject", aud="today.bsmart.ios",
                  iat=now, exp=now + 300, nonce=NONCE, email="same@example.invalid")
    if provider == "google":
        claims.update(iss="https://accounts.google.com", aud="server.google", azp="ios.google")
    claims.update(changes)
    return jwt.encode(claims, key, algorithm="RS256", headers={"kid": "key-1"})


class FixedKeys:
    def __init__(self, key):
        self.public = key.public_key()

    async def key(self, provider, kid):
        return self.public


@pytest.mark.parametrize("provider", ["apple", "google"])
def test_verified_identity_uses_subject_not_email(signing_key, provider):
    result = asyncio.run(OIDCVerifier(SETTINGS, FixedKeys(signing_key)).verify(
        provider, token(signing_key, provider), NONCE_HASH))
    assert result == VerifiedIdentity(provider, "provider-subject")
    assert not hasattr(result, "email")


@pytest.mark.parametrize("changes", [
    {"aud": "other.app"}, {"aud": ["today.bsmart.ios", "other.app"]},
    {"iss": "https://attacker.invalid"}, {"exp": 1}, {"nonce": "replayed"},
    {"iat": int(time.time()) + 3600}, {"iat": int(time.time()) - 601},
    {"sub": ""}, {"sub": 123}, {"nonce": None}, {"exp": True},
])
def test_rejects_invalid_claims(signing_key, changes):
    with pytest.raises(InvalidIdentity):
        asyncio.run(OIDCVerifier(SETTINGS, FixedKeys(signing_key)).verify(
            "apple", token(signing_key, **changes), NONCE_HASH))


def test_rejects_google_authorized_party_and_forged_signatures(signing_key):
    verifier = OIDCVerifier(SETTINGS, FixedKeys(signing_key))
    for assertion in [token(signing_key, "google", azp="other.ios"),
                      token(rsa.generate_private_key(public_exponent=65537, key_size=2048), "google")]:
        with pytest.raises(InvalidIdentity):
            asyncio.run(verifier.verify("google", assertion, NONCE_HASH))
    with pytest.raises(InvalidIdentity):
        asyncio.run(verifier.verify("apple", jwt.encode({"sub": "admin"}, "bad" * 16, algorithm="HS256"), NONCE_HASH))


def test_jwks_rotation_is_bounded_and_only_uses_fixed_provider_origin(signing_key):
    requests = []
    jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(signing_key.public_key()))
    jwk.update(kid="key-1", use="sig", alg="RS256")

    async def check():
        def respond(request):
            requests.append(request)
            return httpx.Response(200, json={"keys": [jwk]})
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            keys = ProviderKeys(client)
            await keys.key("apple", "key-1")
            await keys.key("apple", "key-1")
            with pytest.raises(IdentityUnavailable):
                await keys.key("apple", "attacker-key")
    asyncio.run(check())
    assert len(requests) == 1
    assert str(requests[0].url) == "https://appleid.apple.com/auth/keys"


def test_jwks_does_not_follow_redirects():
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(
            lambda _: httpx.Response(302, headers={"Location": "https://attacker.invalid"})
        )) as client:
            with pytest.raises(IdentityUnavailable):
                await ProviderKeys(client).key("apple", "key-1")
    asyncio.run(check())


@pytest.fixture
def repository(tmp_path):
    result = AccountRepository(f"sqlite:///{tmp_path / 'isolated-auth-test.db'}")
    # A new disposable test database only; never uses application environment/database.
    AccountBase.metadata.create_all(result.engine)
    yield result
    result.engine.dispose()


def test_challenge_binding_expiry_and_single_use(repository):
    installation = uuid4()
    challenge = repository.challenge(installation, "apple")
    assert repository.nonce_hash(challenge.id, installation, "apple") == repository.digest(challenge.nonce)
    for other_installation, provider in [(uuid4(), "apple"), (installation, "google")]:
        with pytest.raises(ChallengeRejected):
            repository.nonce_hash(challenge.id, other_installation, provider)
    session = repository.issue(challenge.id, installation, VerifiedIdentity("apple", "subject"))
    assert repository.authenticate(session.accessToken) == session.account
    assert repository.authenticate("bad") is None
    with pytest.raises(ChallengeRejected):
        repository.issue(challenge.id, installation, VerifiedIdentity("apple", "subject"))
    repository.revoke(session.accessToken)
    assert repository.authenticate(session.accessToken) is None
    expired = repository.challenge(installation, "apple")
    with repository.sessions.begin() as db:
        db.execute(update(ChallengeRecord).where(ChallengeRecord.id == str(expired.id)).values(
            expires_at=datetime.now(UTC) - timedelta(seconds=1)))
    with pytest.raises(ChallengeRejected):
        repository.nonce_hash(expired.id, installation, "apple")


def test_same_subject_reuses_account_but_providers_never_merge(repository):
    installation = uuid4()
    def login(provider):
        challenge = repository.challenge(installation, provider)
        return repository.issue(challenge.id, installation, VerifiedIdentity(provider, "identical-subject"))
    first, second, third = login("apple"), login("apple"), login("google")
    assert first.account == second.account
    assert third.account.id != first.account.id


def test_concurrent_replay_only_issues_one_session(repository):
    installation = uuid4()
    challenge = repository.challenge(installation, "apple")
    def attempt(_):
        try:
            return repository.issue(challenge.id, installation, VerifiedIdentity("apple", "subject"))
        except ChallengeRejected:
            return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(attempt, range(2)))
    assert sum(result is not None for result in results) == 1


def test_challenge_limit_and_no_schema_creation_at_runtime(repository, tmp_path):
    installation = uuid4()
    for _ in range(5):
        repository.challenge(installation, "apple")
    with pytest.raises(ChallengeThrottled):
        repository.challenge(installation, "apple")
    path = tmp_path / "not-created.db"
    unopened = AccountRepository(f"sqlite:///{path}")
    assert not path.exists()
    unopened.engine.dispose()


def test_production_cannot_enable_preproduction_auth(monkeypatch):
    monkeypatch.setenv("BSMART_ACCOUNT_AUTH_DEVELOPMENT", "1")
    monkeypatch.setenv("BSMART_APPLE_CLIENT_ID", "today.bsmart.ios")
    assert AccountAuthSettings.from_environment("production").providers == []
    monkeypatch.delenv("BSMART_APPLE_PRIVATE_KEY_FILE", raising=False)
    assert AccountAuthSettings.from_environment("development").providers == []


def test_auth_http_contract_isolated_from_installation_sessions(tmp_path, monkeypatch, signing_key):
    from services.client_api.config import ClientAPISettings, REPO_ROOT
    from services.client_api.main import create_app

    monkeypatch.setenv("BSMART_ACCOUNT_AUTH_DEVELOPMENT", "1")
    monkeypatch.setenv("BSMART_GOOGLE_SERVER_CLIENT_ID", "server.google")
    monkeypatch.setenv("BSMART_GOOGLE_IOS_CLIENT_ID", "ios.google")
    async def fixed_key(self, provider, kid):
        return signing_key.public_key()
    monkeypatch.setattr(ProviderKeys, "key", fixed_key)
    database = f"sqlite:///{tmp_path / 'http-auth-only.db'}"
    setup = AccountRepository(database)
    AccountBase.metadata.create_all(setup.engine)
    setup.engine.dispose()
    app = create_app(ClientAPISettings(environment="test", database_url=database,
                                      read_model_mode="fixture", fixture_root=REPO_ROOT / "contracts/fixtures"))

    async def check():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
                config = await client.get("/v1/auth/configuration")
                assert config.status_code == 200
                assert config.json()["depositsEnabled"] is False
                install = await client.post("/v1/installations", json={
                    "installationId": str(uuid4()), "platform": "ios", "appVersion": "1.0",
                    "locale": "en_US", "timeZone": "UTC"})
                headers = {"Authorization": f"Bearer {install.json()['accessToken']}"}
                assert (await client.get("/v1/auth/account", headers=headers)).status_code == 401
                challenge = await client.post("/v1/auth/challenges", json={"provider": "google"}, headers=headers)
                assert challenge.status_code == 200
                assertion = token(signing_key, "google", nonce=challenge.json()["nonce"])
                payload = {"provider": "google", "challengeId": challenge.json()["id"], "idToken": assertion}
                signed_in = await client.post("/v1/auth/sessions", json=payload, headers=headers)
                assert signed_in.status_code == 200
                assert signed_in.headers["cache-control"] == "no-store"
                assert assertion not in signed_in.text
                assert (await client.post("/v1/auth/sessions", json=payload, headers=headers)).status_code == 401
                account_headers = {"Authorization": f"Bearer {signed_in.json()['accessToken']}"}
                assert (await client.get("/v1/auth/account", headers=account_headers)).status_code == 200
                assert (await client.get("/v1/portfolio", headers=account_headers)).status_code == 401
                invalid = await client.post("/v1/auth/sessions", json={**payload, "idToken": "secret-too-short"}, headers=headers)
                assert invalid.status_code == 422
                assert "secret-too-short" not in invalid.text
                assert invalid.headers["cache-control"] == "no-store"
                invalid_code = await client.post("/v1/auth/sessions", json={**payload, "authorizationCode": "sensitive-code" * 4}, headers=headers)
                assert invalid_code.status_code == 422 and "sensitive-code" not in invalid_code.text
                for code_fields in [{}, {"authorizationCode": None}, {"authorizationCode": "sensitive-code"}]:
                    missing_apple_code = await client.post("/v1/auth/sessions", json={
                        **payload, "provider": "apple", **code_fields}, headers=headers)
                    assert missing_apple_code.status_code == 422
                    assert missing_apple_code.headers["cache-control"] == "no-store"
                    assert assertion not in missing_apple_code.text and "sensitive-code" not in missing_apple_code.text
                await check_wallet_http(client, headers, account_headers, signed_in.json()["account"]["id"])
                assert (await client.delete("/v1/auth/sessions/current", headers=account_headers)).status_code == 204
                assert (await client.get("/v1/auth/account", headers=account_headers)).status_code == 401
                assert (await client.get("/v1/auth/wallet", headers=account_headers)).status_code == 401
    asyncio.run(check())


async def check_wallet_http(client, installation_headers, account_headers, account_id):
    from eth_account import Account
    from eth_account.messages import encode_defunct
    from services.client_api.accounts.wallet_models import WalletChallenge
    from services.client_api.accounts.wallet_proof import binding_message

    # Public disposable key only; no blockchain calls or funds.
    key = bytes.fromhex("11" * 32)
    address = Account.from_key(key).address.lower()
    assert (await client.get("/v1/auth/wallet", headers=installation_headers)).status_code == 401
    unbound = await client.get("/v1/auth/wallet", headers=account_headers)
    assert unbound.json() == {"accountId": account_id, "address": None}
    assert unbound.headers["cache-control"] == "no-store"
    challenge = await client.post("/v1/auth/wallet/challenges", headers=account_headers, json={"address": address})
    assert challenge.status_code == 200
    parsed = WalletChallenge.model_validate(challenge.json())
    signature = "0x" + Account.sign_message(encode_defunct(text=binding_message(parsed)), private_key=key).signature.hex()
    payload = {"challengeId": str(parsed.id), "signature": signature}
    invalid = await client.put("/v1/auth/wallet", headers=account_headers, json={**payload, "mnemonic": "never-accept-secret"})
    assert invalid.status_code == 422 and "never-accept-secret" not in invalid.text
    assert invalid.headers["cache-control"] == "no-store"
    registered = await client.put("/v1/auth/wallet", headers=account_headers, json=payload)
    assert registered.status_code == 200
    assert registered.json() == {"accountId": account_id, "address": address}
    assert signature not in registered.text
    replayed = await client.put("/v1/auth/wallet", headers=account_headers, json=payload)
    assert replayed.status_code == 401 and replayed.headers["cache-control"] == "no-store"
    assert (await client.get("/v1/auth/wallet", headers=account_headers)).json() == registered.json()
