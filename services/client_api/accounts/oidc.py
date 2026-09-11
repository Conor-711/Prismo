"""Strict provider verification with bounded, fixed-origin JWKS retrieval."""
import asyncio
import hashlib
import hmac
import math
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime

import httpx
import jwt

from .settings import AccountAuthSettings
from .provider_http import public_json

JWKS_URLS = {
    "apple": "https://appleid.apple.com/auth/keys",
    "google": "https://www.googleapis.com/oauth2/v3/certs",
}
ISSUERS = {
    "apple": {"https://appleid.apple.com"},
    "google": {"accounts.google.com", "https://accounts.google.com"},
}


class InvalidIdentity(Exception):
    pass


class IdentityUnavailable(Exception):
    pass


@dataclass(frozen=True)
class VerifiedIdentity:
    provider: str
    subject: str
    issued_at: datetime | None = field(default=None, compare=False)


class ProviderKeys:
    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        self.cache: dict[str, tuple[float, dict]] = {}
        self.attempted: dict[str, float] = {}
        self.lock = asyncio.Lock()

    async def key(self, provider: str, kid: str):
        async with self.lock:
            now = time.monotonic()
            cached_at, keys = self.cache.get(provider, (0, {}))
            if now - cached_at < 3600 and kid in keys:
                return keys[kid]
            # Unknown-kid tokens cannot cause unbounded provider requests.
            if now - self.attempted.get(provider, float("-inf")) < 30:
                raise IdentityUnavailable()
            self.attempted[provider] = now
            try:
                document = await public_json(self.client, JWKS_URLS[provider])
                candidates = document["keys"]
                if not isinstance(candidates, list) or not 1 <= len(candidates) <= 16:
                    raise ValueError("Invalid JWKS")
                keys = {}
                for item in candidates:
                    if (item.get("kty") == "RSA" and item.get("use") == "sig"
                            and item.get("alg", "RS256") == "RS256"):
                        key = jwt.PyJWK.from_dict(item, algorithm="RS256").key
                        if key.key_size < 2048 or item["kid"] in keys:
                            raise ValueError("Invalid provider key")
                        keys[item["kid"]] = key
                self.cache[provider] = (now, keys)
            except (httpx.HTTPError, ValueError, KeyError, TypeError, AttributeError, jwt.PyJWTError) as error:
                raise IdentityUnavailable() from error
            if kid not in keys:
                raise InvalidIdentity()
            return keys[kid]


class OIDCVerifier:
    def __init__(self, settings: AccountAuthSettings, keys: ProviderKeys):
        self.settings = settings
        self.keys = keys

    async def verify(self, provider: str, token: str, nonce_hash: str, *, nonce_is_hashed: bool = False) -> VerifiedIdentity:
        if provider not in self.settings.verification_providers or not 32 <= len(token) <= 16384:
            raise InvalidIdentity()
        try:
            header = jwt.get_unverified_header(token)
            kid = header.get("kid")
            if (header.get("alg") != "RS256" or not isinstance(kid, str)
                    or not 1 <= len(kid) <= 256 or any(k in header for k in ("jku", "x5u", "crit"))):
                raise InvalidIdentity()
            key = await self.keys.key(provider, kid)
            audience = (self.settings.apple_audience if provider == "apple"
                        else self.settings.google_audience)
            claims = jwt.decode(token, key, algorithms=["RS256"], audience=audience,
                                options={"require": ["iss", "aud", "exp", "iat", "sub", "nonce"],
                                         "strict_aud": True}, leeway=30)
            if claims["iss"] not in ISSUERS[provider]:
                raise InvalidIdentity()
            if provider == "google" and claims.get("azp") != self.settings.google_ios_client:
                raise InvalidIdentity()
            subject, nonce = claims["sub"], claims["nonce"]
            if not isinstance(subject, str) or not 1 <= len(subject) <= 255:
                raise InvalidIdentity()
            if not isinstance(nonce, str) or not hmac.compare_digest(
                nonce if nonce_is_hashed else hashlib.sha256(nonce.encode()).hexdigest(), nonce_hash
            ):
                raise InvalidIdentity()
            issued, expiry = claims["iat"], claims["exp"]
            if (type(issued) not in (int, float) or type(expiry) not in (int, float)
                    or not math.isfinite(issued) or not math.isfinite(expiry)
                    or time.time() - issued > 600 or expiry <= issued):
                raise InvalidIdentity()
            return VerifiedIdentity(provider, subject, datetime.fromtimestamp(issued, UTC))
        except (jwt.PyJWTError, ValueError, TypeError, KeyError) as error:
            raise InvalidIdentity() from error
