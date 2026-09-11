"""Explicit provider-consent revocation, never normal logout or wallet execution."""
import asyncio
from urllib.parse import urlencode

import httpx

from .apple_oauth import AppleOAuthSettings
from .oidc import IdentityUnavailable

REVOKE_ENDPOINT = "https://appleid.apple.com/auth/revoke"


class AppleTokenRevocation:
    def __init__(self, settings: AppleOAuthSettings, client: httpx.AsyncClient):
        self.settings, self.client = settings, client

    async def revoke(self, refresh_token: str):
        if (not isinstance(refresh_token, str) or not 32 <= len(refresh_token) <= 8192
                or not all(33 <= ord(c) <= 126 for c in refresh_token)):
            raise IdentityUnavailable()
        request = httpx.Request("POST", REVOKE_ENDPOINT, content=urlencode({
            "client_id": self.settings.client_id, "client_secret": self.settings.client_secret(),
            "token": refresh_token, "token_type_hint": "refresh_token",
        }).encode(), headers={"Content-Type": "application/x-www-form-urlencoded", "Cache-Control": "no-store"},
            extensions={"timeout": dict(connect=8, read=8, write=8, pool=8)})
        try:
            async with asyncio.timeout(12):
                response = await self.client.send(request, auth=None, follow_redirects=False, stream=True)
                try:
                    if response.url != httpx.URL(REVOKE_ENDPOINT) or response.status_code != 200:
                        raise IdentityUnavailable()
                    # Apple's documented success (including already revoked) has no body.
                    async for part in response.aiter_bytes():
                        if part:
                            raise IdentityUnavailable()
                finally:
                    await response.aclose()
        except (httpx.HTTPError, TimeoutError):
            raise IdentityUnavailable() from None
