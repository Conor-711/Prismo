"""Fetch and parse bounded, public SEC 13F holdings reports."""
from __future__ import annotations

from collections import defaultdict
from datetime import date
from decimal import Decimal, InvalidOperation
import re
import time
from xml.etree import ElementTree

import requests


ACCESSION = re.compile(r"[0-9]{10}-[0-9]{2}-[0-9]{6}\Z")
SAFE_XML = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,200}\.xml\Z", re.IGNORECASE)
SAFE_SUBMISSIONS = re.compile(r"CIK[0-9]{10}-submissions-[0-9]{3}\.json\Z")
FORMS = {"13F-HR", "13F-HR/A", "13F-NT", "13F-NT/A"}
MAX_RESPONSE_BYTES = 20_000_000


class FilingError(RuntimeError):
    pass


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _child_text(node: ElementTree.Element, name: str) -> str:
    return next((str(child.text or "").strip() for child in node if _local(child.tag) == name), "")


def _descendant_text(node: ElementTree.Element, name: str) -> str:
    return next((str(child.text or "").strip() for child in node.iter() if _local(child.tag) == name), "")


def _xml(body: bytes) -> ElementTree.Element:
    if b"<!DOCTYPE" in body.upper() or b"<!ENTITY" in body.upper():
        raise FilingError("xml_external_entity")
    try:
        return ElementTree.fromstring(body)
    except ElementTree.ParseError as error:
        raise FilingError("invalid_xml") from error


def filings(payload: dict, *, cik: int) -> list[dict]:
    try:
        if int(payload["cik"]) != cik:
            raise FilingError("filer_cik_mismatch")
        recent = payload["filings"]["recent"]
        fields = ("form", "accessionNumber", "filingDate", "reportDate")
        if len({len(recent[field]) for field in fields}) != 1:
            raise FilingError("filing_columns_misaligned")
    except (KeyError, TypeError, ValueError) as error:
        raise FilingError("invalid_submissions_schema") from error
    rows = []
    for form, accession, filed, period in zip(*(recent[field] for field in fields)):
        if form not in FORMS or not isinstance(accession, str) or not ACCESSION.fullmatch(accession):
            continue
        try:
            date.fromisoformat(filed)
            date.fromisoformat(period)
        except (TypeError, ValueError):
            continue
        rows.append({"form": form, "accession": accession, "filedAt": filed,
                     "periodOfReport": period, "cik": cik})
    return sorted(rows, key=lambda row: (row["periodOfReport"], row["filedAt"], row["accession"]), reverse=True)


def latest_reports(rows: list[dict], *, count: int = 2) -> tuple[list[dict], dict | None]:
    if not rows:
        return [], None
    latest_period = rows[0]["periodOfReport"]
    latest_notice = next((row for row in rows if row["periodOfReport"] == latest_period
                          and row["form"].startswith("13F-NT")), None)
    periods = []
    for row in rows:
        if row["periodOfReport"] not in periods:
            periods.append(row["periodOfReport"])
    selected = []
    for period in periods:
        candidates = [row for row in rows if row["periodOfReport"] == period
                      and row["form"].startswith("13F-HR")]
        if candidates:
            selected.append(candidates[0])
        if len(selected) >= count:
            break
    return selected, latest_notice


