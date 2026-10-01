"""Compare official House PTR coverage with parsed PDF and reference data."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import sqlite3
from collections import Counter
from pathlib import Path

from ...platforms.congress.disclosures import load_disclosures
from .house_pdf import PARSER_VERSION


DOC_ID = re.compile(r"/([0-9]+)\.pdf$")


def audit(
    *, db_path: Path, reference_zip: Path, since: dt.date, until: dt.date,
    csv_path: Path, report_path: Path,
) -> dict:
    _, reference = load_disclosures(reference_zip, start_date=since, end_date=until)
    reference_by_doc: Counter[str] = Counter()
    for trade in reference:
        if trade.member.chamber != "house":
            continue
        match = DOC_ID.search(trade.evidence_url or "")
        if match:
            reference_by_doc[match.group(1)] += 1
    with sqlite3.connect(db_path) as db:
        filings = db.execute("""
            SELECT f.doc_id,f.filing_date,f.pdf_url,d.fetched_at,d.rows_detected,d.error,d.parser_version,
                   COUNT(t.trade_id)
            FROM house_filings f
            LEFT JOIN house_pdf_documents d ON d.doc_id=f.doc_id
            LEFT JOIN house_pdf_trades t ON t.doc_id=f.doc_id
            GROUP BY f.doc_id ORDER BY f.filing_date,f.doc_id
        """).fetchall()
    rows = []
    for doc_id, filing_date, pdf_url, fetched_at, detected, error, parser_version, raw_parsed_count in filings:
        parsed_count = raw_parsed_count if parser_version == PARSER_VERSION and fetched_at and not error else 0
        reference_count = reference_by_doc[doc_id]
        if error:
            status = "parse_or_download_error"
        elif not fetched_at or parser_version != PARSER_VERSION:
            status = "not_parsed_current_version"
        elif reference_count == 0 and parsed_count > 0:
            status = "filled_reference_gap_pending_review"
        elif parsed_count != reference_count:
            status = "row_count_differs"
        else:
            status = "count_matches_not_trade_verified"
        rows.append({
            "doc_id": doc_id, "filing_date": filing_date, "pdf_url": pdf_url,
            "pdf_rows_detected_all_dates": detected if detected is not None else "",
            "pdf_rows_in_window": parsed_count,
            "reference_rows_in_window": reference_count,
            "status": status, "error": error or "",
        })
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]) if rows else ["doc_id"])
        writer.writeheader()
        writer.writerows(rows)
    status_counts = dict(Counter(row["status"] for row in rows))
    report = {
        "since": since.isoformat(), "until": until.isoformat(),
        "official_house_ptr_filings": len(filings),
        "reference_trades": len(reference),
        "reference_latest_transaction_date": max((t.transaction_date for t in reference), default=None).isoformat() if reference else None,
        "reference_latest_filing_date": max((t.filing_date for t in reference if t.filing_date), default=None).isoformat() if reference else None,
        "status_counts": status_counts,
        "pdf_trade_rows": sum(row["pdf_rows_in_window"] for row in rows),
        "reference_house_trade_rows_in_indexed_filings": sum(row["reference_rows_in_window"] for row in rows),
        "trade_level_verified": False,
        "coverage_csv": str(csv_path),
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = report_path.with_suffix(report_path.suffix + ".tmp")
    tmp.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(report_path)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit congressional PTR capture coverage")
    parser.add_argument("--db", dest="db_path", type=Path, required=True)
    parser.add_argument("--reference-zip", type=Path, required=True)
    parser.add_argument("--since", type=dt.date.fromisoformat, required=True)
    parser.add_argument("--until", type=dt.date.fromisoformat, required=True)
    parser.add_argument("--csv", dest="csv_path", type=Path, required=True)
    parser.add_argument("--report", dest="report_path", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(audit(**vars(args)), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
