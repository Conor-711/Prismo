import asyncio
import json
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import uuid4

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import FastAPI
from sqlalchemy import event, func, select, update
from sqlalchemy.exc import OperationalError

from services.client_api.accounts.apple_repository import AppleExchangeRecord, AppleGrantRecord, AppleGrantRepository
from services.client_api.accounts.credential_cipher import CredentialUnavailable
from services.client_api.accounts.oidc import VerifiedIdentity
from services.client_api.accounts.repository import AccountBase, AccountRecord, AccountRepository, ChallengeRejected, SessionRecord
from services.client_api.accounts.router import make_account_router
from services.client_api.accounts.settings import AccountAuthSettings
from services.client_api.accounts.wallet_repository import WalletConflict, WalletRepository
from services.client_api.tests.apple_test_support import ACCESS, CODE, REFRESH, apple_settings
from services.client_api.tests.test_account_auth import token
from services.client_api.tests.test_wallet_binding import ADDRESS, OTHER_ADDRESS, sign


@pytest.fixture
def accounts(tmp_path):
    repository = AccountRepository(f"sqlite:///{tmp_path / 'apple-only.db'}")
    AccountBase.metadata.create_all(repository.engine)
    yield repository
    repository.engine.dispose()


def test_exchange_claim_is_installation_bound_concurrent_and_single_use(accounts):
    grants = AppleGrantRepository(accounts); installation = uuid4()
    identity = VerifiedIdentity("apple", "subject")
    challenge = accounts.challenge(installation, "apple")
    with pytest.raises(ChallengeRejected):
        grants.claim(challenge.id, uuid4(), identity, "today.bsmart.ios")
    def claim(_):
        try:
            return grants.claim(challenge.id, installation, identity, "today.bsmart.ios")
        except ChallengeRejected:
            return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        claims = [value for value in pool.map(claim, range(2)) if value is not None]
    assert len(claims) == 1
    claimed = claims[0]
    cipher = apple_settings().cipher
    for wrong in [replace(claimed, token="wrong"), replace(claimed, client_id="wrong"),
                  replace(claimed, installation_id=uuid4()),
                  replace(claimed, identity=VerifiedIdentity("apple", "other"))]:
        with pytest.raises(ChallengeRejected):
            grants.finish(wrong, REFRESH, cipher)
    first = grants.finish(claimed, REFRESH, cipher)
    with pytest.raises(ChallengeRejected):
        grants.finish(claimed, REFRESH, cipher)
    with accounts.sessions() as db:
        stored = db.get(AppleGrantRecord, str(first.account.id))
        assert cipher.open(stored.key_id, stored.ciphertext, stored.account_id, identity.subject, stored.client_id) == REFRESH
        assert db.scalar(select(func.count()).select_from(SessionRecord)) == 1
    second_challenge = accounts.challenge(installation, "apple")
    second = grants.finish(grants.claim(second_challenge.id, installation, identity, "today.bsmart.ios"), REFRESH, cipher)
    assert first.account == second.account


def test_encryption_failure_rolls_back_session_and_expired_claim_cannot_finish(accounts):
    grants = AppleGrantRepository(accounts); installation = uuid4()
    identity = VerifiedIdentity("apple", "subject")
    challenge = accounts.challenge(installation, "apple")
    claim = grants.claim(challenge.id, installation, identity, "today.bsmart.ios")
    cipher = apple_settings().cipher
    with pytest.raises(CredentialUnavailable):
        grants.finish(claim, "malformed", cipher)
    with accounts.sessions() as db:
        assert db.scalar(select(func.count()).select_from(AccountRecord)) == 0
        assert db.scalar(select(func.count()).select_from(SessionRecord)) == 0
        assert db.scalar(select(func.count()).select_from(AppleGrantRecord)) == 0
    with accounts.sessions.begin() as db:
        db.execute(update(AppleExchangeRecord).values(expires_at=datetime.now(UTC) - timedelta(seconds=1)))
    with pytest.raises(ChallengeRejected):
        grants.finish(claim, REFRESH, cipher)


def test_concurrent_finish_can_publish_only_one_session(accounts):
    grants = AppleGrantRepository(accounts)
    installation = uuid4()
    challenge = accounts.challenge(installation, "apple")
    claim = grants.claim(challenge.id, installation, VerifiedIdentity("apple", "subject"), "today.bsmart.ios")
    cipher = apple_settings().cipher

    def finish(_):
        try:
            return grants.finish(claim, REFRESH, cipher)
        except ChallengeRejected:
            return None

    with ThreadPoolExecutor(max_workers=2) as pool:
        sessions = [value for value in pool.map(finish, range(2)) if value is not None]
    assert len(sessions) == 1
    with accounts.sessions() as db:
        assert db.scalar(select(func.count()).select_from(SessionRecord)) == 1
        assert db.scalar(select(func.count()).select_from(AppleGrantRecord)) == 1
        assert db.get(AppleExchangeRecord, str(claim.id)) is None


