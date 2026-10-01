# Disclosed Capitol Congress Trade Capture

This is an evaluation feed, not an App publication source. Its current `/trades`
response omits `owner` and an original filing URL, both required by the
`congress_score` contract. Do not attribute household trades to a member
personally or score them without independent source verification.

## Run

Put `DISCLOSED_CAPITOL_API_KEY` in the ignored repository `.env` or the process
environment. Keep it server-side; never put it in iOS or web bundles.

```sh
uv run --with requests --with python-dotenv python -m pipeline.jobs.congress_capture
```

The job stores an idempotent raw snapshot at
`data/exports/congress/disclosed_capitol.json`. By default it requests the last
30 days, or resumes from the last complete query with a seven-day overlap.
Use `--since` and `--until` for a bounded historical window. The normal
`pipeline.manage congress-fetch` command is also registered when the full
pipeline environment is installed.

The default is one page of 50 rows. `possibly_truncated: true` means that the
query was not proven complete and the completion watermark is not advanced.
The command rejects requests whose estimated maximum cost exceeds 100 credits;
raise `--credit-budget` explicitly if a wider fetch is intended.

## Cost and provenance

The API's response headers on 2026-09-28 indicated a charge of 15 credits plus
approximately one credit per returned row. This is an observed estimate, not
a price guarantee. Check current vendor pricing before automation; the free
grant is not enough to assume continuous production updates.

The snapshot preserves the vendor's original rows and metadata. A row's
`source: house.gov` or `senate.gov` is not a document-level citation. The
`missing_owner_count` and `missing_filing_url_count` fields expose those gaps.
Before app publication, obtain the filing URL and actual owner, reconcile
amendments, validate coverage against official disclosures, and review whether
the proposed commercial use is permitted under 5 U.S.C. 13107(c).
