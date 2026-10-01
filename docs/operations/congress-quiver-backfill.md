# Congressional trade backfill

This workflow captures licensed Quiver public-page trade records for a bounded
transaction-date window and checks its House filer selection against the official
House Clerk's annual financial-disclosure ZIP indexes. It does not scrape the Senate
eFD site or bypass Quiver rate limits. Only normalized data is stored, not the
downloaded web pages or ZIP archives.

## Run

From the repository root:

```sh
uv run --with requests python -m pipeline.jobs.congress_quiver_backfill \
  --since 2025-09-29 --until 2026-09-29 \
  --db data/exports/congress/quiver_backfill.sqlite \
  --report data/exports/congress/quiver_backfill.report.json
```

The SQLite database is a checkpoint. Repeating the command with the same date
window resumes unfinished member pages. Use `--refresh` to re-fetch successful
pages after source corrections. Use a different database for a different window.
HTTP 401/403/429 stops the crawl immediately; honor any `Retry-After` header and
the licensed access terms before resuming. Do not rotate identities or proxies to
work around a limit. If the license includes an export or API, prefer that over
public HTML.

## Data quality and coverage

- `trades` are vendor-derived. `source_url` is the member's Quiver page and
  `verification` remains `vendor_only`. Do not represent it as an original filing.
- `house_filings` contain PTR document IDs and official PDF URLs, but are only a
  filing-level checklist. A filing may contain multiple transactions; its filing
  date may fall inside the window while its transactions do not, or vice versa.
- `unmatched_house_filers`, `house_index_errors`, and `member_errors` must be empty
  before considering capture technically complete. Even then, trade-level match
  to the official House PDFs and equivalent Senate source checks remain required
  before claiming complete official coverage or publishing performance scores.
- The current Senate eFD portal does not provide a public bulk index in this
  workflow; Senate rows remain licensed-vendor observations, not official audits.
- The source may later publish a transaction that occurred during a prior window.
  Re-run overlapping windows or refresh historical member pages to ingest late
  disclosures.

The code deliberately keeps Quiver-specific parsing isolated from the existing
Disclosed Capitol and investor-score pipelines. Promotion to app-facing feeds
requires explicit provenance, deduplication against original filings, and a
separate review of completeness and licensing scope.

## Official House gap extraction

The reference dataset can be used to identify which House PTR PDFs have no
parsed trades at all. The House parser fetches only those missing documents,
extracts transaction rows from text-based PDFs, and records scanned or malformed
PDFs as failures. It never silently accepts a document with an unrecognized row.

```sh
uv run --with requests --with pdfplumber python -m pipeline.jobs.congress_quiver_backfill.house_pdf \
  --db data/exports/congress/quiver_backfill.sqlite \
  --report data/exports/congress/house_pdf_gap_report.json \
  --since 2025-09-29 --until 2026-09-29 \
  --reference-zip data/exports/congress/congress-trading-monitor-current.zip
```

Re-running resumes successful PDFs. `--refresh` forces another attempt, including
known scanned documents. The parser version is stored per PDF so future parser
changes trigger reprocessing. Scanned documents require a separate reviewed OCR
workflow; the current extractor does not treat rough OCR as reliable trade data.

Produce a filing-level comparison and a research-only merged export:

```sh
uv run --with requests --with pdfplumber python -m pipeline.jobs.congress_quiver_backfill.audit \
  --db data/exports/congress/quiver_backfill.sqlite \
  --reference-zip data/exports/congress/congress-trading-monitor-current.zip \
  --since 2025-09-29 --until 2026-09-29 \
  --csv data/exports/congress/house_ptr_coverage.csv \
  --report data/exports/congress/house_ptr_coverage.json

uv run --with requests --with pdfplumber python -m pipeline.jobs.congress_quiver_backfill.consolidate \
  --db data/exports/congress/quiver_backfill.sqlite \
  --reference-zip data/exports/congress/congress-trading-monitor-current.zip \
  --since 2025-09-29 --until 2026-09-29 \
  --output data/exports/congress/congress_trades_1y_research.jsonl \
  --manifest data/exports/congress/congress_trades_1y_research.manifest.json
```

The merged export labels each record's extraction source and review status. It
does not merge partially crawled Quiver rows or claim complete House/Senate
coverage. As of 2026-09-29, 30 indexed House PTRs are unresolved (29 scanned,
one download failure), and Senate original-filing coverage is unverified.
