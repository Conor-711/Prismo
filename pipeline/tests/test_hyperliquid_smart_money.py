from __future__ import annotations

import datetime as dt
import json
import sqlite3

from pipeline.domain.smart_voice.hyperliquid import (
    _compact_period_metrics,
    _market_rollup,
    _recent_rows,
    _smart_wallet_cutoff,
    build_hyperliquid_client_collections,
    hyperliquid_candidate_addresses,
    latest_positions,
    movement_from_trade,
    score_wallet_fills,
)
from pipeline.platforms.hyperliquid.client import HyperliquidInfoClient
from pipeline.platforms.hyperliquid.storage import HyperliquidStore
from pipeline.platforms.hyperliquid.stream import (
    HyperliquidTradeStream,
    parse_all_dexs_state_message,
    parse_trade_message,
)
from pipeline.platforms.hyperliquid.normalizer import (
    TradFiInstrument,
    discover_tradfi_instruments,
    normalize_fill,
    normalize_ledger_updates,
    normalize_portfolio,
    normalize_wallet_state,
)
from pipeline.jobs.smart_voice.hyperliquid import (
    _fill_limit_reason,
    _select_wallets_for_fill_sync,
    _select_wallets_for_profile_sync,
    _sync_wallet_fills,
    _sync_wallet_profiles,
    _wallet_seeds,
)
from pipeline.jobs.smart_voice.hyperliquid_live import (
    _prune_pending_active,
    _runtime_health,
    _select_live_fill_addresses,
    run_hyperliquid_live,
)


def instrument() -> TradFiInstrument:
    return TradFiInstrument(
        coin="xyz:NVDA",
        dex="xyz",
        symbol="NVDA",
        category="stocks",
        sz_decimals=3,
        max_leverage=20,
        mark_px=200,
        oracle_px=200,
        open_interest=10_000,
        day_notional_volume=5_000_000,
    )


def test_client_payload_is_limited_to_recent_month_and_bounded_detail() -> None:
    points = [[index, float(index)] for index in range(180)]
    periods = _compact_period_metrics(
        {
            "1D": {"accountValueHistory": points, "pnlHistory": points},
            "7D": {"accountValueHistory": points, "pnlHistory": points},
            "30D": {"accountValueHistory": points, "pnlHistory": points},
            "ALL": {"accountValueHistory": points, "pnlHistory": points},
        }
    )
    assert list(periods) == ["1D", "7D", "30D"]
    assert len(periods["30D"]["accountValueHistory"]) == 90
    assert periods["30D"]["accountValueHistory"][0] == points[0]
    assert periods["30D"]["accountValueHistory"][-1] == points[-1]

    generated_at = dt.datetime(2026, 8, 6, tzinfo=dt.timezone.utc)
    rows = [
        {
            "id": f"recent-{index}",
            "time": (generated_at - dt.timedelta(hours=index)).isoformat(),
        }
        for index in range(25)
    ]
    rows.append({"id": "old", "time": "2026-06-01T00:00:00+00:00"})
    recent = _recent_rows(
        rows,
        generated_at=generated_at,
        timestamp_key="time",
        limit=20,
    )
    assert len(recent) == 20
    assert recent[0]["id"] == "recent-0"
    assert all(row["id"] != "old" for row in recent)


def fill(index: int, pnl: float, *, crossed: bool = True) -> dict[str, object]:
    day = 1 + index // 2
    return {
        "address": "0xabc",
        "tid": str(index),
        "coin": "xyz:NVDA",
        "dex": "xyz",
        "symbol": "NVDA",
        "category": "stocks",
        "side": "A" if index % 2 else "B",
        "direction": "Close Long",
        "price": 200.0,
        "size": 10.0,
        "notional": 2_000.0,
        "time_ms": index,
        "created_day": f"2026-07-{day:02d}",
        "position_after": 10.0,
        "closed_pnl": pnl,
        "fee": 0.1,
        "crossed": crossed,
        "liquidation": 0,
    }


def test_discovers_only_official_tradfi_categories() -> None:
    meta = {
        "universe": [
            {"name": "xyz:NVDA", "szDecimals": 3, "maxLeverage": 20},
            {"name": "xyz:BTC", "szDecimals": 4, "maxLeverage": 20},
        ]
    }
    contexts = [
        {"markPx": "200", "oraclePx": "199", "openInterest": "10", "dayNtlVlm": "1000"},
        {"markPx": "100000", "oraclePx": "100000", "openInterest": "5", "dayNtlVlm": "500"},
    ]
    rows = discover_tradfi_instruments(
        [("xyz:NVDA", "stocks"), ("xyz:BTC", "crypto")],
        {"xyz": (meta, contexts)},
    )
    assert [row.coin for row in rows] == ["xyz:NVDA"]


