"""One-shot native Apple code exchange; no implicit token refresh or revocation."""
import asyncio
import json
import os
import re
import time
from dataclasses import dataclass, field
from urllib.parse import urlencode

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import load_pem_private_key

from .credential_cipher import CredentialCipher, protected_file, unique_object
from .oidc import IdentityUnavailable, InvalidIdentity

TOKEN_ENDPOINT = "https://appleid.apple.com/auth/token"


@dataclass(frozen=True)
class AppleOAuthSettings:
    client_id: str
    team_id: str
    key_id: str
    signing_key: ec.EllipticCurvePrivateKey = field(repr=False)
    cipher: CredentialCipher = field(repr=False)

    def __post_init__(self):
        if (not re.fullmatch(r"[A-Za-z0-9.-]{1,255}", self.client_id)
                or not re.fullmatch(r"[A-Z0-9]{10}", self.team_id)
                or not re.fullmatch(r"[A-Z0-9]{10}", self.key_id)
                or not isinstance(self.signing_key, ec.EllipticCurvePrivateKey)
                or not isinstance(self.signing_key.curve, ec.SECP256R1)):
            raise ValueError("Invalid Apple OAuth configuration")

    @classmethod
    def from_environment(cls, client_id: str):
        return cls(client_id, os.getenv("BSMART_APPLE_TEAM_ID", ""), os.getenv("BSMART_APPLE_KEY_ID", ""),
            load_pem_private_key(protected_file(os.getenv("BSMART_APPLE_PRIVATE_KEY_FILE", "")), password=None),
            CredentialCipher.from_file(os.getenv("BSMART_ACCOUNT_CREDENTIAL_KEY_FILE", "")))

    def client_secret(self) -> str:
        now = int(time.time())
        return jwt.encode({"iss": self.team_id, "sub": self.client_id, "aud": "https://appleid.apple.com",
                           "iat": now, "exp": now + 300}, self.signing_key, algorithm="ES256", headers={"kid": self.key_id})


@dataclass(frozen=True, repr=False)
class AppleTokenGrant:
    id_token: str
    refresh_token: str


class AppleCodeExchange:
    def __init__(self, settings: AppleOAuthSettings, client: httpx.AsyncClient):
        self.settings, self.client = settings, client

    async def exchange(self, code: str) -> AppleTokenGrant:
        if not 32 <= len(code) <= 2048 or not all(33 <= ord(c) <= 126 for c in code):
            raise InvalidIdentity()
        # Construct the request directly: no inherited client authorization, cookies or headers.
        request = httpx.Request("POST", TOKEN_ENDPOINT, content=urlencode({
            "client_id": self.settings.client_id, "client_secret": self.settings.client_secret(),
            "grant_type": "authorization_code", "code": code,
        }).encode(), headers={"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json",
                              "Cache-Control": "no-store"},
            extensions={"timeout": dict(connect=8, read=8, write=8, pool=8)})
        try:
            async with asyncio.timeout(12):
                response = await self.client.send(request, auth=None, follow_redirects=False, stream=True)
                try:
                    if response.url != httpx.URL(TOKEN_ENDPOINT):
                        raise IdentityUnavailable()
                    if response.status_code in (400, 401):
                        raise InvalidIdentity()
                    if response.status_code != 200 or response.headers.get("content-type", "").split(";")[0] != "application/json":
                        raise IdentityUnavailable()
                    body = bytearray()
                    async for part in response.aiter_bytes():
                        if len(body) + len(part) > 32768:
                            raise IdentityUnavailable()
                        body.extend(part)
                    document = json.loads(body, object_pairs_hook=unique_object)
                    if not isinstance(document, dict) or "error" in document or document.get("token_type") != "Bearer":
                        raise IdentityUnavailable()
                    for name, maximum in [("id_token", 16384), ("refresh_token", 8192), ("access_token", 8192)]:
                        value = document.get(name)
                        if not isinstance(value, str) or not 32 <= len(value) <= maximum or not all(33 <= ord(c) <= 126 for c in value):
                            raise IdentityUnavailable()
                    expires = document.get("expires_in")
                    if type(expires) is not int or not 1 <= expires <= 86400:
                        raise IdentityUnavailable()
                    return AppleTokenGrant(document["id_token"], document["refresh_token"])
                finally:
                    await response.aclose()
        except (httpx.HTTPError, TimeoutError, ValueError, TypeError):
            raise IdentityUnavailable() from None
