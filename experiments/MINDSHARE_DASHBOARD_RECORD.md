# Mindshare Dashboard Record

Date: 2026-06-20

## What changed

- Added a self-contained `dashboard.html` generated from current local data.
- Added `experiments/build_mindshare_dashboard.py` to rebuild the HTML without Next.js.
- Added `make mindshare-dashboard` as the repeatable command.
- Documented the experiment entry point in `ARCHITECTURE.md`.

## Data sources

- `data/prismo_snapshot.db`: Prismo Reddit snapshot.
- Optional forum aggregate: `/Users/tongzheng/equity1000/forum_mindshare.json`, or the file pointed to by `FORUM_MINDSHARE_JSON`.

The forum aggregate contributes ticker-by-region and region-by-ticker examples for:

- JP Yahoo Finance
- KR Naver
- US Reddit
- TW PTT

## Supabase audit

Supabase was checked read-only on 2026-06-20. The cloud database currently has the Reddit core tables and app tables, but does not have persisted multi-forum tables:

- `asia_posts`: absent
- `asia_analysis`: absent
- `asia_ticker_summary`: absent
- `asia_price`: absent
- `gr_post`: absent
- `gr_ticker_region`: absent
- `gr_ticker`: absent
- `gr_quote`: absent

So the generated HTML uses Supabase/SQLite Reddit data for Prismo core metrics, and the local equity1000 forum aggregate for JP/KR/US/TW examples.

## Verification

- `make mindshare-dashboard`
- Parsed the embedded JSON from `dashboard.html`.
- Checked that forum data is embedded: 40 tickers, JP/KR/US/TW region lanes.
- Ran `node --check` on the generated page script.

No database writes or DDL were run.
