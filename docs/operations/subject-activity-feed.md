# Subject activity feed

The home activity feed accepts politicians, public figures, and institutions through one snapshot contract. Social and bSmart accounts continue to use their existing content sources. `subject-activity.json` is a local fallback; authenticated iOS clients prefer `GET /functions/v1/bsmart-content/subject-activity` when a production snapshot exists.

## Subject images

On October 1, the user selected six original images for Citadel, Nancy Pelosi,
Duan Yongping, Ken Griffin, Bill Ackman, and Warren Buffett. Their unmodified PNGs
are bundled under the existing stable subject IDs; `bundledOverrides` in
`subject_avatar_sources.json` records their checksums and user-provided provenance.
The congressional portrait sync validates and preserves Pelosi's override instead
of replacing it with a downloaded JPEG. Remote URLs and credits below still describe
fallback images, not the selected originals. Citadel's square blue mark uses the
full avatar bounds rather than the old horizontal-logo crop. These changes require
a new iOS build and have not been uploaded to TestFlight.

The published congressional snapshot has 110 politicians with Bioguide-keyed portraits in `ios/BSmart/Assets.xcassets/SubjectAvatar_politician_*.imageset`. Their HTTPS image URLs are also in the snapshot for installed builds without the new bundled assets. `pipeline/jobs/congress_capture/research_feed.py` contains the reviewed corrections for wrong or missing upstream portrait IDs; `portrait_assets.py` fetches and validates every selected JPEG before writing any assets. A record with unresolved politician identity or portrait is withheld from the public feed, not shown with a guessed face. Verified public-figure portraits and existing institutional marks are documented in `subject_avatar_sources.json`; institutions without a vetted compact mark use their text monogram, not another firm's logo.

Subject detail portraits resolve a bundled name only when the image actually exists;
otherwise they load the published HTTPS URL through the shared avatar cache. A name
alone must never disable remote loading for newly published subjects. Duan Yongping's
Renmin University photograph and Leopold Aschenbrenner's personal-site photograph
are also bundled unchanged for offline display, using the reviewed sources and
copyright notices in `subject_avatar_sources.json`. This fallback fix and the new
bundled assets require a new iOS build; a server snapshot alone cannot repair older
clients that skip remote loading.

