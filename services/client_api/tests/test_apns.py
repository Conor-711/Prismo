from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from services.client_api.apns import APNsProviderToken, APNsPushProvider, APNsSettings
from services.client_api.state_store import ClaimedNotification


@pytest.mark.anyio
async def test_apns_provider_refreshes_expired_auth_and_sends_deep_link_payload() -> None:
    calls: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        if len(calls) == 1:
            return httpx.Response(403, json={"reason": "ExpiredProviderToken"})
        return httpx.Response(200)

    token = StubProviderToken()
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler), http2=True)
    provider = APNsPushProvider(
        APNsSettings(
            team_id="TEAM123456",
            key_id="KEY1234567",
            topic="today.bsmart.ios",
            private_key_path=Path("unused"),
        ),
        client=client,
        provider_token=token,
    )
    signal_id = uuid4()
    result = await provider.send(ClaimedNotification(
        installation_id=uuid4(),
        signal_id=signal_id,
        ticker="NVDA",
        title="NVDA changed",
        body="A qualified account changed its view.",
        deep_link=f"bsmart://signals/{signal_id}",
        apns_token="device-token",
        environment="development",
    ))
    await provider.close()

    assert result.success is True
    assert token.invalidations == 1
    assert len(calls) == 2
    assert calls[-1].url.host == "api.sandbox.push.apple.com"
    assert calls[-1].headers["apns-topic"] == "today.bsmart.ios"
    assert calls[-1].headers["apns-push-type"] == "alert"
    payload = json.loads(calls[-1].content)
    assert payload["signalId"] == str(signal_id)
    assert payload["aps"]["thread-id"] == "ticker.nvda"


@pytest.mark.anyio
async def test_apns_provider_marks_unregistered_device_as_permanent() -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(410, json={"reason": "Unregistered"})
        ),
        http2=True,
    )
    provider = APNsPushProvider(
        APNsSettings("TEAM123456", "KEY1234567", "today.bsmart.ios", Path("unused")),
        client=client,
        provider_token=StubProviderToken(),
    )
    result = await provider.send(ClaimedNotification(
        installation_id=uuid4(),
        signal_id=uuid4(),
        ticker="HOOD",
        title="HOOD changed",
        body="Capital moved.",
        deep_link="bsmart://signals/example",
        apns_token="expired-device",
        environment="production",
    ))
    await provider.close()

    assert result.permanent is True
    assert result.invalidate_device is True
    assert result.reason == "Unregistered"


def test_provider_jwt_is_reused_then_refreshed_after_fifty_minutes() -> None:
    with TemporaryDirectory() as directory:
        private_key = ec.generate_private_key(ec.SECP256R1())
        key_path = Path(directory) / "AuthKey.p8"
        key_path.write_bytes(private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ))
        current = [datetime(2026, 8, 4, 12, tzinfo=UTC)]
        provider_token = APNsProviderToken(
            APNsSettings("TEAM123456", "KEY1234567", "today.bsmart.ios", key_path),
            now=lambda: current[0],
        )

        first = provider_token.value()
        current[0] += timedelta(minutes=49)
        second = provider_token.value()
        current[0] += timedelta(minutes=1)
        third = provider_token.value()
        claims = jwt.decode(
            third,
            private_key.public_key(),
            algorithms=["ES256"],
            options={"verify_iat": False},
        )

        assert first == second
        assert third != second
        assert claims["iss"] == "TEAM123456"
        assert claims["iat"] == int(current[0].timestamp())


def test_apns_settings_accept_private_key_secret(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("BSMART_APNS_TEAM_ID", "TEAM123456")
    monkeypatch.setenv("BSMART_APNS_KEY_ID", "KEY1234567")
    monkeypatch.setenv("BSMART_APNS_TOPIC", "today.bsmart.ios")
    monkeypatch.delenv("BSMART_APNS_PRIVATE_KEY_PATH", raising=False)
    monkeypatch.setenv("BSMART_APNS_PRIVATE_KEY", "line-one\\nline-two")

    settings = APNsSettings.from_environment()

    assert settings.private_key_path is None
    assert settings.private_key == "line-one\\nline-two"


class StubProviderToken:
    def __init__(self) -> None:
        self.invalidations = 0

    def value(self) -> str:
        return "provider-token"

    def invalidate(self) -> None:
        self.invalidations += 1
