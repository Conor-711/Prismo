"""Deterministic Hyperliquid TradFi smart-money scoring and export."""
from __future__ import annotations

import collections
import datetime as dt
import json
import math
import sqlite3
import uuid
from pathlib import Path
from typing import Any, Iterable

from .smart_money_evidence import build_smart_money_representative_evidence
from .smart_money_identity import smart_money_public_identities


HL_SCORING_VERSION = "hl-wallet-v2-hyperdash-parity"
HL_EXPORT_VERSION = "hyperliquid-tradfi-smart-money-v2"
HL_DISCOVERY_MIN_TRADES = 5
HL_DISCOVERY_MIN_NOTIONAL = 10_000.0
HL_CANDIDATE_POOL_SIZE = 500
HL_CANDIDATE_ACTIVITY_DAYS = 30
SIGNAL_WINDOWS = (1, 3, 7)
CLIENT_VISIBLE_DAYS = 30
CLIENT_VISIBLE_PERIODS = ("1D", "7D", "30D")
CLIENT_MAX_METRIC_POINTS = 90
CLIENT_MAX_RECENT_TRADES = 20
CLIENT_MAX_CAPITAL_ACTIVITY = 10
CLIENT_MAX_POSITIONS = 12
CLIENT_MAX_ASSET_PERFORMANCE = 10
SMART_MONEY_NAMESPACE = uuid.UUID("9fa6c937-6ef2-4a3e-8d2e-41ef5cdf3a08")


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def percentile(values: list[float], quantile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    position = clamp(quantile, 0.0, 1.0) * (len(ordered) - 1)
    low = int(math.floor(position))
    high = int(math.ceil(position))
    if low == high:
        return ordered[low]
    fraction = position - low
    return ordered[low] * (1 - fraction) + ordered[high] * fraction


def max_drawdown(values: Iterable[float]) -> float:
    peak = 0.0
    equity = 0.0
    drawdown = 0.0
    for value in values:
        equity += value
        peak = max(peak, equity)
        drawdown = max(drawdown, peak - equity)
    return drawdown


def hyperliquid_candidate_addresses(
    connection: sqlite3.Connection,
    *,
    limit: int = HL_CANDIDATE_POOL_SIZE,
    as_of: dt.datetime | None = None,
    activity_days: int = HL_CANDIDATE_ACTIVITY_DAYS,
) -> list[str]:
    """Return the bounded, highest-observed-activity Smart Money cohort."""
    if limit <= 0:
        return []
    current = (as_of or dt.datetime.now(dt.timezone.utc)).astimezone(dt.timezone.utc)
    active_since = (current - dt.timedelta(days=max(1, activity_days))).replace(
        microsecond=0
    ).isoformat()
    return [
        str(row[0])
        for row in connection.execute(
            """
            SELECT address
            FROM hl_wallet
            WHERE last_seen_at>=?
              AND (discovery_trade_count>=? OR discovery_notional>=?)
            ORDER BY discovery_notional DESC, discovery_trade_count DESC,
                     first_seen_at, address
            LIMIT ?
            """,
            (active_since, HL_DISCOVERY_MIN_TRADES, HL_DISCOVERY_MIN_NOTIONAL, limit),
        )
    ]


def _standard_deviation(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    mean = sum(values) / len(values)
    return math.sqrt(sum((value - mean) ** 2 for value in values) / (len(values) - 1))


def _period_metrics(
    account_history: list[list[float]],
    pnl_history: list[list[float]],
    volume: float,
) -> dict[str, Any]:
    pnl_values = [float(point[1]) for point in pnl_history if len(point) >= 2]
    account_values = [float(point[1]) for point in account_history if len(point) >= 2]
    pnl = pnl_values[-1] if pnl_values else 0.0
    equity = account_values[-1] if account_values else 0.0
    pnl_changes = [current - previous for previous, current in zip(pnl_values, pnl_values[1:])]
    denominator = max(percentile([abs(value) for value in account_values if value], 0.5), 1.0)
    returns = [change / denominator for change in pnl_changes]
    volatility = _standard_deviation(returns)
    sharpe = (sum(returns) / len(returns)) / volatility * math.sqrt(252) if returns and volatility else 0.0
    drawdown_pnl = max_drawdown(pnl_changes)
    return {
        "equity": round(equity, 2),
        "pnl": round(pnl, 2),
        "volume": round(volume, 2),
        "sharpe": round(clamp(sharpe, -20, 20), 2),
        "maxDrawdown": round(drawdown_pnl, 2),
        "maxDrawdownPercent": round(drawdown_pnl / denominator, 4),
        "accountValueHistory": [[int(point[0]), round(float(point[1]), 2)] for point in account_history],
        "pnlHistory": [[int(point[0]), round(float(point[1]), 2)] for point in pnl_history],
    }


def _downsample_points(points: list[Any], limit: int = CLIENT_MAX_METRIC_POINTS) -> list[Any]:
    if len(points) <= limit:
        return points
    if limit <= 1:
        return [points[-1]]
    indices = {
        round(index * (len(points) - 1) / (limit - 1))
        for index in range(limit)
    }
    return [points[index] for index in sorted(indices)]


def _compact_period_metrics(periods: dict[str, Any]) -> dict[str, Any]:
    compact: dict[str, Any] = {}
    for period in CLIENT_VISIBLE_PERIODS:
        metric = periods.get(period)
        if not isinstance(metric, dict):
            continue
        compact[period] = {
            **metric,
            "accountValueHistory": _downsample_points(
                list(metric.get("accountValueHistory") or [])
            ),
            "pnlHistory": _downsample_points(list(metric.get("pnlHistory") or [])),
        }
    return compact


def _recent_rows(
    rows: list[dict[str, Any]],
    *,
    generated_at: dt.datetime,
    timestamp_key: str,
    limit: int,
) -> list[dict[str, Any]]:
    cutoff = generated_at - dt.timedelta(days=CLIENT_VISIBLE_DAYS)
    recent = [
        row
        for row in rows
        if (timestamp := _parse_client_time(row.get(timestamp_key))) is not None
        and timestamp >= cutoff
    ]
    recent.sort(key=lambda row: str(row.get(timestamp_key) or ""), reverse=True)
    return recent[:limit]


def _trade_duration_stats(fills: list[dict[str, Any]]) -> dict[str, Any]:
    opened_at: dict[str, int] = {}
    durations: list[float] = []
    for row in sorted(fills, key=lambda item: int(item.get("time_ms") or 0)):
        coin = str(row.get("coin") or "")
        timestamp = int(row.get("time_ms") or 0)
        before = float(row.get("start_position") or 0)
        after = float(row.get("position_after") or 0)
        if abs(before) <= 1e-12 and abs(after) > 1e-12:
            opened_at[coin] = timestamp
        elif before * after < 0:
            if coin in opened_at:
                durations.append(max(0.0, (timestamp - opened_at[coin]) / 3_600_000))
            opened_at[coin] = timestamp
        elif abs(before) > 1e-12 and abs(after) <= 1e-12:
            if coin in opened_at:
                durations.append(max(0.0, (timestamp - opened_at.pop(coin)) / 3_600_000))
    average = sum(durations) / len(durations) if durations else 0.0
    median = percentile(durations, 0.5) if durations else 0.0
    if not durations:
        style = "Unclassified"
    elif median < 1:
        style = "Scalp"
    elif median < 24:
        style = "Intraday"
    elif median < 24 * 7:
        style = "Swing"
    else:
        style = "Position"
    return {
        "completedTrades": len(durations),
        "averageHoldHours": round(average, 2),
        "medianHoldHours": round(median, 2),
        "style": style,
    }


def _asset_performance(fills: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, float]] = collections.defaultdict(
        lambda: {"pnl": 0.0, "fees": 0.0, "volume": 0.0, "trades": 0.0, "wins": 0.0, "losses": 0.0}
    )
    for row in fills:
        symbol = str(row.get("symbol") or row.get("coin") or "")
        item = grouped[symbol]
        pnl = float(row.get("closed_pnl") or 0)
        item["pnl"] += pnl
        item["fees"] += float(row.get("fee") or 0)
        item["volume"] += abs(float(row.get("notional") or 0))
        if str(row.get("direction") or "").lower().startswith("close") or abs(pnl) > 1e-9:
            item["trades"] += 1
            item["wins"] += 1 if pnl > 0 else 0
            item["losses"] += 1 if pnl < 0 else 0
    rows = []
    for symbol, item in grouped.items():
        settled = item["wins"] + item["losses"]
        rows.append(
            {
                "symbol": symbol,
                "netPnl": round(item["pnl"] - item["fees"], 2),
                "fees": round(item["fees"], 2),
                "volume": round(item["volume"], 2),
                "trades": int(item["trades"]),
                "winRate": round(item["wins"] / settled, 4) if settled else 0.0,
            }
        )
    return sorted(rows, key=lambda row: (-float(row["netPnl"]), -float(row["volume"])))


def _size_cohort(account_value: float) -> str:
    if account_value >= 1_000_000:
        return "Kraken"
    if account_value >= 250_000:
        return "Whale"
    if account_value >= 100_000:
        return "Shark"
    if account_value >= 25_000:
        return "Dolphin"
    if account_value >= 10_000:
        return "Fish"
    if account_value >= 2_000:
        return "Crab"
    return "Shrimp"


def _pnl_cohort(net_pnl: float, pnl_values: list[float]) -> str:
    if net_pnl < 0:
        loss_values = sorted(abs(value) for value in pnl_values if value < 0)
        rank = sum(1 for value in loss_values if value <= abs(net_pnl)) / max(len(loss_values), 1)
        if rank >= 0.9:
            return "Rekt"
        if rank >= 0.65:
            return "Heavily Losing"
        if rank >= 0.35:
            return "Losing"
        return "Slight Loss"
    profit_values = sorted(value for value in pnl_values if value >= 0)
    rank = sum(1 for value in profit_values if value <= net_pnl) / max(len(profit_values), 1)
    if rank >= 0.9:
        return "Extremely Profitable"
    if rank >= 0.65:
        return "Highly Profitable"
    if rank >= 0.35:
        return "Profitable"
    return "Slightly Profitable"


def score_wallet_fills(
    address: str,
    fills: list[dict[str, Any]],
    *,
    truncated: bool = False,
    history_complete: bool = True,
) -> dict[str, Any]:
    ordered = sorted(fills, key=lambda row: int(row.get("time_ms") or 0))
    day_pnl: dict[str, float] = collections.defaultdict(float)
    market_notional: dict[str, float] = collections.defaultdict(float)
    traded_notional = 0.0
    closed_notional = 0.0
    realized_pnl = 0.0
    fees = 0.0
    liquidation_count = 0
    maker_count = 0
    closed_count = 0
    long_closed_pnl = 0.0
    short_closed_pnl = 0.0
    long_open_notional = 0.0
    short_open_notional = 0.0

    for row in ordered:
        notional = abs(float(row.get("notional") or 0))
        closed_pnl = float(row.get("closed_pnl") or 0)
        fee = float(row.get("fee") or 0)
        direction = str(row.get("direction") or "").lower()
        symbol = str(row.get("symbol") or row.get("coin") or "")
        traded_notional += notional
        market_notional[symbol] += notional
        realized_pnl += closed_pnl
        fees += fee
        liquidation_count += int(row.get("liquidation") or 0)
        maker_count += 0 if bool(row.get("crossed")) else 1
        day_pnl[str(row.get("created_day") or "")] += closed_pnl - fee
        if direction.startswith("close") or abs(closed_pnl) > 1e-9:
            closed_count += 1
            closed_notional += notional
        if "long" in direction:
            long_closed_pnl += closed_pnl
            if direction.startswith("open"):
                long_open_notional += notional
        elif "short" in direction:
            short_closed_pnl += closed_pnl
            if direction.startswith("open"):
                short_open_notional += notional

    active_days = len({str(row.get("created_day") or "") for row in ordered})
    close_days = [value for value in day_pnl.values() if abs(value) > 1e-9]
    profitable_days = sum(1 for value in close_days if value > 0)
    losing_days = sum(1 for value in close_days if value < 0)
    gross_profit = sum(value for value in close_days if value > 0)
    gross_loss = abs(sum(value for value in close_days if value < 0))
    net_pnl = realized_pnl - fees
    return_proxy = net_pnl / max(closed_notional, 1.0)
    bayes_win_rate = (profitable_days + 2.5) / (profitable_days + losing_days + 5.0)
    profit_factor = gross_profit / max(gross_loss, 1.0)
    drawdown = max_drawdown(day_pnl[day] for day in sorted(day_pnl))
    pnl_scale = gross_profit + gross_loss + 1.0
    drawdown_ratio = drawdown / pnl_scale
    maker_ratio = maker_count / max(len(ordered), 1)
    daily_fill_rate = len(ordered) / max(active_days, 1)

    if not history_complete:
        classification = "incomplete"
    elif truncated or len(ordered) >= 2_000 or (daily_fill_rate >= 180 and maker_ratio >= 0.4):
        classification = "algorithmic"
    elif closed_count < 5 or active_days < 3 or closed_notional < 10_000:
        classification = "insufficient"
    else:
        classification = "directional"

    performance = 50.0 + 50.0 * math.tanh(return_proxy / 0.02)
    consistency = bayes_win_rate * 100.0
    payoff = 100.0 * profit_factor / (profit_factor + 1.0)
    risk = 100.0 * (1.0 - clamp(drawdown_ratio * 1.75, 0.0, 1.0))
    risk -= min(75.0, liquidation_count * 25.0)
    fee_ratio = max(0.0, fees) / max(traded_notional, 1.0)
    execution = 50.0 + (maker_ratio - 0.5) * 20.0 - min(30.0, fee_ratio * 100_000)
    components = {
        "performance": round(clamp(performance, 0, 100), 2),
        "consistency": round(clamp(consistency, 0, 100), 2),
        "payoff": round(clamp(payoff, 0, 100), 2),
        "risk": round(clamp(risk, 0, 100), 2),
        "execution": round(clamp(execution, 0, 100), 2),
    }
    raw_score = (
        components["performance"] * 0.35
        + components["consistency"] * 0.25
        + components["payoff"] * 0.20
        + components["risk"] * 0.15
        + components["execution"] * 0.05
    )
    confidence = min(1.0, math.sqrt(closed_count / 40.0))
    confidence *= min(1.0, math.sqrt(active_days / 20.0))
    confidence *= min(1.0, math.sqrt(closed_notional / 100_000.0))
    score = 50.0 + confidence * (raw_score - 50.0)
    eligible = classification == "directional" and confidence >= 0.2
    top_markets = [
        {"symbol": symbol, "notional": round(notional, 2)}
        for symbol, notional in sorted(market_notional.items(), key=lambda item: -item[1])[:6]
    ]
    duration = _trade_duration_stats(ordered)
    directional_notional = long_open_notional + short_open_notional
    recent_trades = [
        {
            "id": str(row.get("tid") or ""),
            "symbol": str(row.get("symbol") or row.get("coin") or ""),
            "coin": str(row.get("coin") or ""),
            "direction": str(row.get("direction") or "Trade"),
            "side": "Buy" if str(row.get("side") or "").upper() == "B" else "Sell",
            "price": round(float(row.get("price") or 0), 6),
            "size": round(float(row.get("size") or 0), 6),
            "notional": round(abs(float(row.get("notional") or 0)), 2),
            "startPosition": round(float(row.get("start_position") or 0), 8),
            "positionAfter": round(float(row.get("position_after") or 0), 8),
            "closedPnl": round(float(row.get("closed_pnl") or 0), 2),
            "time": str(row.get("created_at") or ""),
            "hash": str(row.get("hash") or ""),
        }
        for row in reversed(ordered[-100:])
    ]
    return {
        "address": address.lower(),
        "score": round(clamp(score, 0, 100), 2),
        "raw_score": round(clamp(raw_score, 0, 100), 2),
        "confidence": round(confidence, 4),
        "eligible": eligible,
        "history_complete": history_complete,
        "classification": classification,
        "fill_count": len(ordered),
        "closed_fill_count": closed_count,
        "active_days": active_days,
        "realized_pnl": round(realized_pnl, 4),
        "fees": round(fees, 4),
        "net_pnl": round(net_pnl, 4),
        "closed_notional": round(closed_notional, 2),
        "traded_notional": round(traded_notional, 2),
        "return_proxy": round(return_proxy, 8),
        "win_rate": round(bayes_win_rate, 4),
        "profit_factor": round(profit_factor, 4),
        "max_drawdown_pnl": round(drawdown, 4),
        "liquidation_count": liquidation_count,
        "maker_ratio": round(maker_ratio, 4),
        "long_closed_pnl": round(long_closed_pnl, 4),
        "short_closed_pnl": round(short_closed_pnl, 4),
        "long_bias": round(long_open_notional / directional_notional, 4) if directional_notional else 0.5,
        "trade_duration": duration,
        "asset_performance": _asset_performance(ordered),
        "recent_trades": recent_trades,
        "top_markets": top_markets,
        "components": components,
    }


def latest_positions(fills: Iterable[dict[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    positions: dict[tuple[str, str], dict[str, Any]] = {}
    for row in sorted(fills, key=lambda item: int(item.get("time_ms") or 0)):
        key = (str(row["address"]), str(row["coin"]))
        positions[key] = {
            "address": str(row["address"]),
            "coin": str(row["coin"]),
            "symbol": str(row["symbol"]),
            "category": str(row["category"]),
            "dex": str(row["dex"]),
            "position": float(row.get("position_after") or 0),
            "last_time_ms": int(row.get("time_ms") or 0),
            "last_action": str(row.get("direction") or ""),
            "last_price": float(row.get("price") or 0),
        }
    return positions


def ensure_derived_tables(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS hl_wallet_score (
          as_of_day TEXT NOT NULL,
          address TEXT NOT NULL,
          scoring_version TEXT NOT NULL,
          score REAL NOT NULL,
          raw_score REAL NOT NULL,
          confidence REAL NOT NULL,
          eligible INTEGER NOT NULL,
          history_complete INTEGER NOT NULL DEFAULT 0,
          classification TEXT NOT NULL,
          fill_count INTEGER NOT NULL,
          closed_fill_count INTEGER NOT NULL,
          active_days INTEGER NOT NULL,
          realized_pnl REAL NOT NULL,
          fees REAL NOT NULL,
          net_pnl REAL NOT NULL,
          closed_notional REAL NOT NULL,
          traded_notional REAL NOT NULL,
          return_proxy REAL NOT NULL,
          win_rate REAL NOT NULL,
          profit_factor REAL NOT NULL,
          max_drawdown_pnl REAL NOT NULL,
          liquidation_count INTEGER NOT NULL,
          maker_ratio REAL NOT NULL,
          top_markets_json TEXT NOT NULL,
          components_json TEXT NOT NULL,
          PRIMARY KEY(as_of_day, address)
        );
        CREATE INDEX IF NOT EXISTS idx_hl_wallet_score_rank
          ON hl_wallet_score(as_of_day, eligible, score DESC);

        CREATE TABLE IF NOT EXISTS hl_asset_signal (
          as_of_day TEXT NOT NULL,
          window_days INTEGER NOT NULL,
          symbol TEXT NOT NULL,
          category TEXT NOT NULL,
          coins_json TEXT NOT NULL,
          venues_json TEXT NOT NULL,
          mark_px REAL NOT NULL,
          day_notional_volume REAL NOT NULL,
          open_interest_notional REAL NOT NULL,
          qualified_wallets INTEGER NOT NULL,
          long_wallets INTEGER NOT NULL,
          short_wallets INTEGER NOT NULL,
          gross_position_notional REAL NOT NULL,
          net_position_notional REAL NOT NULL,
          consensus REAL NOT NULL,
          net_flow_notional REAL NOT NULL,
          weighted_flow REAL NOT NULL,
          signal TEXT NOT NULL,
          top_wallets_json TEXT NOT NULL,
          evidence_json TEXT NOT NULL,
          daily_flow_json TEXT NOT NULL,
          PRIMARY KEY(as_of_day, window_days, symbol, category)
        );
        """
    )
    score_columns = {
        str(row[1]) for row in connection.execute("PRAGMA table_info(hl_wallet_score)")
    }
    if "history_complete" not in score_columns:
        connection.execute(
            "ALTER TABLE hl_wallet_score ADD COLUMN history_complete INTEGER NOT NULL DEFAULT 0"
        )


def _row_dicts(connection: sqlite3.Connection, query: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    return [dict(row) for row in connection.execute(query, params).fetchall()]


def _table_exists(connection: sqlite3.Connection, table: str) -> bool:
    return connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (table,),
    ).fetchone() is not None


def _wallet_label(address: str) -> str:
    return f"Wallet {address[2:6].upper()}...{address[-4:].upper()}"


def _enrich_wallet_scores(
    connection: sqlite3.Connection,
    scores: list[dict[str, Any]],
) -> None:
    if not _table_exists(connection, "hl_wallet_state"):
        return
    states_by_wallet: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    positions_by_wallet: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    portfolios_by_wallet: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    ledgers_by_wallet: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for row in _row_dicts(connection, "SELECT * FROM hl_wallet_state"):
        states_by_wallet[str(row["address"])].append(row)
    for row in _row_dicts(connection, "SELECT * FROM hl_wallet_position"):
        positions_by_wallet[str(row["address"])].append(row)
    for row in _row_dicts(connection, "SELECT * FROM hl_wallet_portfolio"):
        portfolios_by_wallet[str(row["address"])].append(row)
    for row in _row_dicts(connection, "SELECT * FROM hl_wallet_ledger ORDER BY time_ms DESC"):
        if len(ledgers_by_wallet[str(row["address"])]) < 20:
            ledgers_by_wallet[str(row["address"])].append(row)

    pnl_values = [float(row["net_pnl"]) for row in scores if row["eligible"]]
    period_labels = {
        "day": "1D",
        "week": "7D",
        "month": "30D",
        "allTime": "ALL",
    }
    for score in scores:
        address = str(score["address"])
        states = states_by_wallet.get(address, [])
        position_rows = positions_by_wallet.get(address, [])
        account_value = sum(float(row["account_value"]) for row in states)
        total_notional = sum(float(row["total_notional"]) for row in states)
        margin_used = sum(float(row["margin_used"]) for row in states)
        withdrawable = sum(float(row["withdrawable"]) for row in states)
        positions = []
        for row in position_rows:
            size = float(row["size"])
            mark = float(row["mark_px"] or 0)
            liquidation = float(row["liquidation_px"] or 0)
            positions.append(
                {
                    "coin": row["coin"],
                    "symbol": row["symbol"],
                    "category": row["category"],
                    "dex": row["dex"],
                    "direction": "Long" if size > 0 else "Short",
                    "size": round(size, 6),
                    "notional": round(abs(float(row["position_value"])), 2),
                    "entryPrice": round(float(row["entry_px"]), 6) if row["entry_px"] is not None else None,
                    "markPrice": round(mark, 6) if mark else None,
                    "unrealizedPnl": round(float(row["unrealized_pnl"]), 2),
                    "returnOnEquity": round(float(row["return_on_equity"]), 4),
                    "liquidationPrice": round(liquidation, 6) if liquidation else None,
                    "liquidationDistance": round(abs(mark - liquidation) / mark, 4) if mark and liquidation else None,
                    "leverage": round(float(row["leverage"]), 2),
                    "marginUsed": round(float(row["margin_used"]), 2),
                    "fundingSinceOpen": round(float(row["funding_since_open"]), 2),
                }
            )
        positions.sort(key=lambda row: -float(row["notional"]))

        periods: dict[str, Any] = {}
        for row in portfolios_by_wallet.get(address, []):
            label = period_labels.get(str(row["period"]))
            if not label:
                continue
            periods[label] = _period_metrics(
                json.loads(str(row["account_value_history_json"])),
                json.loads(str(row["pnl_history_json"])),
                float(row["volume"]),
            )
        activity = [
            {
                "id": row["event_id"],
                "type": row["event_type"],
                "direction": row["direction"],
                "amount": round(float(row["amount_usd"]), 2),
                "token": row["token"],
                "time": row["created_at"],
                "hash": row["hash"],
            }
            for row in ledgers_by_wallet.get(address, [])
        ]
        style = str(score["trade_duration"]["style"])
        if score["classification"] == "algorithmic":
            style = "Algo"
        score.update(
            {
                "label": _wallet_label(address),
                "style": style,
                "size_cohort": _size_cohort(account_value),
                "pnl_cohort": _pnl_cohort(float(score["net_pnl"]), pnl_values),
                "account_value": round(account_value, 2),
                "total_notional": round(total_notional, 2),
                "margin_used": round(margin_used, 2),
                "withdrawable": round(withdrawable, 2),
                "leverage": round(total_notional / max(account_value, 1.0), 2),
                "margin_utilization": round(margin_used / max(account_value, 1.0), 4),
                "unrealized_pnl": round(sum(float(row["unrealized_pnl"]) for row in position_rows), 2),
                "funding_since_open": round(sum(float(row["funding_since_open"]) for row in position_rows), 2),
                "current_positions": positions,
                "period_metrics": periods,
                "capital_activity": activity,
            }
        )


def _market_rollup(instruments: list[dict[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    groups: dict[tuple[str, str], dict[str, Any]] = {}
    for row in instruments:
        key = (str(row["symbol"]), str(row["category"]))
        group = groups.setdefault(
            key,
            {
                "symbol": key[0],
                "category": key[1],
                "coins": [],
                "venues": [],
                "day_notional_volume": 0.0,
                "open_interest_notional": 0.0,
                "mark_px": 0.0,
                "primary_volume": -1.0,
                "coin_marks": {},
            },
        )
        coin = str(row["coin"])
        dex = str(row["dex"])
        mark = float(row.get("mark_px") or 0)
        volume = float(row.get("day_notional_volume") or 0)
        open_interest = float(row.get("open_interest") or 0)
        group["coins"].append(coin)
        if dex not in group["venues"]:
            group["venues"].append(dex)
        group["day_notional_volume"] += volume
        group["open_interest_notional"] += abs(open_interest * mark)
        group["coin_marks"][coin] = mark
        if volume > group["primary_volume"]:
            # HIP-3 venues can use different contract multipliers for the same
            # ticker. Never average their raw contract prices.
            group["primary_volume"] = volume
            group["mark_px"] = mark
    return groups


def _smart_wallet_cutoff(scores: list[dict[str, Any]]) -> tuple[set[str], float]:
    eligible = [row for row in scores if row["eligible"]]
    if not eligible:
        return set(), 100.0
    threshold = max(55.0, percentile([float(row["score"]) for row in eligible], 0.75))
    selected = [row for row in eligible if float(row["score"]) >= threshold]
    return {str(row["address"]) for row in selected}, threshold


def build_wallet_scores_and_signals(
    connection: sqlite3.Connection,
    *,
    as_of: dt.datetime,
    lookback_days: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], float]:
    ensure_derived_tables(connection)
    as_of = as_of.astimezone(dt.timezone.utc)
    as_of_day = as_of.date().isoformat()
    cutoff_ms = int((as_of - dt.timedelta(days=lookback_days)).timestamp() * 1000)
    fills = _row_dicts(
        connection,
        "SELECT * FROM hl_fill WHERE time_ms>=? ORDER BY time_ms",
        (cutoff_ms,),
    )
    wallet_flags = {
        str(row["address"]): (
            bool(row["fills_truncated"]),
            bool(row["fills_backfill_complete"]),
        )
        for row in connection.execute(
            "SELECT address, fills_truncated, fills_backfill_complete FROM hl_wallet"
        )
    }
    by_wallet: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for fill in fills:
        by_wallet[str(fill["address"])].append(fill)
    scores = [
        score_wallet_fills(
            address,
            rows,
            truncated=wallet_flags.get(address, (False, False))[0],
            history_complete=wallet_flags.get(address, (False, False))[1],
        )
        for address, rows in by_wallet.items()
    ]
    scores.sort(key=lambda row: (-int(row["eligible"]), -float(row["score"]), row["address"]))
    _enrich_wallet_scores(connection, scores)

    connection.execute("DELETE FROM hl_wallet_score WHERE as_of_day=?", (as_of_day,))
    connection.executemany(
        """
        INSERT INTO hl_wallet_score (
          as_of_day, address, scoring_version, score, raw_score, confidence,
          eligible, history_complete, classification, fill_count, closed_fill_count, active_days,
          realized_pnl, fees, net_pnl, closed_notional, traded_notional,
          return_proxy, win_rate, profit_factor, max_drawdown_pnl,
          liquidation_count, maker_ratio, top_markets_json, components_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (
                as_of_day, row["address"], HL_SCORING_VERSION, row["score"], row["raw_score"],
                row["confidence"], 1 if row["eligible"] else 0,
                1 if row["history_complete"] else 0, row["classification"],
                row["fill_count"], row["closed_fill_count"], row["active_days"], row["realized_pnl"],
                row["fees"], row["net_pnl"], row["closed_notional"], row["traded_notional"],
                row["return_proxy"], row["win_rate"], row["profit_factor"], row["max_drawdown_pnl"],
                row["liquidation_count"], row["maker_ratio"], json.dumps(row["top_markets"], separators=(",", ":")),
                json.dumps(row["components"], separators=(",", ":")),
            )
            for row in scores
        ],
    )

    smart_addresses, smart_threshold = _smart_wallet_cutoff(scores)
    score_by_address = {str(row["address"]): row for row in scores}
    positions = latest_positions(fills)
    instruments = _row_dicts(
        connection,
        "SELECT * FROM hl_tradfi_instrument WHERE is_active=1 ORDER BY day_notional_volume DESC",
    )
    if _table_exists(connection, "hl_wallet_position"):
        for row in _row_dicts(connection, "SELECT * FROM hl_wallet_position"):
            size = float(row["size"])
            positions[(str(row["address"]), str(row["coin"]))] = {
                "address": row["address"],
                "coin": row["coin"],
                "symbol": row["symbol"],
                "category": row["category"],
                "dex": row["dex"],
                "position": size,
                "signed_notional": math.copysign(abs(float(row["position_value"])), size),
                "last_time_ms": int(as_of.timestamp() * 1000),
                "last_action": "Open position",
                "last_price": float(row["mark_px"] or 0),
                "entry_price": float(row["entry_px"] or 0),
                "unrealized_pnl": float(row["unrealized_pnl"]),
                "liquidation_price": float(row["liquidation_px"] or 0),
                "leverage": float(row["leverage"]),
                "margin_used": float(row["margin_used"]),
                "funding_since_open": float(row["funding_since_open"]),
                "observed_at": row["observed_at"],
            }
    markets = _market_rollup(instruments)
    connection.execute("DELETE FROM hl_asset_signal WHERE as_of_day=?", (as_of_day,))
    signal_rows: list[dict[str, Any]] = []

    for window_days in SIGNAL_WINDOWS:
        window_start_ms = int((as_of - dt.timedelta(days=window_days)).timestamp() * 1000)
        window_fills = [
            row for row in fills
            if int(row["time_ms"]) >= window_start_ms and str(row["address"]) in smart_addresses
        ]
        for (symbol, category), market in markets.items():
            market_coins = set(market["coins"])
            market_positions = [
                position for (address, coin), position in positions.items()
                if address in smart_addresses and coin in market_coins and abs(float(position["position"])) > 1e-9
            ]
            notionals = [
                abs(
                    float(position.get("signed_notional"))
                    if position.get("signed_notional") is not None
                    else float(position["position"]) * float(market["coin_marks"].get(position["coin"]) or position["last_price"] or 0)
                )
                for position in market_positions
            ]
            notional_cap = max(percentile(notionals, 0.75), 1.0) if notionals else 1.0
            weighted_position = 0.0
            weighted_gross = 0.0
            net_position = 0.0
            gross_position = 0.0
            long_wallets: set[str] = set()
            short_wallets: set[str] = set()
            wallet_items: list[dict[str, Any]] = []
            for position in market_positions:
                address = str(position["address"])
                score = score_by_address[address]
                notional = (
                    float(position["signed_notional"])
                    if position.get("signed_notional") is not None
                    else float(position["position"]) * float(market["coin_marks"].get(position["coin"]) or position["last_price"] or 0)
                )
                magnitude = min(abs(notional), notional_cap)
                score_weight = max(0.1, (float(score["score"]) - 50.0) / 25.0) * float(score["confidence"])
                vote = math.copysign(math.sqrt(magnitude) * score_weight, notional)
                weighted_position += vote
                weighted_gross += abs(vote)
                net_position += notional
                gross_position += abs(notional)
                (long_wallets if notional > 0 else short_wallets).add(address)
                wallet_items.append(
                    {
                        "address": address,
                        "score": score["score"],
                        "confidence": score["confidence"],
                        "position": round(float(position["position"]), 6),
                        "notional": round(notional, 2),
                        "direction": "long" if notional > 0 else "short",
                        "coin": position["coin"],
                        "dex": position["dex"],
                        "lastAction": position["last_action"],
                        "lastPrice": round(float(position["last_price"]), 6),
                        "entryPrice": round(float(position.get("entry_price") or 0), 6) or None,
                        "unrealizedPnl": round(float(position.get("unrealized_pnl") or 0), 2),
                        "liquidationPrice": round(float(position.get("liquidation_price") or 0), 6) or None,
                        "leverage": round(float(position.get("leverage") or 0), 2),
                        "marginUsed": round(float(position.get("margin_used") or 0), 2),
                        "fundingSinceOpen": round(float(position.get("funding_since_open") or 0), 2),
                        "netPnl30d": score["net_pnl"],
                    }
                )
            wallet_items.sort(key=lambda row: (-abs(float(row["notional"])), -float(row["score"])))

            relevant_fills = [row for row in window_fills if str(row["coin"]) in market_coins]
            net_flow = 0.0
            weighted_flow = 0.0
            daily_flow: dict[str, float] = collections.defaultdict(float)
            for row in relevant_fills:
                sign = 1.0 if str(row["side"]) == "B" else -1.0
                signed_notional = sign * float(row["notional"])
                score = score_by_address[str(row["address"])]
                score_weight = max(0.1, (float(score["score"]) - 50.0) / 25.0) * float(score["confidence"])
                net_flow += signed_notional
                weighted_flow += signed_notional * score_weight
                daily_flow[str(row["created_day"])] += signed_notional * score_weight
            consensus = weighted_position / weighted_gross if weighted_gross else 0.0
            if len(long_wallets | short_wallets) < 3:
                signal = "insufficient"
            elif consensus >= 0.25:
                signal = "bullish"
            elif consensus <= -0.25:
                signal = "bearish"
            else:
                signal = "mixed"

            evidence = []
            top_addresses = {str(row["address"]) for row in wallet_items[:8]}
            for row in sorted(relevant_fills, key=lambda item: -int(item["time_ms"])):
                if str(row["address"]) not in top_addresses:
                    continue
                evidence.append(
                    {
                        "address": row["address"],
                        "coin": row["coin"],
                        "side": "buy" if row["side"] == "B" else "sell",
                        "action": row["direction"],
                        "price": round(float(row["price"]), 6),
                        "size": round(float(row["size"]), 6),
                        "notional": round(float(row["notional"]), 2),
                        "time": row["created_at"],
                        "hash": row["hash"],
                    }
                )
                if len(evidence) >= 12:
                    break
            signal_row = {
                "asOfDay": as_of_day,
                "windowDays": window_days,
                "symbol": symbol,
                "category": category,
                "coins": sorted(market["coins"]),
                "venues": sorted(market["venues"]),
                "markPrice": round(float(market["mark_px"]), 6),
                "dayVolume": round(float(market["day_notional_volume"]), 2),
                "openInterestNotional": round(float(market["open_interest_notional"]), 2),
                "qualifiedWallets": len(long_wallets | short_wallets),
                "longWallets": len(long_wallets),
                "shortWallets": len(short_wallets),
                "grossPositionNotional": round(gross_position, 2),
                "netPositionNotional": round(net_position, 2),
                "consensus": round(consensus, 4),
                "netFlowNotional": round(net_flow, 2),
                "weightedFlow": round(weighted_flow, 2),
                "signal": signal,
                "topWallets": wallet_items[:8],
                "evidence": evidence,
                "dailyFlow": [
                    {"day": day, "value": round(value, 2)} for day, value in sorted(daily_flow.items())
                ],
            }
            signal_rows.append(signal_row)
            connection.execute(
                """
                INSERT INTO hl_asset_signal (
                  as_of_day, window_days, symbol, category, coins_json, venues_json,
                  mark_px, day_notional_volume, open_interest_notional, qualified_wallets,
                  long_wallets, short_wallets, gross_position_notional,
                  net_position_notional, consensus, net_flow_notional, weighted_flow,
                  signal, top_wallets_json, evidence_json, daily_flow_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    as_of_day, window_days, symbol, category,
                    json.dumps(signal_row["coins"], separators=(",", ":")),
                    json.dumps(signal_row["venues"], separators=(",", ":")),
                    signal_row["markPrice"], signal_row["dayVolume"], signal_row["openInterestNotional"],
                    signal_row["qualifiedWallets"], signal_row["longWallets"], signal_row["shortWallets"],
                    signal_row["grossPositionNotional"], signal_row["netPositionNotional"],
                    signal_row["consensus"], signal_row["netFlowNotional"], signal_row["weightedFlow"],
                    signal_row["signal"], json.dumps(signal_row["topWallets"], separators=(",", ":")),
                    json.dumps(signal_row["evidence"], separators=(",", ":")),
                    json.dumps(signal_row["dailyFlow"], separators=(",", ":")),
                ),
            )
    connection.commit()
    return scores, signal_rows, smart_threshold


def export_hyperliquid_smart_money(
    output_path: str | Path,
    *,
    generated_at: dt.datetime,
    lookback_days: int,
    scores: list[dict[str, Any]],
    signals: list[dict[str, Any]],
    smart_threshold: float,
) -> dict[str, Any]:
    generated_at = generated_at.astimezone(dt.timezone.utc)
    by_market: dict[tuple[str, str], dict[str, Any]] = {}
    for signal in signals:
        key = (str(signal["symbol"]), str(signal["category"]))
        market = by_market.setdefault(
            key,
            {
                "symbol": signal["symbol"],
                "category": signal["category"],
                "coins": signal["coins"],
                "venues": signal["venues"],
                "markPrice": signal["markPrice"],
                "dayVolume": signal["dayVolume"],
                "openInterestNotional": signal["openInterestNotional"],
                "signals": {},
            },
        )
        market["signals"][str(signal["windowDays"])] = {
            key: value
            for key, value in signal.items()
            if key not in {"asOfDay", "windowDays", "symbol", "category", "coins", "venues", "markPrice", "dayVolume", "openInterestNotional"}
        }
    markets = sorted(by_market.values(), key=lambda row: -float(row["dayVolume"]))
    leaderboard = []
    for rank, row in enumerate([row for row in scores if row["eligible"]], start=1):
        periods = _compact_period_metrics(row.get("period_metrics") or {})
        risk_period = periods.get("30D") or {}
        recent_trades = _recent_rows(
            list(row.get("recent_trades") or []),
            generated_at=generated_at,
            timestamp_key="time",
            limit=CLIENT_MAX_RECENT_TRADES,
        )
        capital_activity = _recent_rows(
            list(row.get("capital_activity") or []),
            generated_at=generated_at,
            timestamp_key="time",
            limit=CLIENT_MAX_CAPITAL_ACTIVITY,
        )
        leaderboard.append(
            {
                "rank": rank,
                "address": row["address"],
                "walletLabel": row.get("label") or _wallet_label(str(row["address"])),
                "tier": "Smart" if float(row["score"]) >= smart_threshold else "Qualified",
                "score": row["score"],
                "rawScore": row["raw_score"],
                "confidence": row["confidence"],
                "classification": row["classification"],
                "historyComplete": bool(row.get("history_complete", False)),
                "style": row.get("style") or row.get("trade_duration", {}).get("style") or "Unclassified",
                "sizeCohort": row.get("size_cohort") or "Shrimp",
                "pnlCohort": row.get("pnl_cohort") or "Unclassified",
                "accountValue": row.get("account_value") or 0,
                "totalNotional": row.get("total_notional") or 0,
                "unrealizedPnl": row.get("unrealized_pnl") or 0,
                "currentLeverage": row.get("leverage") or 0,
                "marginUtilization": row.get("margin_utilization") or 0,
                "withdrawable": row.get("withdrawable") or 0,
                "fundingSinceOpen": row.get("funding_since_open") or 0,
                "fillCount": row["fill_count"],
                "closedFillCount": row["closed_fill_count"],
                "activeDays": row["active_days"],
                "netPnl": row["net_pnl"],
                "longPnl": row.get("long_closed_pnl") or 0,
                "shortPnl": row.get("short_closed_pnl") or 0,
                "longBias": row.get("long_bias") or 0.5,
                "tradedNotional": row["traded_notional"],
                "winRate": row["win_rate"],
                "profitFactor": row["profit_factor"],
                "sharpe": risk_period.get("sharpe") or 0,
                "maxDrawdownPnl": risk_period.get("maxDrawdown") or row["max_drawdown_pnl"],
                "maxDrawdownPercent": risk_period.get("maxDrawdownPercent") or 0,
                "liquidationCount": row["liquidation_count"],
                "makerRatio": row["maker_ratio"],
                "tradeDuration": row.get("trade_duration") or {},
                "topMarkets": row["top_markets"],
                "assetPerformance": list(row.get("asset_performance") or [])[
                    :CLIENT_MAX_ASSET_PERFORMANCE
                ],
                "currentPositions": list(row.get("current_positions") or [])[
                    :CLIENT_MAX_POSITIONS
                ],
                "periodMetrics": periods,
                "recentTrades": recent_trades,
                "capitalActivity": capital_activity,
                "components": row["components"],
            }
        )
    categories = ["stocks", "indices", "commodities", "fx", "preipo"]
    payload = {
        "version": HL_EXPORT_VERSION,
        "scoringVersion": HL_SCORING_VERSION,
        "generatedAt": generated_at.replace(microsecond=0).isoformat(),
        "lookbackDays": lookback_days,
        "summary": {
            "instrumentCount": len(markets),
            "observedWalletCount": len(scores),
            "qualifiedWalletCount": sum(1 for row in scores if row["eligible"]),
            "smartWalletCount": sum(1 for row in scores if row["eligible"] and float(row["score"]) >= smart_threshold),
            "algorithmicExcluded": sum(1 for row in scores if row["classification"] == "algorithmic"),
            "incompleteHistoryExcluded": sum(
                1 for row in scores if row["classification"] == "incomplete"
            ),
            "smartScoreThreshold": round(smart_threshold, 2),
            "dayNotionalVolume": round(sum(float(row["dayVolume"]) for row in markets), 2),
        },
        "methodology": {
            "scoreRange": [0, 100],
            "weights": {"performance": 35, "consistency": 25, "payoff": 20, "risk": 15, "execution": 5},
            "confidenceShrinkage": True,
            "minimums": {"closedFills": 5, "activeDays": 3, "closedNotional": 10_000},
            "candidateUniverse": {
                "maximumWallets": HL_CANDIDATE_POOL_SIZE,
                "activityLookbackDays": HL_CANDIDATE_ACTIVITY_DAYS,
                "minimumObservedTrades": HL_DISCOVERY_MIN_TRADES,
                "minimumObservedNotional": HL_DISCOVERY_MIN_NOTIONAL,
                "ranking": "observed_notional_desc",
            },
            "excludes": [
                "crypto",
                "incomplete_history",
                "algorithmic_or_truncated_accounts",
            ],
            "accountDimensions": [
                "pnl_and_equity_history",
                "win_rate_and_sharpe",
                "max_drawdown",
                "trade_style_and_duration",
                "account_size_and_pnl_cohorts",
                "current_positions_and_liquidation_risk",
                "per_asset_performance",
                "capital_activity",
            ],
            "identityPolicy": "public_pseudonymous_account_not_institutional_ownership",
        },
        "categories": categories,
        "markets": markets,
        "leaderboard": leaderboard,
    }
    path = Path(output_path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return payload


def movement_from_trade(trade: dict[str, Any]) -> dict[str, Any] | None:
    """Translate one public fill into an exact position-state transition."""
    price = float(trade.get("price") or 0)
    before_size = float(trade.get("startPosition") or 0)
    after_size = float(trade.get("positionAfter") or 0)
    if price <= 0 or abs(before_size - after_size) <= 1e-12:
        return None

    before_notional = abs(before_size * price)
    after_notional = abs(after_size * price)
    if abs(before_size) <= 1e-12:
        action = "opened"
        impact_sign = after_size
    elif abs(after_size) <= 1e-12:
        action = "closed"
        impact_sign = -before_size
    elif before_size * after_size < 0:
        action = "flipped"
        impact_sign = after_size
    elif abs(after_size) > abs(before_size):
        action = "increased"
        impact_sign = after_size
    else:
        action = "reduced"
        impact_sign = -before_size
    rounded_before = round(before_notional, 2)
    rounded_after = round(after_notional, 2)
    return {
        "action": action,
        "direction": "bullish" if impact_sign > 0 else "bearish",
        "notionalBefore": rounded_before,
        "notionalAfter": rounded_after,
        "notionalChange": round(rounded_after - rounded_before, 2),
    }


def _parse_client_time(value: Any) -> dt.datetime | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _movement_effect(movement: dict[str, Any]) -> float:
    magnitude = abs(
        float(movement.get("notionalAfter") or 0)
        - float(movement.get("notionalBefore") or 0)
    )
    return magnitude if movement.get("direction") == "bullish" else -magnitude


def _significant_movement(movement: dict[str, Any]) -> bool:
    before = abs(float(movement.get("notionalBefore") or 0))
    after = abs(float(movement.get("notionalAfter") or 0))
    change = abs(after - before)
    relative = change / max(before, after, 1.0)
    action = str(movement.get("action") or "")
    return (
        change >= 100_000
        or (change >= 10_000 and relative >= 0.10)
        or (action in {"opened", "closed", "flipped"} and change >= 5_000)
    )


def _account_snapshot(
    updates: list[dict[str, Any]],
    *,
    generated_at: dt.datetime,
    max_age_days: int = 7,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    cutoff = generated_at - dt.timedelta(days=max_age_days)
    current = [
        row
        for row in updates
        if (published := _parse_client_time(row.get("publishedAt"))) is not None
        and published >= cutoff
    ]
    current.sort(key=lambda row: str(row.get("publishedAt") or ""), reverse=True)
    if not current:
        return (
            {
                "direction": "neutral",
                "headline": "No recent qualified Smart Account view",
                "detail": "No qualified public view is inside the current seven-day monitoring window.",
                "qualifiedAuthorCount": 0,
                "latestUpdateAt": None,
            },
            [],
        )

    latest_by_author: dict[str, dict[str, Any]] = {}
    for row in current:
        latest_by_author.setdefault(str(row.get("authorId") or row.get("authorName") or ""), row)
    distinct = list(latest_by_author.values())
    bullish = sum(float(row.get("score") or 0) for row in distinct if row.get("direction") == "bullish")
    bearish = sum(float(row.get("score") or 0) for row in distinct if row.get("direction") == "bearish")
    total = bullish + bearish
    net = (bullish - bearish) / total if total else 0.0
    if net >= 0.20:
        direction = "bullish"
    elif net <= -0.20:
        direction = "bearish"
    else:
        direction = "mixed"
    latest = current[0]
    label = "net bullish" if direction == "bullish" else "net bearish" if direction == "bearish" else "split"
    return (
        {
            "direction": direction,
            "headline": f"{len(distinct)} qualified Smart Account{'s are' if len(distinct) != 1 else ' is'} {label}",
            "detail": str(latest.get("thesis") or "The latest qualified public view is available as source evidence."),
            "qualifiedAuthorCount": len(distinct),
            "latestUpdateAt": latest.get("publishedAt"),
        },
        distinct,
    )


def _selected_market_window(market: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    windows = market.get("signals") or {}
    ordered = [windows.get(str(day)) or {} for day in SIGNAL_WINDOWS]
    for row in ordered:
        if row.get("signal") in {"bullish", "bearish", "mixed"}:
            return row, True
    return max(ordered, key=lambda row: int(row.get("qualifiedWallets") or 0), default={}), False


def _money_snapshot(
    market: dict[str, Any] | None,
    ticker_movements: list[dict[str, Any]],
    *,
    generated_at: dt.datetime,
    movement_hours: int,
) -> tuple[dict[str, Any], list[dict[str, Any]], bool]:
    cutoff = generated_at - dt.timedelta(hours=movement_hours)
    recent = [
        row
        for row in ticker_movements
        if (observed := _parse_client_time(row.get("observedAt"))) is not None
        and observed >= cutoff
        and _significant_movement(row)
    ]
    recent.sort(key=lambda row: str(row.get("observedAt") or ""), reverse=True)
    selected, aggregate_qualified = _selected_market_window(market or {})
    accounts = {str(row.get("accountId") or "") for row in recent if row.get("accountId")}

    if aggregate_qualified:
        direction = str(selected.get("signal") or "mixed")
        qualified_count = int(selected.get("qualifiedWallets") or 0)
        long_count = int(selected.get("longWallets") or 0)
        short_count = int(selected.get("shortWallets") or 0)
        net_position = float(selected.get("netPositionNotional") or 0)
        headline = f"{qualified_count} qualified public accounts are {direction}"
        detail = (
            f"The current qualified cohort includes {long_count} long and {short_count} short accounts, "
            f"with ${abs(net_position):,.0f} of net visible exposure."
        )
        latest = recent[0].get("observedAt") if recent else None
        return (
            {
                "coverage": "available",
                "direction": direction,
                "headline": headline,
                "detail": detail,
                "qualifiedAccountCount": qualified_count,
                "latestMovementAt": latest,
            },
            recent,
            True,
        )

    if recent:
        effect = sum(_movement_effect(row) for row in recent)
        direction = "bullish" if effect > 0 else "bearish" if effect < 0 else "mixed"
        magnitude = abs(effect)
        return (
            {
                "coverage": "available",
                "direction": direction,
                "headline": f"{len(accounts)} qualified public account{'s moved' if len(accounts) != 1 else ' moved'}",
                "detail": (
                    f"{len(recent)} significant auditable movement{'s' if len(recent) != 1 else ''} produced "
                    f"a ${magnitude:,.0f} net {direction} change. Aggregate consensus remains below the three-account threshold."
                ),
                "qualifiedAccountCount": len(accounts),
                "latestMovementAt": recent[0].get("observedAt"),
            },
            recent,
            False,
        )

    sample_count = int(selected.get("qualifiedWallets") or 0)
    return (
        {
            "coverage": "unavailable",
            "direction": "neutral",
            "headline": "No qualifying public capital movement",
            "detail": (
                f"The current observation has {sample_count} qualified account{'s' if sample_count != 1 else ''}; "
                "no recent movement passes the significance and coverage gates."
            ),
            "qualifiedAccountCount": sample_count,
            "latestMovementAt": None,
        },
        [],
        False,
    )


def _relationship(
    account: dict[str, Any],
    money: dict[str, Any],
    *,
    aggregate_qualified: bool,
) -> tuple[str, str, str]:
    account_direction = str(account.get("direction") or "neutral")
    money_direction = str(money.get("direction") or "neutral")
    account_directional = account_direction in {"bullish", "bearish"}
    money_directional = money_direction in {"bullish", "bearish"}
    if aggregate_qualified and account_directional and money_directional:
        if account_direction == money_direction:
            return (
                "confirmation",
                account_direction,
                f"Qualified public views and qualified onchain capital are both {account_direction}.",
            )
        return (
            "divergence",
            "mixed",
            f"Qualified public views are {account_direction} while qualified onchain capital is {money_direction}.",
        )
    if money.get("coverage") == "available":
        kind = "money_leads" if aggregate_qualified else "smart_money_movement"
        return kind, money_direction, "Onchain capital changed before a matching qualified social consensus formed."
    if account_direction != "neutral":
        return "account_leads", account_direction, "Qualified public views changed without sufficient current capital verification."
    return "smart_account_new_view", "neutral", "No current relationship signal meets the evidence threshold."


def _evidence_from_account(update: dict[str, Any]) -> dict[str, Any]:
    reference_id = str(update["id"])
    return {
        "id": str(uuid.uuid5(SMART_MONEY_NAMESPACE, f"account-evidence:{reference_id}")),
        "source": "smart_account",
        "referenceId": reference_id,
        "actorName": update.get("authorName") or "Smart Account",
        "title": f"{str(update.get('direction') or 'neutral').title()} view · {update.get('lifecycle') or 'new'}",
        "detail": update.get("originalText") or update.get("thesis") or "Qualified public view",
        "metric": f"Score {float(update.get('score') or 0):.0f}",
        "observedAt": update.get("publishedAt"),
        "sourceURL": update.get("evidenceURL"),
    }


def _evidence_from_movement(movement: dict[str, Any]) -> dict[str, Any]:
    reference_id = str(movement["id"])
    change = abs(_movement_effect(movement))
    return {
        "id": str(uuid.uuid5(SMART_MONEY_NAMESPACE, f"money-evidence:{reference_id}")),
        "source": "smart_money",
        "referenceId": reference_id,
        "actorName": movement.get("accountDisplayName") or "Anonymous capital account",
        "avatarVariant": movement.get("avatarVariant"),
        "title": f"Public position {movement.get('action') or 'changed'}",
        "detail": (
            f"A qualified public account changed visible {movement.get('ticker')} exposure from "
            f"${float(movement.get('notionalBefore') or 0):,.0f} to ${float(movement.get('notionalAfter') or 0):,.0f}."
        ),
        "metric": f"${change:,.0f}",
        "observedAt": movement.get("observedAt"),
        "sourceURL": movement.get("evidenceURL"),
    }


def build_hyperliquid_client_collections(
    payload: dict[str, Any],
    *,
    smart_account_updates: list[dict[str, Any]] | None = None,
    smart_money_candles: dict[str, list[dict[str, Any]]] | None = None,
    movement_hours: int = 72,
) -> dict[str, list[dict[str, Any]]]:
    """Project the auditable wallet export into the public mobile/API contract."""
    generated_at = str(payload.get("generatedAt") or "")
    signals: list[dict[str, Any]] = []
    movements: list[dict[str, Any]] = []
    leaderboard = list(payload.get("leaderboard") or [])
    public_identities = smart_money_public_identities(str(wallet["address"]) for wallet in leaderboard)
    for wallet in leaderboard:
        public_identity = public_identities[str(wallet["address"]).strip().lower()]
        positions = list(wallet.get("currentPositions") or [])
        positions.sort(key=lambda row: -float(row.get("notional") or 0))
        recent_trades = list(wallet.get("recentTrades") or [])
        changed_at = str(recent_trades[0].get("time") or generated_at) if recent_trades else generated_at
        top_position = positions[0] if positions else {}
        asset_performance = list(wallet.get("assetPerformance") or [])
        ticker = str(
            top_position.get("symbol")
            or (asset_performance[0].get("symbol") if asset_performance else "")
            or ((wallet.get("topMarkets") or [{}])[0].get("symbol") if wallet.get("topMarkets") else "")
            or "MARKET"
        )
        direction = str(top_position.get("direction") or ("Long" if float(wallet.get("longBias") or 0.5) >= 0.5 else "Short"))

        period_metrics: dict[str, Any] = {}
        for period, metric in (wallet.get("periodMetrics") or {}).items():
            period_metrics[str(period)] = {
                **{key: value for key, value in metric.items() if key not in {"accountValueHistory", "pnlHistory"}},
                "accountValueHistory": [
                    {"timestamp": point[0], "value": point[1]} for point in metric.get("accountValueHistory") or []
                ],
                "pnlHistory": [
                    {"timestamp": point[0], "value": point[1]} for point in metric.get("pnlHistory") or []
                ],
            }

        signal = {
            "id": wallet["address"],
            "walletLabel": wallet["walletLabel"],
            **public_identity,
            "score": wallet["score"],
            "ticker": ticker,
            "direction": direction,
            "notionalValue": float(top_position.get("notional") or 0),
            "changedAt": changed_at,
            "address": wallet["address"],
            "rank": wallet["rank"],
            "tier": wallet["tier"],
            "style": wallet["style"],
            "sizeCohort": wallet["sizeCohort"],
            "pnlCohort": wallet["pnlCohort"],
            "accountValue": wallet["accountValue"],
            "totalNotional": wallet["totalNotional"],
            "unrealizedPnl": wallet["unrealizedPnl"],
            "currentLeverage": wallet["currentLeverage"],
            "marginUtilization": wallet["marginUtilization"],
            "netPnl": wallet["netPnl"],
            "winRate": wallet["winRate"],
            "sharpe": wallet["sharpe"],
            "maxDrawdownPercent": wallet["maxDrawdownPercent"],
            "profitFactor": wallet["profitFactor"],
            "fillCount": wallet["fillCount"],
            "activeDays": wallet["activeDays"],
            "longBias": wallet["longBias"],
            "tradeDuration": wallet["tradeDuration"],
            "periodMetrics": period_metrics,
            "currentPositions": positions,
            "assetPerformance": asset_performance,
            "recentTrades": recent_trades,
            "capitalActivity": wallet.get("capitalActivity") or [],
            "components": wallet.get("components"),
            "scoreSource": wallet.get("scoreSource") or payload.get("scoringVersion"),
            "source": wallet.get("source") or (
                (payload.get("source") or {}).get("provider")
                if isinstance(payload.get("source"), dict)
                else "hyperliquid"
            ),
            "sourceUpdatedAt": wallet.get("sourceUpdatedAt") or generated_at,
            "sourceURL": wallet.get("profileURL"),
        }
        signals.append(signal)

        position_by_symbol = {str(row.get("symbol")): row for row in positions}
        for trade in recent_trades:
            transition = movement_from_trade(trade)
            if transition is None:
                continue
            position = position_by_symbol.get(str(trade.get("symbol") or "")) or {}
            movement_id = str(uuid.uuid5(SMART_MONEY_NAMESPACE, f"{wallet['address']}:{trade.get('id')}"))
            movements.append(
                {
                    "id": movement_id,
                    "ticker": trade.get("symbol") or ticker,
                    "companyName": trade.get("symbol") or ticker,
                    "accountId": wallet["address"],
                    "accountLabel": wallet["walletLabel"],
                    "accountDisplayName": public_identity["displayName"],
                    "avatarVariant": public_identity["avatarVariant"],
                    "accountScore": wallet["score"],
                    "market": trade.get("coin") or "Hyperliquid",
                    **transition,
                    "price": float(trade.get("price") or 0),
                    "sizeBefore": float(trade.get("startPosition") or 0),
                    "sizeAfter": float(trade.get("positionAfter") or 0),
                    "leverage": position.get("leverage"),
                    "observedAt": trade.get("time") or changed_at,
                    "evidenceURL": trade.get("evidenceURL") or (
                        f"https://app.hyperliquid.xyz/explorer/tx/{trade['hash']}"
                        if trade.get("hash")
                        else wallet.get("profileURL")
                    ),
                }
            )
    movements = list({str(row["id"]): row for row in movements}.values())
    movements.sort(key=lambda row: str(row["observedAt"]), reverse=True)
    client_collections: dict[str, list[dict[str, Any]]] = {
        "smart-money": signals,
        "smart-money-movements": movements,
        "smart-money-evidence": build_smart_money_representative_evidence(
            signals,
            movements,
            candles_by_market=smart_money_candles,
        ),
    }
    if smart_account_updates is None:
        return client_collections

    generated = _parse_client_time(generated_at) or dt.datetime.now(dt.timezone.utc)
    updates_by_ticker: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for update in smart_account_updates:
        updates_by_ticker[str(update.get("ticker") or "").upper()].append(update)
    movements_by_ticker: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for movement in movements:
        movements_by_ticker[str(movement.get("ticker") or "").upper()].append(movement)
    markets = {
        str(market.get("symbol") or "").upper(): market
        for market in payload.get("markets") or []
        if market.get("category") == "stocks"
    }
    tickers = sorted(set(updates_by_ticker) | set(markets))
    intelligence: list[dict[str, Any]] = []
    portfolio_signals: list[dict[str, Any]] = []

    for ticker in tickers:
        market = markets.get(ticker)
        account, account_updates = _account_snapshot(
            updates_by_ticker.get(ticker, []),
            generated_at=generated,
        )
        money, significant_movements, aggregate_qualified = _money_snapshot(
            market,
            movements_by_ticker.get(ticker, []),
            generated_at=generated,
            movement_hours=movement_hours,
        )
        if account["qualifiedAuthorCount"] == 0 and money["coverage"] == "unavailable":
            continue
        kind, direction, conclusion = _relationship(
            account,
            money,
            aggregate_qualified=aggregate_qualified,
        )
        latest_account = account_updates[0] if account_updates else None
        latest_movement = significant_movements[0] if significant_movements else None
        evidence: list[dict[str, Any]] = []
        if latest_account is not None:
            evidence.append(_evidence_from_account(latest_account))
        if latest_movement is not None:
            evidence.extend(_evidence_from_movement(row) for row in significant_movements[:3])
        evidence_times = [
            parsed
            for item in evidence
            if (parsed := _parse_client_time(item.get("observedAt"))) is not None
        ]
        occurred_at = max(evidence_times, default=generated)
        latest_reference_ids = ":".join(str(item["referenceId"]) for item in evidence)
        signal_id = str(uuid.uuid5(SMART_MONEY_NAMESPACE, f"portfolio:{ticker}:{kind}:{latest_reference_ids}"))
        company_name = str(
            (latest_account or {}).get("companyName")
            or ticker
        )
        current_price = float((market or {}).get("markPrice") or 0)
        intelligence.append(
            {
                "ticker": ticker,
                "companyName": company_name,
                "currentPrice": current_price,
                "dayChangePercent": 0.0,
                "dataAsOf": generated.isoformat().replace("+00:00", "Z"),
                "relationship": kind,
                "direction": direction,
                "conclusion": conclusion,
                "latestSignalId": signal_id if evidence else None,
                "smartAccount": account,
                "smartMoney": money,
            }
        )
        if not evidence:
            continue
        if kind == "divergence":
            title = f"{ticker} public views and capital diverged"
            priority = "important"
        elif kind == "confirmation":
            title = f"{ticker} public views and capital confirmed each other"
            priority = "important"
        elif kind == "money_leads":
            title = f"Qualified capital moved first in {ticker}"
            priority = "important"
        elif kind == "smart_money_movement":
            title = f"A qualified public account changed {ticker} exposure"
            priority = "notable"
        else:
            title = f"Qualified Smart Accounts updated their {ticker} view"
            priority = "notable"
        limitations = [
            "Smart Money reflects public tokenized-equity derivatives on Hyperliquid, not traditional stock ownership.",
            "Public accounts and social authors are independent unless a verified identity link is explicitly available.",
        ]
        if money["coverage"] == "unavailable":
            limitations.append("No current capital cohort meets the minimum evidence threshold.")
        elif not aggregate_qualified:
            limitations.append("This movement is auditable, but aggregate direction remains below the three-account consensus threshold.")
        portfolio_signals.append(
            {
                "id": signal_id,
                "ticker": ticker,
                "companyName": company_name,
                "title": title,
                "summary": conclusion,
                "occurredAt": occurred_at.isoformat().replace("+00:00", "Z"),
                "dataAsOf": generated.isoformat().replace("+00:00", "Z"),
                "dataStatus": "current",
                "priority": priority,
                "kind": kind,
                "direction": direction,
                "smartMoneyCoverage": money["coverage"],
                "conclusion": conclusion,
                "positionImpact": "Review this evidence against your cost basis, position size and downside tolerance.",
                "nextStep": "Open the source evidence and monitor whether the next qualified account or author reinforces or reverses the change.",
                "limitations": limitations,
                "evidence": evidence,
            }
        )

    portfolio_signals.sort(key=lambda row: str(row["occurredAt"]), reverse=True)
    intelligence.sort(key=lambda row: str(row["ticker"]))
    client_collections["portfolio-signals"] = portfolio_signals
    client_collections["ticker-intelligence"] = intelligence
    return client_collections