The U.S. congressional photos are from the public-domain [Images of Congress](https://github.com/unitedstates/images) collection, except Alan Armstrong's [official Senate portrait](https://commons.wikimedia.org/wiki/File:Alan_S_Armstrong_official_portrait_(cropped_2).jpg). Bill Ackman's [photo](https://commons.wikimedia.org/wiki/File:Bill_Ackman_(26410186110)_(cropped).jpg) is by Senate Democrats under [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/); it is cropped for the circular avatar. Warren Buffett's [White House photo](https://commons.wikimedia.org/wiki/File:Warren_Buffett_in_2010_(cropped).jpg) is public domain. Cathie Wood's [photo](https://commons.wikimedia.org/wiki/File:Cathie_Wood_ARK_Invest_Photo.jpg) is by Caroline Wood under CC BY-SA 4.0. David Tepper's [photo](https://commons.wikimedia.org/wiki/File:David_Tepper_01.jpg) is by Appaloosa Management under CC BY-SA 3.0. Daniel Loeb's [photo](https://commons.wikimedia.org/wiki/File:Daniel_Loeb,_Third_Point.jpg) is by Hedge Funds under CC BY 3.0. The three new portraits are bundled without modification. Michael Burry's portrait is the user-provided image already used in the product prototype. Organization marks are used for identification only and remain their owners' trademarks.

Peter Thiel's [portrait](https://commons.wikimedia.org/wiki/File:Peter_Thiel_by_Dan_Taylor.jpg) is by Dan Taylor under CC BY 2.0; the feed uses an accessible copy of that image hosted by Inter Press Service, and the bundled iOS avatar is square-cropped. His display identity follows Thiel Macro LLC (SEC CIK 1562087) 13F filings, not personal trading or Founders Fund's separate filings.

On September 30, the verified Thiel Macro 2026-Q2 filing added Peter Thiel as the 19th public figure with eight highlighted holdings events. The production snapshot was published and read back with 162 subjects and 5,793 events. Its Q2 report period is June 30 and filing date is August 14; the feed uses the latter for display ordering.

## Contract

`schemaVersion` is `1`. `subjects` contains stable `id`, `kind` (`politician`, `celebrity`, or `institution`), `name`, optional `avatarURL`, and `metrics`. `events` contains stable `id`, `subjectID`, optional `ticker`, `type` (`trade`, `opinion`, or `holding`), `occurredDay`, `displayDay`, optional `assetName`, `assetDescription`, `sourceURL`, `sourceNote`, and `isSample`. A trade requires `ticker` and `action` (`buy` or `sell`). An opinion requires `ticker`, `direction` (`bullish`, `bearish`, or `neutral`), and a nonempty `summary`. A holding requires `assetName`, a source URL, and an `action` (`new`, `increased`, `reduced`, `no_longer_reported`, or `held`); `ticker` stays null if it cannot be resolved. Dates use `YYYY-MM-DD`. `displayDay` controls feed ordering. A subject's `metrics` is either null (the app shows labeled preview values) or `{ "wins": 12, "losses": 5, "trackedReturn": 0.18 }` (a fraction, not a percent). A sample event must set `isSample: true`; real imports set it to `false`.

The bundled fallback is generated from `data/exports/congress/congress_trades_1y_research.jsonl`, its source ZIP, and available verified SEC 13F files in `data/exports/institutional_holdings`. The production snapshot now uses the trailing-three-year backfill below: as of September 30 it has 164 politician, 19 public-figure, and 34 institutional display identities with 19,802 events. This is **not** proof of every official congressional transaction: the upstream extraction is incomplete, and unsupported tickers, actions, or unverified portraits are withheld. Each included trade links its source filing and says whether extraction is pending review. Cathie Wood and ARK Investment Management share the same underlying ARK 13F filing, as do other person/manager pairs; these entries are not independent transactions. Farallon's latest amendment requires review and is withheld rather than merged into the original filing. David Einhorn and Greenlight Capital use the current DME Capital Management LP filing, not Greenlight Capital Inc.'s stale historical filing. No win rate, follow return, or rank is fabricated for these subjects. The home activity view shows recent disclosures; an opened subject timeline in updated clients can load imported older events. Each 13F subject contributes up to eight leading reported positions or changes per quarter. These are selected highlights, not a complete portfolio. For a 13F event, `occurredDay` is the report period end and `displayDay` is the filing date; it is not an executed trade timestamp. In particular, Michael Burry's available filing is stale, and some managers file partial combination reports. The associated manager's 13F is attributed to the named subject but does not establish a personal trade ledger. The source attribution and original filing link remain available in event details.

The bundled export does not update automatically when the source files change. The production snapshot can instead be checked and published by the half-day refresh worker below. Supply non-null metrics only after a compatible performance calculation is complete.

## Three-year research estimates

`pipeline.jobs.subject_open_returns.publish` attaches the reviewed three-year report to each matching production subject as `research`, without writing the separate audited `metrics` or Score. It publishes direction wins/losses from the next executable post-disclosure open to the latest close; derived rates use wins / (wins + losses), excluding flat observations from the denominator. It also publishes the equal-lot average return on proxy positions still open at the report date. The latter is not a 30-day hold, a copyable portfolio return, or a personal realized return. Each record carries `method`, `sourceSince`, `asOf`, `latestMarketDate`, priced/candidate counts, and nullable rates. Missing sample coverage stays null. In the iOS activity card and subject detail, “Win rate” (胜率) displays the two win/lose counts as green/red badges, matching Smart Account cards; it does not display a percentage. “Follow return” (跟踪收益) is the fixed title for the open-position return percentage. After publication and before building iOS, run `export_ios_bundle` so the offline fallback also includes the validated production research; otherwise the app initially displays dashes until its optional network fetch completes. The half-day content refresh preserves research for identities that still match but does not recalculate it; rerun the research job and publisher when source data or prices change.

```sh
uv run --offline --with requests --with 'psycopg[binary]' --with pdfplumber \
  python -m pipeline.jobs.subject_open_returns.publish
uv run --offline --with requests --with 'psycopg[binary]' --with pdfplumber \
  python -m pipeline.jobs.subject_open_returns.publish --apply
  python -m pipeline.jobs.subject_open_returns.export_ios_bundle
```

All three commands require the protected `BSMART_CONTENT_DATABASE_URL`; dry-run reports the intended number of changed subjects. `--apply` locks the live row, validates the merged snapshot, commits atomically, and reads it back. The export reads the same 400-day server projection, validates complete research coverage, and atomically replaces the bundled JSON; it does not publish to the server. Do not substitute these estimates for published Score or the existing platform-account research.

## Three-year history backfill

### Duan Yongping and home editorial priority

`celebrity:duan-yongping` maps to H&H International Investment, LLC (CIK 1759760).
The [HKEX controlled-corporation disclosure](https://di.hkex.com.hk/di/NSForm1.aspx?fn=IS20260710E00009)
identifies Yong Ping Duan as its controlling shareholder. This remains the firm's
delayed U.S. 13F book, not a complete personal or live portfolio. His portrait is
the single-person lecture photograph in the [Renmin University alumni report](https://econ.ruc.edu.cn/xwdt/eb8b92e039fb45778939b738cd7c2337.htm),
an editorial identity reference with no open license asserted.

Use the scoped backfill below with `--subject duan-yongping`, then compute research
with `python -m pipeline.jobs.subject_open_returns --subject duan-yongping --output
data/reports/duan-open-returns --as-of <completed-market-day>`. Scoped research
cannot overwrite the default full-roster report directory and does not read the
congressional archive or unrelated SEC histories. Review pricing coverage before
attaching the validated research via `research_rows(..., subject_ids={...})` and
the atomic scoped publisher. Scoped publication validates the full merged snapshot
before writing, then checks the complete subject/event counts, root metadata and
every selected subject/event in SQL without transferring the full three-year JSON
again inside the locked transaction. No change to the metric algorithms or audited Score.

The updated iOS home trend rail prioritizes Pelosi (`politician:P000197`), Peter
Thiel, Duan Yongping, Citadel, Bill Ackman, Leopold and Warren Buffett, one latest real event per
identity. These editorial slots can use the existing 400-day home disclosure
window so quarterly filers are not silently excluded by the general seven-day
trending filter. Missing, future, sample and expired records do not create cards.
Other slots keep the current recent trend ordering. Main feed and leaderboard
ordering are unchanged; the rail change requires a new iOS build.

All subject portraits in the trend rail, leaderboard, activity cards, detail pages and quoted
activity cards use `TodaySubjectProfile.avatarAssetName(for:)` with the stable
subject ID. The bundled asset takes priority over a stale remote URL; the remote
URL is a fallback only when that asset does not exist. Institutional quote avatars
retain the organization-logo treatment rather than the person-photo crop.

October 1 publication verified 12 quarters (Q3 2023 through Q2 2026), 93 disclosed
highlights (80 resolved cash-equity event tickers), the university portrait, and
the existing research methodology at September 29 close: 47 win / 54 lose and
+24.01% mean open-proxy return across 16 priced positions. Two latest holdings
remain unmapped and are excluded from research, not guessed. All price downloads
passed on retry. The production roster is 219 subjects / 19,949 events, verified
again after commit; the regenerated 400-day iOS fallback has 8,693 events and
research for all 219 identities. Receipt: ignored `data/runtime/duan-publication/receipt.json`.
This is estimated institution-disclosure performance, not live personal returns.

For a newly verified curated identity, use the scoped backfill instead of re-fetching every source:

```sh
uv run --offline --with requests --with 'psycopg[binary]' --with pdfplumber \
  python -m pipeline.jobs.institutional_holdings.backfill_subjects --subject leopold-aschenbrenner
```

Review `data/reports/selected-subject-backfill.json` and period coverage before repeating with `--apply`. Every report must match the curated reporting manager; unknown identities and conflicting amendments fail closed. Publication merges under the production row lock and reads back the result, retaining other subjects/events and existing research/metrics. This imports disclosed highlights, not a live portfolio or three years of invented history before the manager first reported. Leopold Aschenbrenner maps to Situational Awareness LP, CIK 2045724, with available reports starting Q4 2024. His personal-site portrait is an editorial identity reference; no open image license is asserted.

The research publisher accepts `--subject leopold-aschenbrenner --report-dir <reviewed-scoped-report>` for a scoped report containing exactly the requested verified 13F identities. Without explicit selection it still requires the full reviewed roster. The underlying win/lose and open-position return algorithms are unchanged; exclude incomplete market sessions from the research valuation date. A newly added identity may carry its validated `research` in the scoped feed so history and indicators publish in one transaction.

October 1 verification: Leopold's seven available quarters produced 54 disclosed highlights, 37 with resolved cash-equity tickers. The atomic production merge increased the roster to 218 subjects and 19,856 events; a separate post-commit read verified his portrait, every event count and research fields. The reviewed September 29 completed-session research has 19 priced open proxies, 55 direction wins / 48 losses (one flat observation), and +59.59% equal-lot mean open return. Price downloads passed after using the local trusted CA bundle; no TLS verification was disabled. These are filing-based estimates, not proof of live holdings or realized fund returns. Receipt: ignored `data/runtime/leopold-publication/receipt.json`; reviewed scoped report: `data/reports/leopold-open-returns/`.

Tristan Thompson remains pending: [the supplied September 30 post](https://x.com/burrytracker/status/2105315068040581307) claims 20 Flagship holdings but does not identify an accession, reporting manager or reporting period. SEC full-text checks on October 1 found Fourth Pick Ventures/SPV II Form D fundraising notices and other mentions, not a matched Flagship 13F. Do not use those Form D CIKs as portfolio filers or calculate returns from the post's weights. A primary manager/portfolio source is required before publication.

`pipeline.jobs.congress_capture.backfill_three_years` checks congressional transactions dated in the trailing three calendar years and SEC 13F reports whose quarter ends fall in that window. The validated upstream congressional ZIP is retained in the ignored `data/exports/congress` directory for audit. It fetches the immediately preceding 13F quarter only as a comparison baseline. SEC filing documents are verified by CIK, report period, accession, filing date, manager and amendment type, then compressed under the ignored `data/exports/institutional_holdings/history` directory by CIK/accession. This local archive is a resumable research checkpoint, not an iOS asset. A restatement replaces the base filing; a NEW HOLDINGS amendment supplements it and retains its own disclosure date and filing URL. Additional shares of the same security are summed only when its issuer and security identity agree. A failed or conflicting amendment blocks full backfill publication rather than being mistaken for a complete filing. The command writes a per-subject quarter-coverage and source-error report under `data/reports/`.

Run a dry check first, then publish only after its coverage report is reviewed:

```sh
uv run --with requests --with 'psycopg[binary]' --with pdfplumber python -m pipeline.jobs.congress_capture.backfill_three_years
uv run --with requests --with 'psycopg[binary]' --with pdfplumber python -m pipeline.jobs.congress_capture.backfill_three_years --apply
```

The server stores one validated three-year snapshot, but `bsmart_subject_activity_read` filters its JSONB in Postgres: the home endpoint returns only the most recent 400 days, and the subject detail endpoint accepts `?subjectID=<kind>:<id>` for that subject's complete history on demand. This keeps older TestFlight builds below their 8 MB response limit and avoids transferring the full snapshot through the Edge Function for every home refresh. A build containing the subject-detail request is needed to browse all three years in the app. The published institutional feed still selects up to eight leading disclosed holdings/changes per filer and quarter; the compressed archive holds the full verified information tables. A 13F is neither a live portfolio nor a personal trade ledger. The Kadoa source and old House-gap parser do not prove complete official House/Senate coverage, so the year-by-year report must not be described as every transaction.

## Half-day production refresh

`pipeline.jobs.congress_capture.refresh_cycle` checks the trailing three calendar years of Kadoa congressional disclosures and the curated SEC 13F filers. It uses temporary files only, so a container needs no persistent disk. The worker keeps previously published, automatically extracted House rows, older verified 13F quarters within the window, and live records for a source that fails its check. It rejects truncated congressional coverage, insufficient verified 13F coverage, and a candidate losing more than 20% of existing events. Matching events keep newer live price observations. Within a database transaction it locks the production row, validates the candidate, and publishes only when subjects or events changed. An unchanged check does not update `snapshotAt` or the row's `updated_at`.
The publication transaction uses a 180-second local statement timeout so a large validated JSONB snapshot is not canceled by the database role's shorter default; failure still rolls back the whole update.

For local verification, run from the repository root:

```sh
uv run --with requests --with 'psycopg[binary]' --with pdfplumber \
  python -m pipeline.jobs.congress_capture.refresh_cycle --dry-run
```

The protected `BSMART_CONTENT_DATABASE_URL` and real `BSMART_OFFICIAL_CONTACT` must be set in the environment. The local developer configuration may also provide them from `services/client_api/.env.content.local` and `.env`. Do not commit either secret. The JSON result includes source failures, quarantined amendments, whether publication happened, and the count of new event IDs. An unexpected source failure exits with status 2 even if another source published successfully. The known Farallon `amendment_requires_review` remains quarantined and is rechecked on later runs; it is never represented as a full filing.

`services/subject_activity_refresh/Dockerfile` and `railway.json` define a cloud cron service at 00:00 and 12:00 UTC. Deploy it from the repository root as a separate Railway service, selecting that config file and setting both variables above in Railway's protected service variables. Verify a successful run and a subsequent no-change run in its logs. **The cron configuration in the repository is not itself a deployed schedule.** Until the service is deployed, no server-side automatic check is guaranteed.

The existing TestFlight app reads `GET /functions/v1/bsmart-content/subject-activity` for an authenticated user when loading and on foreground refresh. A successful server publication therefore appears without a new iOS build after the app fetches again; this workflow does not send an APNs push or force an inactive app to refresh in the background. The App retains its last in-memory or bundled snapshot when the endpoint fails.

## Update

1. Apply `supabase/ios-account/supabase/migrations/202609290001_subject_activity.sql` and `202609290003_subject_activity_publish_chunks.sql`, then deploy the `bsmart-content` function.
2. Set the operator's real `BSMART_OFFICIAL_CONTACT` in the process environment and run `python3 -m pipeline.jobs.institutional_holdings` after quarterly filings. Shared-CIK identities are fetched only once. A fresh snapshot is never inferred from a reused local copy; `--reuse-verified-filing-from ark --subject cathie-wood` preserves the original check time.
3. Generate the local snapshot with `python3 -m pipeline.jobs.congress_capture.research_feed`, then run `python3 -m pipeline.jobs.congress_capture.portrait_assets` to audit and bundle all politician portraits.
4. Validate an incoming complete snapshot with `python3 -m pipeline.jobs.congress_capture.subject_feed_publish path/to/snapshot.json`. Add `--allow-samples` only for testing sample rows.
5. Set `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`, then add `--apply` to publish. When project REST is unreachable, use `SUPABASE_ACCESS_TOKEN` with `--management-project-ref <ref> --apply`; snapshots too large for one Management API request are staged in chunks and promoted only after count, order, and MD5 checks. The publisher verifies subject and event counts by readback. Publication replaces the one production snapshot atomically. Deploy `bsmart-content` after creating the table. The App retains the last loaded/bundled snapshot when the optional endpoint is unavailable.

Do not put credentials in the snapshot or commit them to the repository. The publisher is deliberately not run as part of building the iOS app.
