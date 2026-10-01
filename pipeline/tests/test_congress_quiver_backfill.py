from __future__ import annotations

import datetime as dt
import io
import json
import sqlite3
import zipfile

import pytest

from pipeline.jobs.congress_quiver_backfill.capture import (
    CaptureError,
    active_profile_urls,
    capture,
    parse_house_index,
    parse_roster,
    parse_trades,
    select_members,
)


SINCE = dt.date(2025, 9, 29)
UNTIL = dt.date(2026, 9, 29)
MEMBER = {
    "member_id": "P000197", "name": "Nancy Pelosi", "chamber": "House",
    "party": "D", "profile_url": "https://www.quiverquant.com/congresstrading/politician/Nancy%20Pelosi-P000197",
}


def _dashboard() -> str:
    roster = [{"name": "Nancy Pelosi", "bioguideID": "P000197", "chamber": "House", "party": "D"}]
    return (
        "const allCongressMembers = JSON.parse(`" + json.dumps(roster) + "`);"
        '<table id="mostActiveTradersTable"><tbody><tr><td>'
        '<a href="../congresstrading/politician/Nancy Pelosi-P000197">Nancy</a>'
        "</td></tr></tbody></table>"
    )


def _profile() -> str:
    rows = [
        ["BE", "Purchase", "2026-08-21T00:00:00", "2026-07-28T00:00:00",
         "Purchased shares", None, "Nancy Pelosi", "House-P000197-223", "BLOOM ENERGY",
         "Stock", "$500,001 - $1,000,000", "House", "D", "Industrials", 750000],
        ["BE", "Sale", "2026-08-21T00:00:00", "2025-09-28T00:00:00",
         "Old", None, "Nancy Pelosi", "House-P000197-100", "BLOOM ENERGY",
         "Stock", "$1,001 - $15,000", "House", "D", "Industrials", 8000],
    ]
    return "let tradeData = " + json.dumps(rows) + ";"


def _house_zip() -> bytes:
    xml = (
        "<FinancialDisclosure><Member><First>Nancy</First><Last>Pelosi</Last>"
        "<FilingType>P</FilingType><FilingDate>9/30/2025</FilingDate>"
        "<DocID>20035411</DocID></Member></FinancialDisclosure>"
    )
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        archive.writestr("2025FD.xml", xml)
    return stream.getvalue()


def test_quiver_roster_and_trades() -> None:
    assert parse_roster(_dashboard()) == [MEMBER]
    assert len(active_profile_urls(_dashboard())) == 1
    trades = parse_trades(_profile(), MEMBER, SINCE, UNTIL)
    assert len(trades) == 1
    assert trades[0]["transaction_date"] == "2026-07-28"
    assert trades[0]["filing_date"] == "2026-08-21"
    assert trades[0]["amount_low"] == 500001
    assert trades[0]["amount_high"] == 1000000
    assert trades[0]["verification"] == "vendor_only"


def test_numeric_vendor_id_requires_matching_member_name() -> None:
    numeric_id = _profile().replace("House-P000197-223", "House-9115821-1")
    assert len(parse_trades(numeric_id, MEMBER, SINCE, UNTIL)) == 1
    wrong_name = numeric_id.replace("Nancy Pelosi", "Another Senator")
    with pytest.raises(CaptureError, match="another member"):
        parse_trades(wrong_name, MEMBER, SINCE, UNTIL)


def test_house_index_and_resumable_capture(tmp_path) -> None:
    filings = parse_house_index(_house_zip(), 2025, SINCE, UNTIL)
    assert len(filings) == 1
    assert filings[0]["pdf_url"].endswith("/2025/20035411.pdf")
    calls = []

    def get_html(url):
        calls.append(url)
        return _dashboard() if url.endswith("/congresstrading/") else _profile()

    db_path = tmp_path / "trades.sqlite"
    report_path = tmp_path / "report.json"
    args = dict(
        since=SINCE, until=UNTIL, db_path=db_path, report_path=report_path,
        max_members=1, delay=0, get_html=get_html,
        get_house_index=lambda year: _house_zip() if year == 2025 else _empty_house_zip(2026),
    )
    first = capture(**args)
    assert first["trade_count"] == 1
    assert first["house_ptr_filings_in_filing_window"] == 1
    assert not first["capture_complete"]
    capture(**args)
    assert len(calls) == 3  # Dashboard twice; member page only once.
    with sqlite3.connect(db_path) as db:
        assert db.execute("SELECT COUNT(*) FROM trades").fetchone()[0] == 1
    with pytest.raises(CaptureError, match="different date window"):
        capture(**{**args, "since": dt.date(2025, 9, 30)})


def test_legal_name_alias_does_not_select_another_same_surname() -> None:
    roster = [
        {**MEMBER, "name": "Lizzie Fletcher", "member_id": "F000468"},
        {**MEMBER, "name": "Ernie Fletcher", "member_id": "F000441", "chamber": "Inactive"},
    ]
    filings = [{"first": "Elizabeth", "last": "Fletcher"}]
    selected, unmatched = select_members(roster, set(), filings)
    assert [m["member_id"] for m in selected] == ["F000468"]
    assert unmatched == []


def _empty_house_zip(year: int) -> bytes:
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        archive.writestr(f"{year}FD.xml", "<FinancialDisclosure/>")
    return stream.getvalue()
