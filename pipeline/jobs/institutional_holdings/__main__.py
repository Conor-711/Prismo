from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path

from ...domain.institutional_holdings import SUBJECTS, HoldingsSubject
from ...platforms.institutional_holdings.sec_13f import SEC13FClient, FilingError, changes, latest_reports


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUTPUT = ROOT / "data/exports/institutional_holdings"


def _write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    temporary.replace(path)


def refresh(subject: HoldingsSubject, client: SEC13FClient, now: datetime) -> dict:
    reports, notice = latest_reports(client.submissions(subject.filer_cik))
    if not reports:
        raise FilingError("no_holdings_report")
    snapshots = [client.report(report) for report in reports]
    for snapshot in snapshots:
        if snapshot["managerName"].casefold() != subject.filer_name.casefold():
            raise FilingError("reporting_manager_mismatch")
    current = snapshots[0]
    latest_period = datetime.fromisoformat(current["periodOfReport"]).date()
    days_old = (now.date() - latest_period).days
    if days_old < 0:
        raise FilingError("future_report_period")
    comparable = False
    if len(snapshots) > 1:
        previous_period = datetime.fromisoformat(snapshots[1]["periodOfReport"]).date()
        comparable = (75 <= (latest_period - previous_period).days <= 105
                      and all(item["reportType"] == "13F HOLDINGS REPORT" for item in snapshots))
    disclosure_status = ("newer_notice_without_holdings" if notice and notice["periodOfReport"] > current["periodOfReport"]
                         else "stale" if days_old > 150 else
                         "partial_quarterly_report" if current["reportType"] != "13F HOLDINGS REPORT"
                         else "current_quarterly_report")
    return {
        "schemaVersion": 1, "source": "SEC EDGAR Form 13F", "checkedAt": now.isoformat(),
        "subjectId": subject.id, "title": subject.title, "kind": subject.kind,
        "attribution": subject.attribution, "filerCik": subject.filer_cik,
        "filerName": current["managerName"], "disclosureStatus": disclosure_status,
        "periodOfReport": current["periodOfReport"], "filedAt": current["filedAt"],
        "daysSinceReport": days_old, "form": current["form"], "accession": current["accession"],
        "filingUrl": current["filingUrl"], "informationTableUrl": current["informationTableUrl"],
        "reportType": current["reportType"], "coverage": "complete" if current["reportType"] == "13F HOLDINGS REPORT" else "partial",
        "latestNotice": notice, "holdings": current["holdings"],
        "comparisonPeriod": snapshots[1]["periodOfReport"] if comparable else None,
        "changes": changes(current["holdings"], snapshots[1]["holdings"]) if comparable else [],
        "limitations": ["quarter_end_snapshot_not_live", "covered_13f_securities_only",
                        "share_changes_are_not_confirmed_trades", "not_personal_holdings"]
                       + (["prior_report_not_comparable"] if len(snapshots) > 1 and not comparable else []),
    }


def as_subject(snapshot: dict, subject: HoldingsSubject) -> dict:
    """Relabel a verified manager filing without changing its original check time."""
    if (snapshot.get("source") != "SEC EDGAR Form 13F"
            or snapshot.get("filerCik") != subject.filer_cik
            or str(snapshot.get("filerName") or "").casefold() != subject.filer_name.casefold()
            or not snapshot.get("filingUrl", "").startswith("https://www.sec.gov/")):
        raise FilingError("shared_filer_snapshot_mismatch")
    return {**snapshot, "subjectId": subject.id, "title": subject.title,
            "kind": subject.kind, "attribution": subject.attribution}