def test_parses_all_dex_account_state_snapshot() -> None:
    address = "0x" + "1" * 40
    parsed = parse_all_dexs_state_message(json.dumps({
        "channel": "allDexsClearinghouseState",
        "data": {
            "user": address.upper(),
            "clearinghouseStates": [
                ["xyz", {"marginSummary": {"accountValue": "100"}, "assetPositions": []}],
                ["km", {"marginSummary": {"accountValue": "0"}, "assetPositions": []}],
            ],
        },
    }))
    assert parsed is not None
    assert parsed[0] == address
    assert [row[0] for row in parsed[1]] == ["xyz", "km"]


def test_trade_stream_updates_live_subscription_set_without_reconnect() -> None:
    class Connection:
        def __init__(self) -> None:
            self.messages: list[dict[str, object]] = []

        def send(self, message: str) -> None:
            self.messages.append(json.loads(message))

    stream = HyperliquidTradeStream(proxy_url="", reconnect=False)
    connection = Connection()
    stream._subscriptions = {"xyz:MU"}
    stream._connection = connection
    stream.update_subscriptions(["xyz:NVDA"])

    assert stream._subscriptions == {"xyz:NVDA"}
    assert connection.messages == [
        {
            "method": "unsubscribe",
            "subscription": {"type": "trades", "coin": "xyz:MU"},
        },
        {
            "method": "subscribe",
            "subscription": {"type": "trades", "coin": "xyz:NVDA"},
        },
    ]


def test_normalized_fill_reconstructs_position_after_trade() -> None:
    row = normalize_fill(
        "0x0000000000000000000000000000000000000001",
        {
            "coin": "xyz:NVDA",
            "tid": 1,
            "px": "200",
            "sz": "3",
            "side": "A",
            "time": 1_783_000_000_000,
            "startPosition": "8",
            "dir": "Close Long",
            "closedPnl": "30",
        },
        {"xyz:NVDA": instrument()},
    )
    assert row is not None
    assert row["position_after"] == 5
    positions = latest_positions([row])
    assert positions[(row["address"], "xyz:NVDA")]["position"] == 5


def test_normalized_fill_rejects_invalid_trade_facts() -> None:
    base = {
        "coin": "xyz:NVDA",
        "tid": 1,
        "px": "200",
        "sz": "3",
        "side": "B",
        "time": 1_783_000_000_000,
        "startPosition": "0",
    }
    assert normalize_fill("0xabc", {**base, "side": ""}, {"xyz:NVDA": instrument()}) is None
    assert normalize_fill("0xabc", {**base, "px": "0"}, {"xyz:NVDA": instrument()}) is None


def test_paginated_fill_fetch_advances_cursor_and_preserves_every_page() -> None:
    class FakeClient(HyperliquidInfoClient):
        def __init__(self) -> None:
            self.starts: list[int] = []

        def user_fills_by_time(self, _address: str, *, start_ms: int, end_ms=None, aggregate_by_time=False):
            self.starts.append(start_ms)
            if start_ms <= 10:
                return [
                    {"coin": "xyz:NVDA", "tid": 1, "hash": "0x1", "time": 10},
                    {"coin": "xyz:NVDA", "tid": 2, "hash": "0x2", "time": 20},
                ]
            if start_ms <= 21:
                return [{"coin": "xyz:NVDA", "tid": 3, "hash": "0x3", "time": 30}]
            return []

    client = FakeClient()
    rows, limited = client.paginated_user_fills_by_time(
        "0x" + "1" * 40,
        start_ms=10,
        end_ms=40,
        page_size=2,
    )
    assert [row["tid"] for row in rows] == [1, 2, 3]
    assert client.starts == [10, 21]
    assert limited is False


def test_info_client_weights_large_fill_responses_conservatively() -> None:
    assert HyperliquidInfoClient._response_weight(
        {"type": "userFillsByTime"},
        [{} for _ in range(2_000)],
    ) == 120
    assert HyperliquidInfoClient._response_weight({"type": "clearinghouseState"}, {}) == 20


def test_trade_stream_parser_ignores_non_trade_channels() -> None:
    assert parse_trade_message('{"channel":"subscriptionResponse","data":{}}') == []
    trades = parse_trade_message(
        '{"channel":"trades","data":[{"coin":"xyz:NVDA","tid":1,"time":10}]}'
    )
    assert trades == [{"coin": "xyz:NVDA", "tid": 1, "time": 10}]


def test_trade_stream_explicit_http_proxy_is_forwarded_to_websocket_client() -> None:
    stream = HyperliquidTradeStream(proxy_url="http://user:pass@127.0.0.1:7897")
    assert stream._proxy_options() == {
        "http_proxy_host": "127.0.0.1",
        "http_proxy_port": 7897,
        "proxy_type": "http",
        "http_proxy_auth": ("user", "pass"),
    }


def test_profitable_directional_wallet_scores_above_losing_wallet() -> None:
    profitable = score_wallet_fills("0xabc", [fill(index, 80.0) for index in range(20)])
    losing = score_wallet_fills("0xdef", [fill(index, -80.0) for index in range(20)])
    assert profitable["eligible"] is True
    assert losing["eligible"] is True
    assert profitable["score"] > 60
    assert losing["score"] < 40


