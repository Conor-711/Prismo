# Supabase Research Content

Version 1, 2026-09-15. This is a separate research read channel, not Auth,
wallets, orders, user profiles, or the trade feed. Existing `/v1` contracts remain.

`bsmart-content` verifies the current Supabase Google/Apple user before any read.
No anonymous, installation-token, or service-key access from iOS. Database tables
have RLS enabled with no client policies; only the Edge Function's service role
can read. Publication uses a protected PostgreSQL connection, never an app key.

GET `/functions/v1/bsmart-content/manifest` returns an immutable release manifest:
`schemaVersion: 1`, `revision: sha256`, and `collections` containing `count`,
`sha256`, `checkedAt`, `latestContentAt` (nullable). A pointer selects the active
revision. Changing the pointer does not modify previous releases.

Collection hashes use items sorted by id (or ticker), recursively sorted object
keys and compact UTF-8 JSON. Integral floats are normalized to integers, including
negative zero to zero, before hashing; JSONB/JavaScript numeric spellings must not
change a content hash. Booleans remain booleans, and NaN/infinity are rejected.
Input file checksums remain hashes of exact file bytes, a separate validation.

GET `/functions/v1/bsmart-content/page?revision=...&collection=...&owner=...&page=0`
returns `{revision, page, pages, total, items}`. Non-evidence collections use owner
`_`; evidence uses the exact author/account ID. Unknown evidence owner returns an
empty page only for a valid retained release. Unknown release returns 404, never
silently the latest revision. Each stored page is at most 256 KiB and 100 items.
Invalid parameters: 422; invalid credentials: 401; Auth/database failure: 503.
Authenticated responses use `Cache-Control: no-store`; iOS keeps decoded content
and compares manifest hashes rather than relying on a shared HTTP cache.

Collections retain existing `bsmart-v1.yaml` item schemas: smart-accounts,
smart-account-updates, smart-account-evidence, portfolio-signals, ticker-intelligence,
smart-money, smart-money-movements, smart-money-evidence. No personal portfolio,
balances, read states, session, or wallet data belongs in a research release.

iOS stages all six non-evidence collections from one revision and decodes all
before committing. Unchanged collection hashes reuse decoded data. Evidence is
read lazily with the captured revision; a response for an obsolete revision is
discarded. Errors retain prior content and actual timestamps. Polling is foreground
only, every 60 seconds, with existing persisted-cache fallback.

First publication requires a complete reviewed baseline, not an X-only package.
`content-manifest.json` contains schemaVersion 1, status ready, and all eight
collection entries (`count`, file `sha256`, `checkedAt`, `latestContentAt`).
Dates must describe the actual source processing, not a file copy time. Publisher
validates the existing OpenAPI models before storing. Subsequent daily-X releases
reuse the existing daily-X validation and replace only X rows in four collections.
Other platforms, metadata and collections are preserved. Daily-X hashes are
deduplicated; older daily data and unexplained drops over 25% are rejected.
The pointer and pages commit in one PostgreSQL transaction under a publisher lock.
Rollback explicitly reactivates a retained revision without changing timestamps.
`--baseline --reencode-baseline` permits replacing a legacy hash encoding only
when every stored item and source timestamp equals the reviewed baseline. It
creates/reuses a corrected immutable version and retains the previous version;
it cannot replace baseline content or be used as a daily update bypass.

Deployment is opt-in (`BSMART_CONTENT_BACKEND=supabase`). No automatic fallthrough
to Vultr on server failure; legacy mode remains available at build configuration.
Local user-state persistence remains; legacy installation-state cloud sync is not
used in this mode. It is not a migration of that private state to Supabase.
