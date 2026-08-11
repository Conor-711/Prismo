# bSmart iOS

The iOS app is the primary MVP client. It is a native SwiftUI application and
shares backend, database, algorithms, API contracts, and design tokens with the
rest of the bSmart repository.

## Requirements

- Xcode 16 or newer
- XcodeGen 2.44 or newer
- iOS 17 or newer

## Generate and run

```bash
make ios-generate
open ios/bSmart.xcodeproj
```

For command-line verification:

```bash
make ios-build
make ios-test
```

## Data environments

Normal Debug launches use the bundled contract fixtures, so Simulator and
physical iPhone previews work without a development server. The `bSmart Local`
scheme is reserved for an explicitly configured local API.

`bSmart Internal Alpha` is a separate release-optimized scheme. It excludes all
fixture JSON and connects through `HTTPBSmartAPIClient` to the live Vultr API.
Validate it with `make ios-alpha-check`; override `IOS_ALPHA_API_BASE_URL` only
with an HTTPS Internal Alpha deployment. The bundle gate verifies that the
declared endpoint is embedded exactly. `make ios-release-check` separately
proves that the public Release points to `https://api.bsmart.today`.

GitHub Actions runs the iOS unit suite and both bundle gates for every
iOS-affecting pull request. To create a signed
Internal Alpha archive locally, set `APPLE_TEAM_ID` and run
`make ios-alpha-archive`; `IOS_ALPHA_API_BASE_URL` and
`IOS_ALPHA_ARCHIVE_PATH` are optional overrides.

The live client creates an anonymous installation session before the first
protected request. Its stable installation UUID is kept in `UserDefaults`; the
opaque Bearer token is kept in Keychain and refreshed after authorization
failure. This is transport identity, not a user login.

Live mutations are local-first. Portfolio edits, signal state, notification
preferences, and APNs device registration enter a durable, coalescing outbox and
retry in the background. Portfolio entries retain their client-generated UUID
through idempotent `PUT /v1/portfolio/{id}`. Debug fixture scenarios do not start
the sync coordinator.

The current fixture slice exercises the first portfolio-signal loop, including
an explicit Smart Account-only MSTR signal with `smartMoneyCoverage=unavailable`.
Today surfaces signals for locally held and watched tickers; event detail shows
coverage, user context, evidence, and the next research step. Portfolio entries
support add, edit, delete, position/watchlist conversion, optional cost basis,
optional declared weight, and `UserDefaults` restoration.

The Mock-data MVP also includes a generated daily portfolio brief and persistent
Smart Account / Smart Money follows. Signals from followed actors can surface in
Today even when the ticker is outside the current portfolio, while tracked ticker
signals remain the primary feed. Today can filter the current feed by evidence
system, relationship state, or unread state. Follow state and signal state are
both local-first.

Alert preferences are also local-first. `NotificationPreferencesStore` persists
important-change delivery, daily digest time, quiet-hour boundaries, and
per-ticker switches while preserving the existing local preview notification.
The production APNs service will consume the same choices after device and
anonymous-session endpoints are available.

The secondary Opportunity Radar exercises discovery without turning Today into
a generic market feed. It only shows important fixture signals from the covered
stock universe that are outside the local portfolio and watchlist. Users can
inspect the same Smart Account / Smart Money evidence detail and add the ticker
to their watchlist in one step. Production candidate qualification remains a
backend Signal Engine responsibility.

Debug launch scenarios support repeatable UI and screenshot acceptance:

```text
--ui-scenario=first-use|loaded|no-signals|loading|error
--ui-section=today|portfolio|research|smart
```

These arguments compile only in Debug and do not change production navigation.

## Module boundaries

- `bSmart/App`: app lifecycle and root navigation.
- `bSmart/Core/Models`: stable client-side representations of API contracts.
- `bSmart/Core/Data`: API clients, anonymous session, local state, and durable remote sync.
- `bSmart/Core/DesignSystem`: shared native tokens and components.
- `bSmart/Core/Notifications`: notification permission, preview, and preference state.
- `bSmart/Features`: user-facing product scenes.
- `BSmartTests`: model, ranking, persistence, and presentation tests.

SwiftUI code must not read `data/dev.db`, reproduce Score calculations, or call
platform-specific data providers directly.
