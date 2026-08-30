"""End-to-end Hyperliquid TradFi smart-money job."""
from __future__ import annotations

import collections
import contextlib
import datetime as dt
import json
import math
import time
from pathlib import Path
from typing import Any

from ...common.config import ROOT, RUNTIME_DATA_DIR
from ...domain.smart_voice.client_read_model import build_smart_account_client_collections
from ...domain.smart_voice.hyperliquid import (
    build_hyperliquid_client_collections,
    build_wallet_scores_and_signals,
    export_hyperliquid_smart_money,
    hyperliquid_candidate_addresses,
)
from ...platforms.hyperliquid import (
    HyperliquidInfoClient,
    HyperliquidStore,
    discover_tradfi_instruments,
    normalize_fill,
    normalize_ledger_updates,
    normalize_portfolio,
    normalize_wallet_state,
)


def _utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _iso(value: dt.datetime) -> str:
    return value.replace(microsecond=0).isoformat()


def _parse_iso(value: str) -> dt.datetime | None:
    if not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _discover_instruments(client: HyperliquidInfoClient):
    categories = client.perp_categories()
    dexes = sorted({coin.split(":", 1)[0] for coin, category in categories if ":" in coin and category.lower() in {"stocks", "stock", "indices", "index", "commodities", "commodity", "fx", "preipo"}})
    dex_markets = {dex: client.meta_and_asset_contexts(dex) for dex in dexes}
    return discover_tradfi_instruments(categories, dex_markets)


def _wallet_seeds(
    client: HyperliquidInfoClient,
    instruments,
    *,
    max_markets: int,
    api_pause: bool,
) -> list[dict[str, Any]]:
    seeds: dict[str, dict[str, Any]] = {}
    per_market: dict[str, list[tuple[str, float]]] = {}
    for instrument in instruments[:max_markets]:
        trades = client.recent_trades(instrument.coin)
        market_addresses: dict[str, float] = collections.defaultdict(float)
        for trade in trades:
            notional = abs(float(trade.get("px") or 0) * float(trade.get("sz") or 0))
            users = trade.get("users") or []
            side = str(trade.get("side") or "").upper()
            # recentTrades returns [buyer, seller]; side is the taker's side.
            taker_index = 0 if side == "B" else 1 if side == "A" else -1
            if taker_index < 0 or taker_index >= len(users):
                continue
            address = str(users[taker_index]).lower()
            if not address.startswith("0x") or len(address) != 42:
                continue
            row = seeds.setdefault(address, {"address": address, "notional": 0.0, "trade_count": 0, "coins": set()})
            row["notional"] += notional
            row["trade_count"] += 1
            row["coins"].add(instrument.coin)
            market_addresses[address] += notional
        per_market[instrument.coin] = list(market_addresses.items())
        if api_pause and not getattr(client, "pacing_enabled", False):
            time.sleep(1.05)

    ordered: list[str] = []
    for coin, market_rows in per_market.items():
        per_market[coin] = sorted(
            market_rows,
            key=lambda item: (
                len(seeds[item[0]]["coins"]),
                int(seeds[item[0]]["trade_count"]),
                -item[1],
            ),
        )
    for depth in range(4):
        for instrument in instruments[:max_markets]:
            market_rows = per_market.get(instrument.coin) or []
            if depth < len(market_rows) and market_rows[depth][0] not in ordered:
                ordered.append(market_rows[depth][0])
    remaining = sorted(
        seeds.values(),
        key=lambda row: (
            len(row["coins"]),
            int(row["trade_count"]),
            -math.log1p(float(row["notional"])),
        ),
    )
    for row in remaining:
        if row["address"] not in ordered:
            ordered.append(row["address"])
    return [seeds[address] for address in ordered]


