from __future__ import annotations

import datetime as dt
import uuid

from pipeline.domain.smart_voice.smart_money_evidence import (
    build_smart_money_representative_evidence,
    representative_market_ranges,
)


ACCOUNT = "0xaccount"


def movement(
    market: str,
    action: str,
    before: float,
    after: float,
    *,
    hour: int,
    price: float,
) -> dict:
    return {
        "id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{market}:{action}:{hour}")),
        "accountId": ACCOUNT,
        "accountDisplayName": "Clara",
        "avatarVariant": 1,
        "ticker": market.split(":")[-1],
        "market": market,
        "action": action,
        "direction": "bullish" if market != "xyz:TSLA" else "bearish",
        "notionalBefore": before,
        "notionalAfter": after,
        "price": price,
        "observedAt": f"2026-08-01T{hour:02d}:00:00Z",
        "evidenceURL": "https://example.com/evidence",
    }


def test_representative_entries_rank_only_new_exposure_and_keep_exact_market_price() -> None:
    movements = [
        movement("xyz:NVDA", "opened", 0, 50_000, hour=1, price=180),
        movement("xyz:NVDA", "increased", 50_000, 80_000, hour=2, price=182),
        movement("xyz:TSLA", "opened", 0, 70_000, hour=3, price=320),
        movement("xyz:MU", "opened", 0, 20_000, hour=4, price=140),
        movement("xyz:AAPL", "opened", 0, 10_000, hour=5, price=210),
        movement("xyz:NVDA", "reduced", 80_000, 10_000, hour=6, price=184),
        movement("xyz:TSLA", "closed", 70_000, 0, hour=7, price=318),
    ]
    candles = {
        "xyz:NVDA": [
            {"t": 1_754_006_400_000, "o": "179", "h": "183", "l": "178", "c": "182", "v": "1000"},
        ],
        "xyz:TSLA": [
            {"t": 1_754_006_400_000, "o": "318", "h": "322", "l": "317", "c": "320", "v": "800"},
        ],
        "xyz:MU": [
            {"t": 1_754_006_400_000, "o": "138", "h": "142", "l": "137", "c": "140", "v": "600"},
        ],
    }
    signals = [{
        "id": ACCOUNT,
        "displayName": "Clara",
        "avatarVariant": 1,
        "assetPerformance": [
            {"symbol": "NVDA", "netPnl": 12_000},
            {"symbol": "TSLA", "netPnl": -3_000},
        ],
    }]

    evidence = build_smart_money_representative_evidence(
        signals,
        movements,
        candles_by_market=candles,
    )

    assert [row["ticker"] for row in evidence] == ["NVDA", "TSLA", "MU"]
    assert evidence[0]["cumulativeEntryNotional"] == 80_000
    assert evidence[0]["entryCount"] == 2
    assert evidence[0]["assetNetPnl"] == 12_000
    assert evidence[0]["priceEvidence"]["market"] == "xyz:NVDA"
    assert evidence[0]["priceEvidence"]["candles"][0]["close"] == 182
    assert [row["price"] for row in evidence[0]["priceEvidence"]["entryMarkers"]] == [180, 182]
    assert all(row["action"] not in {"reduced", "closed"} for item in evidence for row in item["priceEvidence"]["entryMarkers"])


def test_ranges_and_markers_are_bounded() -> None:
    movements = [
        movement("xyz:NVDA", "opened" if index == 0 else "increased", index * 1_000, (index + 1) * 1_000, hour=index, price=180 + index)
        for index in range(12)
    ]
    evidence = build_smart_money_representative_evidence(
        [],
        movements,
        candles_by_market={
            "xyz:NVDA": [
                {"t": 1_754_006_400_000, "o": "179", "h": "183", "l": "178", "c": "182", "v": "1000"},
            ]
        },
        marker_limit=10,
    )
    ranges = representative_market_ranges(movements)

    assert len(evidence[0]["priceEvidence"]["entryMarkers"]) == 10
    assert set(ranges) == {"xyz:NVDA"}
    start, end = ranges["xyz:NVDA"]
    assert start == dt.datetime(2026, 7, 29, tzinfo=dt.timezone.utc)
    assert end == dt.datetime(2026, 8, 11, 11, tzinfo=dt.timezone.utc)


def test_representative_evidence_omits_markets_without_price_candles() -> None:
    movements = [movement("xyz:NVDA", "opened", 0, 50_000, hour=1, price=180)]

    assert build_smart_money_representative_evidence([], movements) == []
