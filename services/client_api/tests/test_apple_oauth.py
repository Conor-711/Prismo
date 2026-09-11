import asyncio
from urllib.parse import parse_qs

import httpx
import jwt
import pytest

from services.client_api.accounts.apple_oauth import AppleCodeExchange, TOKEN_ENDPOINT
from services.client_api.accounts.credential_cipher import CredentialCipher, CredentialUnavailable
from services.client_api.accounts.models import SessionInput
from services.client_api.accounts.oidc import IdentityUnavailable, InvalidIdentity
from services.client_api.accounts.settings import AccountAuthSettings
from services.client_api.tests.apple_test_support import ACCESS, CODE, REFRESH, apple_settings, configure_apple_files


def response():
    return dict(id_token="identity-token-" * 5, refresh_token=REFRESH, access_token=ACCESS,
                token_type="Bearer", expires_in=3600)


def test_native_code_exchange_is_fixed_one_shot_and_does_not_inherit_credentials():
    settings = apple_settings()
    captured = []
    def transport(request):
        captured.append(request)
        assert request.method == "POST" and str(request.url) == TOKEN_ENDPOINT
        assert request.headers.get("authorization") is None
        assert request.headers.get("cookie") is None
        assert request.headers["cache-control"] == "no-store"
        fields = parse_qs(request.content.decode())
        assert set(fields) == {"client_id", "client_secret", "code", "grant_type"}
        assert fields["code"] == [CODE] and fields["grant_type"] == ["authorization_code"]
        secret = fields["client_secret"][0]
        assert jwt.get_unverified_header(secret)["kid"] == settings.key_id
        claims = jwt.decode(secret, settings.signing_key.public_key(), algorithms=["ES256"],
                            audience="https://appleid.apple.com", issuer=settings.team_id)
        assert claims["sub"] == settings.client_id and claims["exp"] - claims["iat"] == 300
        return httpx.Response(200, json=response())
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport), auth=("do-not", "send"),
                                     cookies={"private": "cookie"}, headers={"X-Secret": "no"}) as client:
            grant = await AppleCodeExchange(settings, client).exchange(CODE)
            assert grant.refresh_token == REFRESH
            assert REFRESH not in repr(grant) and "identity-token" not in repr(grant)
            assert "x-secret" not in captured[0].headers
    asyncio.run(check())
    assert len(captured) == 1


@pytest.mark.parametrize("status,mime,body", [
    (302, "application/json", b"{}"), (400, "application/json", b'{"error":"invalid_grant"}'),
    (401, "application/json", b"{}"), (429, "application/json", b"{}"), (500, "application/json", b"{}"),
    (200, "text/html", b"{}"), (200, "application/json", b"x" * 32769),
    (200, "application/json", b"null"), (200, "application/json", b'{"id_token":"a","id_token":"b"}'),
])
def test_transport_fails_without_retry_or_provider_error_disclosure(status, mime, body):
    captured = []
    async def check():
        def transport(request):
            captured.append(request)
            return httpx.Response(status, content=body, headers={"Content-Type": mime, "Location": "https://attacker.invalid"})
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport), follow_redirects=True) as client:
            with pytest.raises((IdentityUnavailable, InvalidIdentity)) as error:
                await AppleCodeExchange(apple_settings(), client).exchange(CODE)
            assert CODE not in str(error.value) and "invalid_grant" not in str(error.value)
    asyncio.run(check())
    assert len(captured) == 1


@pytest.mark.parametrize("field,value", [
    ("refresh_token", None), ("refresh_token", "too-short"), ("id_token", "x" * 16385),
    ("access_token", "has spaces " * 4), ("token_type", "Basic"), ("expires_in", True), ("expires_in", -1),
    ("error", "must-not-succeed"),
])
def test_malformed_grants_are_not_credentials(field, value):
    payload = response(); payload[field] = value
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json=payload))) as client:
            with pytest.raises(IdentityUnavailable):
                await AppleCodeExchange(apple_settings(), client).exchange(CODE)
    asyncio.run(check())


def test_invalid_code_and_cancellation_never_retry():
    async def check():
        started = asyncio.Event(); captured = []
        async def transport(request):
            captured.append(request); started.set()
            await asyncio.sleep(60)
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            exchange = AppleCodeExchange(apple_settings(), client)
            for code in ["", "a" * 31, "a" * 2049, " " * 32, "非" * 32]:
                with pytest.raises(InvalidIdentity):
                    await exchange.exchange(code)
            assert not captured
            task = asyncio.create_task(exchange.exchange(CODE))
            await asyncio.wait_for(started.wait(), 2); task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task
            assert len(captured) == 1
    asyncio.run(check())


def test_encrypted_grant_is_context_bound_and_rotation_can_read_old_keys():
    cipher = apple_settings().cipher
    key_id, ciphertext = cipher.seal(REFRESH, "account-a", "subject-a", "client-a")
    assert REFRESH.encode() not in ciphertext
    assert cipher.open(key_id, ciphertext, "account-a", "subject-a", "client-a") == REFRESH
    for args in [("account-b", "subject-a", "client-a"), ("account-a", "subject-b", "client-a"),
                 ("account-a", "subject-a", "client-b")]:
        with pytest.raises(CredentialUnavailable):
            cipher.open(key_id, ciphertext, *args)
    for changed in [ciphertext[:-1], bytes([ciphertext[0] ^ 1]) + ciphertext[1:], ciphertext[:-1] + bytes([ciphertext[-1] ^ 1]), b""]:
        with pytest.raises(CredentialUnavailable):
            cipher.open(key_id, changed, "account-a", "subject-a", "client-a")
    rotated = CredentialCipher("v2", {"v1": cipher.keys["v1"], "v2": b"2" * 32})
    assert rotated.open("v1", ciphertext, "account-a", "subject-a", "client-a") == REFRESH
    with pytest.raises(CredentialUnavailable):
        rotated.open("v2", ciphertext, "account-a", "subject-a", "client-a")
    assert rotated.seal(REFRESH, "a", "s", "c")[0] == "v2"
    with pytest.raises(TypeError):
        cipher.keys["v1"] = b"x" * 32


def test_apple_configuration_requires_protected_credentials_and_stays_disabled_in_production(monkeypatch, tmp_path):
    _, signing, keyring = configure_apple_files(monkeypatch, tmp_path)
    assert AccountAuthSettings.from_environment("test").providers == ["apple"]
    assert AccountAuthSettings.from_environment("production").providers == []
    signing.chmod(0o644)
    assert AccountAuthSettings.from_environment("test").providers == []
    signing.chmod(0o600)
    keyring.write_text("{}")
    assert AccountAuthSettings.from_environment("test").providers == []
    alias = tmp_path / "alias.p8"; alias.symlink_to(signing)
    monkeypatch.setenv("BSMART_APPLE_PRIVATE_KEY_FILE", str(alias))
    assert AccountAuthSettings.from_environment("test").providers == []


def test_provider_specific_codes_are_required_and_redacted():
    payload = dict(challengeId="11111111-1111-4111-8111-111111111111", provider="apple", idToken="i" * 40)
    assert CODE not in repr(SessionInput(**payload, authorizationCode=CODE))
    for changed in [payload, {**payload, "authorizationCode": None}, {**payload, "authorizationCode": " " * 32},
                    {**payload, "provider": "google", "authorizationCode": CODE},
                    {**payload, "provider": "google", "authorizationCode": None}]:
        with pytest.raises(ValueError):
            SessionInput(**changed)
    assert SessionInput(**{**payload, "provider": "google"}).authorizationCode is None
