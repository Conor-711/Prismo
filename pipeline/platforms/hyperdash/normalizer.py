"""Normalize Hyperdash's 30-day public account data into bSmart's contract."""
from __future__ import annotations

import datetime as dt
import uuid
from typing import Any


HYPERDASH_EXPORT_VERSION = "hyperdash-smart-money-v1"
HYPERDASH_SCORE_VERSION = "hyperdash-copy-score"
_NAMESPACE = uuid.UUID("77b49bd5-9f96-4fd8-aef9-e6ac9739fc53")
_MAX_GRAPH_POINTS = 90
_MAX_RECENT_TRADES = 20


def build_hyperdash_smart_money_payload(
    traders: list[dict[str, Any]],
    positions_by_address: dict[str, dict[str, Any]],
    *,
    generated_at: dt.datetime,
    previous_payload: dict[str, Any] | None = None,
    lookback_days: int = 30,
) -> dict[str, Any]:
    generated_at = generated_at.astimezone(dt.timezone.utc)
    previous_wallets = {
        str(row.get("address") or "").lower(): row
        for row in (previous_payload or {}).get("leaderboard") or []
        if isinstance(row, dict) and row.get("address")
    }
    ordered = sorted(traders, key=lambda row: -_number(row.get("copyScore")))
    leaderboard: list[dict[str, Any]] = []
    for rank, row in enumerate(ordered, start=1):
        address = str(row.get("address") or "").lower()
        if not address:
            continue
        snapshot = positions_by_address.get(address) or {}
        positions = [
            _normalize_position(position)
            for position in snapshot.get("positions") or []
            if isinstance(position, dict) and _is_tradfi_market(position.get("market"))
        ]
        positions.sort(key=lambda item: -float(item.get("notional") or 0))
        assets = [
            _normalize_asset(item)
            for item in row.get("topAssets") or []
            if isinstance(item, dict) and _is_tradfi_market(item.get("coin"))
        ][:10]
        graph = _graph(row.get("portfolioGraph"))
        pnl = _number(row.get("pnl"))
        equity = _number(row.get("perpsEquity"))
        total_trades = _integer(row.get("totalTrades"))
        long_trades = _integer(row.get("totalLongTrades"))
        previous = previous_wallets.get(address) or {}
        recent_trades = _position_changes(
            address,
            previous.get("currentPositions") or [],
            positions,
            generated_at=generated_at,
        )
        recent_trades.extend(
            trade
            for trade in previous.get("recentTrades") or []
            if isinstance(trade, dict) and _inside_window(trade.get("time"), generated_at, lookback_days)
        )
        recent_trades = _unique_recent_trades(recent_trades)
        score = round(max(0.0, min(100.0, _number(row.get("copyScore")))), 2)
        position_snapshot_at = (
            _snapshot_iso(snapshot) if address in positions_by_address else None
        ) or previous.get("positionSnapshotAt")
        label = (
            str(row.get("displayName") or row.get("label") or "").strip()
            or f"{address[:6]}...{address[-4:]}"
        )
        volume = sum(float(asset.get("volume") or 0) for asset in assets)
        top_markets = [
            {"symbol": asset["symbol"], "netPnl": asset["netPnl"], "volume": asset["volume"]}
            for asset in assets[:5]
        ]
        leaderboard.append(
            {
                "rank": rank,
                "address": address,
                "walletLabel": label,
                "avatar": row.get("avatar"),
                "profileURL": f"https://hyperdash.com/trader/{address}",
                "verified": bool(row.get("verified")),
                "twitter": row.get("twitter"),
                "tier": "Smart" if score >= 75 else "Qualified",
                "score": score,
                "rawScore": score,
                "scoreSource": HYPERDASH_SCORE_VERSION,
                "confidence": None,
                "classification": "hyperdash_equities_focused",
                "historyComplete": True,
                "style": str(row.get("tag") or "Unclassified").title(),
                "sizeCohort": str(row.get("sizeCohort") or "Unclassified"),
                "pnlCohort": str(row.get("pnlCohort") or "Unclassified"),
                "accountValue": round(equity, 2),
                "totalNotional": round(sum(float(item["notional"]) for item in positions), 2),
                "unrealizedPnl": round(_number(snapshot.get("totalUnrealizedPnl")), 2),
                "currentLeverage": 0,
                "marginUtilization": 0,
                "withdrawable": 0,
                "fundingSinceOpen": round(sum(float(item["fundingSinceOpen"]) for item in positions), 2),
                "fillCount": total_trades,
                "closedFillCount": total_trades,
                "activeDays": len({dt.datetime.fromtimestamp(point[0] / 1000, tz=dt.timezone.utc).date() for point in graph}),
                "netPnl": round(pnl, 2),
                "longPnl": 0,
                "shortPnl": 0,
                "longBias": round(long_trades / total_trades, 4) if total_trades else 0.5,
                "tradedNotional": round(volume, 2),
                "winRate": round(_ratio(row.get("winrate")), 4),
                "profitFactor": 0,
                "sharpe": round(_number(row.get("sharpe")), 4),
                "maxDrawdownPnl": 0,
                "maxDrawdownPercent": round(abs(_number(row.get("drawdown"))), 4),
                "liquidationCount": 0,
                "makerRatio": 0,
                "tradeDuration": {
                    "completedTrades": total_trades,
                    "averageHoldHours": 0,
                    "medianHoldHours": 0,
                    "style": str(row.get("tag") or "Unclassified").title(),
                },
                "topMarkets": top_markets,
                "assetPerformance": assets,
                "currentPositions": positions,
                "positionSnapshotAt": position_snapshot_at,
                "periodMetrics": _period_metrics(
                    graph,
                    equity=equity,
                    current_pnl=pnl,
                    volume=volume,
                    sharpe=_number(row.get("sharpe")),
                    reported_drawdown=abs(_number(row.get("drawdown"))),
                    generated_at=generated_at,
                ),
                "recentTrades": recent_trades,
                "capitalActivity": [],
                "components": None,
                "source": "hyperdash",
                "sourceUpdatedAt": _iso(generated_at),
            }
        )

    return {
        "version": HYPERDASH_EXPORT_VERSION,
        "scoringVersion": HYPERDASH_SCORE_VERSION,
        "generatedAt": _iso(generated_at),
        "lookbackDays": min(30, max(1, int(lookback_days))),
        "source": {
            "provider": "hyperdash",
            "group": "equities",
            "score": "Copy Score",
            "url": "https://hyperdash.com/explore/equities",
            "updatedAt": _iso(generated_at),
        },
        "summary": {
            "instrumentCount": len({asset["symbol"] for wallet in leaderboard for asset in wallet["assetPerformance"]}),
            "observedWalletCount": len(leaderboard),
            "qualifiedWalletCount": len(leaderboard),
            "smartWalletCount": sum(1 for row in leaderboard if row["tier"] == "Smart"),
            "smartScoreThreshold": 75,
        },
        "methodology": {
            "scoreRange": [0, 100],
            "scoreProvider": "Hyperdash Copy Score",
            "cohort": "Equities Focused",
            "windowDays": 30,
            "localRescoring": False,
        },
        "categories": ["stocks", "indices", "commodities", "fx", "preipo"],
        "markets": [],
        "leaderboard": leaderboard,
    }


