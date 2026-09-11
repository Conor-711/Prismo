import asyncio
import json
import time
from uuid import uuid4

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from services.client_api.accounts.oidc import IdentityUnavailable, InvalidIdentity, OIDCVerifier, ProviderKeys
from services.client_api.accounts.security_event_verifier import GoogleRISCConfiguration, RISC, SecurityEventVerifier
from services.client_api.accounts.settings import AccountAuthSettings

SETTINGS = AccountAuthSettings("today.bsmart.ios", "server.google", "ios.google", True)


@pytest.fixture(scope="module")
def event_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def claims(provider="apple", **changes):
    issued = int(time.time()) - 120
    value = {"iss": "https://appleid.apple.com", "aud": "today.bsmart.ios", "iat": issued,
             "jti": str(uuid4()), "events": {"type": "consent-revoked", "sub": "owner", "event_time": issued}}
    if provider == "google":
        value.update(iss="https://accounts.google.com", aud="server.google", events={RISC + "sessions-revoked": {
            "subject": {"subject_type": "iss-sub", "iss": "https://accounts.google.com/", "sub": "owner"}}})
    value.update(changes)
    return value


def signed(key, value, **headers):
    return jwt.encode(value, key, algorithm="RS256", headers={"kid": "event-key", **headers})


class EventKeys:
    def __init__(self, key): self.value = key.public_key()
    async def key(self, provider, kid):
        if kid != "event-key": raise InvalidIdentity()
        return self.value


class EventMetadata:
    async def issuer(self): return "https://accounts.google.com"


def verifier(key):
    return SecurityEventVerifier(SETTINGS, EventKeys(key), EventMetadata())


@pytest.mark.parametrize("provider", ["apple", "google"])
def test_historical_signed_notifications_have_no_login_expiry_or_nonce_requirement(event_key, provider):
    value = claims(provider, iat=int(time.time()) - 86400 * 90, exp=1)
    if provider == "apple": value["events"]["event_time"] = value["iat"]
    event = asyncio.run(verifier(event_key).verify(provider, signed(event_key, value)))
    assert event.action == "revoke" and event.subject == "owner"
    assert "owner" not in repr(event) and value["jti"] not in repr(event)
    with pytest.raises(InvalidIdentity):
        asyncio.run(OIDCVerifier(SETTINGS, EventKeys(event_key)).verify(provider, signed(event_key, value), "hash"))


@pytest.mark.parametrize("changes", [
    {"iss": "https://attacker.invalid"}, {"aud": "other.app"}, {"jti": ""}, {"jti": None},
    {"iat": True}, {"iat": float("nan")}, {"iat": int(time.time()) + 3600}, {"events": []},
    {"events": {"type": "consent-revoked", "sub": "", "event_time": 1}},
    {"events": {"type": "consent-revoked", "sub": "owner", "event_time": int(time.time()) + 3600}},
])
def test_rejects_invalid_signed_claims(event_key, changes):
    with pytest.raises(InvalidIdentity):
        asyncio.run(verifier(event_key).verify("apple", signed(event_key, claims(**changes))))


def test_rejects_forged_signature_untrusted_key_headers_and_duplicate_fields(event_key):
    value = claims()
    altered = [signed(rsa.generate_private_key(public_exponent=65537, key_size=2048), value),
        signed(event_key, value, jku="https://attacker.invalid/key"), signed(event_key, value, crit=["unknown"]),
        jwt.encode(value, "test-only-" * 8, algorithm="HS256", headers={"kid": "event-key"})]
    raw = json.dumps(value)[:-1] + ',"jti":"duplicate"}'
    altered.append(jwt.api_jws.PyJWS().encode(raw.encode(), event_key, algorithm="RS256", headers={"kid": "event-key"}))
    for token in altered:
        with pytest.raises(InvalidIdentity): asyncio.run(verifier(event_key).verify("apple", token))


def test_apple_string_events_are_supported_without_retaining_email(event_key):
    value = claims(events=json.dumps({"type": "email-disabled", "sub": "owner", "event_time": 1,
                                     "email": "sensitive@example.invalid"}))
    event = asyncio.run(verifier(event_key).verify("apple", signed(event_key, value)))
    assert event.action == "ignore" and "sensitive" not in repr(event)


def test_google_subjects_and_event_type_mapping_are_strict(event_key):
    for subject in [{"subject_type": "email", "email": "owner@example.invalid"},
                    {"subject_type": "iss-sub", "iss": "https://attacker.invalid", "sub": "owner"}]:
        value = claims("google", events={RISC + "sessions-revoked": {"subject": subject}})
        with pytest.raises(InvalidIdentity): asyncio.run(verifier(event_key).verify("google", signed(event_key, value)))
    for kind, action in [("account-disabled", "disable"), ("account-enabled", "enable"),
                         ("account-credential-change-required", "revoke")]:
        value = claims("google")
        detail = next(iter(value["events"].values()))
        value["events"] = {RISC + kind: detail}
        assert asyncio.run(verifier(event_key).verify("google", signed(event_key, value))).action == action
    value = claims("google", events={RISC + "verification": {"state": "Operator test with spaces"}})
    result = asyncio.run(verifier(event_key).verify("google", signed(event_key, value)))
    assert result.verification_hash is not None and result.subject is None
    assert "Operator test" not in repr(result)


def test_fixed_google_discovery_and_jwks_strip_credentials_and_cache_reads(event_key):
    captured = []
    jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(event_key.public_key()))
    jwk.update(kid="event-key", use="sig", alg="RS256")
    def respond(request):
        captured.append(request)
        assert not any(name in request.headers for name in ["authorization", "cookie", "x-secret"])
        if str(request.url) == "https://accounts.google.com/.well-known/risc-configuration":
            return httpx.Response(200, json={"issuer": "https://accounts.google.com",
                                            "jwks_uri": "https://www.googleapis.com/oauth2/v3/certs"})
        assert str(request.url) == "https://www.googleapis.com/oauth2/v3/certs"
        return httpx.Response(200, json={"keys": [jwk]})
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond), auth=("no", "credentials"),
            headers={"X-Secret": "no"}, cookies={"secret": "no"}) as client:
            validator = SecurityEventVerifier(SETTINGS, ProviderKeys(client), GoogleRISCConfiguration(client))
            for _ in range(2): await validator.verify("google", signed(event_key, claims("google")))
    asyncio.run(check())
    assert len(captured) == 2


@pytest.mark.parametrize("response", [
    httpx.Response(302, headers={"Location": "https://attacker.invalid"}),
    httpx.Response(200, json={"issuer": "https://attacker.invalid", "jwks_uri": "https://www.googleapis.com/oauth2/v3/certs"}),
    httpx.Response(200, json={"issuer": "https://accounts.google.com", "jwks_uri": "https://attacker.invalid"}),
    httpx.Response(200, content=b"x" * 8193),
])
def test_discovery_cannot_redirect_or_select_an_arbitrary_key_origin(response):
    captured = []
    async def check():
        def respond(request): captured.append(request); return response
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond), follow_redirects=True) as client:
            config = GoogleRISCConfiguration(client)
            for _ in range(2):
                with pytest.raises(IdentityUnavailable): await config.issuer()
    asyncio.run(check())
    assert len(captured) == 1