def parse_cover(body: bytes, *, cik: int, period: str, form: str,
                allow_new_holdings: bool = False) -> dict:
    root = _xml(body)
    if _local(root.tag) != "edgarSubmission":
        raise FilingError("not_13f_cover")
    if (_descendant_text(root, "cik").lstrip("0") != str(cik)
            or _descendant_text(root, "submissionType") != form
            or _descendant_text(root, "periodOfReport") != date.fromisoformat(period).strftime("%m-%d-%Y")):
        raise FilingError("cover_identity_mismatch")
    report_type = _descendant_text(root, "reportType")
    amendment_type = _descendant_text(root, "amendmentType")
    if form == "13F-HR/A" and amendment_type not in ({"RESTATEMENT", "NEW HOLDINGS"}
                                                    if allow_new_holdings else {"RESTATEMENT"}):
        raise FilingError("amendment_requires_review")
    if form.startswith("13F-HR") and report_type not in {"13F HOLDINGS REPORT", "13F COMBINATION REPORT"}:
        raise FilingError("unsupported_report_type")
    manager = next((node for node in root.iter() if _local(node.tag) == "filingManager"), None)
    return {"managerName": _child_text(manager, "name") if manager is not None else "",
            "reportType": report_type, "amendmentType": amendment_type or None}


def _decimal(value: str, field: str) -> Decimal:
    try:
        result = Decimal(value)
        if not result.is_finite() or result < 0:
            raise InvalidOperation
        return result
    except (InvalidOperation, ValueError) as error:
        raise FilingError(f"invalid_{field}") from error


def parse_information_table(body: bytes) -> list[dict]:
    root = _xml(body)
    if _local(root.tag) != "informationTable":
        raise FilingError("not_information_table")
    combined = defaultdict(lambda: {"reportedShares": Decimal(0), "reportedValueUsd": 0})
    for item in root:
        if _local(item.tag) != "infoTable":
            continue
        issuer = _child_text(item, "nameOfIssuer")
        security_class = _child_text(item, "titleOfClass")
        cusip = _child_text(item, "cusip")
        option = _child_text(item, "putCall").upper() or None
        share_type = _descendant_text(item, "sshPrnamtType")
        discretion = _child_text(item, "investmentDiscretion")
        if not issuer or not cusip or share_type not in {"SH", "PRN"}:
            raise FilingError("invalid_information_row")
        value = _decimal(_child_text(item, "value"), "value")
        if value != value.to_integral_value():
            raise FilingError("invalid_value")
        shares = _decimal(_descendant_text(item, "sshPrnamt"), "shares")
        key = (issuer, security_class, cusip, option, share_type, discretion)
        combined[key]["reportedShares"] += shares
        combined[key]["reportedValueUsd"] += int(value)
    if not combined:
        raise FilingError("empty_information_table")
    return [dict(issuer=key[0], securityClass=key[1], cusip=key[2], option=key[3],
                 shareType=key[4], discretion=key[5], reportedShares=str(data["reportedShares"]),
                 reportedValueUsd=data["reportedValueUsd"])
            for key, data in sorted(combined.items(), key=lambda pair: (-pair[1]["reportedValueUsd"], pair[0][0]))]


def changes(current: list[dict], previous: list[dict]) -> list[dict]:
    def keyed(rows: list[dict]) -> dict[tuple, dict]:
        return {(row["cusip"], row["securityClass"], row["option"], row["shareType"], row["discretion"]): row
                for row in rows}
    before, after = keyed(previous), keyed(current)
    result = []
    for key in sorted(before.keys() | after.keys(), key=str):
        old, new = before.get(key), after.get(key)
        old_shares = Decimal(old["reportedShares"]) if old else Decimal(0)
        new_shares = Decimal(new["reportedShares"]) if new else Decimal(0)
        delta = new_shares - old_shares
        if delta:
            result.append({"issuer": (new or old)["issuer"], "cusip": key[0], "securityClass": key[1],
                           "option": key[2], "shareType": key[3], "reportedShareChange": str(delta),
                           "classification": "new_reported_position" if not old else
                           "no_longer_reported" if not new else
                           "reported_shares_increased" if delta > 0 else "reported_shares_decreased"})
    return result