def _normalize_position(row: dict[str, Any]) -> dict[str, Any]:
    coin = str(row.get("market") or "")
    size = _number(row.get("size"))
    entry = _nullable_number(row.get("entryPrice"))
    notional = abs(_number(row.get("notionalSize")))
    return {
        "coin": coin,
        "symbol": _symbol(coin),
        "category": _category(coin),
        "dex": coin.split(":", 1)[0] if ":" in coin else "hyperliquid",
        "direction": "Long" if size >= 0 else "Short",
        "size": abs(size),
        "signedSize": size,
        "notional": notional,
        "entryPrice": entry,
        "markPrice": None,
        "unrealizedPnl": round(_number(row.get("unrealizedPnl")), 2),
        "returnOnEquity": 0,
        "liquidationPrice": _nullable_number(row.get("liquidationPrice")),
        "liquidationDistance": None,
        "leverage": 0,
        "marginUsed": 0,
        "fundingSinceOpen": round(_number(row.get("fundingPnl")), 2),
    }


def _normalize_asset(row: dict[str, Any]) -> dict[str, Any]:
    coin = str(row.get("coin") or "")
    return {
        "symbol": _symbol(coin),
        "netPnl": round(_number(row.get("pnl")), 2),
        "fees": 0,
        "volume": round(_number(row.get("volume")), 2),
        "trades": 0,
        "winRate": 0,
    }


def _position_changes(
    address: str,
    previous_rows: list[dict[str, Any]],
    current_rows: list[dict[str, Any]],
    *,
    generated_at: dt.datetime,
) -> list[dict[str, Any]]:
    before = {str(row.get("coin") or row.get("symbol") or ""): row for row in previous_rows}
    after = {str(row.get("coin") or row.get("symbol") or ""): row for row in current_rows}
    if not before:
        return []
    changes: list[dict[str, Any]] = []
    for coin in sorted(set(before) | set(after)):
        old = _signed_size(before.get(coin))
        new = _signed_size(after.get(coin))
        if abs(old - new) <= 1e-10:
            continue
        row = after.get(coin) or before.get(coin) or {}
        price = _number(row.get("entryPrice"))
        if price <= 0:
            notional = _number(row.get("notional"))
            price = notional / max(abs(new or old), 1e-9)
        event_key = f"{address}:{coin}:{old:.10f}:{new:.10f}:{int(generated_at.timestamp())}"
        changes.append(
            {
                "id": str(uuid.uuid5(_NAMESPACE, event_key)),
                "symbol": str(row.get("symbol") or _symbol(coin)),
                "coin": coin,
                "direction": "Long" if new >= 0 else "Short",
                "side": "Buy" if new > old else "Sell",
                "price": round(price, 8),
                "size": round(abs(new - old), 8),
                "notional": round(abs(new - old) * price, 2),
                "closedPnl": 0,
                "time": _iso(generated_at),
                "hash": "",
                "startPosition": old,
                "positionAfter": new,
                "evidenceURL": f"https://hyperdash.com/trader/{address}",
            }
        )
    return changes


