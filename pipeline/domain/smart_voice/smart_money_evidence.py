"""Client projection for Smart Money representative entries.

The upstream account Score remains authoritative. Representative entries are
ranked only by observable capital deployment and never alter that Score.
"""
from __future__ import annotations

import datetime as dt
import uuid
from collections import defaultdict
from typing import Any


_NAMESPACE = uuid.UUID("e4cecbef-8cf0-47ae-80a7-e100626526d7")
_ENTRY_ACTIONS = {"opened", "increased", "flipped"}


def representative_market_ranges(
    movements: list[dict[str, Any]],
    *,
    per_account_limit: int = 3,
) -> dict[str, tuple[dt.datetime, dt.datetime]]:
    """Return the market/time ranges needed by representative-entry charts."""
    selected = _ranked_groups(movements, per_account_limit=per_account_limit)
    ranges: dict[str, tuple[dt.datetime, dt.datetime]] = {}
    for group in selected:
        market = str(group["market"])
        times = [value for marker in group["markers"] if (value := _time(marker.get("observedAt")))]
        if not times:
            continue
        start = min(times) - dt.timedelta(days=3)
        end = max(times) + dt.timedelta(days=10)
        current = ranges.get(market)
        ranges[market] = (
            min(start, current[0]) if current else start,
            max(end, current[1]) if current else end,
        )
    return ranges


def build_smart_money_representative_evidence(
    signals: list[dict[str, Any]],
    movements: list[dict[str, Any]],
    *,
    candles_by_market: dict[str, list[dict[str, Any]]] | None = None,
    per_account_limit: int = 3,
    marker_limit: int = 10,
) -> list[dict[str, Any]]:
    """Build up to three auditable entry-timing charts per capital account."""
    candles_by_market = candles_by_market or {}
    identities = {str(signal.get("id") or ""): signal for signal in signals}
    asset_pnl = {
        (str(signal.get("id") or ""), str(asset.get("symbol") or "").upper()): float(asset.get("netPnl") or 0)
        for signal in signals
        for asset in signal.get("assetPerformance") or []
        if isinstance(asset, dict) and asset.get("symbol")
    }
    documents: list[dict[str, Any]] = []
    valid_rank_by_account: dict[str, int] = defaultdict(int)
    for group in _ranked_groups(movements, per_account_limit=per_account_limit):
        account_id = str(group["accountId"])
        signal = identities.get(account_id) or {}
        markers = sorted(
            group["markers"],
            key=lambda row: (-_entry_notional(row), str(row.get("observedAt") or "")),
        )[: max(1, marker_limit)]
        market = str(group["market"])
        ticker = str(group["ticker"])
        source_candles = candles_by_market.get(market) or []
        market_candles = _candles(source_candles)
        if not market_candles:
            continue
        valid_rank_by_account[account_id] += 1
        documents.append(
            {
                "id": str(uuid.uuid5(_NAMESPACE, f"{account_id}:{market}")),
                "accountId": account_id,
                "accountDisplayName": signal.get("displayName") or group.get("accountDisplayName") or "Anonymous capital account",
                "avatarVariant": signal.get("avatarVariant") or group.get("avatarVariant"),
                "ticker": ticker,
                "market": market,
                "representativeRank": valid_rank_by_account[account_id],
                "cumulativeEntryNotional": round(float(group["cumulativeEntryNotional"]), 2),
                "entryCount": int(group["entryCount"]),
                "assetNetPnl": round(asset_pnl.get((account_id, ticker), 0.0), 2),
                "latestEntryAt": max(str(marker.get("observedAt") or "") for marker in markers),
                "priceEvidence": {
                    "market": market,
                    "interval": "4h",
                    "source": "Hyperliquid candleSnapshot",
                    "candles": market_candles,
                    "entryMarkers": [_marker(marker, source_candles) for marker in markers],
                },
            }
        )
    documents.sort(key=lambda row: (str(row["accountId"]), int(row["representativeRank"])))
    return documents


