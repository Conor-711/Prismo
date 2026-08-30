"""Outbound TwitterAPI.io WebSocket transport for local realtime ingestion."""
from __future__ import annotations

import json
import logging
import threading
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

import websocket

from pipeline.platforms.x.realtime.normalizer import normalize_delivery
from pipeline.platforms.x.realtime.repository import XRealtimeRepository
from services.x_ingest.config import XIngestSettings


LOGGER = logging.getLogger("bsmart.x_ingest.stream")
WebSocketFactory = Callable[..., Any]


class TwitterAPIIOStreamConsumer:
    """Keep one provider socket open and idempotently persist rule matches."""

    def __init__(
        self,
        settings: XIngestSettings,
        repository: XRealtimeRepository,
        *,
        websocket_factory: WebSocketFactory = websocket.WebSocketApp,
    ) -> None:
        self.settings = settings
        self.repository = repository
        self.websocket_factory = websocket_factory
        self._stop = threading.Event()
        self._socket: Any | None = None
        self._connected_at: datetime | None = None

    def _handle_open(self, _socket: Any) -> None:
        self._connected_at = datetime.now(UTC)
        self.repository.mark_transport_connected("websocket", self._connected_at)
        LOGGER.info("TwitterAPI.io WebSocket opened")

    def _handle_error(self, _socket: Any, error: Any) -> None:
        self.repository.mark_transport_disconnected("websocket", error)
        LOGGER.warning("TwitterAPI.io WebSocket error: %s", error)

    def _handle_close(self, _socket: Any, code: Any, reason: Any) -> None:
        message = f"code={code} reason={reason}"
        self.repository.mark_transport_disconnected("websocket", message)
        LOGGER.warning("TwitterAPI.io WebSocket closed code=%s reason=%s", code, reason)

    def handle_message(self, message: str) -> None:
        try:
            payload = json.loads(message)
        except (TypeError, json.JSONDecodeError):
            LOGGER.warning("Ignoring malformed TwitterAPI.io WebSocket message")
            return
        if not isinstance(payload, dict):
            return
        event_type = str(payload.get("event_type") or "").lower()
        if event_type in {"connected", "ping"}:
            self.repository.mark_transport_heartbeat("websocket")
            if event_type == "connected":
                LOGGER.info("TwitterAPI.io WebSocket connected")
            return
        if event_type != "tweet":
            # fast_tweet belongs to the separately priced account-stream product.
            return
        try:
            tag, posts = normalize_delivery(payload)
        except (TypeError, ValueError) as exc:
            LOGGER.warning("Ignoring invalid TwitterAPI.io tweet event: %s", exc)
            return
        recovered = []
        live = []
        for post in posts:
            published_at = post.published_at
            if published_at.tzinfo is None:
                published_at = published_at.replace(tzinfo=UTC)
            else:
                published_at = published_at.astimezone(UTC)
            if self._connected_at and published_at < self._connected_at:
                recovered.append(post)
            else:
                live.append(post)
        results = [
            self.repository.ingest(
                batch,
                delivery_source=source,
                delivery_tag=tag,
            )
            for source, batch in (
                ("websocket", live),
                ("websocket_backfill", recovered),
            )
            if batch
        ]
        received = sum(result.received for result in results)
        inserted = sum(result.inserted for result in results)
        duplicates = sum(result.duplicates for result in results)
        ignored = sum(result.ignored for result in results)
        self.repository.record_delivery(
            source="websocket",
            received=len(payload.get("tweets") or []),
            inserted=inserted,
            estimated_cost_usd=len(payload.get("tweets") or []) * 0.00015,
        )
        LOGGER.info(
            "WebSocket delivery tag=%s received=%s inserted=%s duplicates=%s ignored=%s recovered=%s",
            tag,
            received,
            inserted,
            duplicates,
            ignored,
            len(recovered),
        )

    def run(self) -> None:
        while not self._stop.is_set():
            self._socket = self.websocket_factory(
                self.settings.twitterapi_io_stream_url,
                header={"x-api-key": self.settings.twitterapi_io_key},
                on_open=self._handle_open,
                on_message=lambda _socket, message: self.handle_message(message),
                on_error=self._handle_error,
                on_close=self._handle_close,
            )
            try:
                self._socket.run_forever(ping_interval=40, ping_timeout=30)
            except Exception:  # noqa: BLE001 - transport reconnects after bounded delay
                LOGGER.exception("TwitterAPI.io WebSocket loop failed")
            finally:
                self._socket = None
            if not self._stop.is_set():
                LOGGER.info(
                    "Reconnecting TwitterAPI.io WebSocket in %s seconds",
                    self.settings.stream_reconnect_seconds,
                )
                self._stop.wait(self.settings.stream_reconnect_seconds)

    def stop(self) -> None:
        self._stop.set()
        socket = self._socket
        if socket is not None:
            try:
                socket.close()
            except Exception:  # noqa: BLE001 - shutdown is best effort
                LOGGER.exception("Could not close TwitterAPI.io WebSocket cleanly")
