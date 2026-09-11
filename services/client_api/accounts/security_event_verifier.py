"""Separate historical SET verification; never treats a SET as an ID token."""
import asyncio
import hashlib
import math
import time
from datetime import UTC, datetime

import httpx
import jwt
from jwt.utils import base64url_decode

from .oidc import IdentityUnavailable, InvalidIdentity, ProviderKeys
from .provider_http import public_json, unique_json
from .security_event_models import VerifiedSecurityEvent
from .settings import AccountAuthSettings

RISC = "https://schemas.openid.net/secevent/risc/event-type/"
OAUTH = "https://schemas.openid.net/secevent/oauth/event-type/"
GOOGLE_SUBJECT_ISSUERS = {"accounts.google.com", "https://accounts.google.com", "https://accounts.google.com/"}


class GoogleRISCConfiguration:
    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        self.cached_until = 0
        self.attempted = float("-inf")
        self.lock = asyncio.Lock()

    async def issuer(self):
        async with self.lock:
            now = time.monotonic()
            if now < self.cached_until:
                return "https://accounts.google.com"
            if now - self.attempted < 30:
                raise IdentityUnavailable()
            self.attempted = now
            try:
                config = await public_json(self.client, "https://accounts.google.com/.well-known/risc-configuration", 8192)
                if (config["issuer"] != "https://accounts.google.com"
                        or config["jwks_uri"] != "https://www.googleapis.com/oauth2/v3/certs"):
                    raise ValueError("Unapproved RISC metadata")
            except (httpx.HTTPError, ValueError, KeyError, TypeError) as error:
                raise IdentityUnavailable() from error
            self.cached_until = now + 3600
            return config["issuer"]


class SecurityEventVerifier:
    def __init__(self, settings: AccountAuthSettings, keys: ProviderKeys, google: GoogleRISCConfiguration):
        self.settings, self.keys, self.google = settings, keys, google

    async def verify(self, provider: str, token: str) -> VerifiedSecurityEvent:
        if provider not in self.settings.verification_providers or not isinstance(token, str) or not 32 <= len(token) <= 16384:
            raise InvalidIdentity()
        try:
            encoded_header, encoded_payload, _ = token.split(".")
            header = unique_json(base64url_decode(encoded_header.encode("ascii")))
            unique_json(base64url_decode(encoded_payload.encode("ascii")))
            kid = header.get("kid")
            if (header.get("alg") != "RS256" or not self.text(kid, 256)
                    or any(key in header for key in ("jku", "x5u", "crit", "b64"))):
                raise InvalidIdentity()
            issuer = "https://appleid.apple.com" if provider == "apple" else await self.google.issuer()
            audience = self.settings.apple_audience if provider == "apple" else [
                self.settings.google_audience, self.settings.google_ios_client]
            key = await self.keys.key(provider, kid)
            claims = jwt.decode(token, key, algorithms=["RS256"], audience=audience, issuer=issuer,
                options={"require": ["iss", "aud", "iat", "jti", "events"],
                         "verify_exp": False, "verify_iat": False, "verify_nbf": False})
            jti = claims["jti"]
            if not self.text(jti, 256):
                raise InvalidIdentity()
            issued = self.timestamp(claims["iat"])
            events = claims["events"]
            if isinstance(events, str) and provider == "apple":
                events = unique_json(events)
            if not isinstance(events, dict):
                raise InvalidIdentity()
            if provider == "apple":
                kind, subject = events["type"], events["sub"]
                occurred = self.timestamp(events["event_time"])
                if not self.text(kind, 200) or not self.text(subject, 255) or (occurred - issued).total_seconds() > 60:
                    raise InvalidIdentity()
                action = {"consent-revoked": "revoke", "account-deleted": "delete"}.get(kind, "ignore")
                return VerifiedSecurityEvent(provider, jti, kind, subject, occurred, action)
            return self.google_event(jti, issued, events)
        except (jwt.PyJWTError, ValueError, TypeError, KeyError, AttributeError, OverflowError) as error:
            raise InvalidIdentity() from error

    def google_event(self, jti, occurred, events):
        if len(events) != 1:
            raise InvalidIdentity()
        kind, detail = next(iter(events.items()))
        if not self.text(kind, 200) or not isinstance(detail, dict):
            raise InvalidIdentity()
        if kind == RISC + "verification":
            state = detail.get("state")
            if not isinstance(state, str) or not 1 <= len(state.encode()) <= 2048 or any(ord(c) < 32 for c in state):
                raise InvalidIdentity()
            return VerifiedSecurityEvent("google", jti, kind, None, occurred, "ignore",
                                         hashlib.sha256(state.encode()).hexdigest())
        action = {RISC + "sessions-revoked": "revoke", OAUTH + "tokens-revoked": "revoke",
                  RISC + "account-credential-change-required": "revoke", RISC + "account-disabled": "disable",
                  RISC + "account-enabled": "enable"}.get(kind, "ignore")
        if action == "ignore":
            return VerifiedSecurityEvent("google", jti, kind, None, occurred, action)
        subject = detail["subject"]
        if (not isinstance(subject, dict) or subject.get("subject_type") not in {"iss-sub", "id_token_claims"}
                or subject.get("iss") not in GOOGLE_SUBJECT_ISSUERS or not self.text(subject.get("sub"), 255)):
            raise InvalidIdentity()
        return VerifiedSecurityEvent("google", jti, kind, subject["sub"], occurred, action)

    @staticmethod
    def text(value, maximum):
        return isinstance(value, str) and 1 <= len(value) <= maximum and all(32 < ord(c) < 127 for c in value)

    @staticmethod
    def timestamp(value):
        if type(value) not in (int, float) or not math.isfinite(value) or not 0 < value <= time.time() + 60:
            raise InvalidIdentity()
        return datetime.fromtimestamp(value, UTC)
