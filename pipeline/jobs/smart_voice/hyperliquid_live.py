"""Continuous Hyperliquid HIP-3 Smart Money ingestion and materialization."""
from __future__ import annotations

import datetime as dt
import concurrent.futures
import hashlib
import json
import queue
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any

from ...common.config import ROOT, RUNTIME_DATA_DIR
from ...domain.smart_voice.hyperliquid import (
    HL_CANDIDATE_ACTIVITY_DAYS,
    HL_CANDIDATE_POOL_SIZE,
    HL_DISCOVERY_MIN_NOTIONAL,
    HL_DISCOVERY_MIN_TRADES,
    build_hyperliquid_client_collections,
    build_wallet_scores_and_signals,
    export_hyperliquid_smart_money,
    hyperliquid_candidate_addresses,
)
from ...domain.smart_voice.client_read_model import build_smart_account_client_collections
from ...platforms.hyperliquid import HyperliquidInfoClient, HyperliquidStore, HyperliquidTradeStream
from .smart_money_publish import CandleCache, fetch_representative_candles
from .hyperliquid import (
    _discover_instruments,
    _iso,
    _select_wallets_for_profile_sync,
    _select_wallets_for_fill_sync,
    _sync_wallet_fills,
    _sync_wallet_profiles,
)


def _write_client_collections(
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
        temporary = target.with_suffix(".json.tmp")
        temporary.replace(target)
    manifest = {
        "generatedAt": payload.get("generatedAt"),
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


def _scalar(connection: sqlite3.Connection, sql: str, parameters: tuple[Any, ...] = ()) -> Any:
    row = connection.execute(sql, parameters).fetchone()
    return row[0] if row else None


def _count_profiled_wallets(connection: sqlite3.Connection, addresses: set[str]) -> int:
    if not addresses:
        return 0
    placeholders = ",".join("?" for _ in addresses)
    return int(
        _scalar(
            connection,
            f"SELECT COUNT(*) FROM hl_wallet WHERE profile_synced_at IS NOT NULL AND address IN ({placeholders})",
            tuple(sorted(addresses)),
        )
        or 0
    )


def _timestamp_from_milliseconds(value: Any) -> str | None:
    milliseconds = int(value or 0)
    if milliseconds <= 0:
        return None
    return _iso(dt.datetime.fromtimestamp(milliseconds / 1000, tz=dt.timezone.utc))


def _age_seconds(value: Any, now: dt.datetime) -> int | None:
    if not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return max(0, int((now - parsed.astimezone(dt.timezone.utc)).total_seconds()))


def _runtime_health(
    connection: sqlite3.Connection,
    *,
    stats: dict[str, Any],
    stream: Any,
    now: dt.datetime,
    refresh_seconds: int,
    publish_seconds: int,
    running: bool,
    instrument_refresh_minutes: int = 60,
) -> dict[str, Any]:
    wallet_count = int(_scalar(connection, "SELECT COUNT(*) FROM hl_wallet") or 0)
    observed_fills_complete = int(
        _scalar(connection, "SELECT COUNT(*) FROM hl_wallet WHERE fills_backfill_complete=1") or 0
    )
    candidate_addresses = hyperliquid_candidate_addresses(connection, as_of=now)
    candidate_count = len(candidate_addresses)
    candidate_placeholders = ",".join("?" for _ in candidate_addresses)
    candidate_parameters = tuple(candidate_addresses)
    fills_complete = int(
        _scalar(
            connection,
            f"""
            SELECT COUNT(*) FROM hl_wallet
            WHERE fills_backfill_complete=1
              AND address IN ({candidate_placeholders})
            """,
            candidate_parameters,
        )
        or 0
    ) if candidate_addresses else 0
    profile_count = int(
        _scalar(connection, "SELECT COUNT(*) FROM hl_wallet WHERE profile_synced_at IS NOT NULL") or 0
    )
    error_count = int(
        _scalar(connection, "SELECT COUNT(*) FROM hl_wallet WHERE last_error IS NOT NULL") or 0
    )
    now_iso = _iso(now)
    fill_retry_count = int(
        _scalar(
            connection,
            "SELECT COUNT(*) FROM hl_wallet WHERE fills_retry_after>?",
            (now_iso,),
        )
        or 0
    )
    profile_retry_count = int(
        _scalar(
            connection,
            "SELECT COUNT(*) FROM hl_wallet WHERE profile_retry_after>?",
            (now_iso,),
        )
        or 0
    )
    latest_tape_ms = int(_scalar(connection, "SELECT MAX(time_ms) FROM hl_trade_tape") or 0)
    latest_fill_ms = int(_scalar(connection, "SELECT MAX(time_ms) FROM hl_fill") or 0)
    latest_state_at = _scalar(connection, "SELECT MAX(observed_at) FROM hl_wallet_state_snapshot")
    latest_tape_at = _timestamp_from_milliseconds(latest_tape_ms)
    latest_fill_at = _timestamp_from_milliseconds(latest_fill_ms)
    truncated_count = int(
        _scalar(
            connection,
            f"""
            SELECT COUNT(*) FROM hl_wallet
            WHERE fills_truncated=1 AND address IN ({candidate_placeholders})
            """,
            candidate_parameters,
        )
        or 0
    ) if candidate_addresses else 0
    policy_limited_count = int(
        _scalar(
            connection,
            f"""
            SELECT COUNT(*) FROM hl_wallet
            WHERE fills_limit_reason='policy_algorithmic_2000'
              AND address IN ({candidate_placeholders})
            """,
            candidate_parameters,
        )
        or 0
    ) if candidate_addresses else 0
    source_limited_count = int(
        _scalar(
            connection,
            f"""
            SELECT COUNT(*) FROM hl_wallet
            WHERE fills_limit_reason='source_10000'
              AND address IN ({candidate_placeholders})
            """,
            candidate_parameters,
        )
        or 0
    ) if candidate_addresses else 0
    full_history_count = int(
        _scalar(
            connection,
            f"""
            SELECT COUNT(*) FROM hl_wallet
            WHERE fills_backfill_complete=1 AND fills_truncated=0
              AND address IN ({candidate_placeholders})
            """,
            candidate_parameters,
        )
        or 0
    ) if candidate_addresses else 0
    published_at = str(stats.get("publishedAt") or "") or None
    connected = bool(getattr(stream, "connected", False))
    stream_error = getattr(stream, "last_error", None)
    last_stream_trade_at = getattr(stream, "last_trade_at", None) or latest_tape_at
    qualified_count = int(stats.get("qualifiedWallets") or 0)
    qualified_profiled_count = int(stats.get("qualifiedProfiledWallets") or 0)
    fill_coverage = round(fills_complete / candidate_count, 4) if candidate_count else 1.0
    observed_fill_coverage = (
        round(observed_fills_complete / wallet_count, 4) if wallet_count else 1.0
    )
    profile_coverage = round(qualified_profiled_count / qualified_count, 4) if qualified_count else 0.0
    publish_age = _age_seconds(published_at, now)
    status = "starting"
    if published_at:
        status = "healthy" if connected or bool(getattr(stream, "last_message_at", None)) else "degraded"
    if stream_error:
        status = "degraded"
    if not running:
        status = "stopped"
    readiness_reasons: list[str] = []
    realtime_ready = bool(
        running
        and published_at
        and connected
        and publish_age is not None
        and publish_age <= max(180, publish_seconds * 3)
        and not stream_error
    )
    if not connected:
        readiness_reasons.append("public_trade_stream_disconnected")
    if not published_at:
        readiness_reasons.append("read_model_not_published")
    elif publish_age is None or publish_age > max(180, publish_seconds * 3):
        readiness_reasons.append("read_model_stale")
    if fill_coverage < 0.95:
        readiness_reasons.append("wallet_fill_catchup_incomplete")
    if qualified_count and profile_coverage < 0.95:
        readiness_reasons.append("qualified_profile_catchup_incomplete")
    if int(stats.get("fillWorkerFailures") or 0):
        readiness_reasons.append("fill_worker_error")
    if int(stats.get("profileWorkerFailures") or 0):
        readiness_reasons.append("profile_worker_error")
    complete_ready = fill_coverage >= 0.95 and (not qualified_count or profile_coverage >= 0.95)
    return {
        "schemaVersion": 1,
        "status": status,
        "running": running,
        "readiness": {
            "realtime": realtime_ready,
            "complete": complete_ready,
            "ready": realtime_ready and complete_ready,
            "reasons": readiness_reasons,
        },
        "generatedAt": _iso(now),
        "startedAt": stats.get("startedAt"),
        "lastRefreshAt": stats.get("lastRefreshAt"),
        "lastPublishAt": published_at,
        "lastPublishAgeSeconds": publish_age,
        "cadence": {
            "refreshSeconds": max(1, refresh_seconds),
            "publishSeconds": max(1, publish_seconds),
            "instrumentRefreshMinutes": max(1, instrument_refresh_minutes),
        },
        "markets": {
            "activeInstrumentCount": int(stats.get("instruments") or 0),
            "lastRefreshAt": stats.get("instrumentsRefreshedAt"),
            "refreshFailures": int(stats.get("instrumentRefreshFailures") or 0),
            "lastError": stats.get("instrumentRefreshError"),
        },
        "stream": {
            "connected": connected,
            "lastConnectedAt": getattr(stream, "last_connected_at", None),
            "lastMessageAt": getattr(stream, "last_message_at", None),
            "lastTradeAt": last_stream_trade_at,
            "lastTradeAgeSeconds": _age_seconds(last_stream_trade_at, now),
            "reconnectCount": int(getattr(stream, "reconnect_count", 0) or 0),
            "lastError": stream_error,
            "subscribedInstrumentCount": int(stats.get("instruments") or 0),
        },
        "coverage": {
            "knownWallets": wallet_count,
            "candidateWallets": candidate_count,
            "candidatePoolLimit": HL_CANDIDATE_POOL_SIZE,
            "candidateActivityLookbackDays": HL_CANDIDATE_ACTIVITY_DAYS,
            "candidateMinimumTrades": HL_DISCOVERY_MIN_TRADES,
            "candidateMinimumObservedNotional": HL_DISCOVERY_MIN_NOTIONAL,
            "nonCandidateObservedWallets": max(0, wallet_count - candidate_count),
            "fillBackfillCompleteWallets": fills_complete,
            "observedFillBackfillCompleteWallets": observed_fills_complete,
            "fillBackfillPendingWallets": max(0, candidate_count - fills_complete),
            "fillBackfillCoverage": fill_coverage,
            "observedFillBackfillCoverage": observed_fill_coverage,
            "fullHistoryWallets": full_history_count,
            "fullHistoryCoverage": round(full_history_count / candidate_count, 4) if candidate_count else 1.0,
            "historyLimitedWallets": truncated_count,
            "policyLimitedWallets": policy_limited_count,
            "sourceLimitedWallets": source_limited_count,
            "profiledWallets": profile_count,
            "qualifiedProfiledWallets": qualified_profiled_count,
            "qualifiedProfileCoverage": profile_coverage,
            "qualifiedWallets": qualified_count,
            "smartWallets": int(stats.get("smartWallets") or 0),
            "walletErrors": error_count,
            "fillRetriesDeferred": fill_retry_count,
            "profileRetriesDeferred": profile_retry_count,
            "latestFillAt": latest_fill_at,
            "latestFillAgeSeconds": _age_seconds(latest_fill_at, now),
            "latestWalletStateAt": latest_state_at,
            "latestWalletStateAgeSeconds": _age_seconds(latest_state_at, now),
        },
        "activity": {
            "cycles": int(stats.get("cycles") or 0),
            "streamTrades": int(stats.get("streamTrades") or 0),
            "newTapeTrades": int(stats.get("newTapeTrades") or 0),
            "walletsSynced": int(stats.get("walletsSynced") or 0),
            "profileWalletsSynced": int(stats.get("profileWalletsSynced") or 0),
            "fillFailures": int(stats.get("fillFailures") or 0),
            "profileFailures": int(stats.get("profileFailures") or 0),
            "fillWorkerBusy": bool(stats.get("fillWorkerBusy", False)),
            "activeFillWorkerBusy": bool(stats.get("activeFillWorkerBusy", False)),
            "backfillWorkerBusy": bool(stats.get("backfillWorkerBusy", False)),
            "profileWorkerBusy": bool(stats.get("profileWorkerBusy", False)),
            "fillWorkerFailures": int(stats.get("fillWorkerFailures") or 0),
            "profileWorkerFailures": int(stats.get("profileWorkerFailures") or 0),
            "activeWalletsSynced": int(stats.get("activeFillWalletsSynced") or 0),
            "backfillWalletsSynced": int(stats.get("backfillWalletsSynced") or 0),
            "pendingActiveWallets": int(stats.get("pendingActiveWallets") or 0),
            "pendingActiveExpired": int(stats.get("pendingActiveExpired") or 0),
        },
        "collections": stats.get("clientCollections") or {},
    }


def _write_health(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _start_trade_ingest(
    *,
    store: HyperliquidStore,
    stream: Any,
    coins: tuple[str, ...],
    events: queue.Queue[tuple[str, Any]],
    stop_event: threading.Event,
    write_lock: threading.Lock,
) -> threading.Thread:
    def consume() -> None:
        try:
            with store.connect() as connection:
                with write_lock:
                    store.ensure_tables(connection)
                    connection.commit()
                for trades in stream.iter_batches(coins, stop_event=stop_event):
                    if stop_event.is_set():
                        break
                    now = dt.datetime.now(dt.timezone.utc)
                    if trades:
                        with write_lock:
                            inserted, active_addresses = store.upsert_trade_tape(
                                connection,
                                trades,
                                observed_at=_iso(now),
                            )
                            connection.commit()
                        activity: dict[str, dict[str, float | int]] = {}
                        for trade in trades:
                            try:
                                timestamp = int(float(trade.get("time") or 0))
                                notional = abs(float(trade.get("px") or 0) * float(trade.get("sz") or 0))
                            except (TypeError, ValueError):
                                continue
                            for address in trade.get("users") or []:
                                normalized = str(address).lower()
                                if normalized not in active_addresses:
                                    continue
                                row = activity.setdefault(normalized, {"timeMs": 0, "notional": 0.0})
                                row["timeMs"] = max(int(row["timeMs"]), timestamp)
                                row["notional"] = float(row["notional"]) + notional
                        events.put(
                            (
                                "trades",
                                {
                                    "received": len(trades),
                                    "inserted": inserted,
                                    "addresses": active_addresses,
                                    "activity": activity,
                                    "observedAt": _iso(now),
                                },
                            )
                        )
                    else:
                        events.put(("heartbeat", {"observedAt": _iso(now)}))
        except Exception as exc:  # The main loop exposes fatal stream failures in health output.
            events.put(("error", str(exc)[:500]))

    thread = threading.Thread(
        target=consume,
        name="hyperliquid-public-trades",
        daemon=True,
    )
    thread.start()
    return thread


def _drain_trade_events(
    events: queue.Queue[tuple[str, Any]],
    *,
    pending_active: dict[str, tuple[int, float]],
    stats: dict[str, Any],
    wait_seconds: float = 0.0,
) -> None:
    first = True
    while True:
        try:
            kind, payload = events.get(timeout=max(0.0, wait_seconds) if first else 0.0)
        except queue.Empty:
            return
        first = False
        if kind == "trades":
            stats["streamTrades"] += int(payload.get("received") or 0)
            stats["newTapeTrades"] += int(payload.get("inserted") or 0)
            activity = payload.get("activity") or {}
            for address in payload.get("addresses") or set():
                normalized = str(address).lower()
                row = activity.get(normalized) or {}
                candidate = (int(row.get("timeMs") or 0), float(row.get("notional") or 0))
                current = pending_active.get(normalized, (0, 0.0))
                pending_active[normalized] = (
                    max(current[0], candidate[0]),
                    current[1] + candidate[1],
                )
            stats["lastStreamTradeAt"] = payload.get("observedAt")
        elif kind == "heartbeat":
            stats["reconnectHeartbeats"] += 1
        elif kind == "error":
            stats["streamFatalError"] = str(payload)


def _select_live_fill_addresses(
    connection: sqlite3.Connection,
    *,
    pending_active: dict[str, tuple[int, float]],
    eligible_addresses: set[str],
    max_active_wallets: int,
    candidate_backfill_per_cycle: int,
    inflight_addresses: set[str] | None = None,
) -> tuple[list[str], list[str]]:
    """Give low-latency activity and historical catch-up independent budgets."""
    inflight = {str(address).lower() for address in (inflight_addresses or set())}
    ordered_active = [
        address
        for address, _activity in sorted(
            pending_active.items(),
            key=lambda item: (-item[1][0], -item[1][1], item[0]),
        )
        if address not in inflight
    ]
    qualified_active = [address for address in ordered_active if address in eligible_addresses][
        :max(0, max_active_wallets)
    ]
    stale_candidates = _select_wallets_for_fill_sync(connection, limit=0)
    discovery_candidates = {str(row["address"]) for row in stale_candidates}
    backlog_addresses = [
        str(row["address"])
        for row in stale_candidates
        if str(row["address"]) not in pending_active and str(row["address"]) not in inflight
    ]
    active_capacity = max(0, max_active_wallets - len(qualified_active))
    discovery_active = [
        address
        for address in ordered_active
        if address not in eligible_addresses and address in discovery_candidates
    ][:active_capacity]
    candidate_addresses = backlog_addresses[:max(0, candidate_backfill_per_cycle)]
    return qualified_active + discovery_active, candidate_addresses


def _prune_pending_active(
    pending_active: dict[str, tuple[int, float]],
    *,
    now_ms: int,
    max_age_minutes: int = 30,
) -> int:
    cutoff = now_ms - max(1, max_age_minutes) * 60_000
    expired = [address for address, activity in pending_active.items() if int(activity[0]) < cutoff]
    for address in expired:
        pending_active.pop(address, None)
    return len(expired)


def _live_smart_account_updates(
    connection: Any,
    *,
    generated_at: dt.datetime,
    tickers: tuple[str, ...],
) -> list[dict[str, Any]] | None:
    required = {"sv_investor_score", "sv_call"}
    available = {
        str(row[0])
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('sv_investor_score','sv_call')"
        ).fetchall()
    }
    if not required.issubset(available):
        return None
    return build_smart_account_client_collections(
        connection,
        as_of=generated_at,
        update_days=30,
        update_limit=500,
        update_tickers=tickers,
        include_profiles=False,
    )["smart-account-updates"]


def _background_fill_sync(
    *,
    store: HyperliquidStore,
    client: Any,
    instruments: tuple[Any, ...],
    addresses: list[str],
    now: dt.datetime,
    lookback_days: int,
    api_pause: bool,
    write_lock: threading.Lock,
) -> dict[str, Any]:
    with store.connect() as connection:
        with write_lock:
            store.ensure_tables(connection)
            connection.commit()
        return _sync_wallet_fills(
            connection,
            client=client,
            store=store,
            instruments=instruments,
            now=now,
            lookback_days=lookback_days,
            max_wallets=len(addresses),
            api_pause=api_pause,
            addresses=addresses,
            write_lock=write_lock,
        )


def _background_profile_sync(
    *,
    store: HyperliquidStore,
    client: Any,
    stream: Any,
    instruments: tuple[Any, ...],
    addresses: list[str],
    now: dt.datetime,
    lookback_days: int,
    api_pause: bool,
    profile_refresh_minutes: int,
    write_lock: threading.Lock,
) -> dict[str, Any]:
    with store.connect() as connection:
        with write_lock:
            store.ensure_tables(connection)
            connection.commit()
        return _sync_wallet_profiles(
            connection,
            client=client,
            store=store,
            instruments=instruments,
            addresses=addresses,
            now=now,
            lookback_days=lookback_days,
            api_pause=api_pause,
            state_freshness_minutes=max(1, profile_refresh_minutes),
            state_snapshot_client=stream,
            write_lock=write_lock,
        )


def _collect_fill_future(
    future: concurrent.futures.Future[dict[str, Any]] | None,
    *,
    inflight_addresses: set[str],
    lane: str,
    stats: dict[str, Any],
    pending_active: dict[str, tuple[int, float]],
) -> tuple[concurrent.futures.Future[dict[str, Any]] | None, set[str]]:
    if future is None or not future.done():
        return future, inflight_addresses
    stat_prefix = "activeFill" if lane == "active" else "backfill"
    try:
        counts = future.result()
        synced = int(counts.get("walletsSynced") or 0)
        failures = int(counts.get("fillFailures") or 0)
        stats["walletsSynced"] = int(stats.get("walletsSynced") or 0) + synced
        stats["fillFailures"] = int(stats.get("fillFailures") or 0) + failures
        stats[f"{stat_prefix}WalletsSynced"] = (
            int(stats.get(f"{stat_prefix}WalletsSynced") or 0) + synced
        )
        stats[f"{stat_prefix}Failures"] = (
            int(stats.get(f"{stat_prefix}Failures") or 0) + failures
        )
        for address in counts.get("successfulAddresses") or []:
            pending_active.pop(str(address).lower(), None)
    except Exception as exc:
        stats["fillWorkerFailures"] = int(stats.get("fillWorkerFailures") or 0) + 1
        stats[f"{stat_prefix}WorkerError"] = str(exc)[:500]
    return None, set()


def _publish_live_outputs(
    connection: sqlite3.Connection,
    *,
    output: Path,
    destination: Path | None,
    generated_at: dt.datetime,
    lookback_days: int,
    scores: list[dict[str, Any]],
    signals: list[dict[str, Any]],
    threshold: float,
    candle_client: HyperliquidInfoClient | None = None,
    candle_cache: CandleCache | None = None,
) -> tuple[dict[str, Any], dict[str, int], int]:
    payload = export_hyperliquid_smart_money(
        output,
        generated_at=generated_at,
        lookback_days=lookback_days,
        scores=scores,
        signals=signals,
        smart_threshold=threshold,
    )
    collection_counts: dict[str, int] = {}
    smart_account_count = 0
    if destination is not None:
        client_tickers = tuple(
            sorted(
                str(market.get("symbol") or "").upper()
                for market in payload.get("markets") or []
                if market.get("category") == "stocks" and market.get("symbol")
            )
        )
        account_updates = _live_smart_account_updates(
            connection,
            generated_at=generated_at,
            tickers=client_tickers,
        )
        collection_counts = _write_client_collections(
            destination,
            payload,
            smart_account_updates=account_updates,
            candle_client=candle_client,
            candle_cache=candle_cache,
        )
        smart_account_count = len(account_updates or [])
    return payload, collection_counts, smart_account_count


def run_hyperliquid_live(
    *,
    db_path: str = "",
    output_path: str = "",
    client_output_dir: str = "",
    health_output_path: str = "",
    lookback_days: int = 30,
    refresh_seconds: int = 30,
    publish_seconds: int = 60,
    candidate_backfill_per_cycle: int = 4,
    max_active_wallets: int = 8,
    max_profile_wallets: int = 8,
    profile_refresh_minutes: int = 5,
    instrument_refresh_minutes: int = 60,
    max_cycles: int = 0,
    api_pause: bool = True,
    client: HyperliquidInfoClient | None = None,
    trade_stream: HyperliquidTradeStream | None = None,
    stop_event: threading.Event | None = None,
) -> dict[str, Any]:
    """Run the realtime stream until stopped or ``max_cycles`` is reached.

    Public trade WebSockets provide low-latency discovery and activity
    triggers. Paginated Info API fills and clearinghouse snapshots remain the
    authoritative, replayable source for position transitions and scoring.
    """
    db = Path(db_path).resolve() if db_path else (RUNTIME_DATA_DIR / "dev.db").resolve()
    output = (
        Path(output_path).resolve()
        if output_path
        else (ROOT / "web" / "lib" / "data" / "hyperliquidSmartMoney.json").resolve()
    )
    destination = Path(client_output_dir).resolve() if client_output_dir else None
    health_output = (
        Path(health_output_path).resolve()
        if health_output_path
        else ((destination or output.parent) / "smart-money-live-health.json").resolve()
    )
    info_client = client or HyperliquidInfoClient()
    candle_cache: CandleCache = {}
    if hasattr(info_client, "set_pacing"):
        info_client.set_pacing(api_pause)
    stream = trade_stream or HyperliquidTradeStream()
    store = HyperliquidStore(db)
    started_at = dt.datetime.now(dt.timezone.utc)
    stats: dict[str, Any] = {
        "db": str(db),
        "output": str(output),
        "healthOutput": str(health_output),
        "startedAt": _iso(started_at),
        "cycles": 0,
        "streamTrades": 0,
        "newTapeTrades": 0,
        "walletsSynced": 0,
        "profileWalletsSynced": 0,
        "reconnectHeartbeats": 0,
        "instrumentRefreshFailures": 0,
    }

    with store.connect() as connection:
        store.ensure_tables(connection)
        instruments = _discover_instruments(info_client)
        store.upsert_instruments(connection, instruments, observed_at=_iso(started_at))
        connection.commit()
        scores, signals, threshold = build_wallet_scores_and_signals(
            connection,
            as_of=started_at,
            lookback_days=lookback_days,
        )
        eligible_addresses = {str(row["address"]) for row in scores if row["eligible"]}
        stats["qualifiedWallets"] = len(eligible_addresses)
        stats["qualifiedProfiledWallets"] = _count_profiled_wallets(connection, eligible_addresses)
        stats["instruments"] = len(instruments)
        stats["instrumentsRefreshedAt"] = _iso(started_at)
        _write_health(
            health_output,
            _runtime_health(
                connection,
                stats=stats,
                stream=stream,
                now=started_at,
                refresh_seconds=refresh_seconds,
                publish_seconds=publish_seconds,
                instrument_refresh_minutes=instrument_refresh_minutes,
                running=True,
            ),
        )

        pending_active: dict[str, tuple[int, float]] = {}
        trade_events: queue.Queue[tuple[str, Any]] = queue.Queue()
        external_stop_event = stop_event
        worker_stop_event = threading.Event()
        db_write_lock = threading.Lock()
        trade_thread = _start_trade_ingest(
            store=store,
            stream=stream,
            coins=tuple(instrument.coin for instrument in instruments),
            events=trade_events,
            stop_event=worker_stop_event,
            write_lock=db_write_lock,
        )
        next_refresh = time.monotonic() + min(1.0, max(0.1, refresh_seconds))
        next_publish = time.monotonic()
        next_instrument_refresh = time.monotonic() + max(60, instrument_refresh_minutes * 60)
        executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=3,
            thread_name_prefix="hyperliquid-enrichment",
        )
        active_fill_future: concurrent.futures.Future[dict[str, Any]] | None = None
        backfill_future: concurrent.futures.Future[dict[str, Any]] | None = None
        active_fill_inflight: set[str] = set()
        backfill_inflight: set[str] = set()
        profile_future: concurrent.futures.Future[dict[str, Any]] | None = None
        try:
            while True:
                if worker_stop_event.is_set() or (
                    external_stop_event is not None and external_stop_event.is_set()
                ):
                    break
                wait_seconds = max(0.0, min(0.5, next_refresh - time.monotonic()))
                _drain_trade_events(
                    trade_events,
                    pending_active=pending_active,
                    stats=stats,
                    wait_seconds=wait_seconds,
                )
                if time.monotonic() < next_refresh:
                    continue
                if stats.get("streamFatalError") and not trade_thread.is_alive():
                    raise RuntimeError(f"Hyperliquid trade ingest stopped: {stats['streamFatalError']}")
                now = dt.datetime.now(dt.timezone.utc)
                expired_pending = _prune_pending_active(
                    pending_active,
                    now_ms=int(now.timestamp() * 1000),
                )
                stats["pendingActiveExpired"] = (
                    int(stats.get("pendingActiveExpired") or 0) + expired_pending
                )
                stats["pendingActiveWallets"] = len(pending_active)
                active_fill_future, active_fill_inflight = _collect_fill_future(
                    active_fill_future,
                    inflight_addresses=active_fill_inflight,
                    lane="active",
                    stats=stats,
                    pending_active=pending_active,
                )
                backfill_future, backfill_inflight = _collect_fill_future(
                    backfill_future,
                    inflight_addresses=backfill_inflight,
                    lane="backfill",
                    stats=stats,
                    pending_active=pending_active,
                )
                if profile_future is not None and profile_future.done():
                    try:
                        profile_counts = profile_future.result()
                        stats["profileWalletsSynced"] += profile_counts["profileWalletsSynced"]
                        stats["profileFailures"] = (
                            stats.get("profileFailures", 0) + profile_counts["profileFailures"]
                        )
                    except Exception as exc:
                        stats["profileWorkerFailures"] = stats.get("profileWorkerFailures", 0) + 1
                        stats["profileWorkerError"] = str(exc)[:500]
                    profile_future = None
                if time.monotonic() >= next_instrument_refresh:
                    try:
                        refreshed_instruments = _discover_instruments(info_client)
                        if refreshed_instruments:
                            instruments = refreshed_instruments
                            with db_write_lock:
                                store.upsert_instruments(connection, instruments, observed_at=_iso(now))
                                connection.commit()
                            if hasattr(stream, "update_subscriptions"):
                                stream.update_subscriptions(
                                    tuple(instrument.coin for instrument in instruments)
                                )
                            stats["instruments"] = len(instruments)
                            stats["instrumentsRefreshedAt"] = _iso(now)
                    except RuntimeError as exc:
                        stats["instrumentRefreshFailures"] += 1
                        stats["instrumentRefreshError"] = str(exc)[:500]
                    next_instrument_refresh = time.monotonic() + max(
                        60,
                        instrument_refresh_minutes * 60,
                    )
                active_addresses: list[str] = []
                if active_fill_future is None or backfill_future is None:
                    active_addresses, candidate_addresses = _select_live_fill_addresses(
                        connection,
                        pending_active=pending_active,
                        eligible_addresses=eligible_addresses,
                        max_active_wallets=max_active_wallets,
                        candidate_backfill_per_cycle=candidate_backfill_per_cycle,
                        inflight_addresses=active_fill_inflight | backfill_inflight,
                    )
                    if active_fill_future is None and active_addresses:
                        active_fill_inflight = set(active_addresses)
                        active_fill_future = executor.submit(
                            _background_fill_sync,
                            store=store,
                            client=info_client,
                            instruments=tuple(instruments),
                            addresses=active_addresses,
                            now=now,
                            lookback_days=lookback_days,
                            api_pause=api_pause,
                            write_lock=db_write_lock,
                        )
                    if backfill_future is None and candidate_addresses:
                        backfill_inflight = set(candidate_addresses)
                        backfill_future = executor.submit(
                            _background_fill_sync,
                            store=store,
                            client=info_client,
                            instruments=tuple(instruments),
                            addresses=candidate_addresses,
                            now=now,
                            lookback_days=lookback_days,
                            api_pause=api_pause,
                            write_lock=db_write_lock,
                        )

                with db_write_lock:
                    scores, signals, threshold = build_wallet_scores_and_signals(
                        connection,
                        as_of=now,
                        lookback_days=lookback_days,
                    )
                eligible_addresses = {str(row["address"]) for row in scores if row["eligible"]}
                stats["qualifiedWallets"] = len(eligible_addresses)
                stats["qualifiedProfiledWallets"] = _count_profiled_wallets(connection, eligible_addresses)

                if time.monotonic() >= next_publish:
                    published_now = dt.datetime.now(dt.timezone.utc)
                    payload, collection_counts, smart_account_count = _publish_live_outputs(
                        connection,
                        output=output,
                        destination=destination,
                        generated_at=published_now,
                        lookback_days=lookback_days,
                        scores=scores,
                        signals=signals,
                        threshold=threshold,
                        candle_client=info_client,
                        candle_cache=candle_cache,
                    )
                    if destination is not None:
                        stats["clientCollections"] = collection_counts
                        stats["smartAccountUpdates"] = smart_account_count
                    stats["publishedAt"] = payload["generatedAt"]
                    stats["qualifiedWallets"] = payload["summary"]["qualifiedWalletCount"]
                    stats["smartWallets"] = payload["summary"]["smartWalletCount"]
                    next_publish = time.monotonic() + max(1, publish_seconds)

                if profile_future is None and max_profile_wallets > 0:
                    qualified = [str(row["address"]).lower() for row in scores if row["eligible"]]
                    profile_addresses = _select_wallets_for_profile_sync(
                        connection,
                        eligible_addresses=qualified,
                        limit=max_profile_wallets,
                        active_addresses=set(active_addresses),
                    )
                    if profile_addresses:
                        profile_future = executor.submit(
                            _background_profile_sync,
                            store=store,
                            client=info_client,
                            stream=stream,
                            instruments=tuple(instruments),
                            addresses=profile_addresses,
                            now=now,
                            lookback_days=lookback_days,
                            api_pause=api_pause,
                            profile_refresh_minutes=profile_refresh_minutes,
                            write_lock=db_write_lock,
                        )
                stats["qualifiedProfiledWallets"] = _count_profiled_wallets(
                    connection,
                    {str(row["address"]) for row in scores if row["eligible"]},
                )

                stats["cycles"] += 1
                stats["lastRefreshAt"] = _iso(now)
                stats["fillWorkerBusy"] = (
                    active_fill_future is not None or backfill_future is not None
                )
                stats["activeFillWorkerBusy"] = active_fill_future is not None
                stats["backfillWorkerBusy"] = backfill_future is not None
                stats["profileWorkerBusy"] = profile_future is not None
                _write_health(
                    health_output,
                    _runtime_health(
                        connection,
                        stats=stats,
                        stream=stream,
                        now=now,
                        refresh_seconds=refresh_seconds,
                        publish_seconds=publish_seconds,
                        instrument_refresh_minutes=instrument_refresh_minutes,
                        running=True,
                    ),
                )
                next_refresh = time.monotonic() + max(1, refresh_seconds)
                if max_cycles > 0 and stats["cycles"] >= max_cycles:
                    break
        finally:
            worker_stop_event.set()
            if hasattr(stream, "close"):
                stream.close()
            trade_thread.join(timeout=5.0)
            executor.shutdown(wait=True, cancel_futures=False)
            active_fill_future, active_fill_inflight = _collect_fill_future(
                active_fill_future,
                inflight_addresses=active_fill_inflight,
                lane="active",
                stats=stats,
                pending_active=pending_active,
            )
            backfill_future, backfill_inflight = _collect_fill_future(
                backfill_future,
                inflight_addresses=backfill_inflight,
                lane="backfill",
                stats=stats,
                pending_active=pending_active,
            )
            if profile_future is not None:
                try:
                    profile_counts = profile_future.result()
                    stats["profileWalletsSynced"] += profile_counts["profileWalletsSynced"]
                    stats["profileFailures"] = stats.get("profileFailures", 0) + profile_counts["profileFailures"]
                except Exception as exc:
                    stats["profileWorkerFailures"] = stats.get("profileWorkerFailures", 0) + 1
                    stats["profileWorkerError"] = str(exc)[:500]
            _drain_trade_events(
                trade_events,
                pending_active=pending_active,
                stats=stats,
            )
            stats["tradeIngestStopped"] = not trade_thread.is_alive()
            stats["fillWorkerBusy"] = False
            stats["activeFillWorkerBusy"] = False
            stats["backfillWorkerBusy"] = False
            stats["profileWorkerBusy"] = False
            final_now = dt.datetime.now(dt.timezone.utc)
            with db_write_lock:
                scores, signals, threshold = build_wallet_scores_and_signals(
                    connection,
                    as_of=final_now,
                    lookback_days=lookback_days,
                )
            eligible_addresses = {str(row["address"]) for row in scores if row["eligible"]}
            stats["qualifiedProfiledWallets"] = _count_profiled_wallets(
                connection,
                eligible_addresses,
            )
            payload, collection_counts, smart_account_count = _publish_live_outputs(
                connection,
                output=output,
                destination=destination,
                generated_at=final_now,
                lookback_days=lookback_days,
                scores=scores,
                signals=signals,
                threshold=threshold,
                candle_client=info_client,
                candle_cache=candle_cache,
            )
            if destination is not None:
                stats["clientCollections"] = collection_counts
                stats["smartAccountUpdates"] = smart_account_count
            stats["publishedAt"] = payload["generatedAt"]
            stats["qualifiedWallets"] = payload["summary"]["qualifiedWalletCount"]
            stats["smartWallets"] = payload["summary"]["smartWalletCount"]
    finished_at = dt.datetime.now(dt.timezone.utc)
    stats["finishedAt"] = _iso(finished_at)
    with store.connect() as connection:
        _write_health(
            health_output,
            _runtime_health(
                connection,
                stats=stats,
                stream=stream,
                now=finished_at,
                refresh_seconds=refresh_seconds,
                publish_seconds=publish_seconds,
                instrument_refresh_minutes=instrument_refresh_minutes,
                running=False,
            ),
        )
    return stats
