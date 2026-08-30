"""Normalize Hyperliquid HIP-3 TradFi instruments and fills."""
from __future__ import annotations

import datetime as dt
from dataclasses import asdict, dataclass
from typing import Any, Iterable


TRADFI_CATEGORIES = {
    "stocks": "stocks",
    "stock": "stocks",
    "indices": "indices",
    "index": "indices",
    "commodities": "commodities",
    "commodity": "commodities",
    "fx": "fx",
    "preipo": "preipo",
}


def as_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def split_coin(coin: str) -> tuple[str, str]:
    if ":" not in coin:
        return "", coin.upper()
    dex, symbol = coin.split(":", 1)
    return dex.lower(), symbol.upper()


@dataclass(frozen=True)
class TradFiInstrument:
    coin: str
    dex: str
    symbol: str
    category: str
    sz_decimals: int
    max_leverage: float
    mark_px: float
    oracle_px: float
    open_interest: float
    day_notional_volume: float

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def discover_tradfi_instruments(
    categories: Iterable[tuple[str, str]],
    dex_markets: dict[str, tuple[dict[str, Any], list[dict[str, Any]]]],
) -> list[TradFiInstrument]:
    category_by_coin = {
        str(coin): TRADFI_CATEGORIES[str(category).lower()]
        for coin, category in categories
        if str(category).lower() in TRADFI_CATEGORIES and ":" in str(coin)
    }
    instruments: list[TradFiInstrument] = []
    for dex, (meta, contexts) in dex_markets.items():
        universe = meta.get("universe") if isinstance(meta, dict) else None
        if not isinstance(universe, list):
            continue
        for index, raw in enumerate(universe):
            if not isinstance(raw, dict):
                continue
            coin = str(raw.get("name") or "")
            category = category_by_coin.get(coin)
            if not category:
                continue
            context = contexts[index] if index < len(contexts) else {}
            parsed_dex, symbol = split_coin(coin)
            instruments.append(
                TradFiInstrument(
                    coin=coin,
                    dex=parsed_dex or dex,
                    symbol=symbol,
                    category=category,
                    sz_decimals=int(raw.get("szDecimals") or 0),
                    max_leverage=as_float(raw.get("maxLeverage")),
                    mark_px=as_float(context.get("markPx")),
                    oracle_px=as_float(context.get("oraclePx")),
                    open_interest=as_float(context.get("openInterest")),
                    day_notional_volume=as_float(context.get("dayNtlVlm")),
                )
            )
    return sorted(instruments, key=lambda item: (-item.day_notional_volume, item.coin))


def normalize_fill(
    address: str,
    raw: dict[str, Any],
    instruments: dict[str, TradFiInstrument],
) -> dict[str, Any] | None:
    coin = str(raw.get("coin") or "")
    instrument = instruments.get(coin)
    if not instrument:
        return None
    time_ms = int(as_float(raw.get("time")))
    if time_ms <= 0:
        return None
    timestamp = dt.datetime.fromtimestamp(time_ms / 1000, tz=dt.timezone.utc)
    side = str(raw.get("side") or "").upper()
    price = as_float(raw.get("px"))
    size = as_float(raw.get("sz"))
    if side not in {"A", "B"} or price <= 0 or size <= 0:
        return None
    start_position = as_float(raw.get("startPosition"))
    position_after = start_position + size if side == "B" else start_position - size
    return {
        "address": address.lower(),
        "tid": str(raw.get("tid") or f"{raw.get('hash', '')}:{raw.get('oid', '')}:{time_ms}"),
        "coin": coin,
        "dex": instrument.dex,
        "symbol": instrument.symbol,
        "category": instrument.category,
        "side": side,
        "direction": str(raw.get("dir") or ""),
        "price": price,
        "size": size,
        "notional": abs(price * size),
        "time_ms": time_ms,
        "created_at": timestamp.replace(microsecond=0).isoformat(),
        "created_day": timestamp.date().isoformat(),
        "start_position": start_position,
        "position_after": position_after,
        "closed_pnl": as_float(raw.get("closedPnl")),
        "fee": as_float(raw.get("fee")),
        "crossed": bool(raw.get("crossed")),
        "liquidation": 1 if raw.get("liquidation") else 0,
        "hash": str(raw.get("hash") or ""),
        "oid": str(raw.get("oid") or ""),
        "raw": raw,
    }