def _period_metrics(
    graph: list[list[float]],
    *,
    equity: float,
    current_pnl: float,
    volume: float,
    sharpe: float,
    reported_drawdown: float,
    generated_at: dt.datetime,
) -> dict[str, dict[str, Any]]:
    metrics: dict[str, dict[str, Any]] = {}
    for label, days in (("1D", 1), ("7D", 7), ("30D", 30)):
        cutoff = (generated_at - dt.timedelta(days=days)).timestamp() * 1_000
        points = [point for point in graph if point[0] >= cutoff]
        if not points and graph:
            points = graph[-min(2, len(graph)) :]
        baseline_pnl = points[0][1] if points else current_pnl
        period_pnl = (points[-1][1] - baseline_pnl) if points else 0.0
        account_history = [
            [point[0], round(equity - current_pnl + point[1], 6)]
            for point in points
        ]
        calculated_drawdown = _maximum_drawdown(account_history)
        metrics[label] = {
            "equity": round(equity, 2),
            "pnl": round(period_pnl if label != "30D" else current_pnl, 2),
            "volume": round(volume, 2),
            "sharpe": round(sharpe, 4) if label == "30D" else 0,
            "maxDrawdown": round(calculated_drawdown[0], 2),
            "maxDrawdownPercent": round(
                reported_drawdown if label == "30D" else calculated_drawdown[1],
                4,
            ),
            "accountValueHistory": account_history,
            "pnlHistory": points,
        }
    return metrics


def _maximum_drawdown(points: list[list[float]]) -> tuple[float, float]:
    peak = 0.0
    maximum = 0.0
    maximum_ratio = 0.0
    for _, value in points:
        peak = max(peak, value)
        drawdown = max(0.0, peak - value)
        maximum = max(maximum, drawdown)
        if peak > 0:
            maximum_ratio = max(maximum_ratio, drawdown / peak)
    return maximum, maximum_ratio


def _signed_size(row: dict[str, Any] | None) -> float:
    if not row:
        return 0.0
    if row.get("signedSize") is not None:
        return _number(row.get("signedSize"))
    size = _number(row.get("size"))
    return -abs(size) if str(row.get("direction") or "").lower() == "short" else abs(size)


def _unique_recent_trades(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    unique = {str(row.get("id") or ""): row for row in rows if row.get("id")}
    ordered = sorted(unique.values(), key=lambda row: str(row.get("time") or ""), reverse=True)
    return ordered[:_MAX_RECENT_TRADES]


def _graph(value: Any) -> list[list[float]]:
    rows = []
    for point in value or []:
        if not isinstance(point, dict):
            continue
        timestamp = _number(point.get("timestamp"))
        if timestamp <= 0:
            continue
        rows.append([timestamp, round(_number(point.get("value")), 6)])
    rows.sort(key=lambda point: point[0])
    if len(rows) <= _MAX_GRAPH_POINTS:
        return rows
    step = (len(rows) - 1) / (_MAX_GRAPH_POINTS - 1)
    return [rows[round(index * step)] for index in range(_MAX_GRAPH_POINTS)]


def _snapshot_iso(snapshot: dict[str, Any]) -> str | None:
    timestamp = _number(snapshot.get("bucketTs") or snapshot.get("requestedTs"))
    if timestamp <= 0:
        return None
    return _iso(dt.datetime.fromtimestamp(timestamp / 1_000, tz=dt.timezone.utc))


def _inside_window(value: Any, generated_at: dt.datetime, days: int) -> bool:
    try:
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return False
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed >= generated_at - dt.timedelta(days=min(30, max(1, days)))


def _is_tradfi_market(value: Any) -> bool:
    return ":" in str(value or "")


def _symbol(value: Any) -> str:
    return str(value or "").split(":", 1)[-1].upper()


def _category(value: Any) -> str:
    symbol = _symbol(value)
    if symbol in {"CL", "GOLD", "SILVER", "COPPER", "NATGAS"}:
        return "commodities"
    if symbol in {"SP500", "XYZ100", "NIKKEI", "DAX", "FTSE"}:
        return "indices"
    if symbol in {"SPCX", "OPENAI", "ANTHROPIC"}:
        return "preipo"
    return "stocks"


def _ratio(value: Any) -> float:
    number = _number(value)
    return number / 100 if number > 1 else number


def _number(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def _nullable_number(value: Any) -> float | None:
    if value is None or value == "":
        return None
    return _number(value)


def _integer(value: Any) -> int:
    try:
        return int(float(value or 0))
    except (TypeError, ValueError):
        return 0


def _iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat()
