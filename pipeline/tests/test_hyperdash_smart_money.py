from __future__ import annotations

import datetime as dt
import json

from pipeline.domain.smart_voice.hyperliquid import build_hyperliquid_client_collections
from pipeline.jobs.smart_voice.hyperdash_live import run_hyperdash_live
from pipeline.platforms.hyperdash import (
    HyperdashGraphQLClient,
    build_hyperdash_smart_money_payload,
)
from services.client_api.publish_realtime_smart_money import _load


ADDRESS = "0x0ad9e656d9e6211d0ea1c5462342e1fc94cc4cbf"
NOW = dt.datetime(2026, 8, 6, 12, 0, tzinfo=dt.timezone.utc)


def _trader() -> dict:
    return {
        "address": ADDRESS,
        "displayName": "Equity Whale",
        "verified": True,
        "portfolioGraph": [
            {"timestamp": int((NOW - dt.timedelta(days=30)).timestamp() * 1_000), "value": "0"},
            {"timestamp": int((NOW - dt.timedelta(days=7)).timestamp() * 1_000), "value": "5000"},
            {"timestamp": int(NOW.timestamp() * 1_000), "value": "12000"},
        ],
        "pnl": "12000",
        "perpsEquity": "250000",
        "winrate": 72.5,
        "pnlCohort": "Profitable",
        "sizeCohort": "Large",
        "totalTrades": 80,
        "totalLongTrades": 50,
        "totalShortTrades": 30,
        "totalWinningTrades": 58,
        "totalLosingTrades": 22,
        "sharpe": 2.4,
        "drawdown": 8.5,
        "copyScore": 88.25,
        "tag": "swing",
        "topAssets": [
            {"coin": "xyz:MU", "volume": 1_500_000, "pnl": 18_000},
            {"coin": "BTC", "volume": 8_000_000, "pnl": 30_000},
        ],
    }


def _positions(size: float = 100) -> dict:
    return {
        "requestedTs": int(NOW.timestamp() * 1_000),
        "bucketTs": int(NOW.timestamp() * 1_000),
        "positionsCount": 1,
        "totalUnrealizedPnl": 2500,
        "positions": [
            {
                "market": "xyz:MU",
                "size": size,
                "notionalSize": abs(size) * 150,
                "entryPrice": 145,
                "liquidationPrice": 95,
                "unrealizedPnl": 2500,
                "fundingPnl": -25,
            }
        ],
    }


class _Response:
    def __init__(self, payload: dict) -> None:
        self.payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict:
        return self.payload


class _Session:
    def __init__(self) -> None:
        self.headers: dict[str, str] = {}
        self.requests: list[dict] = []

    def post(self, url, *, json, headers, timeout):
        self.requests.append({"url": url, "json": json, "headers": headers, "timeout": timeout})
        if json["operationName"] == "GetSystemGroupTraders":
            return _Response({"data": {"getSystemGroupTraders": [_trader()]}})
        return _Response(
            {"data": {"wallet0": _positions()}}
        )


class _FakeHyperdash:
    def equity_traders(self, **_):
        return [_trader()]

    def trader_positions(self, addresses, **_):
        return {str(next(iter(addresses))).lower(): _positions()}


class _PartialPositionsHyperdash:
    def equity_traders(self, **_):
        second = {**_trader(), "address": "0x1111111111111111111111111111111111111111"}
        return [_trader(), second]

    def trader_positions(self, addresses, **_):
        del addresses
        return {ADDRESS: _positions(140)}


class _FailingHyperdash:
    def equity_traders(self, **_):
        raise RuntimeError("temporary Hyperdash outage")


def test_client_fetches_equity_cohort_and_batches_position_queries() -> None:
    session = _Session()
    client = HyperdashGraphQLClient(session=session, retries=1)

    traders = client.equity_traders(limit=10)
    positions = client.trader_positions([ADDRESS], timestamp_ms=int(NOW.timestamp() * 1_000))

    assert traders[0]["copyScore"] == 88.25
    assert positions[ADDRESS]["positions"][0]["market"] == "xyz:MU"
    assert session.requests[0]["headers"]["X-Apollo-Operation-Name"] == "GetSystemGroupTraders"
    assert "$address0: String!" in session.requests[1]["json"]["query"]


