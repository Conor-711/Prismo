from __future__ import annotations

import datetime as dt
import json

import pytest

from pipeline.platforms.congress.disclosed_capitol import fetch_trades, save_snapshot


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self.payload


def test_fetch_trades_paginates_without_putting_key_in_url() -> None:
    requests = []

    def getter(url, *, params, headers, timeout):
        requests.append((url, params, headers))
        page = [{"id": 1, "disclosure_date": "2026-09-27"}] if len(requests) == 1 else []
        return FakeResponse(page)

    rows, pages, truncated = fetch_trades(
        "secret-key",
        since=dt.date(2026, 9, 1),
        until=dt.date(2026, 9, 28),
        page_size=1,
        max_pages=2,
        getter=getter,
    )

    assert rows == [{"id": 1, "disclosure_date": "2026-09-27"}]
    assert pages == 2
    assert truncated is False
    assert "secret-key" not in requests[0][0]
    assert requests[0][2]["DC-API-Key"] == "secret-key"
    assert requests[1][1]["offset"] == 1


def test_fetch_trades_reports_page_cap() -> None:
    def getter(url, *, params, headers, timeout):
        return FakeResponse([{"id": 1}])

    rows, pages, truncated = fetch_trades(
        "secret", since=dt.date(2026, 9, 1), until=dt.date(2026, 9, 28),
        page_size=1, max_pages=1, getter=getter,
    )
    assert len(rows) == 1
    assert pages == 1
    assert truncated is True


def test_fetch_trades_rejects_excessive_credit_spend_before_request() -> None:
    with pytest.raises(ValueError, match="credit_budget"):
        fetch_trades(
            "secret", since=dt.date(2026, 9, 1), until=dt.date(2026, 9, 28),
            page_size=1000, max_pages=1,
        )


def test_fetch_trades_rejects_unexpected_payload() -> None:
    def getter(url, *, params, headers, timeout):
        return FakeResponse({"error": "failed"})

    with pytest.raises(ValueError, match="unexpected trades response"):
        fetch_trades(
            "secret", since=dt.date(2026, 9, 1), until=dt.date(2026, 9, 28),
            getter=getter,
        )


def test_save_snapshot_upserts_by_vendor_id(tmp_path) -> None:
    path = tmp_path / "trades.json"
    dates = {"since": dt.date(2026, 9, 1), "until": dt.date(2026, 9, 28)}
    save_snapshot(
        path, [{"id": 1, "disclosure_date": "2026-09-20", "ticker": "AAPL"}],
        pages=1, possibly_truncated=False, **dates,
    )
    snapshot = save_snapshot(
        path,
        [
            {"id": 1, "disclosure_date": "2026-09-20", "ticker": "NVDA"},
            {"id": 2, "disclosure_date": "2026-09-28", "ticker": "META"},
        ],
        pages=1, possibly_truncated=False, **dates,
    )

    assert snapshot["total_count"] == 2
    assert snapshot["trades"][0]["id"] == 2
    assert snapshot["trades"][1]["ticker"] == "NVDA"
    assert snapshot["missing_owner_count"] == 2
    assert snapshot["missing_filing_url_count"] == 2
    assert snapshot["complete_through"] == "2026-09-28"
    assert json.loads(path.read_text()) == snapshot

    partial = save_snapshot(
        path, [{"id": 3, "disclosure_date": "2026-09-29"}],
        since=dt.date(2026, 9, 22), until=dt.date(2026, 9, 29),
        pages=1, possibly_truncated=True,
    )
    assert partial["complete_through"] == "2026-09-28"
