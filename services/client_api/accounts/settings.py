from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .apple_oauth import AppleOAuthSettings


@dataclass(frozen=True)
class AccountAuthSettings:
    apple_audience: str = ""
    google_audience: str = ""
    google_ios_client: str = ""
    enabled: bool = False
    apple: AppleOAuthSettings | None = field(default=None, repr=False)
    deletion_worker_enabled: bool = False
    supabase_url: str = ""
    supabase_publishable_key: str = field(default="", repr=False)

    @classmethod
    def from_environment(cls, environment: str) -> "AccountAuthSettings":
        # Lifecycle/recovery is not production-ready. Client IDs cannot open this gate.
        enabled = (environment in {"development", "test"}
                   and os.getenv("BSMART_ACCOUNT_AUTH_DEVELOPMENT", "") == "1")
        apple_audience = os.getenv("BSMART_APPLE_CLIENT_ID", "").strip()
        apple = None
        if enabled and apple_audience:
            from cryptography.exceptions import UnsupportedAlgorithm
            from .apple_oauth import AppleOAuthSettings
            try:
                apple = AppleOAuthSettings.from_environment(apple_audience)
            except (OSError, ValueError, TypeError, KeyError, UnsupportedAlgorithm):
                # Configuration failure hides Apple sign-in; never expose secret-file contents.
                pass
        return cls(
            apple_audience=apple_audience,
            google_audience=os.getenv("BSMART_GOOGLE_SERVER_CLIENT_ID", "").strip(),
            google_ios_client=os.getenv("BSMART_GOOGLE_IOS_CLIENT_ID", "").strip(),
            enabled=enabled,
            apple=apple,
            deletion_worker_enabled=enabled and os.getenv("BSMART_ACCOUNT_DELETION_WORKER", "") == "1",
            supabase_url=os.getenv("BSMART_SUPABASE_URL", "").strip().rstrip("/"),
            supabase_publishable_key=os.getenv("BSMART_SUPABASE_PUBLISHABLE_KEY", "").strip(),
        )

    @property
    def uses_supabase(self) -> bool:
        return bool(self.supabase_url or self.supabase_publishable_key)

    @property
    def supabase_configured(self) -> bool:
        # Never accept a service-role credential or an arbitrary token destination.
        return bool(re.fullmatch(r"https://[a-z0-9]{20}\.supabase\.co", self.supabase_url)
                    and re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{16,128}", self.supabase_publishable_key))

    @property
    def providers(self) -> list[str]:
        if self.uses_supabase:
            return (["google"] if self.supabase_configured and "google" in self.verification_providers else [])
        return [provider for provider in self.verification_providers if provider != "apple"
                or (self.apple is not None and self.apple.client_id == self.apple_audience)]

    @property
    def verification_providers(self) -> list[str]:
        if not self.enabled:
            return []
        return (["apple"] if self.apple_audience else []) + (
            ["google"] if self.google_audience and self.google_ios_client else []
        )