def _sync_wallet_profiles(
    connection,
    *,
    client: HyperliquidInfoClient,
    store: HyperliquidStore,
    instruments,
    addresses: list[str],
    now: dt.datetime,
    lookback_days: int,
    api_pause: bool,
    state_freshness_minutes: int = 5,
    extended_freshness_hours: int = 6,
    state_snapshot_client: Any | None = None,
    write_lock: Any | None = None,
) -> dict[str, int]:
    instrument_map = {instrument.coin: instrument for instrument in instruments}
    observed_at = _iso(now)
    start_ms = int((now - dt.timedelta(days=lookback_days)).timestamp() * 1000)
    positions = 0
    portfolios = 0
    ledger_events = 0
    failures = 0
    fresh = 0
    synced = 0
    state_cutoff = now - dt.timedelta(minutes=max(1, state_freshness_minutes))
    extended_cutoff = now - dt.timedelta(hours=max(1, extended_freshness_hours))
    all_dexes = sorted({instrument.dex for instrument in instruments if instrument.dex})
    snapshot_addresses: list[str] = []
    for address in addresses:
        row = connection.execute(
            "SELECT profile_synced_at FROM hl_wallet WHERE address=?",
            (address,),
        ).fetchone()
        latest_state = _parse_iso(str(row[0] or "")) if row else None
        if not latest_state or latest_state < state_cutoff:
            snapshot_addresses.append(address.lower())
    state_snapshots: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    if state_snapshot_client is not None and hasattr(state_snapshot_client, "account_state_snapshots"):
        for offset in range(0, len(snapshot_addresses), 10):
            batch = snapshot_addresses[offset:offset + 10]
            try:
                state_snapshots.update(state_snapshot_client.account_state_snapshots(batch))
            except RuntimeError as exc:
                print(f"[hyperliquid] account-state snapshot fallback error={exc}", flush=True)
    for address in addresses:
        sync_row = connection.execute(
            """
            SELECT profile_synced_at, extended_profile_synced_at
            FROM hl_wallet WHERE address=?
            """,
            (address,),
        ).fetchone()
        latest_state = _parse_iso(str(sync_row[0] or "")) if sync_row else None
        latest_extended = _parse_iso(str(sync_row[1] or "")) if sync_row else None
        if latest_state and latest_state >= state_cutoff:
            fresh += 1
            continue
        extended_due = not latest_extended or latest_extended < extended_cutoff
        known_dexes = [
            str(row[0])
            for row in connection.execute(
                """
                SELECT dex FROM (
                  SELECT DISTINCT dex FROM hl_fill WHERE address=?
                  UNION
                  SELECT DISTINCT dex FROM hl_wallet_state WHERE address=?
                ) ORDER BY dex
                """,
                (address, address),
            )
            if str(row[0])
        ]
        snapshot_states = state_snapshots.get(address.lower())
        dexes = all_dexes if extended_due else known_dexes
        if not dexes:
            dexes = all_dexes[:1]
        try:
            state_rows = snapshot_states if snapshot_states is not None else [
                (dex, client.clearinghouse_state(address, dex=dex))
                for dex in dexes
            ]
            normalized_states: list[tuple[dict[str, Any], list[dict[str, Any]]]] = []
            for dex, raw_state in state_rows:
                state, position_rows = normalize_wallet_state(
                    address,
                    dex,
                    raw_state,
                    instrument_map,
                    observed_at=observed_at,
                )
                normalized_states.append((state, position_rows))
                if snapshot_states is None and api_pause:
                    time.sleep(0.12)

            portfolio_rows: list[dict[str, Any]] = []
            raw_ledger: list[dict[str, Any]] = []
            if extended_due:
                portfolio_rows = normalize_portfolio(client.portfolio(address))
                raw_ledger = client.user_non_funding_ledger_updates(
                    address,
                    start_ms=start_ms,
                    end_ms=int(now.timestamp() * 1000),
                )
            normalized_ledger = normalize_ledger_updates(address, raw_ledger)

            # Keep network I/O outside SQLite write transactions. The live worker
            # serializes only these short commits with trade ingest and scoring.
            with write_lock if write_lock is not None else contextlib.nullcontext():
                wallet_positions = 0
                for state, position_rows in normalized_states:
                    store.upsert_wallet_state(connection, state)
                    wallet_positions += store.replace_wallet_positions(
                        connection,
                        address=address,
                        dex=str(state["dex"]),
                        rows=position_rows,
                        observed_at=observed_at,
                    )
                positions += wallet_positions
                if extended_due:
                    portfolios += store.upsert_wallet_portfolio(
                        connection,
                        address=address,
                        rows=portfolio_rows,
                        observed_at=observed_at,
                    )
                    ledger_events += store.upsert_wallet_ledger(
                        connection,
                        address=address,
                        rows=normalized_ledger,
                    )
                store.mark_profile_synced(
                    connection,
                    address,
                    synced_at=observed_at,
                    extended=extended_due,
                )
                connection.commit()
            synced += 1
            print(
                f"[hyperliquid] profile={address[:8]}... dexes={len(dexes)} positions={wallet_positions} periods={len(portfolio_rows)} ledger={len(raw_ledger)}",
                flush=True,
            )
            if api_pause and not getattr(client, "pacing_enabled", False):
                time.sleep(1.25 if extended_due else 0.35)
        except RuntimeError as exc:
            failures += 1
            with write_lock if write_lock is not None else contextlib.nullcontext():
                store.mark_wallet_error(
                    connection,
                    address,
                    str(exc),
                    stage="profile",
                    observed_at=now,
                )
                connection.commit()
            print(f"[hyperliquid] profile={address[:8]}... error={exc}", flush=True)
    return {
        "profileWallets": len(addresses),
        "profileWalletsSynced": synced,
        "profileWalletsFresh": fresh,
        "positionSnapshots": positions,
        "portfolioPeriods": portfolios,
        "ledgerEvents": ledger_events,
        "profileFailures": failures,
    }


