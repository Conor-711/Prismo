"""Atomic Smart Money collection publication shared by upstream sources."""
from __future__ import annotations

import hashlib
import json
import datetime as dt
import time
from pathlib import Path
from typing import Any

from ...domain.smart_voice.hyperliquid import build_hyperliquid_client_collections
from ...domain.smart_voice.smart_money_evidence import representative_market_ranges
from ...platforms.hyperliquid import HyperliquidInfoClient


CandleCache = dict[str, tuple[float, list[dict[str, Any]]]]


def fetch_representative_candles(
    payload: dict[str, Any],
    *,
    client: HyperliquidInfoClient,
    cache: CandleCache,
    refresh_seconds: int = 600,
) -> dict[str, list[dict[str, Any]]]:
    preliminary = build_hyperliquid_client_collections(payload)
    ranges = representative_market_ranges(preliminary["smart-money-movements"])
    now = dt.datetime.now(dt.timezone.utc)
    monotonic_now = time.monotonic()
    result: dict[str, list[dict[str, Any]]] = {}
    for market, (start, end) in ranges.items():
        cached = cache.get(market)
        if cached and monotonic_now - cached[0] < max(60, refresh_seconds):
            result[market] = cached[1]
            continue
        try:
            candles = client.candles(
                market,
                interval="4h",
                start_ms=int(start.timestamp() * 1_000),
                end_ms=int(min(end, now).timestamp() * 1_000),
            )
        except RuntimeError:
            candles = cached[1] if cached else []
        cache[market] = (monotonic_now, candles)
        result[market] = candles
    return result


def write_smart_money_client_collections(
    destination: Path,
    payload: dict[str, Any],
    *,
    smart_account_updates: list[dict[str, Any]] | None = None,
    candle_client: HyperliquidInfoClient | None = None,
    candle_cache: CandleCache | None = None,
) -> dict[str, int]:
    destination.mkdir(parents=True, exist_ok=True)
    candles = (
        fetch_representative_candles(
            payload,
            client=candle_client,
            cache=candle_cache if candle_cache is not None else {},
        )
        if candle_client is not None
        else {}
    )
    collections = build_hyperliquid_client_collections(
        payload,
        smart_account_updates=smart_account_updates,
        smart_money_candles=candles,
    )
    serialized: dict[str, bytes] = {}
    for name, documents in collections.items():
        target = destination / f"{name}.json"
        temporary = target.with_suffix(".json.tmp")
        raw = (json.dumps(documents, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        temporary.write_bytes(raw)
        serialized[name] = raw
    for name in collections:
        target = destination / f"{name}.json"
        target.with_suffix(".json.tmp").replace(target)

    source = payload.get("source") if isinstance(payload.get("source"), dict) else {}
    manifest = {
        "generatedAt": payload.get("generatedAt"),
        "source": source.get("provider") or "hyperliquid",
        "sourceUpdatedAt": source.get("updatedAt") or payload.get("generatedAt"),
        "collections": {
            name: {
                "count": len(collections[name]),
                "sha256": hashlib.sha256(serialized[name]).hexdigest(),
            }
            for name in sorted(collections)
        },
    }
    manifest_target = destination / "smart-money-live-manifest.json"
    manifest_temporary = manifest_target.with_suffix(".json.tmp")
    manifest_temporary.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    manifest_temporary.replace(manifest_target)
    return {name: len(documents) for name, documents in collections.items()}