def test_truncated_high_frequency_wallet_is_excluded() -> None:
    result = score_wallet_fills("0xabc", [fill(index, 1.0, crossed=False) for index in range(20)], truncated=True)
    assert result["classification"] == "algorithmic"
    assert result["eligible"] is False


def test_incomplete_wallet_history_is_excluded_from_formal_scoring() -> None:
    result = score_wallet_fills(
        "0xabc",
        [fill(index, 80.0) for index in range(20)],
        history_complete=False,
    )
    assert result["history_complete"] is False
    assert result["classification"] == "incomplete"
    assert result["eligible"] is False


def test_fill_policy_limit_is_distinct_from_exchange_source_limit() -> None:
    assert _fill_limit_reason(fill_count=2_000, history_limited=True) == "policy_algorithmic_2000"
    assert _fill_limit_reason(fill_count=1_999, history_limited=True) == "source_10000"
    assert _fill_limit_reason(fill_count=2_000, history_limited=False) is None


def test_smart_wallet_cutoff_never_backfills_below_minimum_score() -> None:
    selected, threshold = _smart_wallet_cutoff(
        [
            {"address": "0x1", "eligible": True, "score": 54.9},
            {"address": "0x2", "eligible": True, "score": 52.0},
        ]
    )
    assert selected == set()
    assert threshold == 55.0


def test_wallet_discovery_uses_only_the_aggressing_side() -> None:
    buyer = "0x" + "1" * 40
    seller = "0x" + "2" * 40

    class FakeClient:
        def recent_trades(self, _coin: str):
            return [
                {"side": "B", "px": "200", "sz": "2", "users": [buyer, seller]},
                {"side": "A", "px": "201", "sz": "1", "users": [buyer, seller]},
            ]

    seeds = _wallet_seeds(FakeClient(), [instrument()], max_markets=1, api_pause=False)
    assert {row["address"] for row in seeds} == {buyer, seller}
    assert next(row for row in seeds if row["address"] == buyer)["notional"] == 400
    assert next(row for row in seeds if row["address"] == seller)["notional"] == 201


def test_wallet_state_preserves_public_position_risk_fields() -> None:
    state, positions = normalize_wallet_state(
        "0x" + "1" * 40,
        "xyz",
        {
            "marginSummary": {"accountValue": "10000", "totalNtlPos": "25000", "totalMarginUsed": "2500"},
            "withdrawable": "5000",
            "assetPositions": [
                {
                    "position": {
                        "coin": "xyz:NVDA",
                        "szi": "-10",
                        "positionValue": "2000",
                        "entryPx": "210",
                        "unrealizedPnl": "100",
                        "returnOnEquity": "0.5",
                        "liquidationPx": "280",
                        "leverage": {"value": 5},
                        "marginUsed": "400",
                        "maxLeverage": 20,
                        "cumFunding": {"allTime": "8", "sinceOpen": "3"},
                    }
                }
            ],
        },
        {"xyz:NVDA": instrument()},
        observed_at="2026-08-05T00:00:00+00:00",
    )
    assert state["account_value"] == 10000
    assert positions[0]["size"] == -10
    assert positions[0]["mark_px"] == 200
    assert positions[0]["liquidation_px"] == 280
    assert positions[0]["funding_since_open"] == 3


def test_portfolio_and_ledger_normalizers_keep_auditable_history() -> None:
    periods = normalize_portfolio(
        [["month", {"accountValueHistory": [[1, "100"]], "pnlHistory": [[1, "12"]], "vlm": "500"}]]
    )
    assert periods[0]["period"] == "month"
    assert periods[0]["pnl_history"] == [[1, 12.0]]

    address = "0x" + "1" * 40
    ledger = normalize_ledger_updates(
        address,
        [{"time": 1_783_000_000_000, "hash": "0xabc", "delta": {"type": "send", "user": "0x" + "2" * 40, "destination": address, "usdcValue": "900", "token": "USDC"}}],
    )
    assert ledger[0]["direction"] == "in"
    assert ledger[0]["amount_usd"] == 900


def test_market_rollup_does_not_average_incompatible_contract_prices() -> None:
    market = _market_rollup(
        [
            {"symbol": "MU", "category": "stocks", "coin": "xyz:MU", "dex": "xyz", "mark_px": 900, "open_interest": 10, "day_notional_volume": 1000},
            {"symbol": "MU", "category": "stocks", "coin": "km:MU", "dex": "km", "mark_px": 90, "open_interest": 5, "day_notional_volume": 100},
        ]
    )[("MU", "stocks")]
    assert market["mark_px"] == 900
    assert market["coin_marks"] == {"xyz:MU": 900.0, "km:MU": 90.0}


