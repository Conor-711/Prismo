import asyncio
from urllib.parse import parse_qs

import httpx
import jwt
import pytest

from services.client_api.accounts.apple_revocation import AppleTokenRevocation, REVOKE_ENDPOINT
from services.client_api.accounts.oidc import IdentityUnavailable
from services.client_api.tests.apple_test_support import REFRESH, apple_settings


def test_revocation_uses_fixed_origin_post_no_inherited_credentials_and_short_client_secret():
    settings = apple_settings()
    calls = []
    def handle(request):
        calls.append(request)
        assert str(request.url) == REVOKE_ENDPOINT
        assert request.method == "POST" and not request.url.query
        assert not any(key in request.headers for key in ("authorization", "cookie", "x-inherited-secret"))
        body = parse_qs(request.content.decode())
        assert set(body) == {"client_id", "client_secret", "token", "token_type_hint"}
        assert body["client_id"] == [settings.client_id] and body["token"] == [REFRESH]
        assert body["token_type_hint"] == ["refresh_token"]
        claims = jwt.decode(body["client_secret"][0], settings.signing_key.public_key(), algorithms=["ES256"],
                            audience="https://appleid.apple.com", issuer=settings.team_id)
        assert claims["sub"] == settings.client_id and claims["exp"] - claims["iat"] == 300
        return httpx.Response(200)
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle), auth=("private", "secret"),
                headers={"X-Inherited-Secret": "secret"}, cookies={"session": "secret"}) as client:
            await AppleTokenRevocation(settings, client).revoke(REFRESH)
    asyncio.run(check())
    assert len(calls) == 1


@pytest.mark.parametrize("status,body", [(200, b'{}'), (200, b'{"error":"secret"}'), (200, b'x' * 40000),
                                         (204, b''), (302, b''), (400, b''), (401, b''), (500, b'')])
def test_only_documented_empty_200_confirms_revocation_without_retry(status, body):
    calls = []
    def handle(request):
        calls.append(request)
        return httpx.Response(status, content=body, headers={"Location": "https://untrusted.invalid"})
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            with pytest.raises(IdentityUnavailable) as failure:
                await AppleTokenRevocation(apple_settings(), client).revoke(REFRESH)
            assert REFRESH not in str(failure.value) and "secret" not in str(failure.value)
    asyncio.run(check())
    assert len(calls) == 1


@pytest.mark.parametrize("value", ["", "short", REFRESH + "\n", "x" * 8193, None])
def test_invalid_tokens_never_make_an_external_request(value):
    def handle(_):
        pytest.fail("Invalid token left process")
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            with pytest.raises(IdentityUnavailable):
                await AppleTokenRevocation(apple_settings(), client).revoke(value)
    asyncio.run(check())


def test_network_error_and_cancel_do_not_retry():
    async def check():
        for cancelled in [False, True]:
            calls = []
            def handle(_):
                calls.append(1)
                if cancelled:
                    raise asyncio.CancelledError()
                raise httpx.ReadTimeout("provider-secret")
            async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
                with pytest.raises(asyncio.CancelledError if cancelled else IdentityUnavailable):
                    await AppleTokenRevocation(apple_settings(), client).revoke(REFRESH)
            assert len(calls) == 1
    asyncio.run(check())