def _ranked_groups(
    movements: list[dict[str, Any]],
    *,
    per_account_limit: int,
) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str], dict[str, Any]] = {}
    for movement in movements:
        action = str(movement.get("action") or "").lower()
        account_id = str(movement.get("accountId") or "")
        market = str(movement.get("market") or "")
        ticker = str(movement.get("ticker") or "").upper()
        entry_notional = _entry_notional(movement)
        if action not in _ENTRY_ACTIONS or not account_id or not market or not ticker or entry_notional <= 0:
            continue
        key = (account_id, market)
        group = grouped.setdefault(
            key,
            {
                "accountId": account_id,
                "accountDisplayName": movement.get("accountDisplayName"),
                "avatarVariant": movement.get("avatarVariant"),
                "ticker": ticker,
                "market": market,
                "cumulativeEntryNotional": 0.0,
                "entryCount": 0,
                "markers": [],
            },
        )
        group["cumulativeEntryNotional"] += entry_notional
        group["entryCount"] += 1
        group["markers"].append(movement)

    by_account: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for group in grouped.values():
        by_account[str(group["accountId"])].append(group)
    ranked: list[dict[str, Any]] = []
    for account_id in sorted(by_account):
        values = sorted(
            by_account[account_id],
            key=lambda row: (
                -float(row["cumulativeEntryNotional"]),
                -int(row["entryCount"]),
                str(row["ticker"]),
            ),
        )[: max(1, per_account_limit)]
        for rank, value in enumerate(values, start=1):
            ranked.append({**value, "rank": rank})
    return ranked


def _entry_notional(movement: dict[str, Any]) -> float:
    action = str(movement.get("action") or "").lower()
    before = abs(float(movement.get("notionalBefore") or 0))
    after = abs(float(movement.get("notionalAfter") or 0))
    if action in {"opened", "flipped"}:
        return after
    if action == "increased":
        return max(0.0, after - before)
    return 0.0


def _marker(movement: dict[str, Any], candles: list[dict[str, Any]]) -> dict[str, Any]:
    explicit_price = _movement_price(movement)
    return {
        "id": movement["id"],
        "observedAt": movement["observedAt"],
        "price": explicit_price or _nearest_candle_price(movement.get("observedAt"), candles),
        "priceBasis": "reported" if explicit_price > 0 else "nearest_4h_close",
        "direction": movement.get("direction") or "neutral",
        "action": movement["action"],
        "entryNotional": round(_entry_notional(movement), 2),
        "evidenceURL": movement.get("evidenceURL"),
    }


def _movement_price(movement: dict[str, Any]) -> float:
    explicit = movement.get("price")
    if explicit is not None:
        return float(explicit)
    notional = abs(float(movement.get("notionalAfter") or 0))
    size = abs(float(movement.get("sizeAfter") or 0))
    return notional / size if size > 0 else 0.0


def _nearest_candle_price(observed_at: Any, candles: list[dict[str, Any]]) -> float:
    observed = _time(observed_at)
    if observed is None:
        return 0.0
    candidates: list[tuple[float, float]] = []
    for row in candles:
        timestamp = row.get("timestamp") or row.get("t")
        if isinstance(timestamp, (int, float)):
            candle_time = dt.datetime.fromtimestamp(float(timestamp) / 1_000, tz=dt.timezone.utc)
        else:
            candle_time = _time(timestamp)
        close = float(row.get("close") if row.get("close") is not None else row.get("c") or 0)
        if candle_time is not None and close > 0:
            candidates.append((abs((candle_time - observed).total_seconds()), close))
    return min(candidates)[1] if candidates else 0.0


def _candles(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    for row in rows:
        timestamp = row.get("timestamp") or row.get("t")
        if timestamp is None:
            continue
        if isinstance(timestamp, (int, float)):
            timestamp = dt.datetime.fromtimestamp(float(timestamp) / 1_000, tz=dt.timezone.utc).isoformat().replace("+00:00", "Z")
        result.append(
            {
                "timestamp": timestamp,
                "open": float(row.get("open") if row.get("open") is not None else row.get("o") or 0),
                "high": float(row.get("high") if row.get("high") is not None else row.get("h") or 0),
                "low": float(row.get("low") if row.get("low") is not None else row.get("l") or 0),
                "close": float(row.get("close") if row.get("close") is not None else row.get("c") or 0),
                "volume": float(row.get("volume") if row.get("volume") is not None else row.get("v") or 0),
            }
        )
    return sorted(result, key=lambda row: str(row["timestamp"]))


def _time(value: Any) -> dt.datetime | None:
    try:
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return parsed.replace(tzinfo=parsed.tzinfo or dt.timezone.utc).astimezone(dt.timezone.utc)
