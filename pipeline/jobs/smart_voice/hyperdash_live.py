"""Continuously materialize Hyperdash Smart Money data for bSmart clients."""
from __future__ import annotations

import datetime as dt
import json
import threading
import time
from pathlib import Path
from typing import Any

from ...common.config import ROOT, RUNTIME_DATA_DIR
from ...platforms.hyperdash import HyperdashGraphQLClient, build_hyperdash_smart_money_payload
from ...platforms.hyperliquid import HyperliquidInfoClient
from .smart_money_publish import write_smart_money_client_collections


def run_hyperdash_live(
    *,
    db_path: str = "",
    output_path: str = "",
    client_output_dir: str = "",
    health_output_path: str = "",
    lookback_days: int = 30,
    refresh_seconds: int = 600,
    publish_seconds: int = 60,
    max_cycles: int = 0,
    hyperdash_graphql_url: str = "",
    hyperdash_group_id: str = "equities",
    hyperdash_max_wallets: int = 100,
    hyperdash_position_limit: int = 12,
    hyperdash_max_stale_seconds: int = 1800,
    smart_account_updates_path: str = "",
    client: HyperdashGraphQLClient | None = None,
    candle_client: HyperliquidInfoClient | None = None,
    stop_event: threading.Event | None = None,
    **_: Any,
) -> dict[str, Any]:
    """Poll Hyperdash's public 30-day equity cohort and atomically publish it.

    ``db_path`` and ``publish_seconds`` are accepted to preserve the common
    service runner interface. Hyperdash remains the scoring authority; this
    job only normalizes, diffs snapshots for movement events, and publishes.
    """
    del db_path, publish_seconds
    output = (
        Path(output_path).resolve()
        if output_path
        else (ROOT / "web" / "lib" / "data" / "hyperliquidSmartMoney.json").resolve()
    )
    destination = Path(client_output_dir).resolve() if client_output_dir else None
    health_output = (
        Path(health_output_path).resolve()
        if health_output_path
        else (RUNTIME_DATA_DIR / "smart-money-live-health.json").resolve()
    )
    state_dir = health_output.parent
    cache_path = state_dir / "hyperdash-last-good.json"
    fallback_path = state_dir / "hyperliquid-fallback.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    health_output.parent.mkdir(parents=True, exist_ok=True)

    existing = _read_json(output)
    if existing and _provider(existing) != "hyperdash" and not fallback_path.exists():
        _atomic_write_json(fallback_path, existing)
    previous = _read_json(cache_path)
    if not previous and _provider(existing) == "hyperdash":
        previous = existing

    source_client = client or HyperdashGraphQLClient(
        graphql_url=hyperdash_graphql_url or None,
    )
    price_client = candle_client or (HyperliquidInfoClient() if client is None else None)
    candle_cache: dict[str, tuple[float, list[dict[str, Any]]]] = {}
    stop = stop_event or threading.Event()
    cycles = 0
    last_success_at = _payload_time(previous)
    last_error: str | None = None
    result: dict[str, Any] = {}

    while not stop.is_set():
        started_at = dt.datetime.now(dt.timezone.utc)
        collection_counts: dict[str, int] = {}
        position_coverage = 0.0
        position_error: str | None = None
        active_source = "hyperdash"
        try:
            traders = source_client.equity_traders(
                group_id=hyperdash_group_id,
                limit=max(1, int(hyperdash_max_wallets)),
            )
            if not traders:
                raise RuntimeError("Hyperdash Equities Focused cohort returned no traders")
            addresses = [str(row.get("address") or "") for row in traders]
            try:
                positions = source_client.trader_positions(
                    addresses,
                    timestamp_ms=int(started_at.timestamp() * 1_000),
                    position_limit=max(1, int(hyperdash_position_limit)),
                )
            except Exception as exc:
                position_error = str(exc)[:1_000]
                positions = _positions_from_payload(previous)
            position_coverage = len(positions) / len(traders)
            if position_coverage < 1:
                positions = {
                    **_positions_from_payload(previous),
                    **positions,
                }
            payload = build_hyperdash_smart_money_payload(
                traders,
                positions,
                generated_at=started_at,
                previous_payload=previous,
                lookback_days=min(30, max(1, int(lookback_days))),
            )
            _atomic_write_json(output, payload)
            _atomic_write_json(cache_path, payload)
            if destination is not None:
                collection_counts = write_smart_money_client_collections(
                    destination,
                    payload,
                    candle_client=price_client,
                    candle_cache=candle_cache,
                    smart_account_updates=(
                        _read_json_array(Path(smart_account_updates_path).resolve())
                        if smart_account_updates_path
                        else []
                    ),
                )
            previous = payload
            last_success_at = started_at
            last_error = None
            ready = True
            reasons = []
            if position_coverage < 0.95:
                reasons.append("hyperdash_position_coverage_incomplete")
        except Exception as exc:
            last_error = str(exc)[:1_000]
            payload, active_source = _best_available_payload(
                previous=previous,
                fallback_path=fallback_path,
                now=started_at,
                max_stale_seconds=max(60, int(hyperdash_max_stale_seconds)),
            )
            age = _age_seconds(payload, started_at) if payload else None
            ready = bool(payload) and age is not None and age <= max(60, int(hyperdash_max_stale_seconds))
            reasons = ["hyperdash_fetch_failed"]
            if not payload:
                reasons.append("no_fallback_snapshot")
            elif not ready:
                reasons.append("fallback_snapshot_stale")
            if payload:
                _atomic_write_json(output, payload)
                if destination is not None:
                    collection_counts = write_smart_money_client_collections(
                        destination,
                        payload,
                        candle_client=price_client,
                        candle_cache=candle_cache,
                        smart_account_updates=(
                            _read_json_array(Path(smart_account_updates_path).resolve())
                            if smart_account_updates_path
                            else []
                        ),
                    )

        source_age = _age_seconds(payload, started_at) if payload else None
        health = {
            "status": (
                "healthy"
                if ready and active_source == "hyperdash" and not reasons
                else "degraded"
            ),
            "running": True,
            "primarySource": "hyperdash",
            "activeSource": active_source,
            "sourceUpdatedAt": (payload or {}).get("generatedAt"),
            "sourceLagSeconds": source_age,
            "lastSuccessfulHyperdashAt": _iso(last_success_at) if last_success_at else None,
            "lastError": last_error,
            "positionError": position_error,
            "lookbackDays": min(30, max(1, int(lookback_days))),
            "positionCoverage": round(position_coverage, 4),
            "walletCount": len((payload or {}).get("leaderboard") or []),
            "collectionCounts": collection_counts,
            "readiness": {
                "realtime": bool(ready and active_source == "hyperdash"),
                "complete": bool(ready and position_coverage >= 0.95),
                "ready": bool(ready),
                "reasons": reasons,
            },
        }
        _atomic_write_json(health_output, health)
        result = health
        cycles += 1
        if max_cycles and cycles >= max_cycles:
            break
        elapsed = (dt.datetime.now(dt.timezone.utc) - started_at).total_seconds()
        stop.wait(max(1.0, float(refresh_seconds) - elapsed))

    if stop.is_set():
        result = {**result, "running": False}
        _atomic_write_json(health_output, result)
    return result


