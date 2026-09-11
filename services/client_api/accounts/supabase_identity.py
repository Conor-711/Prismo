"""Google identity admission through Supabase; wallet/account IDs stay unchanged."""
import asyncio
from uuid import UUID

import httpx

from .oidc import IdentityUnavailable, InvalidIdentity, VerifiedIdentity
from .provider_http import unique_json
from .settings import AccountAuthSettings


class SupabaseGoogleIdentity:
    def __init__(self, settings: AccountAuthSettings, client: httpx.AsyncClient):
        self.settings = settings
        self.client = client

    async def verify(self, identity: VerifiedIdentity, token: str, nonce: str) -> VerifiedIdentity:
        if not self.settings.supabase_configured or identity.provider != "google":
            raise IdentityUnavailable()
        url = self.settings.supabase_url + "/auth/v1/token?grant_type=id_token"
        request = httpx.Request("POST", url, headers={
            "apikey": self.settings.supabase_publishable_key,
            "Accept": "application/json", "Cache-Control": "no-store",
        }, json={"provider": "google", "id_token": token, "nonce": nonce},
            extensions={"timeout": {"connect": 8, "read": 8, "write": 8, "pool": 8}})
        try:
            async with asyncio.timeout(15):
                response = await self.client.send(request, stream=True, follow_redirects=False, auth=None)
                try:
                    if response.url != httpx.URL(url):
                        raise IdentityUnavailable()
                    if response.status_code in (400, 401, 403, 422):
                        raise InvalidIdentity()
                    if (response.status_code != 200 or
                            response.headers.get("content-type", "").split(";")[0] != "application/json"):
                        raise IdentityUnavailable()
                    body = bytearray()
                    async for part in response.aiter_bytes():
                        body.extend(part)
                        if len(body) > 65536:
                            raise IdentityUnavailable()
                    document = unique_json(body)
                finally:
                    await response.aclose()
            user = document["user"]
            user_id = str(UUID(user["id"]))
            if user.get("is_anonymous") is not False or document.get("token_type") != "bearer":
                raise InvalidIdentity()
            # Compare to the independently verified Google subject, never user-editable metadata/email.
            identities = user["identities"]
            if not isinstance(identities, list) or not any(
                item.get("provider") == "google" and item.get("user_id") == user_id
                and item.get("identity_data", {}).get("sub") == identity.subject
                for item in identities
            ):
                raise InvalidIdentity()
            return identity
        except (httpx.HTTPError, TimeoutError) as error:
            raise IdentityUnavailable() from error
        except (ValueError, KeyError, TypeError, AttributeError) as error:
            raise InvalidIdentity() from error
