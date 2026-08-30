"""Small GraphQL client for the public data used by Hyperdash's web app."""
from __future__ import annotations

import os
import re
import time
from typing import Any, Iterable

import requests


DEFAULT_GRAPHQL_URL = "https://api.hyperdash.com/graphql"
_ADDRESS_PATTERN = re.compile(r"^0x[a-fA-F0-9]{40}$")

SYSTEM_GROUP_TRADERS_QUERY = """
query GetSystemGroupTraders($groupId: ID!) {
  getSystemGroupTraders(groupId: $groupId) {
    address
    label
    verified
    displayName
    avatar
    twitter
    lastTradeAt
    lastFillAt
    portfolioGraph { timestamp value }
    pnl
    perpsEquity
    winrate
    pnlCohort
    sizeCohort
    totalTrades
    totalLongTrades
    totalShortTrades
    totalWinningTrades
    totalLosingTrades
    sharpe
    drawdown
    copyScore
    tag
    topAssets { coin volume pnl }
  }
}
"""

_POSITION_FIELDS = """
requestedTs
bucketTs
positionsCount
totalUnrealizedPnl
positions {
  market
  size
  notionalSize
  entryPrice
  liquidationPrice
  unrealizedPnl
  fundingPnl
}
"""


class HyperdashGraphQLClient:
    """Fetch Hyperdash's Equities Focused cohort and position snapshots.

    This adapter intentionally mirrors the public GraphQL operations used by
    Hyperdash's own web client. Credentials and cookies are optional so an
    approved commercial API session can be supplied without changing code.
    """

    def __init__(
        self,
        *,
        graphql_url: str | None = None,
        timeout: float = 30.0,
        retries: int = 3,
        session: requests.Session | None = None,
        authorization: str | None = None,
        cookie: str | None = None,
    ) -> None:
        self.graphql_url = (
            graphql_url
            or os.environ.get("BSMART_HYPERDASH_GRAPHQL_URL")
            or DEFAULT_GRAPHQL_URL
        )
        self.timeout = max(1.0, float(timeout))
        self.retries = max(1, int(retries))
        self.session = session or requests.Session()
        self.session.headers.update(
            {
                "Accept": "application/graphql-response+json, application/json",
                "Content-Type": "application/json",
                "Origin": "https://hyperdash.com",
                "Referer": "https://hyperdash.com/explore/equities",
                "User-Agent": os.environ.get(
                    "BSMART_HYPERDASH_USER_AGENT",
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                ),
            }
        )
        authorization = authorization or os.environ.get("BSMART_HYPERDASH_AUTHORIZATION")
        cookie = cookie or os.environ.get("BSMART_HYPERDASH_COOKIE")
        if authorization:
            self.session.headers["Authorization"] = authorization
        if cookie:
            self.session.headers["Cookie"] = cookie

    def execute(
        self,
        operation_name: str,
        query: str,
        variables: dict[str, Any],
    ) -> dict[str, Any]:
        last_error: Exception | None = None
        for attempt in range(self.retries):
            try:
                response = self.session.post(
                    self.graphql_url,
                    json={
                        "operationName": operation_name,
                        "query": query,
                        "variables": variables,
                    },
                    headers={"X-Apollo-Operation-Name": operation_name},
                    timeout=self.timeout,
                )
                response.raise_for_status()
                response_headers = getattr(response, "headers", {})
                content_type = str(response_headers.get("Content-Type") or "").lower()
                if content_type and "json" not in content_type and "graphql-response" not in content_type:
                    raise RuntimeError(
                        f"Hyperdash GraphQL {operation_name} returned unexpected "
                        f"content type {content_type or 'unknown'}"
                    )
                payload = response.json()
                errors = payload.get("errors") if isinstance(payload, dict) else None
                if errors:
                    message = "; ".join(
                        str(row.get("message") or row)
                        for row in errors
                        if isinstance(row, dict)
                    ) or str(errors)
                    raise RuntimeError(f"Hyperdash GraphQL {operation_name} failed: {message}")
                data = payload.get("data") if isinstance(payload, dict) else None
                if not isinstance(data, dict):
                    raise RuntimeError(
                        f"Hyperdash GraphQL {operation_name} returned no data object"
                    )
                return data
            except (requests.RequestException, ValueError, RuntimeError) as exc:
                last_error = exc
                if attempt + 1 < self.retries:
                    time.sleep(min(8.0, 1.5 * (2**attempt)))
        raise RuntimeError(f"Hyperdash GraphQL {operation_name} unavailable: {last_error}")

    def equity_traders(
        self,
        *,
        group_id: str = "equities",
        limit: int = 100,
    ) -> list[dict[str, Any]]:
        data = self.execute(
            "GetSystemGroupTraders",
            SYSTEM_GROUP_TRADERS_QUERY,
            {"groupId": group_id},
        )
        rows = data.get("getSystemGroupTraders")
        traders = [row for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []
        traders.sort(key=lambda row: -_number(row.get("copyScore")))
        return traders[: max(1, int(limit))]

    def trader_positions(
        self,
        addresses: Iterable[str],
        *,
        timestamp_ms: int | None = None,
        position_limit: int = 12,
        batch_size: int = 20,
    ) -> dict[str, dict[str, Any]]:
        normalized = []
        seen: set[str] = set()
        for value in addresses:
            address = str(value).lower()
            if address in seen or not _ADDRESS_PATTERN.fullmatch(address):
                continue
            seen.add(address)
            normalized.append(address)
        requested_at = int(timestamp_ms or time.time() * 1_000)
        results: dict[str, dict[str, Any]] = {}
        size = max(1, min(25, int(batch_size)))
        for offset in range(0, len(normalized), size):
            batch = normalized[offset : offset + size]
            variable_definitions = ["$timestamp: Float!", "$limit: Int"]
            variables: dict[str, Any] = {
                "timestamp": requested_at,
                "limit": max(1, int(position_limit)),
            }
            fields: list[str] = []
            for index, address in enumerate(batch):
                variable = f"address{index}"
                alias = f"wallet{index}"
                variable_definitions.append(f"${variable}: String!")
                variables[variable] = address
                fields.append(
                    f"{alias}: traderPerpPositionsTooltip("
                    f"address: ${variable}, timestamp: $timestamp, limit: $limit"
                    f") {{ {_POSITION_FIELDS} }}"
                )
            query = (
                f"query TraderPositionsBatch({', '.join(variable_definitions)}) "
                f"{{ {' '.join(fields)} }}"
            )
            data = self.execute("TraderPositionsBatch", query, variables)
            for index, address in enumerate(batch):
                row = data.get(f"wallet{index}")
                if isinstance(row, dict):
                    results[address] = row
        return results


def _number(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0
