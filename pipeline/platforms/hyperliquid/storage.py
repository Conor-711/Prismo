"""SQLite persistence for Hyperliquid raw and normalized facts."""
from __future__ import annotations

import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Any, Iterable

from .normalizer import TradFiInstrument


class HyperliquidStore:
    def __init__(self, db_path: str | Path) -> None:
        self.db_path = Path(db_path).resolve()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA busy_timeout=8000")
        return connection

    def ensure_tables(self, connection: sqlite3.Connection) -> None:
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS hl_tradfi_instrument (
              coin TEXT PRIMARY KEY,
              dex TEXT NOT NULL,
              symbol TEXT NOT NULL,
              category TEXT NOT NULL,
              sz_decimals INTEGER NOT NULL DEFAULT 0,
              max_leverage REAL NOT NULL DEFAULT 0,
              mark_px REAL NOT NULL DEFAULT 0,
              oracle_px REAL NOT NULL DEFAULT 0,
              open_interest REAL NOT NULL DEFAULT 0,
              day_notional_volume REAL NOT NULL DEFAULT 0,
              is_active INTEGER NOT NULL DEFAULT 1,
              last_seen_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_hl_instrument_category
              ON hl_tradfi_instrument(category, day_notional_volume DESC);

            CREATE TABLE IF NOT EXISTS hl_wallet (
              address TEXT PRIMARY KEY,
              first_seen_at TEXT NOT NULL,
              last_seen_at TEXT NOT NULL,
              discovery_notional REAL NOT NULL DEFAULT 0,
              discovery_trade_count INTEGER NOT NULL DEFAULT 0,
              discovery_coins_json TEXT NOT NULL DEFAULT '[]',
              fills_synced_at TEXT,
              fills_truncated INTEGER NOT NULL DEFAULT 0,
              fills_limit_reason TEXT,
              fills_cursor_ms INTEGER NOT NULL DEFAULT 0,
              fills_backfill_complete INTEGER NOT NULL DEFAULT 0,
              fills_retry_count INTEGER NOT NULL DEFAULT 0,
              fills_retry_after TEXT,
              fills_last_error TEXT,
              profile_synced_at TEXT,
              extended_profile_synced_at TEXT,
              profile_retry_count INTEGER NOT NULL DEFAULT 0,
              profile_retry_after TEXT,
              profile_last_error TEXT,
              last_error TEXT
            );

            CREATE TABLE IF NOT EXISTS hl_fill (
              address TEXT NOT NULL,
              tid TEXT NOT NULL,
              coin TEXT NOT NULL,
              dex TEXT NOT NULL,
              symbol TEXT NOT NULL,
              category TEXT NOT NULL,
              side TEXT NOT NULL,
              direction TEXT NOT NULL,
              price REAL NOT NULL,
              size REAL NOT NULL,
              notional REAL NOT NULL,
              time_ms INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              created_day TEXT NOT NULL,
              start_position REAL NOT NULL,
              position_after REAL NOT NULL,
              closed_pnl REAL NOT NULL DEFAULT 0,
              fee REAL NOT NULL DEFAULT 0,
              crossed INTEGER NOT NULL DEFAULT 0,
              liquidation INTEGER NOT NULL DEFAULT 0,
              hash TEXT NOT NULL DEFAULT '',
              oid TEXT NOT NULL DEFAULT '',
              raw_json TEXT NOT NULL DEFAULT '{}',
              PRIMARY KEY(address, tid)
            );
            CREATE INDEX IF NOT EXISTS idx_hl_fill_address_time
              ON hl_fill(address, time_ms DESC);
            CREATE INDEX IF NOT EXISTS idx_hl_fill_coin_time
              ON hl_fill(coin, time_ms DESC);
            CREATE INDEX IF NOT EXISTS idx_hl_fill_time
              ON hl_fill(time_ms DESC);

            CREATE TABLE IF NOT EXISTS hl_trade_tape (
              coin TEXT NOT NULL,
              tid TEXT NOT NULL,
              time_ms INTEGER NOT NULL,
              side TEXT NOT NULL,
              price REAL NOT NULL,
              size REAL NOT NULL,
              notional REAL NOT NULL,
              buyer TEXT NOT NULL,
              seller TEXT NOT NULL,
              hash TEXT NOT NULL DEFAULT '',
              observed_at TEXT NOT NULL,
              raw_json TEXT NOT NULL DEFAULT '{}',
              PRIMARY KEY(coin, tid, time_ms)
            );
            CREATE INDEX IF NOT EXISTS idx_hl_trade_tape_time
              ON hl_trade_tape(time_ms DESC, coin);
            CREATE INDEX IF NOT EXISTS idx_hl_trade_tape_buyer
              ON hl_trade_tape(buyer, time_ms DESC);
            CREATE INDEX IF NOT EXISTS idx_hl_trade_tape_seller
              ON hl_trade_tape(seller, time_ms DESC);

            CREATE TABLE IF NOT EXISTS hl_wallet_state (
              address TEXT NOT NULL,
              dex TEXT NOT NULL,
              account_value REAL NOT NULL DEFAULT 0,
              total_notional REAL NOT NULL DEFAULT 0,
              margin_used REAL NOT NULL DEFAULT 0,
              maintenance_margin REAL NOT NULL DEFAULT 0,
              withdrawable REAL NOT NULL DEFAULT 0,
              observed_at TEXT NOT NULL,
              raw_json TEXT NOT NULL DEFAULT '{}',
              PRIMARY KEY(address, dex)
            );

            CREATE TABLE IF NOT EXISTS hl_wallet_state_snapshot (
              address TEXT NOT NULL,
              dex TEXT NOT NULL,
              account_value REAL NOT NULL DEFAULT 0,
              total_notional REAL NOT NULL DEFAULT 0,
              margin_used REAL NOT NULL DEFAULT 0,
              maintenance_margin REAL NOT NULL DEFAULT 0,
              withdrawable REAL NOT NULL DEFAULT 0,
              observed_at TEXT NOT NULL,
              raw_json TEXT NOT NULL DEFAULT '{}',
              PRIMARY KEY(address, dex, observed_at)
            );
            CREATE INDEX IF NOT EXISTS idx_hl_wallet_state_snapshot_time
              ON hl_wallet_state_snapshot(observed_at DESC, address);

            CREATE TABLE IF NOT EXISTS hl_wallet_position (
              address TEXT NOT NULL,
              coin TEXT NOT NULL,
              dex TEXT NOT NULL,
              symbol TEXT NOT NULL,
              category TEXT NOT NULL,
              size REAL NOT NULL DEFAULT 0,
              position_value REAL NOT NULL DEFAULT 0,
              entry_px REAL,
              mark_px REAL,
              unrealized_pnl REAL NOT NULL DEFAULT 0,
              return_on_equity REAL NOT NULL DEFAULT 0,
              liquidation_px REAL,
              leverage REAL NOT NULL DEFAULT 0,
              margin_used REAL NOT NULL DEFAULT 0,
              max_leverage REAL NOT NULL DEFAULT 0,
              funding_all_time REAL NOT NULL DEFAULT 0,
              funding_since_open REAL NOT NULL DEFAULT 0,
              observed_at TEXT NOT NULL,
              raw_json TEXT NOT NULL DEFAULT '{}',
              PRIMARY KEY(address, coin)
            );
            CREATE INDEX IF NOT EXISTS idx_hl_wallet_position_symbol
              ON hl_wallet_position(symbol, ABS(position_value) DESC);

            CREATE TABLE IF NOT EXISTS hl_wallet_position_snapshot (
              address TEXT NOT NULL,
              coin TEXT NOT NULL,
              dex TEXT NOT NULL,
              symbol TEXT NOT NULL,
              category TEXT NOT NULL,
              size REAL NOT NULL DEFAULT 0,
              position_value REAL NOT NULL DEFAULT 0,
              entry_px REAL,
              mark_px REAL,
              unrealized_pnl REAL NOT NULL DEFAULT 0,
              return_on_equity REAL NOT NULL DEFAULT 0,
              liquidation_px REAL,
              leverage REAL NOT NULL DEFAULT 0,
              margin_used REAL NOT NULL DEFAULT 0,
              max_leverage REAL NOT NULL DEFAULT 0,
              funding_all_time REAL NOT NULL DEFAULT 0,
              funding_since_open REAL NOT NULL DEFAULT 0,
              observed_at TEXT NOT NULL,
              raw_json TEXT NOT NULL DEFAULT '{}',
              PRIMARY KEY(address, coin, observed_at)
            );
            CREATE INDEX IF NOT EXISTS idx_hl_position_snapshot_symbol_time
              ON hl_wallet_position_snapshot(symbol, observed_at DESC);

            CREATE TABLE IF NOT EXISTS hl_wallet_portfolio (
              address TEXT NOT NULL,
              period TEXT NOT NULL,
              volume REAL NOT NULL DEFAULT 0,
              account_value_history_json TEXT NOT NULL DEFAULT '[]',
              pnl_history_json TEXT NOT NULL DEFAULT '[]',
              observed_at TEXT NOT NULL,
              PRIMARY KEY(address, period)
            );

            CREATE TABLE IF NOT EXISTS hl_wallet_ledger (
              address TEXT NOT NULL,
              event_id TEXT NOT NULL,
              time_ms INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              event_type TEXT NOT NULL,
              amount_usd REAL NOT NULL DEFAULT 0,
              direction TEXT NOT NULL,
              token TEXT NOT NULL DEFAULT '',
              hash TEXT NOT NULL DEFAULT '',
              raw_json TEXT NOT NULL DEFAULT '{}',
              PRIMARY KEY(address, event_id)
            );
            CREATE INDEX IF NOT EXISTS idx_hl_wallet_ledger_time
              ON hl_wallet_ledger(address, time_ms DESC);
            """
        )
        self._ensure_column(connection, "hl_wallet", "fills_cursor_ms", "INTEGER NOT NULL DEFAULT 0")
        self._ensure_column(connection, "hl_wallet", "fills_backfill_complete", "INTEGER NOT NULL DEFAULT 0")
        self._ensure_column(connection, "hl_wallet", "fills_limit_reason", "TEXT")
        self._ensure_column(connection, "hl_wallet", "fills_retry_count", "INTEGER NOT NULL DEFAULT 0")
        self._ensure_column(connection, "hl_wallet", "fills_retry_after", "TEXT")
        self._ensure_column(connection, "hl_wallet", "fills_last_error", "TEXT")
        self._ensure_column(connection, "hl_wallet", "profile_synced_at", "TEXT")
        self._ensure_column(connection, "hl_wallet", "extended_profile_synced_at", "TEXT")
        self._ensure_column(connection, "hl_wallet", "profile_retry_count", "INTEGER NOT NULL DEFAULT 0")
        self._ensure_column(connection, "hl_wallet", "profile_retry_after", "TEXT")
        self._ensure_column(connection, "hl_wallet", "profile_last_error", "TEXT")
        self._ensure_column(connection, "hl_wallet", "last_error", "TEXT")
        # Older runs marked the source's 10,000-fill ceiling without making it
        # terminal. Preserve that limitation, reconstruct a forward cursor, and
        # stop repeatedly downloading history that the official API cannot expose.
        connection.execute(
            """
            UPDATE hl_wallet
            SET fills_backfill_complete=1,
                fills_cursor_ms=CASE
                  WHEN fills_cursor_ms>0 THEN fills_cursor_ms
                  WHEN (SELECT MAX(time_ms) FROM hl_fill WHERE hl_fill.address=hl_wallet.address) IS NOT NULL
                    THEN (SELECT MAX(time_ms) FROM hl_fill WHERE hl_fill.address=hl_wallet.address)
                  WHEN fills_synced_at IS NOT NULL
                    THEN CAST(strftime('%s', fills_synced_at) AS INTEGER) * 1000
                  ELSE 0
                END
            WHERE fills_truncated=1 AND fills_backfill_complete=0
              AND (fills_synced_at IS NOT NULL OR EXISTS (
                SELECT 1 FROM hl_fill WHERE hl_fill.address=hl_wallet.address
              ))
            """
        )
        connection.execute(
            """
            UPDATE hl_wallet
            SET fills_limit_reason='source_10000'
            WHERE fills_truncated=1 AND fills_limit_reason IS NULL
            """
        )

    @staticmethod
    def _ensure_column(
        connection: sqlite3.Connection,
        table: str,
        column: str,
        declaration: str,
    ) -> None:
        columns = {str(row[1]) for row in connection.execute(f"PRAGMA table_info({table})")}
        if column not in columns:
            connection.execute(f"ALTER TABLE {table} ADD COLUMN {column} {declaration}")

    def upsert_instruments(
        self,
        connection: sqlite3.Connection,
        instruments: Iterable[TradFiInstrument],
        *,
        observed_at: str,
    ) -> None:
        connection.execute("UPDATE hl_tradfi_instrument SET is_active=0")
        connection.executemany(
            """
            INSERT INTO hl_tradfi_instrument (
              coin, dex, symbol, category, sz_decimals, max_leverage,
              mark_px, oracle_px, open_interest, day_notional_volume,
              is_active, last_seen_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
            ON CONFLICT(coin) DO UPDATE SET
              dex=excluded.dex,
              symbol=excluded.symbol,
              category=excluded.category,
              sz_decimals=excluded.sz_decimals,
              max_leverage=excluded.max_leverage,
              mark_px=excluded.mark_px,
              oracle_px=excluded.oracle_px,
              open_interest=excluded.open_interest,
              day_notional_volume=excluded.day_notional_volume,
              is_active=1,
              last_seen_at=excluded.last_seen_at
            """,
            [
                (
                    item.coin,
                    item.dex,
                    item.symbol,
                    item.category,
                    item.sz_decimals,
                    item.max_leverage,
                    item.mark_px,
                    item.oracle_px,
                    item.open_interest,
                    item.day_notional_volume,
                    observed_at,
                )
                for item in instruments
            ],
        )

    def upsert_wallet_seeds(
        self,
        connection: sqlite3.Connection,
        seeds: Iterable[dict[str, Any]],
        *,
        observed_at: str,
    ) -> None:
        connection.executemany(
            """
            INSERT INTO hl_wallet (
              address, first_seen_at, last_seen_at, discovery_notional,
              discovery_trade_count, discovery_coins_json
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(address) DO UPDATE SET
              last_seen_at=excluded.last_seen_at,
              discovery_notional=excluded.discovery_notional,
              discovery_trade_count=excluded.discovery_trade_count,
              discovery_coins_json=excluded.discovery_coins_json
            """,
            [
                (
                    str(seed["address"]).lower(),
                    observed_at,
                    observed_at,
                    float(seed.get("notional") or 0),
                    int(seed.get("trade_count") or 0),
                    json.dumps(sorted(seed.get("coins") or []), separators=(",", ":")),
                )
                for seed in seeds
            ],
        )

    def upsert_fills(
        self,
        connection: sqlite3.Connection,
        fills: Iterable[dict[str, Any]],
    ) -> int:
        rows = list(fills)
        connection.executemany(
            """
            INSERT INTO hl_fill (
              address, tid, coin, dex, symbol, category, side, direction,
              price, size, notional, time_ms, created_at, created_day,
              start_position, position_after, closed_pnl, fee, crossed,
              liquidation, hash, oid, raw_json
            ) VALUES (
              ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT(address, tid) DO UPDATE SET
              direction=excluded.direction,
              price=excluded.price,
              size=excluded.size,
              notional=excluded.notional,
              start_position=excluded.start_position,
              position_after=excluded.position_after,
              closed_pnl=excluded.closed_pnl,
              fee=excluded.fee,
              crossed=excluded.crossed,
              liquidation=excluded.liquidation,
              raw_json=excluded.raw_json
            """,
            [
                (
                    row["address"], row["tid"], row["coin"], row["dex"], row["symbol"],
                    row["category"], row["side"], row["direction"], row["price"], row["size"],
                    row["notional"], row["time_ms"], row["created_at"], row["created_day"],
                    row["start_position"], row["position_after"], row["closed_pnl"], row["fee"],
                    1 if row["crossed"] else 0, row["liquidation"], row["hash"], row["oid"],
                    json.dumps(row["raw"], ensure_ascii=False, separators=(",", ":")),
                )
                for row in rows
            ],
        )
        return len(rows)

    def upsert_trade_tape(
        self,
        connection: sqlite3.Connection,
        trades: Iterable[dict[str, Any]],
        *,
        observed_at: str,
    ) -> tuple[int, set[str]]:
        inserted = 0
        active_addresses: set[str] = set()
        for row in trades:
            users = row.get("users") or []
            if not isinstance(users, list) or len(users) < 2:
                continue
            buyer = str(users[0]).lower()
            seller = str(users[1]).lower()
            if not (
                buyer.startswith("0x")
                and seller.startswith("0x")
                and len(buyer) == 42
                and len(seller) == 42
            ):
                continue
            coin = str(row.get("coin") or "")
            tid = str(row.get("tid") or "")
            time_ms = int(float(row.get("time") or 0))
            price = float(row.get("px") or 0)
            size = float(row.get("sz") or 0)
            side = str(row.get("side") or "").upper()
            if not coin or not tid or time_ms <= 0 or price <= 0 or size <= 0 or side not in {"A", "B"}:
                continue
            notional = abs(price * size)
            result = connection.execute(
                """
                INSERT OR IGNORE INTO hl_trade_tape (
                  coin, tid, time_ms, side, price, size, notional,
                  buyer, seller, hash, observed_at, raw_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    coin,
                    tid,
                    time_ms,
                    side,
                    price,
                    size,
                    notional,
                    buyer,
                    seller,
                    str(row.get("hash") or ""),
                    observed_at,
                    json.dumps(row, ensure_ascii=False, separators=(",", ":")),
                ),
            )
            active_addresses.update((buyer, seller))
            if result.rowcount != 1:
                continue
            inserted += 1
            for address in (buyer, seller):
                existing = connection.execute(
                    "SELECT discovery_coins_json FROM hl_wallet WHERE address=?",
                    (address,),
                ).fetchone()
                coins = set(json.loads(str(existing[0] or "[]"))) if existing else set()
                coins.add(coin)
                connection.execute(
                    """
                    INSERT INTO hl_wallet (
                      address, first_seen_at, last_seen_at, discovery_notional,
                      discovery_trade_count, discovery_coins_json
                    ) VALUES (?, ?, ?, ?, 1, ?)
                    ON CONFLICT(address) DO UPDATE SET
                      last_seen_at=excluded.last_seen_at,
                      discovery_notional=hl_wallet.discovery_notional + excluded.discovery_notional,
                      discovery_trade_count=hl_wallet.discovery_trade_count + 1,
                      discovery_coins_json=excluded.discovery_coins_json
                    """,
                    (
                        address,
                        observed_at,
                        observed_at,
                        notional,
                        json.dumps(sorted(coins), separators=(",", ":")),
                    ),
                )
        return inserted, active_addresses

    def mark_wallet_synced(
        self,
        connection: sqlite3.Connection,
        address: str,
        *,
        synced_at: str,
        truncated: bool,
        limit_reason: str | None = None,
        cursor_ms: int,
        backfill_complete: bool,
    ) -> None:
        connection.execute(
            """
            UPDATE hl_wallet
            SET fills_synced_at=?, fills_truncated=?, fills_cursor_ms=?,
                fills_backfill_complete=?, fills_retry_count=0,
                fills_retry_after=NULL, fills_last_error=NULL,
                fills_limit_reason=CASE
                  WHEN ?=0 THEN NULL
                  ELSE COALESCE(?, fills_limit_reason, 'source_or_policy_limit')
                END,
                last_error=profile_last_error
            WHERE address=?
            """,
            (
                synced_at,
                1 if truncated else 0,
                max(0, int(cursor_ms)),
                1 if backfill_complete else 0,
                1 if truncated else 0,
                limit_reason,
                address.lower(),
            ),
        )

    def mark_wallet_error(
        self,
        connection: sqlite3.Connection,
        address: str,
        message: str,
        *,
        stage: str = "general",
        observed_at: dt.datetime | None = None,
    ) -> None:
        normalized_stage = stage.strip().lower()
        error = message[:500]
        if normalized_stage not in {"fills", "profile"}:
            connection.execute(
                "UPDATE hl_wallet SET last_error=? WHERE address=?",
                (error, address.lower()),
            )
            return

        prefix = "fills" if normalized_stage == "fills" else "profile"
        row = connection.execute(
            f"SELECT {prefix}_retry_count FROM hl_wallet WHERE address=?",
            (address.lower(),),
        ).fetchone()
        retry_count = min(16, int(row[0] or 0) + 1) if row else 1
        lowered = error.lower()
        if "429" in lowered or "too many requests" in lowered:
            base_seconds, cap_seconds = 60, 3_600
        elif "timeout" in lowered or "temporar" in lowered:
            base_seconds, cap_seconds = 15, 900
        else:
            base_seconds, cap_seconds = 30, 1_800
        delay_seconds = min(cap_seconds, base_seconds * (2 ** (retry_count - 1)))
        now = observed_at or dt.datetime.now(dt.timezone.utc)
        if now.tzinfo is None:
            now = now.replace(tzinfo=dt.timezone.utc)
        retry_after = (now.astimezone(dt.timezone.utc) + dt.timedelta(seconds=delay_seconds)).isoformat()
        connection.execute(
            f"""
            UPDATE hl_wallet
            SET {prefix}_retry_count=?, {prefix}_retry_after=?,
                {prefix}_last_error=?, last_error=?
            WHERE address=?
            """,
            (retry_count, retry_after, error, error, address.lower()),
        )

    def upsert_wallet_state(
        self,
        connection: sqlite3.Connection,
        row: dict[str, Any],
    ) -> None:
        serialized = json.dumps(row.get("raw") or {}, ensure_ascii=False, separators=(",", ":"))
        connection.execute(
            """
            INSERT OR REPLACE INTO hl_wallet_state_snapshot (
              address, dex, account_value, total_notional, margin_used,
              maintenance_margin, withdrawable, observed_at, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                row["address"], row["dex"], row["account_value"], row["total_notional"],
                row["margin_used"], row["maintenance_margin"], row["withdrawable"],
                row["observed_at"], serialized,
            ),
        )
        connection.execute(
            """
            INSERT INTO hl_wallet_state (
              address, dex, account_value, total_notional, margin_used,
              maintenance_margin, withdrawable, observed_at, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(address, dex) DO UPDATE SET
              account_value=excluded.account_value,
              total_notional=excluded.total_notional,
              margin_used=excluded.margin_used,
              maintenance_margin=excluded.maintenance_margin,
              withdrawable=excluded.withdrawable,
              observed_at=excluded.observed_at,
              raw_json=excluded.raw_json
            """,
            (
                row["address"], row["dex"], row["account_value"], row["total_notional"],
                row["margin_used"], row["maintenance_margin"], row["withdrawable"],
                row["observed_at"], serialized,
            ),
        )

    def replace_wallet_positions(
        self,
        connection: sqlite3.Connection,
        *,
        address: str,
        dex: str,
        rows: Iterable[dict[str, Any]],
        observed_at: str | None = None,
    ) -> int:
        positions = list(rows)
        snapshot_time = observed_at or next(
            (str(row.get("observed_at") or "") for row in positions if row.get("observed_at")),
            "",
        )
        previous = {
            str(row["coin"]): dict(row)
            for row in connection.execute(
                "SELECT * FROM hl_wallet_position WHERE address=? AND dex=?",
                (address.lower(), dex),
            )
        }
        connection.execute(
            "DELETE FROM hl_wallet_position WHERE address=? AND dex=?",
            (address.lower(), dex),
        )
        connection.executemany(
            """
            INSERT INTO hl_wallet_position (
              address, coin, dex, symbol, category, size, position_value,
              entry_px, mark_px, unrealized_pnl, return_on_equity,
              liquidation_px, leverage, margin_used, max_leverage,
              funding_all_time, funding_since_open, observed_at, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    row["address"], row["coin"], row["dex"], row["symbol"], row["category"],
                    row["size"], row["position_value"], row.get("entry_px"), row.get("mark_px"),
                    row["unrealized_pnl"], row["return_on_equity"], row.get("liquidation_px"),
                    row["leverage"], row["margin_used"], row["max_leverage"],
                    row["funding_all_time"], row["funding_since_open"], row["observed_at"],
                    json.dumps(row.get("raw") or {}, ensure_ascii=False, separators=(",", ":")),
                )
                for row in positions
            ],
        )
        if snapshot_time:
            snapshots = list(positions)
            active_coins = {str(row["coin"]) for row in positions}
            for coin, row in previous.items():
                if coin in active_coins:
                    continue
                snapshots.append(
                    {
                        **row,
                        "size": 0.0,
                        "position_value": 0.0,
                        "unrealized_pnl": 0.0,
                        "return_on_equity": 0.0,
                        "margin_used": 0.0,
                        "funding_since_open": 0.0,
                        "observed_at": snapshot_time,
                        "raw": {"closed": True},
                    }
                )
            connection.executemany(
                """
                INSERT OR REPLACE INTO hl_wallet_position_snapshot (
                  address, coin, dex, symbol, category, size, position_value,
                  entry_px, mark_px, unrealized_pnl, return_on_equity,
                  liquidation_px, leverage, margin_used, max_leverage,
                  funding_all_time, funding_since_open, observed_at, raw_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        row["address"], row["coin"], row["dex"], row["symbol"], row["category"],
                        row["size"], row["position_value"], row.get("entry_px"), row.get("mark_px"),
                        row["unrealized_pnl"], row["return_on_equity"], row.get("liquidation_px"),
                        row["leverage"], row["margin_used"], row["max_leverage"],
                        row["funding_all_time"], row["funding_since_open"], row["observed_at"],
                        json.dumps(row.get("raw") or {}, ensure_ascii=False, separators=(",", ":")),
                    )
                    for row in snapshots
                ],
            )
        return len(positions)

    def mark_profile_synced(
        self,
        connection: sqlite3.Connection,
        address: str,
        *,
        synced_at: str,
        extended: bool,
    ) -> None:
        if extended:
            connection.execute(
                """
                UPDATE hl_wallet
                SET profile_synced_at=?, extended_profile_synced_at=?,
                    profile_retry_count=0, profile_retry_after=NULL,
                    profile_last_error=NULL, last_error=fills_last_error
                WHERE address=?
                """,
                (synced_at, synced_at, address.lower()),
            )
        else:
            connection.execute(
                """
                UPDATE hl_wallet
                SET profile_synced_at=?, profile_retry_count=0,
                    profile_retry_after=NULL, profile_last_error=NULL,
                    last_error=fills_last_error
                WHERE address=?
                """,
                (synced_at, address.lower()),
            )

    def upsert_wallet_portfolio(
        self,
        connection: sqlite3.Connection,
        *,
        address: str,
        rows: Iterable[dict[str, Any]],
        observed_at: str,
    ) -> int:
        periods = list(rows)
        connection.executemany(
            """
            INSERT INTO hl_wallet_portfolio (
              address, period, volume, account_value_history_json,
              pnl_history_json, observed_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(address, period) DO UPDATE SET
              volume=excluded.volume,
              account_value_history_json=excluded.account_value_history_json,
              pnl_history_json=excluded.pnl_history_json,
              observed_at=excluded.observed_at
            """,
            [
                (
                    address.lower(), row["period"], row["volume"],
                    json.dumps(row["account_value_history"], separators=(",", ":")),
                    json.dumps(row["pnl_history"], separators=(",", ":")), observed_at,
                )
                for row in periods
            ],
        )
        return len(periods)

    def upsert_wallet_ledger(
        self,
        connection: sqlite3.Connection,
        *,
        address: str,
        rows: Iterable[dict[str, Any]],
    ) -> int:
        events = list(rows)
        connection.executemany(
            """
            INSERT INTO hl_wallet_ledger (
              address, event_id, time_ms, created_at, event_type, amount_usd,
              direction, token, hash, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(address, event_id) DO UPDATE SET
              amount_usd=excluded.amount_usd,
              direction=excluded.direction,
              raw_json=excluded.raw_json
            """,
            [
                (
                    address.lower(), row["event_id"], row["time_ms"], row["created_at"],
                    row["event_type"], row["amount_usd"], row["direction"], row["token"],
                    row["hash"], json.dumps(row.get("raw") or {}, ensure_ascii=False, separators=(",", ":")),
                )
                for row in events
            ],
        )
        return len(events)