class SEC13FClient:
    def __init__(self, contact: str, *, session: requests.Session | None = None,
                 min_interval: float = 0.5, request_limit: int = 80):
        if not re.fullmatch(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", contact):
            raise ValueError("BSMART_OFFICIAL_CONTACT must be a real contact email")
        self.session = session or requests.Session()
        self.headers = {"User-Agent": f"bSmart 13F Research (https://bsmart.today; {contact})",
                        "Accept": "application/json, application/xml, text/xml"}
        self.min_interval = min_interval
        self.request_limit = request_limit
        self.requests = 0
        self.last_request = 0.0

    def get(self, url: str) -> bytes:
        if self.requests >= self.request_limit:
            raise FilingError("sec_request_budget_exhausted")
        time.sleep(max(0.0, self.min_interval - (time.monotonic() - self.last_request)))
        self.last_request = time.monotonic()
        self.requests += 1
        try:
            with self.session.get(url, headers=self.headers, timeout=(8, 30),
                                  allow_redirects=False, stream=True) as response:
                if response.status_code != 200:
                    raise FilingError(f"sec_http_{response.status_code}")
                if int(response.headers.get("Content-Length", "0")) > MAX_RESPONSE_BYTES:
                    raise FilingError("sec_document_too_large")
                parts, size = [], 0
                for part in response.iter_content(32768):
                    size += len(part)
                    if size > MAX_RESPONSE_BYTES:
                        raise FilingError("sec_document_too_large")
                    parts.append(part)
                return b"".join(parts)
        except requests.RequestException as error:
            raise FilingError(f"sec_network_{type(error).__name__}") from error

    def submissions(self, cik: int, *, earliest_period: str | None = None) -> list[dict]:
        import json
        body = self.get(f"https://data.sec.gov/submissions/CIK{cik:010d}.json")
        try:
            payload = json.loads(body)
            rows = filings(payload, cik=cik)
            if earliest_period is not None:
                date.fromisoformat(earliest_period)
                for item in payload.get("filings", {}).get("files", []):
                    if not isinstance(item, dict) or item.get("filingTo", "") < earliest_period:
                        continue
                    name = item.get("name")
                    if not isinstance(name, str) or not SAFE_SUBMISSIONS.fullmatch(name):
                        raise FilingError("unsafe_submissions_file")
                    older = json.loads(self.get(f"https://data.sec.gov/submissions/{name}"))
                    rows.extend(filings({"cik": cik, "filings": {"recent": older}}, cik=cik))
            return sorted({row["accession"]: row for row in rows}.values(),
                          key=lambda row: (row["periodOfReport"], row["filedAt"], row["accession"]),
                          reverse=True)
        except (ValueError, TypeError) as error:
            raise FilingError("invalid_submissions_json") from error

    def report(self, row: dict, *, allow_new_holdings: bool = False) -> dict:
        import json
        cik, accession = row["cik"], row["accession"]
        if not isinstance(cik, int) or not ACCESSION.fullmatch(accession):
            raise FilingError("unsafe_filing_identity")
        base = f"https://www.sec.gov/Archives/edgar/data/{cik}/{accession.replace('-', '')}/"
        index = json.loads(self.get(base + "index.json"))
        entries = index.get("directory", {}).get("item", [])
        names = [entry.get("name") for entry in entries if isinstance(entry, dict)]
        primary = next((name for name in names if isinstance(name, str) and name.lower() == "primary_doc.xml"), None)
        tables = [name for name in names if isinstance(name, str) and SAFE_XML.fullmatch(name) and name != primary]
        if not primary or not tables:
            raise FilingError("missing_13f_documents")
        cover = parse_cover(self.get(base + primary), cik=cik, period=row["periodOfReport"],
                            form=row["form"], allow_new_holdings=allow_new_holdings)
        for name in tables[:6]:
            body = self.get(base + name)
            try:
                holdings = parse_information_table(body)
            except FilingError as error:
                if str(error) == "not_information_table":
                    continue
                raise
            return {**row, **cover, "filingUrl": base + accession + "-index.html",
                    "informationTableUrl": base + name, "holdings": holdings}
        raise FilingError("missing_information_table")
