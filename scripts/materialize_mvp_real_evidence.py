#!/usr/bin/env python3
"""Bind mock MVP event relationships to real local Smart Account evidence."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def _load(path: Path) -> list[dict[str, Any]]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, list):
        raise ValueError(f"Expected a JSON array: {path}")
    return value


def _write(path: Path, value: list[dict[str, Any]]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _pick_update(
    updates: list[dict[str, Any]],
    *,
    ticker: str,
    preferred_direction: str | None,
) -> dict[str, Any] | None:
    candidates = [update for update in updates if update.get("ticker") == ticker]
    if preferred_direction:
        directional = [
            update for update in candidates if update.get("direction") == preferred_direction
        ]
        if directional:
            candidates = directional
    candidates.sort(
        key=lambda update: (
            str(update.get("publishedAt") or ""),
            float(update.get("score") or 0),
        ),
        reverse=True,
    )
    return candidates[0] if candidates else None


def _money_directional_change(movement: dict[str, Any]) -> float:
    change = float(movement.get("notionalChange") or 0)
    return change if movement.get("direction") == "bullish" else -change


def _money_snapshot(movements: list[dict[str, Any]]) -> dict[str, Any]:
    accounts = {str(row.get("accountId") or "") for row in movements if row.get("accountId")}
    latest = max((str(row.get("observedAt") or "") for row in movements), default="")
    directional_change = sum(_money_directional_change(row) for row in movements)
    if not movements:
        return {
            "coverage": "unavailable",
            "direction": "neutral",
            "headline": "No qualifying public capital movement",
            "detail": "No qualifying Hyperliquid tokenized-equity account movement is inside the current observation window.",
            "qualifiedAccountCount": 0,
            "latestMovementAt": None,
        }
    direction = "bullish" if directional_change > 0 else "bearish" if directional_change < 0 else "mixed"
    verb = "added" if directional_change > 0 else "reduced" if directional_change < 0 else "left unchanged"
    magnitude = abs(directional_change)
    return {
        "coverage": "available",
        "direction": direction,
        "headline": f"{len(accounts)} qualified public account{'s' if len(accounts) != 1 else ''} {verb} directional exposure",
        "detail": (
            f"Across {len(movements)} auditable Hyperliquid fills, tracked accounts produced "
            f"a ${magnitude:,.0f} net {direction} change in visible directional exposure."
        ),
        "qualifiedAccountCount": len(accounts),
        "latestMovementAt": latest or None,
    }


def materialize(fixtures: Path) -> dict[str, Any]:
    updates_path = fixtures / "smart-account-updates.json"
    signals_path = fixtures / "portfolio-signals.json"
    intelligence_path = fixtures / "ticker-intelligence.json"
    movements_path = fixtures / "smart-money-movements.json"
    updates = _load(updates_path)
    signals = _load(signals_path)
    intelligence = _load(intelligence_path)
    movements = _load(movements_path)
    replaced = 0
    missing: list[str] = []

    for signal in signals:
        direction = signal.get("direction")
        preferred = direction if direction in {"bullish", "bearish"} else None
        update = _pick_update(
            updates,
            ticker=str(signal.get("ticker") or ""),
            preferred_direction=preferred,
        )
        if not update:
            missing.append(str(signal.get("ticker") or ""))
            continue
        for evidence in signal.get("evidence") or []:
            if evidence.get("source") != "smart_account":
                continue
            original = str(update.get("originalText") or update.get("thesis") or "").strip()
            if len(original) > 420:
                original = original[:417].rstrip() + "..."
            evidence.update(
                {
                    "referenceId": update["id"],
                    "actorName": update["authorName"],
                    "title": f"{str(update['direction']).title()} view · {str(update['lifecycle']).replace('_', ' ')}",
                    "detail": original,
                    "metric": f"Score {float(update['score']):.0f}",
                    "observedAt": update["publishedAt"],
                    "sourceURL": update.get("evidenceURL"),
                }
            )
            replaced += 1

    if missing:
        raise RuntimeError(f"No real Smart Account update for: {sorted(set(missing))}")

    for snapshot in intelligence:
        ticker = str(snapshot.get("ticker") or "")
        ticker_updates = [update for update in updates if update.get("ticker") == ticker]
        ticker_updates.sort(key=lambda update: str(update.get("publishedAt") or ""), reverse=True)
        account = snapshot["smartAccount"]
        account["qualifiedAuthorCount"] = len(ticker_updates)
        if ticker_updates:
            latest = ticker_updates[0]
            original = str(latest.get("originalText") or latest.get("thesis") or "").strip()
            if len(original) > 260:
                original = original[:257].rstrip() + "..."
            account.update(
                {
                    "direction": latest["direction"],
                    "headline": f"Latest qualified view from {latest['authorName']}",
                    "detail": original,
                    "latestUpdateAt": latest["publishedAt"],
                }
            )
        ticker_movements = [row for row in movements if row.get("ticker") == ticker]
        snapshot["smartMoney"] = _money_snapshot(ticker_movements)
        latest_money = snapshot["smartMoney"].get("latestMovementAt")
        if latest_money and latest_money > str(snapshot.get("dataAsOf") or ""):
            snapshot["dataAsOf"] = latest_money
        else:
            account.update(
                {
                    "direction": "neutral",
                    "headline": "No recent qualified Smart Account view",
                    "detail": "No database-backed view is inside the current monitoring window.",
                    "latestUpdateAt": None,
                }
            )

    _write(signals_path, signals)
    _write(intelligence_path, intelligence)
    return {
        "signals": len(signals),
        "intelligence": len(intelligence),
        "evidenceReplaced": replaced,
        "smartMoneyMovements": len(movements),
        "missing": missing,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", default="contracts/fixtures")
    args = parser.parse_args()
    print(json.dumps(materialize(Path(args.fixtures)), indent=2))


if __name__ == "__main__":
    main()
