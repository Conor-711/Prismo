"""Produce a provenance-preserving research export without claiming full coverage."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sqlite3
from pathlib import Path

from ...platforms.congress.disclosures import load_disclosures
from .house_pdf import PARSER_VERSION


DOC_ID = re.compile(r"/([0-9]+)\.pdf$")


def consolidate(
    *, db_path: Path, reference_zip: Path, since: dt.date, until: dt.date,
    output_path: Path, manifest_path: Path,
) -> dict:
    _, reference_all = load_disclosures(reference_zip, start_date=dt.date(2000, 1, 1), end_date=until)
    covered_house_docs = {
        match.group(1)
        for trade in reference_all if trade.member.chamber == "house"
        if (match := DOC_ID.search(trade.evidence_url or ""))
    }
    reference = [trade for trade in reference_all if since <= trade.transaction_date <= until]
    rows = []
    for trade in reference:
        rows.append({
            "trade_id": trade.trade_id,
            "member_id": trade.member.member_id,
            "member_name": trade.member.name,
            "chamber": trade.member.chamber,
            "transaction_date": trade.transaction_date.isoformat(),
            "filing_date": trade.filing_date.isoformat() if trade.filing_date else None,
            "notification_date": trade.notification_date.isoformat() if trade.notification_date else None,
            "owner": trade.owner,
            "ticker": trade.ticker,
            "asset_name": trade.asset_name,
            "asset_type": trade.asset_type,
            "action": trade.transaction_type,
            "amount_low": trade.amount_low,
            "amount_high": trade.amount_high,
            "evidence_url": trade.evidence_url,
            "data_source": "kadoa_parsed_official_filing",
            "verification_status": "third_party_extraction_pending_review",
        })
    with sqlite3.connect(db_path) as db:
        gap_rows = db.execute("""
            SELECT t.trade_id,t.doc_id,f.first,f.last,f.filing_date,t.transaction_date,
                   t.notification_date,t.owner,t.ticker,t.asset_name,t.action,
                   t.amount_low,t.amount_high,t.pdf_url
            FROM house_pdf_trades t
            JOIN house_pdf_documents d ON d.doc_id=t.doc_id
            JOIN house_filings f ON f.doc_id=t.doc_id
            WHERE d.parser_version=? AND d.fetched_at IS NOT NULL AND d.error IS NULL
              AND t.transaction_date>=? AND t.transaction_date<=?
            ORDER BY t.transaction_date,t.doc_id,t.page,t.row_on_page
        """, (PARSER_VERSION, since.isoformat(), until.isoformat())).fetchall()
        unresolved = db.execute("""
            SELECT f.doc_id,f.pdf_url,d.fetched_at,d.error,d.parser_version
            FROM house_filings f
            LEFT JOIN house_pdf_documents d ON d.doc_id=f.doc_id
        """).fetchall()
    new_rows = 0
    for (trade_id, doc_id, first, last, filing_date, trade_date, notification_date,
         owner, ticker, asset_name, action, low, high, pdf_url) in gap_rows:
        if doc_id in covered_house_docs:
            continue
        rows.append({
            "trade_id": trade_id, "member_id": None,
            "member_name": f"{first} {last}".strip(), "chamber": "house",
            "transaction_date": trade_date, "filing_date": filing_date,
            "notification_date": notification_date, "owner": owner,
            "ticker": ticker, "asset_name": asset_name,
            "asset_type": None, "action": action,
            "amount_low": low, "amount_high": high,
            "evidence_url": pdf_url,
            "data_source": "house_clerk_pdf_auto_extracted",
            "verification_status": "automatic_extraction_pending_review",
        })
        new_rows += 1
    rows.sort(key=lambda row: (row["transaction_date"], row["trade_id"]))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = output_path.with_suffix(output_path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
    tmp.replace(output_path)
    unresolved_gaps = [
        {"doc_id": doc_id, "pdf_url": pdf_url, "reason": error or "not extracted"}
        for doc_id, pdf_url, fetched_at, error, version in unresolved
        if doc_id not in covered_house_docs and not (fetched_at and not error and version == PARSER_VERSION)
    ]
    manifest = {
        "since": since.isoformat(), "until": until.isoformat(),
        "row_count": len(rows), "reference_rows": len(reference),
        "new_house_pdf_rows": new_rows,
        "latest_transaction_date": max((row["transaction_date"] for row in rows), default=None),
        "unresolved_house_filing_count": len(unresolved_gaps),
        "unresolved_house_filings": unresolved_gaps,
        "senate_official_coverage_verified": False,
        "complete_one_year_history": False,
        "output": str(output_path),
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_manifest = manifest_path.with_suffix(manifest_path.suffix + ".tmp")
    tmp_manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp_manifest.replace(manifest_path)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description="Export congressional research rows with provenance")
    parser.add_argument("--db", dest="db_path", type=Path, required=True)
    parser.add_argument("--reference-zip", type=Path, required=True)
    parser.add_argument("--since", type=dt.date.fromisoformat, required=True)
    parser.add_argument("--until", type=dt.date.fromisoformat, required=True)
    parser.add_argument("--output", dest="output_path", type=Path, required=True)
    parser.add_argument("--manifest", dest="manifest_path", type=Path, required=True)
    args = parser.parse_args()
    result = consolidate(**vars(args))
    print(json.dumps({k: v for k, v in result.items() if k != "unresolved_house_filings"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