@pytest.mark.parametrize("failure", ["encryption", "grant_write"])
def test_failed_credential_update_preserves_account_grant_and_wallet(accounts, failure):
    grants, wallets = AppleGrantRepository(accounts), WalletRepository(accounts)
    apple = apple_settings()
    installation = uuid4()
    identity = VerifiedIdentity("apple", "existing-owner")

    def next_claim():
        challenge = accounts.challenge(installation, "apple")
        return grants.claim(challenge.id, installation, identity, apple.client_id)

    original = grants.finish(next_claim(), REFRESH, apple.cipher)
    proof = wallets.challenge(original.account.id, original.accessToken, ADDRESS)
    binding = wallets.bind(original.account.id, original.accessToken, proof.id, sign(proof))
    with accounts.sessions() as db:
        grant = db.get(AppleGrantRecord, str(original.account.id))
        previous_ciphertext = grant.ciphertext
        previous_updated_at = grant.updated_at

    claim = next_claim()

    def reject_grant_write(conn, cursor, statement, parameters, context, executemany):
        if "INSERT INTO trading_apple_grant" in statement:
            raise OperationalError("injected grant persistence failure", None, Exception("test-only"))

    if failure == "grant_write":
        event.listen(accounts.engine, "before_cursor_execute", reject_grant_write)
    try:
        expected = CredentialUnavailable if failure == "encryption" else OperationalError
        with pytest.raises(expected):
            grants.finish(claim, "short" if failure == "encryption" else REFRESH + "updated", apple.cipher)
    finally:
        if failure == "grant_write":
            event.remove(accounts.engine, "before_cursor_execute", reject_grant_write)

    assert accounts.authenticate(original.accessToken) == original.account
    assert wallets.registration(original.account.id) == binding
    with accounts.sessions() as db:
        grant = db.get(AppleGrantRecord, str(original.account.id))
        assert grant.ciphertext == previous_ciphertext and grant.updated_at == previous_updated_at
        assert apple.cipher.open(grant.key_id, grant.ciphertext, grant.account_id, identity.subject, grant.client_id) == REFRESH
        assert db.scalar(select(func.count()).select_from(AccountRecord)) == 1
        assert db.scalar(select(func.count()).select_from(SessionRecord)) == 1
    with pytest.raises(ChallengeRejected):
        accounts.nonce_hash(claim.id, installation, "apple")

    renewed = grants.finish(next_claim(), REFRESH + "updated", apple.cipher)
    assert renewed.account == original.account
    assert wallets.registration(renewed.account.id) == binding
    with pytest.raises(WalletConflict):
        wallets.challenge(renewed.account.id, renewed.accessToken, OTHER_ADDRESS)
    with accounts.sessions() as db:
        grant = db.get(AppleGrantRecord, str(original.account.id))
        assert grant.ciphertext != previous_ciphertext
        assert apple.cipher.open(grant.key_id, grant.ciphertext, grant.account_id, identity.subject, grant.client_id) == REFRESH + "updated"


@pytest.mark.parametrize("failure", [None, "subject", "nonce", "audience", "signature", "missing_nonce", "timeout"])
def test_http_apple_exchange_verifies_both_tokens_before_atomic_session(accounts, failure):
    apple = apple_settings()
    settings = AccountAuthSettings(apple_audience=apple.client_id, enabled=True, apple=apple)
    signing = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(signing.public_key()))
    jwk.update(kid="key-1", use="sig", alg="RS256")
    installation = uuid4(); native = {}; exchanges = []

    def transport(request):
        if request.method == "GET":
            assert str(request.url) == "https://appleid.apple.com/auth/keys"
            return httpx.Response(200, json={"keys": [jwk]})
        exchanges.append(request)
        if failure == "timeout":
            raise httpx.ReadTimeout("must-not-expose-provider-details", request=request)
        changes = {"nonce": native["nonce"]}
        if failure == "subject": changes["sub"] = "different-owner"
        if failure == "nonce": changes["nonce"] = "not-the-native-nonce"
        if failure == "audience": changes["aud"] = "different.app"
        signing_key = rsa.generate_private_key(public_exponent=65537, key_size=2048) if failure == "signature" else signing
        assertion = token(signing_key, **changes)
        if failure == "missing_nonce":
            claims = jwt.decode(assertion, options={"verify_signature": False}); del claims["nonce"]
            assertion = jwt.encode(claims, signing, algorithm="RS256", headers={"kid": "key-1"})
        return httpx.Response(200, json=dict(id_token=assertion, refresh_token=REFRESH,
                                             access_token=ACCESS, token_type="Bearer", expires_in=3600))

    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as provider:
            app = FastAPI()
            app.include_router(make_account_router(settings, accounts, provider,
                lambda: SimpleNamespace(installation_id=installation)))
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
                challenge = (await client.post("/v1/auth/challenges", json={"provider": "apple"})).json()
                native["nonce"] = challenge["nonce"]
                payload = dict(provider="apple", challengeId=challenge["id"], idToken=token(signing, nonce=native["nonce"]), authorizationCode=CODE)
                result = await client.post("/v1/auth/sessions", json=payload)
                assert result.status_code == (200 if failure is None else 503 if failure == "timeout" else 401)
                assert CODE not in result.text and REFRESH not in result.text and ACCESS not in result.text
                assert "must-not-expose-provider-details" not in result.text
                assert (await client.post("/v1/auth/sessions", json=payload)).status_code == 401
                if failure is None:
                    assert result.headers["cache-control"] == "no-store"
                    with accounts.sessions() as db:
                        stored = db.get(AppleGrantRecord, result.json()["account"]["id"])
                        assert apple.cipher.open(stored.key_id, stored.ciphertext, stored.account_id,
                                                 "provider-subject", stored.client_id) == REFRESH
                else:
                    with accounts.sessions() as db:
                        assert db.scalar(select(func.count()).select_from(SessionRecord)) == 0
                        assert db.scalar(select(func.count()).select_from(AppleGrantRecord)) == 0
    asyncio.run(check())
    assert len(exchanges) == 1
