#!/usr/bin/env python3
"""Verify that the iOS live boundary serves complete database-backed data."""

from __future__ import annotations

import argparse
from datetime import UTC, datetime
import json
import sys
import urllib.error
import urllib.request
import uuid
from typing import Any


def request_json(
    url: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    token: str | None = None,
) -> tuple[Any, dict[str, str]]:
    headers = {"Accept": "application/json"}
    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=10) as response:
        response_headers = {key.lower(): value for key, value in response.headers.items()}
        return json.load(response), response_headers


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def validate_update(update: dict[str, Any]) -> None:
    identity = f"{update.get('ticker', '?')}:{update.get('sourcePostId', '?')}"
    required_strings = (
        "ticker",
        "authorId",
        "authorName",
        "originalText",
        "publishedAt",
        "evidenceURL",
    )
    for field in required_strings:
        value = update.get(field)
        require(isinstance(value, str) and value.strip(), f"{identity} missing {field}")

    platform = update.get("platform")
    require(
        platform in {"X", "YouTube", "Reddit"},
        f"{identity} uses unsupported Smart Account platform {platform!r}",
    )
    require(update.get("direction") in {"bullish", "neutral", "bearish"}, f"{identity} has invalid direction")
    require(update.get("horizon") in {"unknown", "1D", "5D", "20D", "60D", "90D", "180D"}, f"{identity} has invalid horizon")
    require(isinstance(update.get("score"), (int, float)), f"{identity} lacks a real author score")
    evidence_url = str(update["evidenceURL"])
    source_hosts = {
        "X": ("https://x.com/", "https://twitter.com/"),
        "YouTube": ("https://www.youtube.com/", "https://youtube.com/", "https://youtu.be/"),
        "Reddit": ("https://www.reddit.com/", "https://reddit.com/"),
    }
    require(
        evidence_url.startswith(source_hosts[platform]),
        f"{identity} lacks a {platform} source link",
    )
    source_post_id = update.get("sourcePostId")
    source_url = update.get("sourceURL")
    if source_post_id or source_url:
        require(isinstance(source_post_id, str) and source_post_id, f"{identity} has partial source identity")
        require(isinstance(source_url, str) and source_post_id in source_url, f"{identity} source URL does not identify its post")
    translated_zh = update.get("translatedTextZH")
    translated_en = update.get("translatedTextEN")
    if translated_zh and translated_en:
        require(translated_zh != translated_en, f"{identity} translations are identical")
    evidence_span = update.get("evidenceSpan")
    if evidence_span:
        require(evidence_span in update["originalText"], f"{identity} evidence is not traceable to original text")


def parse_timestamp(value: Any, field: str) -> datetime:
    require(isinstance(value, str) and value, f"Smart Money account lacks {field}")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed.replace(tzinfo=parsed.tzinfo or UTC).astimezone(UTC)


