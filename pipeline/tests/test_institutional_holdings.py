from datetime import datetime, timezone
import json

import pytest

from pipeline.domain.institutional_holdings.registry import HoldingsSubject, SUBJECTS
from pipeline.jobs.institutional_holdings.__main__ import reuse_verified_snapshot, run
from pipeline.platforms.institutional_holdings.sec_13f import (
    FilingError, SEC13FClient, changes, filings, latest_reports, parse_cover, parse_information_table,
)


SUBJECT = HoldingsSubject("example", "Famous Manager", "celebrity", 1234567,
                          "Example Capital", "Example Capital 13F, not personal holdings")
NOW = datetime(2026, 9, 29, tzinfo=timezone.utc)


def test_curated_registry_meets_subject_coverage_and_has_unique_ids():
    assert sum(subject.kind == "celebrity" for subject in SUBJECTS) >= 15
    assert sum(subject.kind == "institution" for subject in SUBJECTS) >= 30
    assert len({subject.id for subject in SUBJECTS}) == len(SUBJECTS)
    assert all(subject.filer_cik > 0 and subject.filer_name for subject in SUBJECTS)


def test_peter_thiel_uses_thiel_macro_filing_without_personal_trade_attribution():
    subject = next(subject for subject in SUBJECTS if subject.id == "peter-thiel")
    assert (subject.title, subject.kind, subject.filer_cik, subject.filer_name) == (
        "Peter Thiel", "celebrity", 1562087, "Thiel Macro LLC")
    assert "not Thiel's personal trades" in subject.attribution


def test_leopold_uses_verified_situational_awareness_manager():
    subject = next(subject for subject in SUBJECTS if subject.id == "leopold-aschenbrenner")
    assert (subject.title, subject.kind, subject.filer_cik, subject.filer_name) == (
        "Leopold Aschenbrenner", "celebrity", 2045724, "Situational Awareness LP")
    assert "not Aschenbrenner's personal trades or live holdings" in subject.attribution


def test_tristan_social_claim_is_not_a_verified_13f_manager():
    assert not any(subject.id == "tristan-thompson" for subject in SUBJECTS)


def test_duan_uses_verified_hh_manager_not_a_personal_portfolio():
    subject = next(subject for subject in SUBJECTS if subject.id == "duan-yongping")
    assert (subject.title, subject.kind, subject.filer_cik, subject.filer_name) == (
        "Duan Yongping", "celebrity", 1759760, "H&H International Investment, LLC")
    assert "not Duan's complete personal portfolio" in subject.attribution


def cover(*, amendment=False, amendment_type="RESTATEMENT", form=None):
    form = form or ("13F-HR/A" if amendment else "13F-HR")
    return f'''<edgarSubmission xmlns="urn:sec"><headerData><submissionType>{form}</submissionType>
    <filerInfo><filer><credentials><cik>0001234567</cik></credentials></filer>
    <periodOfReport>06-30-2026</periodOfReport></filerInfo></headerData><formData>
    <coverPage><isAmendment>{str(amendment).lower()}</isAmendment>
    <amendmentInfo><amendmentType>{amendment_type}</amendmentType></amendmentInfo>
    <filingManager><name>Example Capital</name></filingManager>
    <reportType>13F HOLDINGS REPORT</reportType></coverPage></formData></edgarSubmission>'''.encode()


def table():
    return b'''<informationTable xmlns="urn:sec"><infoTable>
    <nameOfIssuer>ACME INC</nameOfIssuer><titleOfClass>COM</titleOfClass><cusip>000000001</cusip>
    <value>100000</value><shrsOrPrnAmt><sshPrnamt>200</sshPrnamt><sshPrnamtType>SH</sshPrnamtType></shrsOrPrnAmt>
    <investmentDiscretion>SOLE</investmentDiscretion></infoTable><infoTable>
    <nameOfIssuer>ACME INC</nameOfIssuer><titleOfClass>COM</titleOfClass><cusip>000000001</cusip>
    <value>50000</value><shrsOrPrnAmt><sshPrnamt>100</sshPrnamt><sshPrnamtType>SH</sshPrnamtType></shrsOrPrnAmt>
    <investmentDiscretion>SOLE</investmentDiscretion></infoTable></informationTable>'''


