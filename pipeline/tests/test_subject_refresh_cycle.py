from datetime import date

from pipeline.jobs.congress_capture.refresh_cycle import (
    content_changed, failed_subject_ids, preserve_newer_prices, retain_unavailable_sources,
    three_year_start,
)
from pipeline.jobs.congress_capture.backfill_three_years import combine_quarter, quarter_before
from pipeline.platforms.institutional_holdings.sec_13f import FilingError
import pytest
from pipeline.domain.institutional_holdings.registry import SUBJECTS


def subject(subject_id):
    kind = subject_id.split(":", 1)[0]
    return {"id": subject_id, "kind": kind, "name": subject_id,
            "avatarURL": None, "metrics": None}


def event(event_id, subject_id, *, source_note="", latest_price_day=None):
    item = {"id": event_id, "subjectID": subject_id, "ticker": "AAPL",
            "type": "trade" if subject_id.startswith("politician:") else "holding",
            "occurredDay": "2026-09-20", "displayDay": "2026-09-25",
            "sourceNote": source_note, "sourceURL": f"https://example.com/{event_id}",
            "action": "buy", "amountRange": "$1 - $2"}
    if latest_price_day:
        item.update({"eventDayAdjustedClose": 200.0, "latestAdjustedClose": 230.0,
                     "latestPriceDay": latest_price_day, "priceBasis": "adjusted"})
    return item


def test_retains_manual_house_rows_and_failed_sec_subjects():
    politician = "politician:A000001"
    institution = "institution:example"
    manual = event("house-gap", politician,
                   source_note="House Clerk filing; automatically extracted, pending review")
    vendor = event("vendor", politician, source_note="Official filing")
    holding = event("13f-old", institution)
    live = {"subjects": [subject(politician), subject(institution)],
            "events": [manual, vendor, holding]}
    candidate = {"subjects": [subject(politician)], "events": [vendor]}

    merged = retain_unavailable_sources(candidate, live, since=date(2025, 9, 30),
                                        congress_ok=True, failed_institutional={institution})
    assert {item["id"] for item in merged["events"]} == {"house-gap", "vendor", "13f-old"}
    assert {item["id"] for item in merged["subjects"]} == {politician, institution}

    unavailable = retain_unavailable_sources(candidate, live, since=date(2025, 9, 30),
                                             congress_ok=False, failed_institutional=set())
    assert {item["id"] for item in unavailable["events"]} == {"house-gap", "vendor"}


def test_does_not_regress_a_live_price_or_publish_a_timestamp_only_change():
    politician = "politician:A000001"
    live_event = event("trade", politician, latest_price_day="2026-09-29")
    live = {"schemaVersion": 1, "snapshotAt": "2026-09-29T00:00:00+00:00",
            "subjects": [subject(politician)], "events": [live_event]}
    candidate = {**live, "snapshotAt": "2026-09-30T00:00:00+00:00",
                 "events": [event("trade", politician)]}
    merged = preserve_newer_prices(candidate, live)
    assert merged["events"] == live["events"]
    assert not content_changed(merged, live)


def test_refresh_preserves_published_research_on_matching_subject():
    actor = subject("politician:A000001")
    actor["research"] = {"method": "three_year_open_positions_v1", "asOf": "2026-09-30"}
    live = {"subjects": [actor], "events": []}
    candidate = {"subjects": [subject(actor["id"])], "events": []}
    assert preserve_newer_prices(candidate, live)["subjects"][0]["research"] == actor["research"]
    candidate["subjects"][0]["name"] = "Changed identity"
    assert "research" not in preserve_newer_prices(candidate, live)["subjects"][0]


def test_refresh_retains_verified_holding_ticker_and_more_specific_source_note():
    institution = "institution:example"
    live_event = {**event("13f-current", institution, latest_price_day="2026-09-29"),
                  "cusip": "123456789",
                  "sourceNote": "Manager 13F; Stale 13F; report period 2025-09-30"}
    candidate_event = {**event("13f-current", institution), "cusip": "123456789",
                       "ticker": None, "sourceNote": "Manager 13F"}
    live = {"subjects": [subject(institution)], "events": [live_event]}
    candidate = {"subjects": [subject(institution)], "events": [candidate_event]}
    assert preserve_newer_prices(candidate, live)["events"] == live["events"]
    richer = {**candidate_event, "sourceNote": "Manager 13F; Partial 13F combination report"}
    assert preserve_newer_prices({**candidate, "events": [richer]}, live)["events"][0]["sourceNote"] == richer["sourceNote"]


