"""Resilient public trade stream for Hyperliquid HIP-3 instruments."""
from __future__ import annotations

import json
import os
import time
from collections.abc import Iterable, Iterator
from datetime import datetime, timezone
from threading import Event, Lock
from typing import Any
from urllib.parse import unquote, urlparse
from urllib.request import getproxies, proxy_bypass

import websocket


DEFAULT_WS_URL = "wss://api.hyperliquid.xyz/ws"


def _utc_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def parse_trade_message(message: str | bytes) -> list[dict[str, Any]]:
    if isinstance(message, bytes):
        message = message.decode("utf-8")
    try:
        payload = json.loads(message)
    except (TypeError, ValueError, UnicodeDecodeError):
        return []
    if not isinstance(payload, dict) or payload.get("channel") != "trades":
        return []
    data = payload.get("data")
    if isinstance(data, dict):
        data = [data]
    return [row for row in data if isinstance(row, dict)] if isinstance(data, list) else []


def parse_all_dexs_state_message(
    message: str | bytes,
) -> tuple[str, list[tuple[str, dict[str, Any]]]] | None:
    """Parse the all-DEX account-state snapshot returned by Hyperliquid WS."""
    if isinstance(message, bytes):
        message = message.decode("utf-8")
    try:
        payload = json.loads(message)
    except (TypeError, ValueError, UnicodeDecodeError):
        return None
    if not isinstance(payload, dict) or payload.get("channel") != "allDexsClearinghouseState":
        return None
    data = payload.get("data")
    if not isinstance(data, dict):
        return None
    address = str(data.get("user") or "").lower()
    if not address:
        return None
    states: list[tuple[str, dict[str, Any]]] = []
    for item in data.get("clearinghouseStates") or []:
        if (
            isinstance(item, list)
            and len(item) >= 2
            and isinstance(item[1], dict)
        ):
            states.append((str(item[0] or ""), item[1]))
    return address, states