def test_normalizer_uses_hyperdash_copy_score_and_only_tradfi_assets() -> None:
    payload = build_hyperdash_smart_money_payload(
        [_trader()],
        {ADDRESS: _positions()},
        generated_at=NOW,
    )
    wallet = payload["leaderboard"][0]

    assert payload["lookbackDays"] == 30
    assert payload["source"]["provider"] == "hyperdash"
    assert payload["scoringVersion"] == "hyperdash-copy-score"
    assert wallet["score"] == 88.25
    assert wallet["scoreSource"] == "hyperdash-copy-score"
    assert wallet["assetPerformance"] == [
        {"symbol": "MU", "netPnl": 18000.0, "fees": 0, "volume": 1500000.0, "trades": 0, "winRate": 0}
    ]
    assert set(wallet["periodMetrics"]) == {"1D", "7D", "30D"}
    assert wallet["positionSnapshotAt"] == NOW.isoformat()

    collections = build_hyperliquid_client_collections(payload)
    assert collections["smart-money"][0]["score"] == 88.25
    assert collections["smart-money"][0]["source"] == "hyperdash"


def test_normalizer_diffs_hyperdash_snapshots_into_movement_events() -> None:
    previous = build_hyperdash_smart_money_payload(
        [_trader()],
        {ADDRESS: _positions(100)},
        generated_at=NOW - dt.timedelta(minutes=1),
    )
    current = build_hyperdash_smart_money_payload(
        [_trader()],
        {ADDRESS: _positions(140)},
        generated_at=NOW,
        previous_payload=previous,
    )
    collections = build_hyperliquid_client_collections(current)

    assert len(collections["smart-money-movements"]) == 1
    movement = collections["smart-money-movements"][0]
    assert movement["action"] == "increased"
    assert movement["ticker"] == "MU"
    assert movement["evidenceURL"] == f"https://hyperdash.com/trader/{ADDRESS}"
    assert collections["smart-money-evidence"][0]["ticker"] == "MU"
    assert collections["smart-money-evidence"][0]["entryCount"] == 1


def test_live_job_publishes_atomic_hyperdash_manifest(tmp_path) -> None:
    output = tmp_path / "smart-money.json"
    client_dir = tmp_path / "client"
    health = tmp_path / "health.json"

    result = run_hyperdash_live(
        output_path=str(output),
        client_output_dir=str(client_dir),
        health_output_path=str(health),
        max_cycles=1,
        client=_FakeHyperdash(),
    )

    collections, _ = _load(client_dir)
    manifest = json.loads((client_dir / "smart-money-live-manifest.json").read_text())
    assert result["activeSource"] == "hyperdash"
    assert result["readiness"]["ready"] is True
    assert manifest["source"] == "hyperdash"
    assert len(collections["smart-money"]) == 1
    assert "smart-money-evidence" in manifest["collections"]


def test_live_job_preserves_cached_positions_when_batch_is_partial(tmp_path) -> None:
    output = tmp_path / "smart-money.json"
    health = tmp_path / "health.json"
    previous = build_hyperdash_smart_money_payload(
        [{**_trader(), "address": "0x1111111111111111111111111111111111111111"}],
        {"0x1111111111111111111111111111111111111111": _positions(75)},
        generated_at=NOW,
    )
    output.write_text(json.dumps(previous))

    result = run_hyperdash_live(
        output_path=str(output),
        health_output_path=str(health),
        max_cycles=1,
        client=_PartialPositionsHyperdash(),
    )

    payload = json.loads(output.read_text())
    cached_wallet = next(
        row for row in payload["leaderboard"] if row["address"].startswith("0x1111")
    )
    assert result["positionCoverage"] == 0.5
    assert cached_wallet["currentPositions"][0]["signedSize"] == 75
    assert cached_wallet["positionSnapshotAt"] == NOW.isoformat()


def test_live_job_keeps_recent_hyperdash_snapshot_during_outage(tmp_path) -> None:
    output = tmp_path / "smart-money.json"
    client_dir = tmp_path / "client"
    health = tmp_path / "health.json"
    run_hyperdash_live(
        output_path=str(output),
        client_output_dir=str(client_dir),
        health_output_path=str(health),
        max_cycles=1,
        client=_FakeHyperdash(),
    )

    result = run_hyperdash_live(
        output_path=str(output),
        client_output_dir=str(client_dir),
        health_output_path=str(health),
        max_cycles=1,
        client=_FailingHyperdash(),
    )

    assert result["activeSource"] == "hyperdash_cached"
    assert "hyperdash_fetch_failed" in result["readiness"]["reasons"]
    assert json.loads(output.read_text())["source"]["provider"] == "hyperdash"
