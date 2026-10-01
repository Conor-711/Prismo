from copy import deepcopy
from datetime import date

import pytest

from pipeline.domain.institutional_holdings.registry import SUBJECTS
from pipeline.jobs.institutional_holdings.backfill_subjects import (
    collect, merge_selected, selected_content, selected_readback,
)
from pipeline.platforms.institutional_holdings.sec_13f import FilingError


SUBJECT = next(subject for subject in SUBJECTS if subject.id == "leopold-aschenbrenner")


class Client:
    def submissions(self, cik, *, earliest_period):
        assert cik == 2045724
        return [{"cik": cik, "form": "13F-HR", "accession": "0000935836-26-000418",
                 "periodOfReport": "2026-06-30", "filedAt": "2026-08-14"}]

    def report(self, row, *, allow_new_holdings):
        return {**row, "managerName": SUBJECT.filer_name, "reportType": "13F HOLDINGS REPORT",
                "filingUrl": "https://www.sec.gov/Archives/edgar/data/2045724/example-index.html",
                "holdings": [{"issuer": "MICRON TECHNOLOGY", "cusip": "595112103",
                              "securityClass": "COM", "shareType": "SH", "option": None,
                              "discretion": "SOLE", "reportedShares": "10", "reportedValueUsd": 1000}]}


def test_selected_backfill_merges_without_losing_other_sources_or_existing_metrics(tmp_path):
    incoming, coverage = collect((SUBJECT,), Client(), tmp_path, date(2026, 10, 1))
    assert coverage == {SUBJECT.id: ["2026-06-30"]}
    assert incoming["events"][0]["occurredDay"] == "2026-06-30"
    assert incoming["events"][0]["displayDay"] == "2026-08-14"
    live = deepcopy(incoming)
    research = {"method": "three_year_open_positions_v1", "asOf": "2026-10-01",
                "sourceSince": "2023-10-01", "latestMarketDate": "2026-09-30",
                "candidatePositions": 1, "pricedPositions": 1, "directionalWins": 2,
                "directionalLosses": 1, "directionalObservations": 3,
                "directionalWinRate": 2 / 3, "meanOpenReturn": .2,
                "openPositionPositiveRate": 1.0}
    live["subjects"][0]["research"] = research
    live["subjects"][0]["metrics"] = {"wins": 2, "losses": 1, "trackedReturn": .2}
    live["subjects"].append({"id": "celebrity:peter-thiel", "kind": "celebrity",
                             "name": "Peter Thiel", "metrics": None})
    other = {**live["events"][0], "id": "13f:unrelated", "subjectID": "celebrity:peter-thiel"}
    live["events"].append(other)
    merged = merge_selected(live, incoming)
    assert other in merged["events"]
    subject = next(subject for subject in merged["subjects"] if subject["id"] == incoming["subjects"][0]["id"])
    assert subject["metrics"] == live["subjects"][0]["metrics"]
    assert subject["research"] == research
    assert merge_selected(merged, incoming) == merged
    assert live["subjects"][0]["research"] == research


def test_selected_backfill_rejects_wrong_reporting_manager(tmp_path):
    class WrongClient(Client):
        def report(self, row, *, allow_new_holdings):
            return {**super().report(row, allow_new_holdings=allow_new_holdings),
                    "managerName": "Fourth Pick Ventures, LLC"}

    with pytest.raises(FilingError, match="reporting_manager_mismatch"):
        collect((SUBJECT,), WrongClient(), tmp_path, date(2026, 10, 1))


def test_selected_backfill_rejects_unverified_identity(tmp_path):
    incoming, _ = collect((SUBJECT,), Client(), tmp_path, date(2026, 10, 1))
    incoming["subjects"][0]["name"] = "Tristan Thompson"
    with pytest.raises(ValueError, match="Unverified selected subject identity"):
        merge_selected({"subjects": [], "events": []}, incoming)


def test_selected_backfill_keeps_newer_live_prices(tmp_path):
    incoming, _ = collect((SUBJECT,), Client(), tmp_path, date(2026, 10, 1))
    live = deepcopy(incoming)
    live["events"][0].update({"latestPriceDay": "2026-09-30", "eventDayAdjustedClose": 100,
                               "latestAdjustedClose": 120, "priceBasis": "adjusted"})
    merged = merge_selected(live, incoming)
    assert merged["events"][0]["latestAdjustedClose"] == 120


def test_bounded_readback_checks_full_counts_and_selected_content(tmp_path):
    incoming, _ = collect((SUBJECT,), Client(), tmp_path, date(2026, 10, 1))
    live = deepcopy(incoming)
    live["subjects"].append({"id": "institution:other", "kind": "institution", "name": "Other"})
    live["events"].append({**incoming["events"][0], "id": "other-event", "subjectID": "institution:other"})
    actual = selected_content(live, [incoming["subjects"][0]["id"]])
    assert actual["subjectCount"] == 2 and actual["eventCount"] == 2
    assert actual["subjects"] == incoming["subjects"]
    assert actual["events"] == incoming["events"]
    assert actual["snapshotAt"] == incoming["snapshotAt"]

    class Connection:
        def execute(self, query, params):
            assert "jsonb_array_length" in query and "jsonb_array_elements" in query
            assert params == ([incoming["subjects"][0]["id"]],) * 2
            assert "SELECT payload FROM" not in query
            return self

        def fetchone(self):
            return (actual,)

    assert selected_readback(Connection(), [incoming["subjects"][0]["id"]]) == actual


def test_bounded_readback_requires_existing_production_row():
    class Connection:
        def execute(self, *args):
            return self

        def fetchone(self):
            return None

    with pytest.raises(RuntimeError, match="No production"):
        selected_readback(Connection(), ["celebrity:duan-yongping"])