class HyperliquidTradeStream:
    """Subscribe to every requested public trade feed with reconnect support."""

    def __init__(
        self,
        *,
        url: str | None = None,
        proxy_url: str | None = None,
        timeout: float = 20.0,
        reconnect: bool = True,
    ) -> None:
        self.url = url or os.environ.get("HYPERLIQUID_WS_URL", DEFAULT_WS_URL)
        if proxy_url is None:
            proxy_url = os.environ.get("HYPERLIQUID_WS_PROXY")
            if proxy_url is None:
                proxies = getproxies()
                proxy_url = proxies.get("https") or proxies.get("http")
        self.proxy_url = proxy_url or ""
        self.timeout = timeout
        self.reconnect = reconnect
        self.connected = False
        self.last_connected_at: str | None = None
        self.last_message_at: str | None = None
        self.last_trade_at: str | None = None
        self.last_error: str | None = None
        self.reconnect_count = 0
        self._connection: Any = None
        self._connection_lock = Lock()
        self._subscription_lock = Lock()
        self._subscriptions: set[str] = set()

    def close(self) -> None:
        with self._connection_lock:
            connection = self._connection
        if connection is not None:
            try:
                connection.close()
            except Exception:
                pass

    def update_subscriptions(self, coins: Iterable[str]) -> None:
        """Apply a complete public-trade subscription set without reconnecting."""
        desired = {str(coin) for coin in coins if str(coin)}
        with self._subscription_lock:
            added = sorted(desired - self._subscriptions)
            removed = sorted(self._subscriptions - desired)
            self._subscriptions = desired
        with self._connection_lock:
            connection = self._connection
            if connection is None:
                return
            try:
                for coin in removed:
                    connection.send(
                        json.dumps(
                            {
                                "method": "unsubscribe",
                                "subscription": {"type": "trades", "coin": coin},
                            },
                            separators=(",", ":"),
                        )
                    )
                for coin in added:
                    connection.send(
                        json.dumps(
                            {
                                "method": "subscribe",
                                "subscription": {"type": "trades", "coin": coin},
                            },
                            separators=(",", ":"),
                        )
                    )
            except (OSError, websocket.WebSocketException) as exc:
                self.last_error = str(exc)[:500]

    def account_state_snapshots(
        self,
        addresses: Iterable[str],
        *,
        timeout: float | None = None,
    ) -> dict[str, list[tuple[str, dict[str, Any]]]]:
        """Fetch one all-DEX state snapshot for up to ten public accounts.

        Hyperliquid limits user-specific WebSocket subscriptions to ten unique
        users per connection. A short-lived second connection keeps the public
        trade tape uninterrupted while replacing dozens of per-DEX REST calls.
        """
        users = list(dict.fromkeys(str(address).lower() for address in addresses if str(address)))
        if len(users) > 10:
            raise ValueError("Hyperliquid account snapshot batches are limited to 10 users")
        if not users:
            return {}
        deadline = time.monotonic() + max(1.0, float(timeout or self.timeout))
        connection = websocket.create_connection(
            self.url,
            timeout=max(1.0, float(timeout or self.timeout)),
            header=["User-Agent: bSmart-Hyperliquid-Smart-Money/1.0"],
            **self._proxy_options(),
        )
        snapshots: dict[str, list[tuple[str, dict[str, Any]]]] = {}
        try:
            for address in users:
                connection.send(
                    json.dumps(
                        {
                            "method": "subscribe",
                            "subscription": {
                                "type": "allDexsClearinghouseState",
                                "user": address,
                            },
                        },
                        separators=(",", ":"),
                    )
                )
            while len(snapshots) < len(users):
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                connection.settimeout(remaining)
                try:
                    parsed = parse_all_dexs_state_message(connection.recv())
                except websocket.WebSocketTimeoutException:
                    break
                if parsed is not None and parsed[0] in users:
                    snapshots[parsed[0]] = parsed[1]
        except (OSError, websocket.WebSocketException) as exc:
            if not snapshots:
                raise RuntimeError(f"Hyperliquid account-state WebSocket failed: {exc}") from exc
        finally:
            connection.close()
        return snapshots

    def _proxy_options(self) -> dict[str, Any]:
        host = urlparse(self.url).hostname or ""
        if not self.proxy_url or proxy_bypass(host):
            return {}
        parsed = urlparse(self.proxy_url if "://" in self.proxy_url else f"http://{self.proxy_url}")
        if not parsed.hostname:
            return {}
        scheme = parsed.scheme.lower()
        proxy_type = "http" if scheme in {"http", "https"} else scheme
        options: dict[str, Any] = {
            "http_proxy_host": parsed.hostname,
            "http_proxy_port": parsed.port or (443 if scheme == "https" else 80),
            "proxy_type": proxy_type,
        }
        if parsed.username is not None:
            options["http_proxy_auth"] = (
                unquote(parsed.username),
                unquote(parsed.password or ""),
            )
        return options

    def iter_batches(
        self,
        coins: Iterable[str],
        *,
        stop_event: Event | None = None,
    ) -> Iterator[list[dict[str, Any]]]:
        self.update_subscriptions(coins)
        with self._subscription_lock:
            subscriptions = sorted(self._subscriptions)
        if not subscriptions:
            return
        stop = stop_event or Event()
        reconnect_delay = 1.0
        while not stop.is_set():
            connection = None
            try:
                connection = websocket.create_connection(
                    self.url,
                    timeout=self.timeout,
                    header=["User-Agent: bSmart-Hyperliquid-Smart-Money/1.0"],
                    **self._proxy_options(),
                )
                with self._connection_lock:
                    self._connection = connection
                self.connected = True
                self.last_connected_at = _utc_iso()
                self.last_error = None
                with self._subscription_lock:
                    subscriptions = sorted(self._subscriptions)
                for coin in subscriptions:
                    connection.send(
                        json.dumps(
                            {
                                "method": "subscribe",
                                "subscription": {"type": "trades", "coin": coin},
                            },
                            separators=(",", ":"),
                        )
                    )
                reconnect_delay = 1.0
                while not stop.is_set():
                    try:
                        message = connection.recv()
                    except websocket.WebSocketTimeoutException:
                        connection.ping()
                        yield []
                        continue
                    if message is None:
                        raise websocket.WebSocketConnectionClosedException("Hyperliquid stream closed")
                    self.last_message_at = _utc_iso()
                    trades = parse_trade_message(message)
                    if trades:
                        self.last_trade_at = self.last_message_at
                        yield trades
            except (OSError, websocket.WebSocketException) as exc:
                self.connected = False
                if stop.is_set():
                    break
                self.last_error = str(exc)[:500]
                self.reconnect_count += 1
                if not self.reconnect:
                    raise RuntimeError(f"Hyperliquid WebSocket failed: {exc}") from exc
                yield []
                time.sleep(reconnect_delay)
                reconnect_delay = min(30.0, reconnect_delay * 2)
            finally:
                self.connected = False
                with self._connection_lock:
                    self._connection = None
                if connection is not None:
                    connection.close()
