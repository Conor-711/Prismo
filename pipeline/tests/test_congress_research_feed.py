from dataclasses import dataclass

import pytest

from pipeline.jobs.congress_capture.research_feed import (
    PORTRAIT_OVERRIDES,
    build_research_feed,
    portrait_for,
    require_institutional_coverage,
)


@dataclass(frozen=True)
class Member:
    member_id: str
    name: str
    photo_url: str | None


def test_export_requires_15_public_figures_and_30_institutions():
    feed = {"subjects": ([{"kind": "celebrity"}] * 15
                         + [{"kind": "institution"}] * 30)}
    require_institutional_coverage(feed)
    feed["subjects"].pop()
    with pytest.raises(ValueError, match="institution: 29/30"):
        require_institutional_coverage(feed)


def trade(trade_id: str, member_id: str | None, name: str, ticker: str,
          *, action: str = "Purchase", date: str = "2026-09-21") -> dict:
    return {"trade_id": trade_id, "member_id": member_id, "member_name": name,
            "ticker": ticker, "action": action, "transaction_date": "2026-09-05",
            "filing_date": date, "evidence_url": "https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/2026/1.pdf",
            "amount_low": 1001, "amount_high": 15000, "asset_name": "Example Corp",
            "data_source": "house_clerk_pdf_auto_extracted"}


def test_wrong_upstream_portrait_is_corrected_by_bioguide_identity():
    member = Member("house_aprilmcclain_delaney", "April McClain Delaney",
                    "https://unitedstates.github.io/images/congress/225x275/D000620.jpg")
    assert portrait_for(member) == PORTRAIT_OVERRIDES[member.member_id]
    assert portrait_for(member)[0] == "M001232"


def test_feed_deduplicates_by_trade_and_bioguide_and_preserves_provenance():
    members = [Member("house_member_a", "Member A",
                      "https://unitedstates.github.io/images/congress/225x275/A000123.jpg"),
               Member("house_member_a_alias", "Member A Jr",
                      "https://unitedstates.github.io/images/congress/225x275/A000123.jpg"),
               Member("house_unknown", "Unknown", None)]
    rows = [trade("1", "house_member_a", "Member A", "AAPL"),
            trade("1", "house_member_a", "Member A", "AAPL"),
            trade("2", "house_member_a_alias", "Member A Jr", "MSFT", action="Sale (Full)"),
            trade("3", "house_unknown", "Unknown", "NVDA"),
            trade("4", None, "Member A", "GOOG"),
            trade("5", "house_member_a", "Member A", ""),
            trade("6", "house_member_a", "Member A", "TSLA", date="2026-09-04")]
    feed, report = build_research_feed(rows, members, snapshot_at="2026-09-29T00:00:00Z")
    assert report["published_trades"] == 3
    assert report["subjects"] == 1
    assert [event["subjectID"] for event in feed["events"]] == ["politician:A000123"] * 3
    assert feed["events"][0]["action"] == "buy"
    assert feed["events"][0]["sourceURL"].endswith("/1.pdf")
    assert "pending review" in feed["events"][0]["sourceNote"]
    assert feed["subjects"][0]["metrics"] is None
    assert report["skipped"] == {"duplicate_or_missing_id": 1, "invalid_date_order": 1,
                                  "unresolved_portrait": 1, "unsupported_ticker": 1}