def _select_wallets_for_fill_sync(
    connection,
    *,
    limit: int,
    now: dt.datetime | None = None,
) -> list[dict[str, Any]]:
    observed_at = _iso(now or dt.datetime.now(dt.timezone.utc))
    candidates = hyperliquid_candidate_addresses(connection, as_of=now)
    if not candidates:
        return []
    placeholders = ",".join("?" for _ in candidates)
    rows = [
        dict(row)
        for row in connection.execute(
            f"""
            SELECT address, fills_synced_at, fills_cursor_ms,
                   fills_backfill_complete, fills_truncated,
                   fills_limit_reason,
                   discovery_notional, discovery_trade_count,
                   fills_retry_count, fills_retry_after
            FROM hl_wallet
            WHERE (fills_retry_after IS NULL OR fills_retry_after<=?)
              AND address IN ({placeholders})
            ORDER BY
              CASE WHEN fills_backfill_complete=0 THEN 0 ELSE 1 END,
              CASE WHEN fills_backfill_complete=0 THEN discovery_notional END DESC,
              CASE WHEN fills_backfill_complete=0 THEN discovery_trade_count END DESC,
              CASE WHEN fills_backfill_complete=1 THEN COALESCE(fills_synced_at, '') END,
              last_seen_at DESC,
              address
            """,
            (observed_at, *candidates),
        )
    ]
    return rows if limit <= 0 else rows[:limit]


def _select_wallets_for_profile_sync(
    connection,
    *,
    eligible_addresses: list[str],
    limit: int,
    active_addresses: set[str] | None = None,
) -> list[str]:
    """Rotate every eligible wallet by profile staleness without Top-N starvation."""
    eligible = {str(address).lower() for address in eligible_addresses if str(address)}
    if not eligible:
        return []
    active = {str(address).lower() for address in (active_addresses or set())}
    observed_at = _iso(dt.datetime.now(dt.timezone.utc))
    placeholders = ",".join("?" for _ in eligible)
    rows = connection.execute(
        f"""
        SELECT address, profile_synced_at
        FROM hl_wallet
        WHERE address IN ({placeholders})
          AND (profile_retry_after IS NULL OR profile_retry_after<=?)
        ORDER BY
          CASE WHEN profile_synced_at IS NULL THEN 0 ELSE 1 END,
          COALESCE(profile_synced_at, ''),
          address
        """,
        (*tuple(sorted(eligible)), observed_at),
    ).fetchall()
    ordered: list[str] = []
    index = 0
    while index < len(rows):
        synced_at = str(rows[index][1] or "")
        group = []
        while index < len(rows) and str(rows[index][1] or "") == synced_at:
            group.append(str(rows[index][0]).lower())
            index += 1
        ordered.extend(sorted(group, key=lambda address: (address not in active, address)))
    missing = sorted(eligible - set(ordered), key=lambda address: (address not in active, address))
    ordered.extend(missing)
    return ordered if limit <= 0 else ordered[:limit]


def _fill_limit_reason(*, fill_count: int, history_limited: bool) -> str | None:
    if not history_limited:
        return None
    return "policy_algorithmic_2000" if fill_count >= 2_000 else "source_10000"