def test_submissions_cik_and_notice_are_not_empty_portfolio():
    payload = {"cik": 1234567, "filings": {"recent": {
        "form": ["13F-NT", "13F-HR/A", "13F-HR", "13F-HR"],
        "accessionNumber": ["0001234567-26-000004", "0001234567-26-000003",
                            "0001234567-26-000002", "0001234567-26-000001"],
        "filingDate": ["2026-08-14", "2026-05-17", "2026-05-15", "2026-02-14"],
        "reportDate": ["2026-06-30", "2026-03-31", "2026-03-31", "2025-12-31"]}}}
    rows = filings(payload, cik=1234567)
    selected, notice = latest_reports(rows)
    assert notice["form"] == "13F-NT"
    assert [row["accession"] for row in selected] == ["0001234567-26-000003", "0001234567-26-000001"]
    with pytest.raises(FilingError, match="cik_mismatch"):
        filings(payload, cik=2222222)


def test_submissions_loads_older_sec_history_shard():
    client = SEC13FClient("ops@example.com", min_interval=0)
    main = {"cik": 1234567, "filings": {"recent": {
        "form": ["13F-HR"], "accessionNumber": ["0001234567-26-000001"],
        "filingDate": ["2026-08-14"], "reportDate": ["2026-06-30"]},
        "files": [{"name": "CIK0001234567-submissions-001.json", "filingFrom": "2020-01-01",
                   "filingTo": "2024-12-31"}]}}
    older = {"form": ["13F-HR"], "accessionNumber": ["0001234567-24-000001"],
             "filingDate": ["2024-02-14"], "reportDate": ["2023-12-31"]}
    client.get = lambda url: json.dumps(older if url.endswith("-001.json") else main).encode()
    assert [row["periodOfReport"] for row in client.submissions(1234567, earliest_period="2023-09-30")] == [
        "2026-06-30", "2023-12-31"]


def test_13f_parser_aggregates_rows_but_preserves_options():
    parsed = parse_information_table(table())
    assert len(parsed) == 1
    assert parsed[0]["reportedShares"] == "300"
    assert parsed[0]["reportedValueUsd"] == 150000
    previous = [{**parsed[0], "reportedShares": "100"}]
    assert changes(parsed, previous)[0]["classification"] == "reported_shares_increased"
    option_table = table().replace(b"<investmentDiscretion>", b"<putCall>Call</putCall><investmentDiscretion>", 1)
    assert len(parse_information_table(option_table)) == 2


def test_cover_rejects_wrong_identity_and_unmergeable_amendment():
    assert parse_cover(cover(amendment=True), cik=1234567, period="2026-06-30", form="13F-HR/A")["managerName"] == "Example Capital"
    with pytest.raises(FilingError, match="amendment_requires_review"):
        parse_cover(cover(amendment=True, amendment_type="NEW HOLDINGS"), cik=1234567,
                    period="2026-06-30", form="13F-HR/A")
    supplemental = parse_cover(cover(amendment=True, amendment_type="NEW HOLDINGS"), cik=1234567,
                               period="2026-06-30", form="13F-HR/A", allow_new_holdings=True)
    assert supplemental["amendmentType"] == "NEW HOLDINGS"
    with pytest.raises(FilingError, match="cover_identity_mismatch"):
        parse_cover(cover(), cik=9999999, period="2026-06-30", form="13F-HR")
    with pytest.raises(FilingError, match="xml_external_entity"):
        parse_information_table(b'<!DOCTYPE x [<!ENTITY x SYSTEM "file:///etc/passwd">]><informationTable/>')


class FakeClient:
    requests = 0
    fail = False

    def submissions(self, cik):
        if self.fail:
            raise FilingError("sec_http_503")
        return [{"cik": cik, "form": "13F-HR", "accession": "0001234567-26-000002",
                 "filedAt": "2026-08-14", "periodOfReport": "2026-06-30"},
                {"cik": cik, "form": "13F-HR", "accession": "0001234567-26-000001",
                 "filedAt": "2026-05-15", "periodOfReport": "2026-03-31"}]

    def report(self, row):
        shares = "300" if row["periodOfReport"] == "2026-06-30" else "100"
        return {**row, "managerName": "Example Capital", "filingUrl": "https://www.sec.gov/example",
                "informationTableUrl": "https://www.sec.gov/table", "reportType": "13F HOLDINGS REPORT",
                "holdings": [{"issuer": "ACME INC", "cusip": "000000001", "securityClass": "COM",
                              "option": None, "shareType": "SH", "discretion": "SOLE", "reportedShares": shares,
                              "reportedValueUsd": 100000}]}


