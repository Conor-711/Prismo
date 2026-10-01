import datetime as dt
import json
import sqlite3
from types import SimpleNamespace

from pipeline.jobs.congress_quiver_backfill import capture as capture_module
from pipeline.jobs.congress_quiver_backfill import consolidate as consolidate_module
from pipeline.jobs.congress_quiver_backfill import house_pdf


def test_consolidate_adds_only_uncovered_official_pdf_rows(tmp_path, monkeypatch) -> None:
    member = SimpleNamespace(member_id="M1", name="Example Member", chamber="house")
    reference = SimpleNamespace(
        trade_id="reference-1", member=member, transaction_date=dt.date(2026, 3, 1),
        filing_date=dt.date(2026, 3, 10), notification_date=None,
        owner=None, ticker="AAPL", asset_name="Apple", asset_type="ST",
        transaction_type="P", amount_low=1001, amount_high=15000,
        evidence_url="https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/2026/100.pdf",
    )
    monkeypatch.setattr(consolidate_module, "load_disclosures", lambda *args, **kwargs: ([], [reference]))
    db_path = tmp_path / "capture.sqlite"
    with sqlite3.connect(db_path) as db:
        capture_module._schema(db)
        house_pdf._schema(db)
        db.executemany(
            "INSERT INTO house_filings VALUES (?,?,?,?,?,?)",
            [
                ("100", "Example", "Member", "CA01", "2026-03-10", reference.evidence_url),
                ("200", "Another", "Member", "CA02", "2026-03-12", "https://example.test/200.pdf"),
                ("300", "Third", "Member", "CA03", "2026-03-13", "https://example.test/300.pdf"),
            ],
        )
        db.execute(
            "INSERT INTO house_pdf_documents VALUES (?,?,?,?,?,?)",
            ("200", "abc", "2026-09-29T00:00:00Z", 1, None, house_pdf.PARSER_VERSION),
        )
        db.execute(
            "INSERT INTO house_pdf_trades VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
            ("house_200_p1_r0", "200", "2026-03-05", "2026-03-11", "SP", "Microsoft", "MSFT",
             "P", 1001, 15000, 1, 0, "https://example.test/200.pdf"),
        )
        db.commit()
    output = tmp_path / "trades.jsonl"
    result = consolidate_module.consolidate(
        db_path=db_path, reference_zip=tmp_path / "unused.zip",
        since=dt.date(2025, 9, 29), until=dt.date(2026, 9, 29),
        output_path=output, manifest_path=tmp_path / "manifest.json",
    )
    rows = [json.loads(line) for line in output.read_text().splitlines()]
    assert result["row_count"] == 2
    assert result["new_house_pdf_rows"] == 1
    assert result["unresolved_house_filing_count"] == 1
    assert not result["complete_one_year_history"]
    assert {row["data_source"] for row in rows} == {
        "kadoa_parsed_official_filing", "house_clerk_pdf_auto_extracted",
    }