def _sync_wallet_fills(
    connection,
    *,
    client: HyperliquidInfoClient,
    store: HyperliquidStore,
    instruments,
    now: dt.datetime,
    lookback_days: int,
    max_wallets: int,
    api_pause: bool,
    overlap_minutes: int = 5,
    addresses: list[str] | None = None,
    write_lock: Any | None = None,
) -> dict[str, Any]:
    instrument_map = {instrument.coin: instrument for instrument in instruments}
    end_ms = int(now.timestamp() * 1000)
    history_start_ms = int((now - dt.timedelta(days=lookback_days)).timestamp() * 1000)
    candidates = _select_wallets_for_fill_sync(connection, limit=0)
    if addresses is not None:
        by_address = {str(row["address"]).lower(): row for row in candidates}
        requested = [str(address).lower() for address in addresses]
        # The caller orders live wallets by signal urgency. Preserve that order
        # instead of falling back to the stale-backfill ordering above.
        candidates = [by_address[address] for address in requested if address in by_address]
    selected = candidates if max_wallets <= 0 else candidates[:max_wallets]
    synced = 0
    normalized_count = 0
    failures = 0
    incomplete = 0
    successful_addresses: list[str] = []
    failed_addresses: list[str] = []
    for wallet in selected:
        address = str(wallet["address"])
        cursor_ms = int(wallet.get("fills_cursor_ms") or 0)
        if cursor_ms > 0 and bool(wallet.get("fills_backfill_complete")):
            start_ms = max(history_start_ms, cursor_ms - max(1, overlap_minutes) * 60_000)
        else:
            start_ms = history_start_ms
        try:
            raw_fills, history_limited = client.paginated_user_fills_by_time(
                address,
                start_ms=start_ms,
                end_ms=end_ms,
                max_fills=2_000,
            )
            normalized = [
                fill
                for raw in raw_fills
                if (fill := normalize_fill(address, raw, instrument_map))
            ]
            latest_fill_ms = max(
                (int(float(row.get("time") or 0)) for row in raw_fills),
                default=end_ms,
            )
            truncated = bool(wallet.get("fills_truncated")) or history_limited
            limit_reason = str(wallet.get("fills_limit_reason") or "") or None
            if history_limited:
                limit_reason = _fill_limit_reason(
                    fill_count=len(raw_fills),
                    history_limited=True,
                )
            # A successful pass is terminal when either the official history
            # ceiling or bSmart's 2,000-fill algorithmic policy ceiling is hit.
            # The explicit reason preserves auditability while preventing
            # repeated downloads for accounts that cannot enter formal scoring.
            backfill_complete = True
            with write_lock if write_lock is not None else contextlib.nullcontext():
                normalized_count += store.upsert_fills(connection, normalized)
                store.mark_wallet_synced(
                    connection,
                    address,
                    synced_at=_iso(now),
                    truncated=truncated,
                    limit_reason=limit_reason,
                    cursor_ms=max(cursor_ms, latest_fill_ms),
                    backfill_complete=backfill_complete,
                )
                connection.commit()
            synced += 1
            successful_addresses.append(address.lower())
            incomplete += 1 if history_limited else 0
            print(
                f"[hyperliquid] wallet={address[:8]}... fills={len(raw_fills)} tradfi={len(normalized)} historyLimited={history_limited}",
                flush=True,
            )
            if api_pause and not getattr(client, "pacing_enabled", False):
                time.sleep(client.suggested_fill_pause(len(raw_fills)))
        except RuntimeError as exc:
            failures += 1
            failed_addresses.append(address.lower())
            with write_lock if write_lock is not None else contextlib.nullcontext():
                store.mark_wallet_error(
                    connection,
                    address,
                    str(exc),
                    stage="fills",
                    observed_at=now,
                )
                connection.commit()
            print(f"[hyperliquid] wallet={address[:8]}... error={exc}", flush=True)
    return {
        "walletsSelected": len(selected),
        "walletsSynced": synced,
        "fills": normalized_count,
        "fillFailures": failures,
        "historyLimitedWallets": incomplete,
        "successfulAddresses": successful_addresses,
        "failedAddresses": failed_addresses,
    }