def test_failed_filers_map_back_to_display_subject_ids():
    selected = SUBJECTS[:2]
    assert failed_subject_ids(selected, {selected[0].id}) == {
        f"{selected[0].kind}:{selected[0].id}"
    }


def test_does_not_duplicate_a_house_gap_later_covered_by_the_vendor():
    politician = "politician:A000001"
    manual = event("house-gap", politician,
                   source_note="House Clerk filing; automatically extracted, pending review")
    vendor = {**manual, "id": "vendor", "sourceNote": "Official filing"}
    live = {"subjects": [subject(politician)], "events": [manual]}
    candidate = {"subjects": [subject(politician)], "events": [vendor]}
    merged = retain_unavailable_sources(candidate, live, since=date(2025, 9, 30),
                                        congress_ok=True, failed_institutional=set())
    assert [item["id"] for item in merged["events"]] == ["vendor"]


def test_three_year_window_uses_calendar_years_and_prior_quarter_baseline():
    assert three_year_start(date(2026, 9, 30)) == date(2023, 9, 30)
    assert three_year_start(date(2028, 2, 29)) == date(2025, 2, 28)
    assert quarter_before(date(2023, 9, 30)) == date(2023, 6, 30)


def test_refresh_keeps_older_verified_13f_history_but_replaces_refiled_period():
    institution = "institution:example"
    older = {**event("older", institution), "occurredDay": "2024-12-31"}
    superseded = {**event("superseded", institution), "occurredDay": "2026-06-30"}
    current = {**event("current", institution), "occurredDay": "2026-06-30"}
    live = {"subjects": [subject(institution)], "events": [older, superseded]}
    candidate = {"subjects": [subject(institution)], "events": [current]}
    merged = retain_unavailable_sources(candidate, live, since=date(2023, 9, 30),
                                        congress_ok=True, failed_institutional=set())
    assert {item["id"] for item in merged["events"]} == {"older", "current"}


def test_restated_13f_base_and_new_holdings_are_combined_without_double_counting():
    row = lambda cusip: {"cusip": cusip, "securityClass": "COM", "option": None,
                         "shareType": "SH", "discretion": "SOLE"}
    def report(accession, form, amendment, filed, holdings):
        return {"accession": accession, "form": form, "amendmentType": amendment,
                "periodOfReport": "2025-12-31", "filedAt": filed, "holdings": holdings}
    original = report("original", "13F-HR", None, "2026-02-10", [row("AAA")])
    restated = report("restated", "13F-HR/A", "RESTATEMENT", "2026-02-11", [row("BBB")])
    added = report("added", "13F-HR/A", "NEW HOLDINGS", "2026-03-01", [row("CCC")])
    combined, pieces = combine_quarter([added, original, restated])
    assert {holding["cusip"] for holding in combined["holdings"]} == {"BBB", "CCC"}
    assert [piece["accession"] for piece in pieces] == ["restated", "added"]
    first = {**row("AAA"), "issuer": "ACME", "reportedShares": "100", "reportedValueUsd": 1000}
    extra = {**first, "reportedShares": "20", "reportedValueUsd": 200}
    combined, _ = combine_quarter([report("base", "13F-HR", None, "2026-02-10", [first]),
                                   report("add", "13F-HR/A", "NEW HOLDINGS", "2026-03-01", [extra])])
    assert combined["holdings"][0]["reportedShares"] == "120"
    assert combined["holdings"][0]["reportedValueUsd"] == 1200
    early_add = report("early", "13F-HR/A", "NEW HOLDINGS", "2026-02-10", [first])
    later_restatement = report("later", "13F-HR/A", "RESTATEMENT", "2026-02-20", [extra])
    combined, pieces = combine_quarter([original, early_add, later_restatement])
    assert [piece["accession"] for piece in pieces] == ["later"]
    assert combined["holdings"] == [extra]
    with pytest.raises(FilingError, match="identity_conflict"):
        combine_quarter([report("base", "13F-HR", None, "2026-02-10", [first]),
                         report("bad", "13F-HR/A", "NEW HOLDINGS", "2026-03-01",
                                [{**extra, "issuer": "OTHER"}])])