def validate_smart_money(accounts: list[dict[str, Any]]) -> datetime:
    require(len(accounts) >= 50, f"Smart Money cohort is unexpectedly small: {len(accounts)}")
    timestamps: list[datetime] = []
    for account in accounts:
        identity = str(account.get("id") or "unknown")
        require(account.get("source") == "hyperdash", f"{identity} is not current Hyperdash data")
        require(
            account.get("scoreSource") == "hyperdash-copy-score",
            f"{identity} does not use Hyperdash Copy Score",
        )
        require(isinstance(account.get("score"), (int, float)), f"{identity} lacks a score")
        require(str(account.get("sourceURL") or "").startswith("https://hyperdash.com/trader/"), f"{identity} lacks Hyperdash evidence")
        timestamps.append(parse_timestamp(account.get("sourceUpdatedAt"), "sourceUpdatedAt"))
    newest = max(timestamps)
    age_seconds = (datetime.now(UTC) - newest).total_seconds()
    require(age_seconds <= 1_800, f"Smart Money data is stale by {int(age_seconds)} seconds")
    return newest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://localhost:8081")
    args = parser.parse_args()
    base_url = args.base_url.rstrip("/")

    try:
        health, _ = request_json(f"{base_url}/health")
        require(health.get("status") == "ok", "Client API is not healthy")
        require(
            health.get("readModelMode") == "database",
            f"Client API uses {health.get('readModelMode')!r}, expected database",
        )

        installation_id = str(uuid.uuid4())
        session, _ = request_json(
            f"{base_url}/v1/installations",
            method="POST",
            payload={
                "installationId": installation_id,
                "platform": "ios",
                "appVersion": "local-check",
                "locale": "zh_CN",
                "timeZone": "Asia/Shanghai",
            },
        )
        require(session.get("installationId") == installation_id, "Installation identity changed")
        token = session.get("accessToken")
        require(isinstance(token, str) and token, "Client API did not issue an access token")

        updates, update_headers = request_json(
            f"{base_url}/v1/smart-account-updates",
            token=token,
        )
        signals, signal_headers = request_json(f"{base_url}/v1/feed", token=token)
        money, money_headers = request_json(f"{base_url}/v1/smart-money", token=token)
        movements, movement_headers = request_json(
            f"{base_url}/v1/smart-money-movements",
            token=token,
        )
        require(isinstance(updates, list) and updates, "No product-ready Smart Account updates")
        require(isinstance(signals, list) and signals, "No product-ready portfolio signals")
        require(update_headers.get("x-bsmart-data-as-of"), "Smart Account response lacks data provenance")
        require(update_headers.get("x-bsmart-latest-content-at"), "Smart Account response lacks content freshness")
        require(
            update_headers.get("x-bsmart-source-item-count") == str(len(updates)),
            "Smart Account response has an invalid source item count",
        )
        require(signal_headers.get("x-bsmart-data-as-of"), "Feed response lacks data provenance")
        require(isinstance(money, list), "Smart Money response is not a list")
        require(isinstance(movements, list), "Smart Money movement response is not a list")
        require(money_headers.get("x-bsmart-data-as-of"), "Smart Money response lacks data provenance")
        require(money_headers.get("x-bsmart-latest-content-at"), "Smart Money response lacks content freshness")
        require(
            money_headers.get("x-bsmart-source-item-count") == str(len(money)),
            "Smart Money response has an invalid source item count",
        )
        require(movement_headers.get("x-bsmart-data-as-of"), "Movement response lacks data provenance")
        require(movement_headers.get("x-bsmart-latest-content-at"), "Movement response lacks content freshness")
        require(
            movement_headers.get("x-bsmart-source-item-count") == str(len(movements)),
            "Movement response has an invalid source item count",
        )

        for update in updates:
            validate_update(update)

        update_tickers = {item["ticker"] for item in updates}
        signal_tickers = {item.get("ticker") for item in signals}
        require(
            bool(update_tickers & signal_tickers),
            "The portfolio feed has no overlap with current Smart Account evidence",
        )
        event_keys = [
            (
                item.get("platform"),
                item.get("sourcePostId"),
                item.get("ticker"),
                item.get("callScoringVersion"),
            )
            for item in updates
            if item.get("sourcePostId")
        ]
        require(
            len(event_keys) == len(set(event_keys)),
            "Duplicate Smart Account events returned to iOS",
        )
        money_as_of = validate_smart_money(money)

        print("iOS local data check: PASS")
        print(f"  API: {base_url}")
        print(f"  read model: {health['readModelMode']}")
        print(f"  Smart Account updates: {len(updates)} ({', '.join(sorted(update_tickers))})")
        print(f"  portfolio signals: {len(signals)}")
        print(f"  Hyperdash accounts: {len(money)}")
        print(f"  Smart Money movements: {len(movements)}")
        print(f"  Hyperdash source as of: {money_as_of.isoformat()}")
        print(f"  data as of: {update_headers['x-bsmart-data-as-of']}")
        print(f"  latest qualified Smart Account view: {update_headers['x-bsmart-latest-content-at']}")
        print(f"  latest capital movement: {movement_headers['x-bsmart-latest-content-at']}")
        return 0
    except (AssertionError, OSError, urllib.error.URLError, json.JSONDecodeError) as error:
        print(f"iOS local data check: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