def run_hyperliquid_smart_money(
    *,
    db_path: str = "",
    output_path: str = "",
    stage: str = "all",
    lookback_days: int = 30,
    max_markets: int = 32,
    max_wallets: int = 32,
    api_pause: bool = True,
    client_output_dir: str = "",
) -> dict[str, Any]:
    if stage not in {"markets", "wallets", "profiles", "score", "all"}:
        raise ValueError(f"Unsupported Hyperliquid stage: {stage}")
    db = Path(db_path).resolve() if db_path else (RUNTIME_DATA_DIR / "dev.db").resolve()
    output = Path(output_path).resolve() if output_path else (ROOT / "web" / "lib" / "data" / "hyperliquidSmartMoney.json").resolve()
    now = _utc_now()
    store = HyperliquidStore(db)
    client = HyperliquidInfoClient()
    client.set_pacing(api_pause)
    counts: dict[str, Any] = {"stage": stage, "db": str(db), "output": str(output)}

    with store.connect() as connection:
        store.ensure_tables(connection)
        if stage in {"markets", "wallets", "all"}:
            instruments = _discover_instruments(client)
            store.upsert_instruments(connection, instruments, observed_at=_iso(now))
            connection.commit()
            counts["instruments"] = len(instruments)
        else:
            raw_instruments = [dict(row) for row in connection.execute("SELECT * FROM hl_tradfi_instrument WHERE is_active=1")]
            from ...platforms.hyperliquid.normalizer import TradFiInstrument
            instruments = [
                TradFiInstrument(
                    coin=row["coin"], dex=row["dex"], symbol=row["symbol"], category=row["category"],
                    sz_decimals=row["sz_decimals"], max_leverage=row["max_leverage"], mark_px=row["mark_px"],
                    oracle_px=row["oracle_px"], open_interest=row["open_interest"], day_notional_volume=row["day_notional_volume"],
                )
                for row in raw_instruments
            ]

        if stage in {"wallets", "all"}:
            seeds = _wallet_seeds(client, instruments, max_markets=max_markets, api_pause=api_pause)
            store.upsert_wallet_seeds(connection, seeds, observed_at=_iso(now))
            connection.commit()
            counts["walletSeeds"] = len(seeds)
            counts.update(
                _sync_wallet_fills(
                    connection,
                    client=client,
                    store=store,
                    instruments=instruments,
                    now=now,
                    lookback_days=lookback_days,
                    max_wallets=max_wallets,
                    api_pause=api_pause,
                )
            )

        scores: list[dict[str, Any]] = []
        signals: list[dict[str, Any]] = []
        threshold = 100.0
        if stage in {"profiles", "score", "all"}:
            scores, signals, threshold = build_wallet_scores_and_signals(
                connection,
                as_of=now,
                lookback_days=lookback_days,
            )

        if stage in {"profiles", "all"}:
            qualified_addresses = [
                str(row["address"])
                for row in scores
                if row["eligible"]
            ]
            profile_addresses = (
                qualified_addresses
                if max_wallets <= 0
                else qualified_addresses[:max_wallets]
            )
            counts.update(
                _sync_wallet_profiles(
                    connection,
                    client=client,
                    store=store,
                    instruments=instruments,
                    addresses=profile_addresses,
                    now=now,
                    lookback_days=lookback_days,
                    api_pause=api_pause,
                )
            )
            scores, signals, threshold = build_wallet_scores_and_signals(
                connection,
                as_of=now,
                lookback_days=lookback_days,
            )

        if stage in {"profiles", "score", "all"}:
            payload = export_hyperliquid_smart_money(
                output,
                generated_at=now,
                lookback_days=lookback_days,
                scores=scores,
                signals=signals,
                smart_threshold=threshold,
            )
            counts.update(
                {
                    "scoredWallets": len(scores),
                    "qualifiedWallets": payload["summary"]["qualifiedWalletCount"],
                    "smartWallets": payload["summary"]["smartWalletCount"],
                    "marketSignals": len(payload["markets"]),
                }
            )
            if client_output_dir:
                destination = Path(client_output_dir).resolve()
                destination.mkdir(parents=True, exist_ok=True)
                available_tables = {
                    str(row[0])
                    for row in connection.execute(
                        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('sv_investor_score','sv_call')"
                    ).fetchall()
                }
                account_updates = None
                if {"sv_investor_score", "sv_call"}.issubset(available_tables):
                    client_tickers = tuple(
                        sorted(
                            str(market.get("symbol") or "").upper()
                            for market in payload.get("markets") or []
                            if market.get("category") == "stocks" and market.get("symbol")
                        )
                    )
                    account_updates = build_smart_account_client_collections(
                        connection,
                        as_of=now,
                        update_days=30,
                        update_limit=500,
                        update_tickers=client_tickers,
                        include_profiles=False,
                    )["smart-account-updates"]
                client_collections = build_hyperliquid_client_collections(
                    payload,
                    smart_account_updates=account_updates,
                )
                for name, documents in client_collections.items():
                    target = destination / f"{name}.json"
                    temporary = target.with_suffix(".json.tmp")
                    temporary.write_text(
                        json.dumps(documents, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8",
                    )
                    temporary.replace(target)
                counts["clientOutput"] = str(destination)
                counts["clientWallets"] = len(client_collections["smart-money"])
                counts["clientMovements"] = len(client_collections["smart-money-movements"])
                if account_updates is not None:
                    counts["clientSignals"] = len(client_collections["portfolio-signals"])
                    counts["clientIntelligence"] = len(client_collections["ticker-intelligence"])
    return counts
