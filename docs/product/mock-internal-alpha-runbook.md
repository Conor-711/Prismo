# bSmart Mock Internal Alpha Runbook

## Purpose

This build validates the complete iOS product, network, cache, offline, deep-link
and notification workflow with mock evidence. It does not validate market
coverage or signal quality. Every tester-facing market claim must remain marked
as demonstration data.

## Environment isolation

| Surface | Internal Alpha | Public Release |
| --- | --- | --- |
| Xcode configuration | `InternalAlpha` | `Release` |
| Scheme | `bSmart Internal Alpha` | `bSmart` |
| Data label | `demo` | `production` |
| API origin | `https://mock-api.bsmart.today` or approved override | `https://api.bsmart.today` |
| APNs environment | development | production |
| Bundled fixture JSON | forbidden | forbidden |

The Internal Alpha API uses separate installation-state and read-model
databases. Contract fixtures are materialized into that database before the API
starts; the iOS app never reads fixture files in a release-optimized build.

## Local API verification

```bash
make client-api-install
make client-api-alpha-seed
make client-api-alpha-dev
```

The local server listens on `http://127.0.0.1:8082`. Use the ordinary Debug
scheme with `--use-live-api` and `BSMART_API_BASE_URL=http://127.0.0.1:8082` for
simulator integration. Real devices and distributed builds require an approved
HTTPS endpoint.

With the server still running, execute the reproducible end-to-end check:

```bash
make client-api-alpha-smoke
```

It creates a fresh anonymous installation, stores one position and one watchlist
ticker, validates protected Smart Account and Smart Money reads plus stable ETag
headers, then generates and reads back an immutable two-signal daily brief.

After registering a device and adding at least one portfolio ticker, generate
the installation's immutable daily brief with:

```bash
make client-api-alpha-plan-digests
```

Until this planner has run after the configured local delivery time,
`GET /v1/daily-digest` returns `404` and iOS deliberately falls back to its
current cached portfolio signals. Once generated, the push, digest screen and
offline cache must continue to show the same evidence snapshot.

The equivalent deployment container is built with
`make client-api-alpha-image`. It uses
`services/client_api/Dockerfile.alpha`, requires a persistent `/data` volume,
and exposes `/health` on port `8080`. The hosting provider must terminate TLS
for `https://mock-api.bsmart.today`.

## Build gates

```bash
make contract-check
make arch-check
make ios-test
make ios-alpha-check
make ios-release-check
```

`ios-alpha-check` fails if JSON fixtures enter the app, privacy metadata is
missing, the build is not labeled `demo`, or the endpoint resolves to the
production API. `ios-release-check` fails if the inverse production guarantees
are not true.

Pull requests that affect iOS, fixtures, client projection, or bundle gates run
the same contract, unit-test, Internal Alpha, and Release checks in
`.github/workflows/ios-mvp.yml`.

After the HTTPS endpoint is deployed and Apple signing is configured, create a
device archive with:

```bash
APPLE_TEAM_ID=YOUR_TEAM_ID make ios-alpha-archive
```

The archive helper refuses non-HTTPS endpoints and reruns the demo bundle gate
against the signed `.xcarchive` before it is uploaded to TestFlight.

## Internal acceptance

1. Start with no saved app state, add a position and a watchlist ticker, then
   reach Today without signing in.
2. Open one confirmation, one divergence and one single-sided event; verify the
   evidence, limitations, position context and next research action.
3. Save, ignore and rate a signal; relaunch and confirm state restoration.
4. Follow one Smart Account and one Smart Money account; verify their eligible
   signals can appear outside the portfolio without replacing portfolio events.
5. Open a local preview notification and a daily brief deep link.
6. Disconnect the API after a successful load; confirm cached reads and queued
   mutations remain usable, then reconnect and flush them once.
7. Reset local app data in Settings and confirm the first-use portfolio flow
   returns while the disclosure correctly states that installation identity is
   retained.
8. Read Data & methodology and Risk disclosure; verify `DEMO` remains visible
   anywhere mock events are presented.

## Verification status

| Gate | Current result | What remains |
| --- | --- | --- |
| Contracts, architecture and terminology | Automated and passing | Keep required on every affected pull request. |
| Client API | 22 tests passing | No code dependency remains for Alpha. |
| Database-backed API | Local process and non-root container smoke passing | Deploy the same image with persistent `/data`. |
| iOS Internal Alpha bundle | Release-optimized simulator build passing | Signed physical-device archive still required. |
| iOS production Release bundle | Simulator build passing; no fixture JSON | App Store signing and review are outside the repository. |
| Anonymous installation, portfolio and cache policy | Container smoke passing | Repeat once against the public HTTPS Alpha origin. |
| Immutable daily brief | Container smoke passing with two evidence snapshots | Schedule the planner in the hosting environment. |
| HTTPS Alpha origin | Not deployed | Hosting account, DNS and TLS for `mock-api.bsmart.today` are required. |
| Real APNs delivery | Not exercised | Apple Team ID, APNs Key ID, topic and private `.p8` key are required. |
| Physical iPhone acceptance | Not started | Device, signing profile and an acceptance owner are required. |
| Internal TestFlight | Not uploaded | App Store Connect access and signed archive are required. |
| Real-data dogfood | Intentionally frozen | Resume only after product approval and both evidence pipelines pass coverage gates. |

External credentials and private keys must be supplied through the deployment
platform or CI secret store. They must not be added to `.env` examples, build
artifacts, the repository or tester documentation. The remaining sequence is:

1. Deploy the validated image with persistent storage and an HTTPS health check.
2. Run `client-api-alpha-smoke` against that origin from a trusted runner.
3. Configure APNs secrets and scheduled instant/digest workers.
4. Produce a signed Internal Alpha archive and install it on a physical iPhone.
5. Record every acceptance item above before uploading the same archive to
   Internal TestFlight.

## TestFlight metadata draft

- **What to test:** add a position, inspect Smart Account and Smart Money events,
  save or ignore an event, follow an account, open the daily brief and test alert
  preferences.
- **Known limitation:** all market evidence and events are demonstration data;
  trading, broker connection and production market coverage are not included.
- **Feedback:** use Settings > Send product feedback and include the screen,
  ticker, expected behavior and observed behavior. Do not include brokerage
  credentials or other sensitive financial information.

## Exit criteria

Internal Alpha is complete only after the release-optimized build passes on a
physical iPhone, the HTTPS Mock API is reachable, notification credentials are
configured outside the repository, and every acceptance item above has an owner
and result. Real-data Dogfood remains a separate milestone and cannot reuse the
mock database or endpoint.
