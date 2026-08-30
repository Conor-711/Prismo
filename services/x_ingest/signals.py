from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any


SIGNAL_NAMESPACE = uuid.UUID("8fa0cb35-4449-4603-a287-f686bcb67a11")
EVIDENCE_NAMESPACE = uuid.UUID("e154cbd1-ec0a-466d-87bc-3a0b44ad922c")


def build_portfolio_signals(updates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    signals = [_signal_from_update(update) for update in updates]
    return sorted(signals, key=lambda item: str(item["occurredAt"]), reverse=True)


def _signal_from_update(update: dict[str, Any]) -> dict[str, Any]:
    update_id = str(update["id"])
    ticker = str(update["ticker"]).upper()
    author = str(update["authorName"])
    direction = str(update.get("direction") or "neutral")
    lifecycle = str(update.get("lifecycle") or "new")
    published_at = str(update["publishedAt"])
    processed_at = str(update.get("processedAt") or update.get("ingestedAt") or published_at)
    latency_seconds = max(0.0, (_parse_time(processed_at) - _parse_time(published_at)).total_seconds())
    thesis = str(update.get("thesis") or update.get("translatedText") or "").strip()
    evidence = str(update.get("evidenceSpan") or update.get("originalText") or thesis).strip()
    score = float(update.get("score") or 0)
    percentile = float(update.get("platformPercentile") or 1)
    signal_id = str(uuid.uuid5(SIGNAL_NAMESPACE, f"x:{update_id}:{ticker}"))
    evidence_id = str(uuid.uuid5(EVIDENCE_NAMESPACE, f"x:{update_id}:{ticker}"))
    direction_label = {
        "bullish": "bullish",
        "bearish": "bearish",
        "neutral": "neutral",
        "mixed": "mixed",
    }.get(direction, "updated")
    priority = "critical" if percentile <= 0.10 or lifecycle in {"reversed", "invalidated"} else "important"
    return {
        "id": signal_id,
        "ticker": ticker,
        "companyName": str(update.get("companyName") or ticker),
        "title": f"{author} published a new {ticker} view",
        "summary": thesis,
        "occurredAt": published_at,
        "dataAsOf": processed_at,
        "dataStatus": "current" if latency_seconds <= 900 else "delayed",
        "priority": priority,
        "kind": "account_leads",
        "direction": direction,
        "smartMoneyCoverage": "unavailable",
        "conclusion": (
            f"A top-ranked Smart Account is now {direction_label} on {ticker}; "
            "no current public on-chain capital verification is available."
        ),
        "positionImpact": (
            "Review whether this new view changes the assumptions behind your cost basis and position size."
        ),
        "nextStep": "Read the complete source view and compare its evidence with your current position plan.",
        "limitations": [
            "This event reflects a public view, not verified account ownership or trade execution.",
            "Smart Money confirmation is currently unavailable for this event.",
        ],
        "evidence": [
            {
                "id": evidence_id,
                "source": "smart_account",
                "referenceId": update_id,
                "actorName": author,
                "title": f"Smart Account Score {score:.1f}",
                "detail": evidence,
                "metric": f"Top {max(1, round(percentile * 100))}% on X",
                "observedAt": published_at,
                "sourceURL": update.get("sourceURL") or update.get("evidenceURL"),
            }
        ],
    }


def _parse_time(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


__all__ = ["build_portfolio_signals"]