def test_refresh_labels_filer_and_keeps_last_good_file_on_error(tmp_path):
    client = FakeClient()
    result = run(output_dir=tmp_path, subjects=(SUBJECT,), client=client, now=NOW)
    assert result["subjects"][0]["status"] == "current_quarterly_report"
    payload = json.loads((tmp_path / "example.json").read_text())
    assert payload["title"] == "Famous Manager"
    assert payload["filerName"] == "Example Capital"
    assert payload["changes"][0]["reportedShareChange"] == "200"
    original = (tmp_path / "example.json").read_bytes()
    client.fail = True
    result = run(output_dir=tmp_path, subjects=(SUBJECT,), client=client, now=NOW)
    assert result["subjects"][0]["retainedPriorSnapshot"] is True
    assert (tmp_path / "example.json").read_bytes() == original


def test_combination_prior_disables_share_change_inference(tmp_path):
    class CombinationClient(FakeClient):
        def report(self, row):
            result = super().report(row)
            if row["periodOfReport"] == "2026-03-31":
                result["reportType"] = "13F COMBINATION REPORT"
            return result

    run(output_dir=tmp_path, subjects=(SUBJECT,), client=CombinationClient(), now=NOW)
    payload = json.loads((tmp_path / "example.json").read_text())
    assert payload["changes"] == []
    assert payload["comparisonPeriod"] is None
    assert "prior_report_not_comparable" in payload["limitations"]


def test_sec_client_enforces_size_limit_even_without_content_length(monkeypatch):
    class Response:
        status_code = 200
        headers = {}

        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

        def iter_content(self, _size):
            yield b"a" * 11

    class Session:
        def get(self, *_args, **kwargs):
            assert kwargs["allow_redirects"] is False
            assert kwargs["stream"] is True
            return Response()

    monkeypatch.setattr("pipeline.platforms.institutional_holdings.sec_13f.MAX_RESPONSE_BYTES", 10)
    client = SEC13FClient("ops@example.com", session=Session(), min_interval=0)
    with pytest.raises(FilingError, match="document_too_large"):
        client.get("https://data.sec.gov/submissions/CIK0001234567.json")


def test_partial_refresh_retains_other_subjects_in_manifest(tmp_path):
    other = HoldingsSubject("other", "Other Fund", "institution", 1234567,
                            "Example Capital", "Example Capital 13F")
    client = FakeClient()
    run(output_dir=tmp_path, subjects=(SUBJECT, other), client=client, now=NOW)
    result = run(output_dir=tmp_path, subjects=(SUBJECT,), client=client, now=NOW)
    assert result["refreshedSubjectIds"] == ["example"]
    assert {item["id"] for item in result["subjects"]} == {"example", "other"}


def test_shared_filer_is_fetched_once_and_keeps_distinct_attribution(tmp_path):
    manager = HoldingsSubject("manager", "Manager", "celebrity", 1234567,
                              "Example Capital", "Manager association, not personal trades")
    client = FakeClient()
    calls = []
    original = client.submissions
    client.submissions = lambda cik: (calls.append(cik), original(cik))[1]
    result = run(output_dir=tmp_path, subjects=(SUBJECT, manager), client=client, now=NOW)
    assert calls == [1234567]
    assert len(result["subjects"]) == 2
    attributed = json.loads((tmp_path / "manager.json").read_text())
    assert attributed["subjectId"] == "manager"
    assert attributed["attribution"] == "Manager association, not personal trades"
    assert attributed["filingUrl"] == json.loads((tmp_path / "example.json").read_text())["filingUrl"]


def test_offline_shared_filer_copy_preserves_check_time_and_rejects_other_cik(tmp_path):
    run(output_dir=tmp_path, subjects=(SUBJECT,), client=FakeClient(), now=NOW)
    manager = HoldingsSubject("manager", "Manager", "celebrity", 1234567,
                              "Example Capital", "Not personal holdings")
    copy = reuse_verified_snapshot(tmp_path, manager, SUBJECT)
    assert copy["checkedAt"] == NOW.isoformat()
    assert copy["attribution"] == "Not personal holdings"
    manifest = json.loads((tmp_path / "manifest.json").read_text())
    assert manifest["reusedSubjectIds"] == ["manager"]
    assert manifest["refreshedSubjectIds"] == []
    with pytest.raises(FilingError, match="cik_mismatch"):
        reuse_verified_snapshot(tmp_path, SUBJECTS[0], SUBJECT)
