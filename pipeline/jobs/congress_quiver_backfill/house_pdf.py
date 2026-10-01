"""Extract transaction rows from House Clerk PTR PDFs with explicit coverage flags."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import re
import sqlite3
import subprocess
import time
from pathlib import Path

import pdfplumber
from pdfplumber.utils.exceptions import PdfminerException

from ...platforms.congress.disclosures import load_disclosures


DATE = re.compile(r"\d{2}/\d{2}/\d{4}$")
MONEY = re.compile(r"\$([\d,]+(?:\.\d{1,2})?)")
TICKER = re.compile(r"\(([A-Z][A-Z0-9.\-]{0,9})\)")
MAX_PDF_BYTES = 20 * 1024 * 1024
PARSER_VERSION = "house-pdf-v2"


def fetch_pdf(url: str) -> bytes:
    try:
        result = subprocess.run(
            ["curl", "--fail", "--location", "--silent", "--show-error",
             "--retry", "1", "--max-time", "25", url],
            check=True, capture_output=True, timeout=65,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as exc:
        raise RuntimeError(f"cannot fetch PDF {url}: {exc}") from exc
    if len(result.stdout) > MAX_PDF_BYTES:
        raise RuntimeError(f"PDF exceeds {MAX_PDF_BYTES} bytes: {url}")
    if not result.stdout.startswith(b"%PDF"):
        raise RuntimeError(f"not a PDF: {url}")
    return result.stdout


def _line_groups(words: list[dict], start: float, end: float) -> list[list[dict]]:
    groups: list[list[dict]] = []
    for word in sorted((w for w in words if start - 1 <= w["top"] < end), key=lambda w: (w["top"], w["x0"])):
        if not groups or abs(groups[-1][0]["top"] - word["top"]) > 2:
            groups.append([])
        groups[-1].append(word)
    return groups


def _column(line: list[dict], left: float, right: float) -> str:
    return " ".join(w["text"] for w in line if left <= w["x0"] < right).strip()


def parse_page_words(words: list[dict]) -> tuple[list[dict], list[str]]:
    """Read fixed-column House PTR rows; return rows and visible parser anomalies."""
    starts = sorted(
        (w for w in words if 320 <= w["x0"] < 360 and DATE.fullmatch(w["text"])),
        key=lambda w: w["top"],
    )
    rows: list[dict] = []
    errors: list[str] = []
    for index, date_word in enumerate(starts):
        top = date_word["top"]
        next_top = starts[index + 1]["top"] if index + 1 < len(starts) else max(w["top"] for w in words) + 1
        lines = _line_groups(words, top, next_top)
        if not lines:
            continue
        first_line = lines[0]
        transaction_lines = []
        for line in lines:
            if any("\x00" in w["text"] and 100 <= w["x0"] < 260 for w in line):
                break
            segment = _column(line, 102, 260)
            if segment.startswith(("For the complete", "I CERTIFY", "Digitally Signed")):
                break
            transaction_lines.append(line)
        action = _column(first_line, 260, 320)
        if not re.fullmatch(r"(?:P|S|E)(?: \(partial\))?", action, re.IGNORECASE):
            errors.append(f"unrecognized action at y={top:.0f}: {action!r}")
            continue
        asset_lines = []
        for line in transaction_lines:
            # House PDFs use corrupt glyphs in filing-status and subholding labels.
            if any("\x00" in w["text"] for w in line):
                continue
            segment = _column(line, 102, 260)
            if segment and not segment.startswith(("Transactions", "Asset")):
                asset_lines.append(segment)
        asset = " ".join(asset_lines).strip()
        amount_text = " ".join(
            _column(line, 442, 526) for line in transaction_lines
            if not any(w["text"] in {"Amount", "Gains", "$200?"} for w in line)
        )
        values = [float(value.replace(",", "")) for value in MONEY.findall(amount_text)]
        if len(values) == 1:
            values.append(values[0])
        if not asset or len(values) != 2 or values[0] > values[1]:
            errors.append(f"incomplete transaction at y={top:.0f}: asset={asset!r}, amount={amount_text!r}")
            continue
        notification = next((w["text"] for w in first_line if 375 <= w["x0"] < 442 and DATE.fullmatch(w["text"])), None)
        if notification is None:
            errors.append(f"missing notification date at y={top:.0f}")
            continue
        ticker_match = TICKER.search(asset)
        rows.append({
            "transaction_date": dt.datetime.strptime(date_word["text"], "%m/%d/%Y").date().isoformat(),
            "notification_date": dt.datetime.strptime(notification, "%m/%d/%Y").date().isoformat() if notification else None,
            "owner": _column(first_line, 64, 102) or None,
            "asset_name": asset,
            "ticker": ticker_match.group(1) if ticker_match else None,
            "action": action,
            "amount_low": values[0], "amount_high": values[1],
            "page": date_word.get("page", 1),
        })
    return rows, errors


def parse_pdf(data: bytes) -> tuple[list[dict], list[str]]:
    words: list[dict] = []
    errors: list[str] = []
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        for page_number, page in enumerate(pdf.pages, start=1):
            page_words = page.extract_words()
            words.extend({**word, "top": word["top"] + (page_number - 1) * 1000, "page": page_number}
                         for word in page_words)
            if not page_words:
                errors.append(f"page {page_number}: no extractable text")
    rows, row_errors = parse_page_words(words)
    errors.extend(row_errors)
    if not rows:
        errors.append("no transaction rows extracted")
    counts: dict[int, int] = {}
    for row in rows:
        page_number = row["page"]
        row["row_on_page"] = counts.get(page_number, 0)
        counts[page_number] = row["row_on_page"] + 1
    return rows, errors


def _schema(db: sqlite3.Connection) -> None:
    db.executescript("""
        CREATE TABLE IF NOT EXISTS house_pdf_documents (
            doc_id TEXT PRIMARY KEY, sha256 TEXT, fetched_at TEXT,
            rows_detected INTEGER, error TEXT, parser_version TEXT
        );
        CREATE TABLE IF NOT EXISTS house_pdf_trades (
            trade_id TEXT PRIMARY KEY, doc_id TEXT NOT NULL,
            transaction_date TEXT NOT NULL, notification_date TEXT,
            owner TEXT, asset_name TEXT NOT NULL, ticker TEXT,
            action TEXT NOT NULL, amount_low REAL, amount_high REAL,
            page INTEGER NOT NULL, row_on_page INTEGER NOT NULL,
            pdf_url TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS house_pdf_trades_date ON house_pdf_trades(transaction_date);
    """)
    columns = {row[1] for row in db.execute("PRAGMA table_info(house_pdf_documents)")}
    if "parser_version" not in columns:
        db.execute("ALTER TABLE house_pdf_documents ADD COLUMN parser_version TEXT")


def backfill(
    *, db_path: Path, report_path: Path, since: dt.date, until: dt.date,
    max_docs: int | None = None, delay: float = 0.5, refresh: bool = False,
    reference_zip: Path | None = None,
) -> dict:
    if since > until or delay < 0:
        raise ValueError("invalid date window or delay")
    with sqlite3.connect(db_path) as db:
        _schema(db)
        filings = db.execute(
            "SELECT doc_id,pdf_url FROM house_filings ORDER BY filing_date,doc_id"
        ).fetchall()
        if not filings:
            raise RuntimeError("no House filings in database; run the Quiver capture first")
        if reference_zip is not None:
            _, reference_trades = load_disclosures(
                reference_zip, start_date=dt.date(2000, 1, 1), end_date=until,
            )
            covered_ids = {
                match.group(1)
                for trade in reference_trades if trade.member.chamber == "house"
                if (match := re.search(r"/([0-9]+)\.pdf$", trade.evidence_url or ""))
            }
            filings = [(doc_id, pdf_url) for doc_id, pdf_url in filings if doc_id not in covered_ids]
        if max_docs is not None:
            filings = filings[:max_docs]
        failures = []
        for index, (doc_id, pdf_url) in enumerate(filings, start=1):
            previous = db.execute(
                "SELECT fetched_at,parser_version,error FROM house_pdf_documents WHERE doc_id=?", (doc_id,)
            ).fetchone()
            if previous and previous[0] and previous[1] == PARSER_VERSION and not refresh:
                continue
            if previous and previous[2] and "no extractable text" in previous[2] and not refresh:
                continue
            try:
                data = fetch_pdf(pdf_url)
                rows, errors = parse_pdf(data)
                if errors:
                    raise RuntimeError("; ".join(errors[:8]))
                with db:
                    db.execute("DELETE FROM house_pdf_trades WHERE doc_id=?", (doc_id,))
                    db.executemany("""
                        INSERT INTO house_pdf_trades VALUES (
                            :trade_id,:doc_id,:transaction_date,:notification_date,
                            :owner,:asset_name,:ticker,:action,:amount_low,:amount_high,
                            :page,:row_on_page,:pdf_url)
                    """, [
                        {**row, "trade_id": f"house_{doc_id}_p{row['page']}_r{row['row_on_page']}",
                         "doc_id": doc_id, "pdf_url": pdf_url}
                        for row in rows if since <= dt.date.fromisoformat(row["transaction_date"]) <= until
                    ])
                    db.execute("""
                        INSERT INTO house_pdf_documents VALUES (?,?,?,?,NULL,?)
                        ON CONFLICT(doc_id) DO UPDATE SET sha256=excluded.sha256,
                            fetched_at=excluded.fetched_at,rows_detected=excluded.rows_detected,
                            error=NULL,parser_version=excluded.parser_version
                    """, (doc_id, hashlib.sha256(data).hexdigest(),
                           dt.datetime.now(dt.timezone.utc).isoformat(), len(rows), PARSER_VERSION))
            except (RuntimeError, ValueError, OSError, PdfminerException) as exc:
                failures.append(f"{doc_id}: {exc}")
                with db:
                    db.execute("DELETE FROM house_pdf_trades WHERE doc_id=?", (doc_id,))
                    db.execute("""
                        INSERT INTO house_pdf_documents(doc_id,error,parser_version) VALUES (?,?,?)
                        ON CONFLICT(doc_id) DO UPDATE SET error=excluded.error,
                            fetched_at=NULL,parser_version=excluded.parser_version
                    """, (doc_id, str(exc), PARSER_VERSION))
            if index % 25 == 0:
                print(f"House PDF {index}/{len(filings)}", flush=True)
            time.sleep(delay)
        selected_ids = [doc_id for doc_id, _ in filings]
        selected_states = [
            db.execute("SELECT fetched_at,error,parser_version FROM house_pdf_documents WHERE doc_id=?", (doc_id,)).fetchone()
            for doc_id in selected_ids
        ]
        selected_parsed = sum(bool(state and state[0] and state[2] == PARSER_VERSION) for state in selected_states)
        selected_errors = [f"{doc_id}: {state[1]}" for doc_id, state in zip(selected_ids, selected_states) if state and state[1]]
        result = {
            "since": since.isoformat(), "until": until.isoformat(),
            "selected_documents": len(filings),
            "selected_parsed_documents": selected_parsed,
            "selected_error_documents": len(selected_errors),
            "parser_version": PARSER_VERSION,
            "transaction_rows": sum(
                db.execute("SELECT COUNT(*) FROM house_pdf_trades WHERE doc_id=?", (doc_id,)).fetchone()[0]
                for doc_id, state in zip(selected_ids, selected_states) if state and state[0] and state[2] == PARSER_VERSION
            ),
            "failures": selected_errors,
            "status": "extracted_pending_trade_level_validation",
            "database": str(db_path),
        }
        report_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = report_path.with_suffix(report_path.suffix + ".tmp")
        tmp.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(report_path)
        return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract trades from official House PTR PDFs")
    parser.add_argument("--db", dest="db_path", type=Path, required=True)
    parser.add_argument("--report", dest="report_path", type=Path, required=True)
    parser.add_argument("--since", type=dt.date.fromisoformat, required=True)
    parser.add_argument("--until", type=dt.date.fromisoformat, required=True)
    parser.add_argument("--max-docs", type=int)
    parser.add_argument("--delay", type=float, default=0.5)
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--reference-zip", type=Path)
    args = parser.parse_args()
    print(json.dumps(backfill(**vars(args)), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