def normalize_wallet_state(
    address: str,
    dex: str,
    raw: dict[str, Any],
    instruments: dict[str, TradFiInstrument],
    *,
    observed_at: str,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Normalize the public clearinghouse response without inferring identity."""
    summary = raw.get("marginSummary") if isinstance(raw.get("marginSummary"), dict) else {}
    state = {
        "address": address.lower(),
        "dex": dex,
        "account_value": as_float(summary.get("accountValue")),
        "total_notional": as_float(summary.get("totalNtlPos")),
        "margin_used": as_float(summary.get("totalMarginUsed")),
        "maintenance_margin": as_float(raw.get("crossMaintenanceMarginUsed")),
        "withdrawable": as_float(raw.get("withdrawable")),
        "observed_at": observed_at,
        "raw": raw,
    }
    positions: list[dict[str, Any]] = []
    for item in raw.get("assetPositions") or []:
        position = item.get("position") if isinstance(item, dict) else None
        if not isinstance(position, dict):
            continue
        coin = str(position.get("coin") or "")
        instrument = instruments.get(coin)
        size = as_float(position.get("szi"))
        position_value = as_float(position.get("positionValue"))
        if not coin or not instrument or abs(size) <= 1e-12:
            continue
        leverage = position.get("leverage") if isinstance(position.get("leverage"), dict) else {}
        funding = position.get("cumFunding") if isinstance(position.get("cumFunding"), dict) else {}
        mark_px = abs(position_value / size) if abs(size) > 1e-12 else 0.0
        positions.append(
            {
                "address": address.lower(),
                "coin": coin,
                "dex": instrument.dex,
                "symbol": instrument.symbol,
                "category": instrument.category,
                "size": size,
                "position_value": position_value,
                "entry_px": as_float(position.get("entryPx")) or None,
                "mark_px": mark_px or None,
                "unrealized_pnl": as_float(position.get("unrealizedPnl")),
                "return_on_equity": as_float(position.get("returnOnEquity")),
                "liquidation_px": as_float(position.get("liquidationPx")) or None,
                "leverage": as_float(leverage.get("value")),
                "margin_used": as_float(position.get("marginUsed")),
                "max_leverage": as_float(position.get("maxLeverage")),
                "funding_all_time": as_float(funding.get("allTime")),
                "funding_since_open": as_float(funding.get("sinceOpen")),
                "observed_at": observed_at,
                "raw": item,
            }
        )
    return state, positions


def normalize_portfolio(raw: Iterable[list[Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, list) or len(item) < 2 or not isinstance(item[1], dict):
            continue
        period = str(item[0])
        payload = item[1]

        def history(name: str) -> list[list[float]]:
            values: list[list[float]] = []
            for point in payload.get(name) or []:
                if not isinstance(point, list) or len(point) < 2:
                    continue
                values.append([int(as_float(point[0])), as_float(point[1])])
            return values

        rows.append(
            {
                "period": period,
                "volume": as_float(payload.get("vlm")),
                "account_value_history": history("accountValueHistory"),
                "pnl_history": history("pnlHistory"),
            }
        )
    return rows


def normalize_ledger_updates(
    address: str,
    raw_rows: Iterable[dict[str, Any]],
) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    normalized_address = address.lower()
    for index, row in enumerate(raw_rows):
        time_ms = int(as_float(row.get("time")))
        delta = row.get("delta") if isinstance(row.get("delta"), dict) else {}
        if time_ms <= 0 or not delta:
            continue
        event_type = str(delta.get("type") or "transfer")
        source = str(delta.get("user") or delta.get("source") or "").lower()
        destination = str(delta.get("destination") or "").lower()
        if destination == normalized_address and source != normalized_address:
            direction = "in"
        elif source == normalized_address and destination != normalized_address:
            direction = "out"
        elif "deposit" in event_type.lower():
            direction = "in"
        elif "withdraw" in event_type.lower():
            direction = "out"
        else:
            direction = "internal"
        amount = as_float(
            delta.get("usdcValue")
            or delta.get("usdValue")
            or delta.get("amount")
            or delta.get("usdc")
        )
        transaction_hash = str(row.get("hash") or "")
        normalized.append(
            {
                "event_id": f"{transaction_hash or time_ms}:{index}",
                "time_ms": time_ms,
                "created_at": dt.datetime.fromtimestamp(time_ms / 1000, tz=dt.timezone.utc).replace(microsecond=0).isoformat(),
                "event_type": event_type,
                "amount_usd": amount,
                "direction": direction,
                "token": str(delta.get("token") or delta.get("coin") or "USDC"),
                "hash": transaction_hash,
                "raw": row,
            }
        )
    return normalized