def run(*, output_dir: Path = DEFAULT_OUTPUT, contact: str | None = None,
        subjects: tuple[HoldingsSubject, ...] = SUBJECTS, client: SEC13FClient | None = None,
        now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    client = client or SEC13FClient(contact or "", request_limit=max(160, len({subject.filer_cik for subject in subjects}) * 10))
    manifest_path = output_dir / "manifest.json"
    previous = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    results = []
    shared_filings: dict[int, dict] = {}
    for subject in subjects:
        path = output_dir / f"{subject.id}.json"
        try:
            if subject.filer_cik in shared_filings:
                payload = as_subject(shared_filings[subject.filer_cik], subject)
            else:
                payload = refresh(subject, client, now)
                shared_filings[subject.filer_cik] = payload
            _write(path, payload)
            results.append({"id": subject.id, "checkedAt": now.isoformat(), "status": payload["disclosureStatus"],
                            "periodOfReport": payload["periodOfReport"],
                            "holdings": len(payload["holdings"]), "changes": len(payload["changes"]),
                            "file": path.name})
        except (FilingError, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
            # A failed refresh must not replace the last verified snapshot.
            results.append({"id": subject.id, "checkedAt": now.isoformat(), "status": "error", "error": str(error),
                            "retainedPriorSnapshot": path.exists()})
    by_id = {item["id"]: item for item in previous.get("subjects", []) if isinstance(item, dict) and "id" in item}
    by_id.update({item["id"]: item for item in results})
    manifest = {"schemaVersion": 1, "checkedAt": now.isoformat(), "source": "SEC EDGAR Form 13F",
                "subjects": sorted(by_id.values(), key=lambda item: item["id"]),
                "refreshedSubjectIds": [subject.id for subject in subjects], "requestCount": client.requests,
                "excluded": [{"title": "Jim Cramer", "reason": "no_verified_public_13f_for_personal_or_club_portfolio"}]}
    _write(manifest_path, manifest)
    return manifest


def reuse_verified_snapshot(output_dir: Path, subject: HoldingsSubject, from_subject: HoldingsSubject) -> dict:
    if from_subject.filer_cik != subject.filer_cik:
        raise FilingError("shared_filer_cik_mismatch")
    source = json.loads((output_dir / f"{from_subject.id}.json").read_text(encoding="utf-8"))
    if source.get("subjectId") != from_subject.id:
        raise FilingError("shared_filer_source_identity_mismatch")
    payload = as_subject(source, subject)
    _write(output_dir / f"{subject.id}.json", payload)
    manifest_path = output_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {
        "schemaVersion": 1, "source": "SEC EDGAR Form 13F", "subjects": []}
    by_id = {item["id"]: item for item in manifest["subjects"]}
    by_id[subject.id] = {"id": subject.id, "checkedAt": payload["checkedAt"],
                         "status": payload["disclosureStatus"], "periodOfReport": payload["periodOfReport"],
                         "holdings": len(payload["holdings"]), "changes": len(payload["changes"]),
                         "file": f"{subject.id}.json", "reusedFrom": from_subject.id}
    manifest.update({"subjects": sorted(by_id.values(), key=lambda item: item["id"]),
                     "refreshedSubjectIds": [], "reusedSubjectIds": [subject.id]})
    _write(manifest_path, manifest)
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(description="Refresh curated celebrity and institutional SEC 13F snapshots")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--subject", action="append", choices=[subject.id for subject in SUBJECTS])
    parser.add_argument("--reuse-verified-filing-from", choices=[subject.id for subject in SUBJECTS],
                        help="For one selected identity sharing a CIK, reuse a previously verified filing without a new SEC fetch")
    args = parser.parse_args()
    selected = tuple(subject for subject in SUBJECTS if not args.subject or subject.id in args.subject)
    if args.reuse_verified_filing_from:
        if len(selected) != 1:
            parser.error("--reuse-verified-filing-from requires exactly one --subject")
        origin = next(subject for subject in SUBJECTS if subject.id == args.reuse_verified_filing_from)
        print(json.dumps(reuse_verified_snapshot(args.output_dir, selected[0], origin), ensure_ascii=False))
        return
    result = run(output_dir=args.output_dir, contact=os.environ.get("BSMART_OFFICIAL_CONTACT"), subjects=selected)
    print(json.dumps(result, ensure_ascii=False))
    if any(item["status"] == "error" for item in result["subjects"]
           if item["id"] in result["refreshedSubjectIds"]):
        raise SystemExit(2)


if __name__ == "__main__":
    main()