def test_position_transition_uses_real_before_and_after_notional() -> None:
    increase = movement_from_trade({"price": 200, "startPosition": 2, "positionAfter": 5})
    assert increase == {
        "action": "increased",
        "direction": "bullish",
        "notionalBefore": 400.0,
        "notionalAfter": 1_000.0,
        "notionalChange": 600.0,
    }
    reduce_short = movement_from_trade({"price": 200, "startPosition": -5, "positionAfter": -2})
    assert reduce_short["action"] == "reduced"
    assert reduce_short["direction"] == "bullish"
    assert reduce_short["notionalChange"] == -600.0
    flip = movement_from_trade({"price": 200, "startPosition": 2, "positionAfter": -3})
    assert flip["action"] == "flipped"
    assert flip["direction"] == "bearish"


def test_store_preserves_immutable_account_and_position_snapshots(tmp_path) -> None:
    address = "0x" + "1" * 40
    store = HyperliquidStore(tmp_path / "hyperliquid.db")
    with store.connect() as connection:
        store.ensure_tables(connection)
        store.upsert_wallet_seeds(
            connection,
            [{"address": address, "notional": 1_000, "trade_count": 1, "coins": {"xyz:NVDA"}}],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        state, positions = normalize_wallet_state(
            address,
            "xyz",
            {
                "marginSummary": {"accountValue": "10000", "totalNtlPos": "1000"},
                "assetPositions": [{"position": {"coin": "xyz:NVDA", "szi": "5", "positionValue": "1000"}}],
            },
            {"xyz:NVDA": instrument()},
            observed_at="2026-08-05T00:00:00+00:00",
        )
        store.upsert_wallet_state(connection, state)
        store.replace_wallet_positions(
            connection,
            address=address,
            dex="xyz",
            rows=positions,
            observed_at="2026-08-05T00:00:00+00:00",
        )
        closed_state, closed_positions = normalize_wallet_state(
            address,
            "xyz",
            {"marginSummary": {"accountValue": "10200", "totalNtlPos": "0"}, "assetPositions": []},
            {"xyz:NVDA": instrument()},
            observed_at="2026-08-05T00:05:00+00:00",
        )
        store.upsert_wallet_state(connection, closed_state)
        store.replace_wallet_positions(
            connection,
            address=address,
            dex="xyz",
            rows=closed_positions,
            observed_at="2026-08-05T00:05:00+00:00",
        )
        state_count = connection.execute("SELECT COUNT(*) FROM hl_wallet_state_snapshot").fetchone()[0]
        position_rows = connection.execute(
            "SELECT size FROM hl_wallet_position_snapshot ORDER BY observed_at"
        ).fetchall()
    assert state_count == 2
    assert [row[0] for row in position_rows] == [5.0, 0.0]


def test_trade_tape_discovers_both_sides_once(tmp_path) -> None:
    buyer = "0x" + "1" * 40
    seller = "0x" + "2" * 40
    store = HyperliquidStore(tmp_path / "hyperliquid.db")
    trade = {
        "coin": "xyz:NVDA",
        "tid": 7,
        "time": 1_783_000_000_000,
        "side": "B",
        "px": "200",
        "sz": "5",
        "users": [buyer, seller],
        "hash": "0xabc",
    }
    with store.connect() as connection:
        store.ensure_tables(connection)
        inserted, addresses = store.upsert_trade_tape(
            connection,
            [trade],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        repeated, _ = store.upsert_trade_tape(
            connection,
            [trade],
            observed_at="2026-08-05T00:01:00+00:00",
        )
        wallets = connection.execute(
            "SELECT address, discovery_trade_count FROM hl_wallet ORDER BY address"
        ).fetchall()
    assert inserted == 1
    assert repeated == 0
    assert addresses == {buyer, seller}
    assert [(row[0], row[1]) for row in wallets] == [(buyer, 1), (seller, 1)]


def test_profile_selection_rotates_oldest_wallets_instead_of_fixed_score_order(tmp_path) -> None:
    addresses = ["0x" + str(index) * 40 for index in range(1, 5)]
    store = HyperliquidStore(tmp_path / "hyperliquid.db")
    with store.connect() as connection:
        store.ensure_tables(connection)
        store.upsert_wallet_seeds(
            connection,
            [
                {"address": address, "notional": 10_000, "trade_count": 1, "coins": {"xyz:NVDA"}}
                for address in addresses
            ],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        connection.execute(
            "UPDATE hl_wallet SET profile_synced_at='2026-08-05T00:03:00+00:00' WHERE address=?",
            (addresses[0],),
        )
        connection.execute(
            "UPDATE hl_wallet SET profile_synced_at='2026-08-05T00:01:00+00:00' WHERE address=?",
            (addresses[1],),
        )
        connection.execute(
            "UPDATE hl_wallet SET profile_synced_at='2026-08-05T00:02:00+00:00' WHERE address=?",
            (addresses[2],),
        )
        selected = _select_wallets_for_profile_sync(
            connection,
            eligible_addresses=addresses,
            active_addresses={addresses[0]},
            limit=2,
        )
        assert selected == [addresses[3], addresses[1]]

        connection.execute(
            "UPDATE hl_wallet SET profile_synced_at=NULL WHERE address IN (?, ?)",
            (addresses[0], addresses[2]),
        )
        selected = _select_wallets_for_profile_sync(
            connection,
            eligible_addresses=addresses,
            active_addresses={addresses[0]},
            limit=2,
        )
    assert selected == [addresses[0], addresses[2]]


def test_initial_fill_backfill_prioritizes_highest_observed_activity(tmp_path) -> None:
    low = "0x" + "1" * 40
    medium = "0x" + "2" * 40
    high = "0x" + "3" * 40
    store = HyperliquidStore(tmp_path / "hyperliquid.db")
    with store.connect() as connection:
        store.ensure_tables(connection)
        store.upsert_wallet_seeds(
            connection,
            [
                {"address": low, "notional": 100, "trade_count": 5, "coins": {"xyz:NVDA"}},
                {"address": medium, "notional": 5_000, "trade_count": 6, "coins": {"xyz:NVDA"}},
                {"address": high, "notional": 50_000, "trade_count": 10, "coins": {"xyz:NVDA"}},
            ],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        selected = _select_wallets_for_fill_sync(
            connection,
            limit=3,
            now=dt.datetime(2026, 8, 5, tzinfo=dt.timezone.utc),
        )

    assert [row["address"] for row in selected] == [high, medium, low]


def test_candidate_universe_is_bounded_to_highest_observed_activity(tmp_path) -> None:
    store = HyperliquidStore(tmp_path / "hyperliquid.db")
    with store.connect() as connection:
        store.ensure_tables(connection)
        store.upsert_wallet_seeds(
            connection,
            [
                {
                    "address": "0x" + f"{index:040x}",
                    "notional": float(10_000 + index),
                    "trade_count": 5,
                    "coins": {"xyz:NVDA"},
                }
                for index in range(510)
            ],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        candidates = hyperliquid_candidate_addresses(connection)

    assert len(candidates) == 500
    assert candidates[0] == "0x" + f"{509:040x}"
    assert candidates[-1] == "0x" + f"{10:040x}"


def test_wallet_lane_retry_is_persisted_deferred_and_cleared_on_success(tmp_path) -> None:
    failed = "0x" + "1" * 40
    available = "0x" + "2" * 40
    observed_at = dt.datetime(2026, 8, 5, tzinfo=dt.timezone.utc)
    store = HyperliquidStore(tmp_path / "hyperliquid.db")
    with store.connect() as connection:
        store.ensure_tables(connection)
        store.upsert_wallet_seeds(
            connection,
            [
                {"address": failed, "notional": 50_000, "trade_count": 10, "coins": {"xyz:NVDA"}},
                {"address": available, "notional": 1_000, "trade_count": 5, "coins": {"xyz:NVDA"}},
            ],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        store.mark_wallet_error(
            connection,
            failed,
            "429 Too Many Requests",
            stage="fills",
            observed_at=observed_at,
        )
        deferred = connection.execute(
            "SELECT fills_retry_count, fills_retry_after, fills_last_error FROM hl_wallet WHERE address=?",
            (failed,),
        ).fetchone()
        selected = _select_wallets_for_fill_sync(
            connection,
            limit=2,
            now=observed_at,
        )
        store.mark_wallet_synced(
            connection,
            failed,
            synced_at="2026-08-05T00:02:00+00:00",
            truncated=False,
            cursor_ms=1,
            backfill_complete=True,
        )
        cleared = connection.execute(
            "SELECT fills_retry_count, fills_retry_after, fills_last_error, last_error FROM hl_wallet WHERE address=?",
            (failed,),
        ).fetchone()

    assert deferred[0] == 1
    assert deferred[1] == "2026-08-05T00:01:00+00:00"
    assert deferred[2] == "429 Too Many Requests"
    assert [row["address"] for row in selected] == [available]
    assert tuple(cleared) == (0, None, None, None)


def test_fill_sync_preserves_live_priority_and_terminally_marks_history_limit(tmp_path) -> None:
    addresses = ["0x" + "1" * 40, "0x" + "2" * 40]
    calls: list[str] = []
    now = dt.datetime(2026, 8, 5, tzinfo=dt.timezone.utc)

    class Client:
        pacing_enabled = False

        def paginated_user_fills_by_time(self, address: str, **_kwargs):
            assert _kwargs["max_fills"] == 2_000
            calls.append(address)
            return ([{
                "coin": "xyz:NVDA",
                "tid": len(calls),
                "hash": f"0x{len(calls)}",
                "time": int(now.timestamp() * 1_000),
                "px": "200",
                "sz": "2",
                "side": "B",
                "startPosition": "0",
                "dir": "Open Long",
                "closedPnl": "0",
            }], address == addresses[1])

        @staticmethod
        def suggested_fill_pause(_count: int) -> float:
            return 0.0

    store = HyperliquidStore(tmp_path / "hyperliquid.db")
    with store.connect() as connection:
        store.ensure_tables(connection)
        store.upsert_wallet_seeds(
            connection,
            [
                {"address": address, "notional": 10_000, "trade_count": 1, "coins": {"xyz:NVDA"}}
                for address in addresses
            ],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        result = _sync_wallet_fills(
            connection,
            client=Client(),
            store=store,
            instruments=[instrument()],
            now=now,
            lookback_days=30,
            max_wallets=2,
            api_pause=False,
            addresses=list(reversed(addresses)),
        )
        limited = connection.execute(
            """
            SELECT fills_backfill_complete, fills_truncated, fills_limit_reason
            FROM hl_wallet WHERE address=?
            """,
            (addresses[1],),
        ).fetchone()

    assert calls == list(reversed(addresses))
    assert result["successfulAddresses"] == list(reversed(addresses))
    assert tuple(limited) == (1, 1, "source_10000")


def test_profile_sync_uses_batched_all_dex_snapshot_without_rest_state_calls(tmp_path) -> None:
    address = "0x" + "3" * 40
    now = dt.datetime(2026, 8, 5, tzinfo=dt.timezone.utc)

    class Client:
        def clearinghouse_state(self, _address: str, *, dex: str = ""):
            raise AssertionError(f"unexpected REST state request for {dex}")

    class SnapshotClient:
        batches: list[list[str]] = []

        def account_state_snapshots(self, addresses):
            self.batches.append(list(addresses))
            return {
                address: [("xyz", {
                    "marginSummary": {
                        "accountValue": "10000",
                        "totalNtlPos": "2000",
                        "totalMarginUsed": "200",
                    },
                    "withdrawable": "8000",
                    "assetPositions": [{
                        "position": {
                            "coin": "xyz:NVDA",
                            "szi": "10",
                            "positionValue": "2000",
                            "unrealizedPnl": "50",
                            "leverage": {"value": 2},
                        }
                    }],
                })],
            }

    store = HyperliquidStore(tmp_path / "hyperliquid.db")
    snapshots = SnapshotClient()
    with store.connect() as connection:
        store.ensure_tables(connection)
        store.upsert_wallet_seeds(
            connection,
            [{"address": address, "notional": 1_000, "trade_count": 1, "coins": {"xyz:NVDA"}}],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        connection.execute(
            "UPDATE hl_wallet SET extended_profile_synced_at=? WHERE address=?",
            ("2026-08-05T00:00:00+00:00", address),
        )
        result = _sync_wallet_profiles(
            connection,
            client=Client(),
            store=store,
            instruments=[instrument()],
            addresses=[address],
            now=now,
            lookback_days=30,
            api_pause=False,
            state_snapshot_client=snapshots,
        )
        position = connection.execute(
            "SELECT size, position_value FROM hl_wallet_position WHERE address=?",
            (address,),
        ).fetchone()

    assert snapshots.batches == [[address]]
    assert result["profileWalletsSynced"] == 1
    assert tuple(position) == (10.0, 2000.0)


def test_live_fill_selection_prioritizes_all_qualified_and_bounds_discovery(tmp_path) -> None:
    qualified = "0x" + "1" * 40
    unknown_latest = "0x" + "2" * 40
    unknown_large = "0x" + "3" * 40
    stale = "0x" + "4" * 40
    store = HyperliquidStore(tmp_path / "hyperliquid.db")
    with store.connect() as connection:
        store.ensure_tables(connection)
        store.upsert_wallet_seeds(
            connection,
            [
                {"address": address, "notional": 10_000, "trade_count": 1, "coins": {"xyz:NVDA"}}
                for address in [qualified, unknown_latest, unknown_large, stale]
            ],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        active, candidates = _select_live_fill_addresses(
            connection,
            pending_active={
                qualified: (100, 10.0),
                unknown_latest: (300, 1.0),
                unknown_large: (200, 1_000.0),
            },
            eligible_addresses={qualified},
            max_active_wallets=2,
            candidate_backfill_per_cycle=1,
        )

    assert active == [qualified, unknown_latest]
    assert candidates == [stale]


def test_pending_live_wallets_are_pruned_after_activity_expires() -> None:
    pending = {
        "0xold": (0, 20_000.0),
        "0xnew": (1_800_001, 20_000.0),
    }
    expired = _prune_pending_active(pending, now_ms=1_800_001, max_age_minutes=30)
    assert expired == 1
    assert pending == {"0xnew": (1_800_001, 20_000.0)}


def test_runtime_health_uses_qualified_wallets_as_profile_coverage_denominator(tmp_path) -> None:
    addresses = ["0x" + "1" * 40, "0x" + "2" * 40]
    store = HyperliquidStore(tmp_path / "hyperliquid.db")

    class Stream:
        connected = True
        last_connected_at = "2026-08-05T00:00:00+00:00"
        last_message_at = "2026-08-05T00:00:09+00:00"
        last_trade_at = "2026-08-05T00:00:09+00:00"
        reconnect_count = 0
        last_error = None

    with store.connect() as connection:
        store.ensure_tables(connection)
        store.upsert_wallet_seeds(
            connection,
            [
                {"address": address, "notional": 10_000, "trade_count": 1, "coins": {"xyz:NVDA"}}
                for address in addresses
            ],
            observed_at="2026-08-05T00:00:00+00:00",
        )
        connection.execute(
            "UPDATE hl_wallet SET fills_backfill_complete=1, profile_synced_at=? WHERE address=?",
            ("2026-08-05T00:00:05+00:00", addresses[0]),
        )
        health = _runtime_health(
            connection,
            stats={
                "startedAt": "2026-08-05T00:00:00+00:00",
                "publishedAt": "2026-08-05T00:00:08+00:00",
                "qualifiedWallets": 2,
                "qualifiedProfiledWallets": 1,
                "instruments": 1,
            },
            stream=Stream(),
            now=dt.datetime(2026, 8, 5, 0, 0, 10, tzinfo=dt.timezone.utc),
            refresh_seconds=30,
            publish_seconds=60,
            running=True,
        )
    assert health["status"] == "healthy"
    assert health["coverage"]["fillBackfillCoverage"] == 0.5
    assert health["coverage"]["qualifiedProfileCoverage"] == 0.5
    assert health["stream"]["lastTradeAgeSeconds"] == 1
    assert health["readiness"] == {
        "realtime": True,
        "complete": False,
        "ready": False,
        "reasons": [
            "wallet_fill_catchup_incomplete",
            "qualified_profile_catchup_incomplete",
        ],
    }


def test_live_worker_ingests_trades_concurrently_and_commits_health(tmp_path) -> None:
    buyer = "0x" + "1" * 40
    seller = "0x" + "2" * 40
    trade_time = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1_000)

    class Client:
        pacing_enabled = False

        def set_pacing(self, enabled: bool) -> None:
            self.pacing_enabled = enabled

        def perp_categories(self):
            return [("xyz:NVDA", "stocks")]

        def meta_and_asset_contexts(self, _dex: str):
            return (
                {"universe": [{"name": "xyz:NVDA", "szDecimals": 3, "maxLeverage": 20}]},
                [{"markPx": "200", "oraclePx": "200", "openInterest": "10", "dayNtlVlm": "5000000"}],
            )

        def paginated_user_fills_by_time(self, address: str, **_kwargs):
            return ([{
                "coin": "xyz:NVDA",
                "tid": 9,
                "hash": "0xfill",
                "time": trade_time,
                "px": "200",
                "sz": "60",
                "side": "B",
                "startPosition": "0",
                "dir": "Open Long",
                "closedPnl": "0",
            }], False)

        @staticmethod
        def suggested_fill_pause(_count: int) -> float:
            return 0.0

    class Stream:
        connected = False
        last_connected_at = None
        last_message_at = None
        last_trade_at = None
        reconnect_count = 0
        last_error = None

        def iter_batches(self, _coins, *, stop_event):
            self.connected = True
            self.last_connected_at = dt.datetime.now(dt.timezone.utc).isoformat()
            self.last_message_at = self.last_connected_at
            self.last_trade_at = self.last_connected_at
            yield [{
                "coin": "xyz:NVDA",
                "tid": 7,
                "time": trade_time,
                "side": "B",
                "px": "200",
                "sz": "60",
                "users": [buyer, seller],
                "hash": "0xtrade",
            }]
            while not stop_event.wait(0.01):
                yield []
            self.connected = False

        def close(self) -> None:
            return None

    db = tmp_path / "live.db"
    health_path = tmp_path / "health.json"
    result = run_hyperliquid_live(
        db_path=str(db),
        output_path=str(tmp_path / "export.json"),
        client_output_dir=str(tmp_path / "client"),
        health_output_path=str(health_path),
        refresh_seconds=1,
        publish_seconds=1,
        candidate_backfill_per_cycle=1,
        max_active_wallets=1,
        max_profile_wallets=1,
        max_cycles=1,
        api_pause=False,
        client=Client(),
        trade_stream=Stream(),
    )
    with sqlite3.connect(db) as connection:
        assert connection.execute("SELECT COUNT(*) FROM hl_trade_tape").fetchone()[0] == 1
        assert connection.execute("SELECT COUNT(*) FROM hl_fill").fetchone()[0] == 1
    health = json.loads(health_path.read_text(encoding="utf-8"))
    assert result["streamTrades"] == 1
    assert result["tradeIngestStopped"] is True
    assert health["status"] == "stopped"
    assert health["coverage"]["fillBackfillCompleteWallets"] == 1


def test_client_projection_preserves_auditable_wallet_and_fill_identity() -> None:
    wallet = {
        "rank": 1,
        "address": "0x" + "1" * 40,
        "walletLabel": "Wallet 1111...1111",
        "tier": "Smart",
        "score": 88,
        "rawScore": 90,
        "confidence": 0.9,
        "classification": "directional",
        "style": "Swing",
        "sizeCohort": "Whale",
        "pnlCohort": "Highly Profitable",
        "accountValue": 500_000,
        "totalNotional": 250_000,
        "unrealizedPnl": 12_000,
        "currentLeverage": 0.5,
        "marginUtilization": 0.2,
        "withdrawable": 300_000,
        "fundingSinceOpen": -10,
        "fillCount": 20,
        "closedFillCount": 10,
        "activeDays": 8,
        "netPnl": 40_000,
        "longPnl": 30_000,
        "shortPnl": 10_000,
        "longBias": 0.75,
        "tradedNotional": 1_000_000,
        "winRate": 0.7,
        "profitFactor": 2.1,
        "sharpe": 1.8,
        "maxDrawdownPnl": 5_000,
        "maxDrawdownPercent": 0.1,
        "liquidationCount": 0,
        "makerRatio": 0.4,
        "tradeDuration": {"style": "Swing", "medianHoldHours": 48},
        "topMarkets": [{"symbol": "NVDA"}],
        "assetPerformance": [{"symbol": "NVDA", "netPnl": 20_000}],
        "currentPositions": [{"symbol": "NVDA", "direction": "Long", "notional": 250_000, "leverage": 2}],
        "periodMetrics": {},
        "recentTrades": [{
            "id": "fill-1", "symbol": "NVDA", "coin": "xyz:NVDA", "direction": "Open Long",
            "side": "Buy", "price": 200, "notional": 25_000, "startPosition": 0,
            "positionAfter": 125, "time": "2026-08-05T00:00:00Z", "hash": "0xabc",
        }],
        "capitalActivity": [],
        "components": {"performance": 90},
    }
    projected = build_hyperliquid_client_collections(
        {"generatedAt": "2026-08-05T00:00:00Z", "leaderboard": [wallet]}
    )
    assert projected["smart-money"][0]["id"] == wallet["address"]
    movement = projected["smart-money-movements"][0]
    assert movement["accountId"] == wallet["address"]
    assert movement["ticker"] == "NVDA"
    assert movement["notionalChange"] == 25_000
    assert movement["evidenceURL"].endswith("/0xabc")
    representative = projected["smart-money-evidence"][0]
    assert representative["ticker"] == "NVDA"
    assert representative["cumulativeEntryNotional"] == 25_000
    assert representative["priceEvidence"]["entryMarkers"][0]["price"] == 200


def test_client_projection_materializes_realtime_intelligence_and_relationship_signal() -> None:
    address = "0x" + "2" * 40
    wallet = {
        "rank": 1,
        "address": address,
        "walletLabel": "Wallet 2222...2222",
        "tier": "Smart",
        "score": 84,
        "style": "Swing",
        "sizeCohort": "Whale",
        "pnlCohort": "Profitable",
        "accountValue": 500_000,
        "totalNotional": 200_000,
        "unrealizedPnl": 10_000,
        "currentLeverage": 1,
        "marginUtilization": 0.2,
        "netPnl": 50_000,
        "winRate": 0.7,
        "sharpe": 1.5,
        "maxDrawdownPercent": 0.1,
        "profitFactor": 2,
        "fillCount": 30,
        "activeDays": 10,
        "longBias": 0.8,
        "tradeDuration": {"style": "Swing"},
        "periodMetrics": {},
        "currentPositions": [{"symbol": "NVDA", "direction": "Long", "notional": 200_000}],
        "assetPerformance": [{"symbol": "NVDA", "netPnl": 20_000}],
        "recentTrades": [{
            "id": "fill-live", "symbol": "NVDA", "coin": "xyz:NVDA", "direction": "Open Long",
            "side": "Buy", "price": 200, "startPosition": 0, "positionAfter": 1_000,
            "time": "2026-08-05T11:59:00Z", "hash": "0xlive",
        }],
        "capitalActivity": [],
        "components": {"performance": 80},
    }
    market = {
        "symbol": "NVDA",
        "category": "stocks",
        "markPrice": 201,
        "signals": {
            "1": {
                "qualifiedWallets": 3,
                "longWallets": 3,
                "shortWallets": 0,
                "netPositionNotional": 400_000,
                "signal": "bullish",
            }
        },
    }
    account_update = {
        "id": "10000000-0000-0000-0000-000000000001",
        "ticker": "NVDA",
        "companyName": "NVIDIA",
        "authorId": "x:bear",
        "authorName": "Bear Analyst",
        "score": 90,
        "direction": "bearish",
        "lifecycle": "new",
        "thesis": "Demand is slowing.",
        "publishedAt": "2026-08-05T11:50:00Z",
        "evidenceURL": "https://x.com/example/status/1",
    }
    projected = build_hyperliquid_client_collections(
        {
            "generatedAt": "2026-08-05T12:00:00Z",
            "leaderboard": [wallet],
            "markets": [market],
        },
        smart_account_updates=[account_update],
    )

    intelligence = projected["ticker-intelligence"][0]
    assert intelligence["ticker"] == "NVDA"
    assert intelligence["relationship"] == "divergence"
    assert intelligence["smartMoney"]["qualifiedAccountCount"] == 3
    signal = projected["portfolio-signals"][0]
    assert signal["kind"] == "divergence"
    assert signal["direction"] == "mixed"
    assert {item["source"] for item in signal["evidence"]} == {"smart_account", "smart_money"}