def _best_available_payload(
    *,
    previous: dict[str, Any],
    fallback_path: Path,
    now: dt.datetime,
    max_stale_seconds: int,
) -> tuple[dict[str, Any], str]:
    previous_age = _age_seconds(previous, now) if previous else None
    if previous and previous_age is not None and previous_age <= max_stale_seconds:
        return previous, "hyperdash_cached"
    fallback = _read_json(fallback_path)
    if fallback:
        return fallback, "hyperliquid_fallback"
    return previous, "hyperdash_cached" if previous else "unavailable"


def _positions_from_payload(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    positions: dict[str, dict[str, Any]] = {}
    for wallet in payload.get("leaderboard") or []:
        if (
            not isinstance(wallet, dict)
            or not wallet.get("address")
            or not wallet.get("positionSnapshotAt")
        ):
            continue
        rows = []
        for row in wallet.get("currentPositions") or []:
            if not isinstance(row, dict):
                continue
            signed_size = row.get("signedSize")
            if signed_size is None:
                size = float(row.get("size") or 0)
                signed_size = -abs(size) if str(row.get("direction") or "").lower() == "short" else abs(size)
            rows.append(
                {
                    "market": row.get("coin") or row.get("symbol"),
                    "size": signed_size,
                    "notionalSize": row.get("notional") or 0,
                    "entryPrice": row.get("entryPrice"),
                    "liquidationPrice": row.get("liquidationPrice"),
                    "unrealizedPnl": row.get("unrealizedPnl") or 0,
                    "fundingPnl": row.get("fundingSinceOpen") or 0,
                }
            )
        positions[str(wallet["address"]).lower()] = {
            "positions": rows,
            "positionsCount": len(rows),
            "totalUnrealizedPnl": wallet.get("unrealizedPnl") or 0,
        }
    return positions


def _provider(payload: dict[str, Any]) -> str:
    source = payload.get("source")
    if isinstance(source, dict):
        return str(source.get("provider") or "")
    return "hyperliquid" if str(payload.get("version") or "").startswith("hyperliquid") else ""


def _payload_time(payload: dict[str, Any]) -> dt.datetime | None:
    raw = str(payload.get("generatedAt") or "")
    if not raw:
        return None
    try:
        parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed.replace(tzinfo=parsed.tzinfo or dt.timezone.utc).astimezone(dt.timezone.utc)


def _age_seconds(payload: dict[str, Any], now: dt.datetime) -> int | None:
    generated_at = _payload_time(payload)
    if generated_at is None:
        return None
    return max(0, int((now - generated_at).total_seconds()))


def _read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def _read_json_array(path: Path) -> list[dict[str, Any]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError):
        return []
    if not isinstance(payload, list):
        return []
    return [item for item in payload if isinstance(item, dict)]


def _atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    temporary.replace(path)


def _iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat()
