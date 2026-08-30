"""Small, read-only client for Hyperliquid's public Info API."""
from __future__ import annotations

import math
import os
import threading
import time
from typing import Any

import requests


DEFAULT_INFO_URL = "https://api.hyperliquid.xyz/info"


class HyperliquidInfoClient:
    def __init__(
        self,
        *,
        base_url: str | None = None,
        timeout: float = 30.0,
        retries: int = 5,
        pacing: bool = True,
        max_weight_per_minute: float = 1_080.0,
        session: requests.Session | None = None,
    ) -> None:
        self.base_url = base_url or os.environ.get("HYPERLIQUID_INFO_URL", DEFAULT_INFO_URL)
        self.timeout = timeout
        self.retries = retries
        self.pacing_enabled = pacing
        self.max_weight_per_minute = max(60.0, float(max_weight_per_minute))
        self._next_request_at = 0.0
        self._request_lock = threading.Lock()
        self.session = session or requests.Session()
        self.session.headers.update(
            {
                "Content-Type": "application/json",
                "User-Agent": "bSmart-Hyperliquid-Smart-Money/1.0",
            }
        )

    def set_pacing(self, enabled: bool) -> None:
        self.pacing_enabled = bool(enabled)

    def _pace_before_request(self) -> None:
        if not self.pacing_enabled:
            return
        delay = self._next_request_at - time.monotonic()
        if delay > 0:
            time.sleep(delay)

    @staticmethod
    def _response_weight(payload: dict[str, Any], result: Any) -> int:
        request_type = str(payload.get("type") or "")
        if request_type in {
            "userFills",
            "userFillsByTime",
            "userNonFundingLedgerUpdates",
            "recentTrades",
        } and isinstance(result, list):
            return 20 + math.ceil(len(result) / 20)
        return 20

    def _record_weight(self, weight: int) -> None:
        if not self.pacing_enabled:
            return
        seconds = max(1, int(weight)) * 60.0 / self.max_weight_per_minute
        self._next_request_at = max(time.monotonic(), self._next_request_at) + seconds

    def request(self, payload: dict[str, Any]) -> Any:
        with self._request_lock:
            return self._request_locked(payload)

    def _request_locked(self, payload: dict[str, Any]) -> Any:
        last_error: Exception | None = None
        for attempt in range(self.retries):
            try:
                self._pace_before_request()
                response = self.session.post(
                    self.base_url,
                    json=payload,
                    timeout=self.timeout,
                )
                response.raise_for_status()
                result = response.json()
                self._record_weight(self._response_weight(payload, result))
                return result
            except (requests.RequestException, ValueError) as exc:
                last_error = exc
                if attempt + 1 < self.retries:
                    retry_after = 0.0
                    response = getattr(exc, "response", None)
                    if response is not None and response.status_code == 429:
                        try:
                            retry_after = float(response.headers.get("Retry-After") or 0)
                        except (TypeError, ValueError):
                            retry_after = 0.0
                    delay = max(retry_after, min(30.0, 2.0 * (2**attempt)))
                    self._next_request_at = max(self._next_request_at, time.monotonic() + delay)
                    time.sleep(delay)
        raise RuntimeError(f"Hyperliquid Info API failed for {payload.get('type')}: {last_error}")

    def all_perp_metas(self) -> list[dict[str, Any]]:
        result = self.request({"type": "allPerpMetas"})
        return result if isinstance(result, list) else []

    def perp_categories(self) -> list[tuple[str, str]]:
        result = self.request({"type": "perpCategories"})
        rows: list[tuple[str, str]] = []
        if not isinstance(result, list):
            return rows
        for item in result:
            if isinstance(item, list) and len(item) >= 2:
                rows.append((str(item[0]), str(item[1])))
        return rows

    def meta_and_asset_contexts(self, dex: str) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        result = self.request({"type": "metaAndAssetCtxs", "dex": dex})
        if not isinstance(result, list) or len(result) < 2:
            return {}, []
        meta = result[0] if isinstance(result[0], dict) else {}
        contexts = result[1] if isinstance(result[1], list) else []
        return meta, [row for row in contexts if isinstance(row, dict)]

    def recent_trades(self, coin: str) -> list[dict[str, Any]]:
        result = self.request({"type": "recentTrades", "coin": coin})
        return [row for row in result if isinstance(row, dict)] if isinstance(result, list) else []

    def candles(
        self,
        coin: str,
        *,
        interval: str,
        start_ms: int,
        end_ms: int,
    ) -> list[dict[str, Any]]:
        result = self.request(
            {
                "type": "candleSnapshot",
                "req": {
                    "coin": coin,
                    "interval": interval,
                    "startTime": int(start_ms),
                    "endTime": int(end_ms),
                },
            }
        )
        return [row for row in result if isinstance(row, dict)] if isinstance(result, list) else []

    def user_fills_by_time(
        self,
        address: str,
        *,
        start_ms: int,
        end_ms: int | None = None,
        aggregate_by_time: bool = False,
    ) -> list[dict[str, Any]]:
        payload: dict[str, Any] = {
            "type": "userFillsByTime",
            "user": address,
            "startTime": int(start_ms),
            "aggregateByTime": aggregate_by_time,
        }
        if end_ms is not None:
            payload["endTime"] = int(end_ms)
        result = self.request(payload)
        return [row for row in result if isinstance(row, dict)] if isinstance(result, list) else []

    def paginated_user_fills_by_time(
        self,
        address: str,
        *,
        start_ms: int,
        end_ms: int | None = None,
        page_size: int = 2_000,
        max_fills: int = 10_000,
    ) -> tuple[list[dict[str, Any]], bool]:
        """Fetch every available fill in a time range without silently truncating.

        Hyperliquid returns at most 2,000 fills per request and only exposes the
        most recent 10,000 fills. Advancing by the last observed millisecond,
        while de-duplicating by the exchange fill identity, preserves fills
        that share a block timestamp and makes the coverage limit explicit.
        """
        upper_bound = int(end_ms if end_ms is not None else time.time() * 1_000)
        cursor = max(0, int(start_ms))
        rows: list[dict[str, Any]] = []
        seen: set[tuple[str, str, str, int]] = set()
        reached_history_limit = False

        while cursor <= upper_bound and len(rows) < max_fills:
            batch = self.user_fills_by_time(
                address,
                start_ms=cursor,
                end_ms=upper_bound,
                aggregate_by_time=False,
            )
            if not batch:
                break
            batch.sort(key=lambda row: int(float(row.get("time") or 0)))
            previous_count = len(rows)
            for row in batch:
                timestamp = int(float(row.get("time") or 0))
                identity = (
                    str(row.get("coin") or ""),
                    str(row.get("tid") or ""),
                    str(row.get("hash") or ""),
                    timestamp,
                )
                if identity in seen:
                    continue
                seen.add(identity)
                rows.append(row)
                if len(rows) >= max_fills:
                    reached_history_limit = True
                    break

            last_timestamp = max(
                (int(float(row.get("time") or 0)) for row in batch),
                default=cursor,
            )
            if len(batch) < page_size:
                break
            if last_timestamp <= cursor and len(rows) == previous_count:
                reached_history_limit = True
                break
            cursor = max(cursor + 1, last_timestamp + 1)

        if len(rows) >= max_fills:
            reached_history_limit = True
        return rows, reached_history_limit

    def clearinghouse_state(self, address: str, *, dex: str = "") -> dict[str, Any]:
        """Return the latest public perpetual account state for one venue."""
        payload: dict[str, Any] = {
            "type": "clearinghouseState",
            "user": address,
        }
        if dex:
            payload["dex"] = dex
        result = self.request(payload)
        return result if isinstance(result, dict) else {}

    def portfolio(self, address: str) -> list[list[Any]]:
        """Return Hyperliquid's public account-value and PnL histories."""
        result = self.request({"type": "portfolio", "user": address})
        return [row for row in result if isinstance(row, list) and len(row) >= 2] if isinstance(result, list) else []

    def user_non_funding_ledger_updates(
        self,
        address: str,
        *,
        start_ms: int,
        end_ms: int | None = None,
    ) -> list[dict[str, Any]]:
        payload: dict[str, Any] = {
            "type": "userNonFundingLedgerUpdates",
            "user": address,
            "startTime": int(start_ms),
        }
        if end_ms is not None:
            payload["endTime"] = int(end_ms)
        result = self.request(payload)
        return [row for row in result if isinstance(row, dict)] if isinstance(result, list) else []

    @staticmethod
    def suggested_fill_pause(fill_count: int) -> float:
        """Stay below the documented 1,200 weight/minute IP limit."""
        request_weight = 20 + math.ceil(max(0, fill_count) / 20)
        return max(0.2, request_weight / 18.0)
