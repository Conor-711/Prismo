from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Callable
from uuid import uuid4

import httpx
import jwt

from services.client_api.notification_delivery import PushResult
from services.client_api.state_store import ClaimedNotification


PERMANENT_REASONS = {
    "BadDeviceToken",
    "DeviceTokenNotForTopic",
    "Forbidden",
    "ExpiredToken",
    "Unregistered",
    "PayloadTooLarge",
}
INVALID_DEVICE_REASONS = {
    "BadDeviceToken",
    "DeviceTokenNotForTopic",
    "ExpiredToken",
    "Unregistered",
}
TOKEN_REFRESH_REASONS = {"ExpiredProviderToken", "InvalidProviderToken"}


@dataclass(frozen=True)
class APNsSettings:
    team_id: str
    key_id: str
    topic: str
    private_key_path: Path | None
    private_key: str | None = None

    @classmethod
    def from_environment(cls) -> "APNsSettings":
        values = {
            "team_id": os.environ.get("BSMART_APNS_TEAM_ID", "").strip(),
            "key_id": os.environ.get("BSMART_APNS_KEY_ID", "").strip(),
            "topic": os.environ.get("BSMART_APNS_TOPIC", "today.bsmart.ios").strip(),
            "private_key_path": os.environ.get("BSMART_APNS_PRIVATE_KEY_PATH", "").strip(),
            "private_key": os.environ.get("BSMART_APNS_PRIVATE_KEY", "").strip(),
        }
        missing = [key for key in ("team_id", "key_id", "topic") if not values[key]]
        if not values["private_key_path"] and not values["private_key"]:
            missing.append("private_key_path or private_key")
        if missing:
            raise RuntimeError(f"Missing APNs configuration: {', '.join(missing)}")
        private_key_path = None
        if values["private_key_path"]:
            private_key_path = Path(values["private_key_path"]).expanduser().resolve()
            if not private_key_path.is_file():
                raise RuntimeError(f"APNs private key does not exist: {private_key_path}")
        return cls(
            team_id=values["team_id"],
            key_id=values["key_id"],
            topic=values["topic"],
            private_key_path=private_key_path,
            private_key=values["private_key"] or None,
        )


class APNsProviderToken:
    def __init__(
        self,
        settings: APNsSettings,
        *,
        now: Callable[[], datetime] = lambda: datetime.now(UTC),
    ):
        self.settings = settings
        self.now = now
        if settings.private_key:
            self.private_key = settings.private_key.replace("\\n", "\n")
        elif settings.private_key_path:
            self.private_key = settings.private_key_path.read_text(encoding="utf-8")
        else:  # APNsSettings.from_environment prevents this in production.
            raise RuntimeError("APNs private key is required")
        self.cached_token: str | None = None
        self.issued_at: datetime | None = None

    def value(self) -> str:
        current_time = self.now().astimezone(UTC)
        if (
            self.cached_token is None
            or self.issued_at is None
            or current_time - self.issued_at >= timedelta(minutes=50)
        ):
            self.cached_token = jwt.encode(
                {"iss": self.settings.team_id, "iat": int(current_time.timestamp())},
                self.private_key,
                algorithm="ES256",
                headers={"kid": self.settings.key_id},
            )
            self.issued_at = current_time
        return self.cached_token

    def invalidate(self) -> None:
        self.cached_token = None
        self.issued_at = None


class APNsPushProvider:
    def __init__(
        self,
        settings: APNsSettings,
        *,
        client: httpx.AsyncClient | None = None,
        provider_token: APNsProviderToken | None = None,
    ):
        self.settings = settings
        self.client = client or httpx.AsyncClient(http2=True, timeout=10)
        self.provider_token = provider_token or APNsProviderToken(settings)

    async def send(self, delivery: ClaimedNotification) -> PushResult:
        for attempt in range(2):
            response = await self.client.post(
                _endpoint(delivery.environment, delivery.apns_token),
                headers={
                    "authorization": f"bearer {self.provider_token.value()}",
                    "apns-id": str(uuid4()),
                    "apns-push-type": "alert",
                    "apns-priority": "10",
                    "apns-expiration": "0",
                    "apns-topic": self.settings.topic,
                },
                json={
                    "aps": {
                        "alert": {"title": delivery.title, "body": delivery.body},
                        "sound": "default",
                        "thread-id": f"ticker.{delivery.ticker.lower()}",
                    },
                    "signalId": str(delivery.signal_id),
                    "deepLink": delivery.deep_link,
                    "ticker": delivery.ticker,
                },
            )
            reason = _response_reason(response)
            if response.status_code == 200:
                return PushResult(success=True, status_code=200)
            if reason in TOKEN_REFRESH_REASONS and attempt == 0:
                self.provider_token.invalidate()
                continue
            return PushResult(
                success=False,
                status_code=response.status_code,
                reason=reason or f"HTTP_{response.status_code}",
                permanent=(reason in PERMANENT_REASONS)
                or (400 <= response.status_code < 500 and response.status_code != 429),
                invalidate_device=reason in INVALID_DEVICE_REASONS,
                retry_after_seconds=_retry_after_seconds(response),
            )
        return PushResult(success=False, status_code=403, reason="InvalidProviderToken", permanent=True)

    async def close(self) -> None:
        await self.client.aclose()


def _endpoint(environment: str, device_token: str) -> str:
    host = "api.sandbox.push.apple.com" if environment == "development" else "api.push.apple.com"
    return f"https://{host}/3/device/{device_token}"


def _response_reason(response: httpx.Response) -> str | None:
    try:
        payload = response.json()
    except ValueError:
        return None
    reason = payload.get("reason") if isinstance(payload, dict) else None
    return str(reason) if reason else None


def _retry_after_seconds(response: httpx.Response) -> int | None:
    value = response.headers.get("retry-after")
    if value is None:
        return None
    try:
        return max(0, int(value))
    except ValueError:
        return None
