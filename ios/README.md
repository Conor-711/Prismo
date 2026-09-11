# bSmart iOS

The iOS app is the primary MVP client. It is a native SwiftUI application and
shares backend, database, algorithms, API contracts, and design tokens with the
rest of the bSmart repository.

## Accounts and device wallet

The current scope is Google login only, directly through Supabase Auth.
Apple sign-in and automatic wallet setup on the account page are disabled.
See [setup checklist](../supabase/ios-account/README.md). Native configuration is
in `project.yml` plus gitignored `Config/Supabase.xcconfig.local`; private wallet
material remains in device-only Keychain. Login also works with fixture research
data. Google login does not require Vultr, wallet tables, or an Edge Function.
Real-user Google authorization still needs acceptance; wallet deployment and
real funds are separate, later steps. See Settings > Account > Google.

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

## Package resolution recovery

If Xcode reports `Missing package product 'WalletCore'` or
`WalletCoreSwiftProtobuf`, inspect the first package-resolution error. A timeout
fetching another dependency (for example GoogleSignIn) can invalidate the entire
graph and produce these secondary errors. Restore network access and run:

```bash
make ios-resolve
```

This regenerates the project from `project.yml` and resolves packages into
Xcode's normal workspace cache. It does not delete DerivedData, remove package
pins, upgrade Wallet Core, or modify wallet data. Then build again in Xcode;
if the open workspace still shows stale errors, use File > Packages > Resolve
Package Versions. The local `Packages/WalletCore` manifest must remain in the
repository; its two official binary artifacts are downloaded and checksum-checked
by SwiftPM, not copied from a temporary build directory.

## Data environments

Normal Debug launches use the bundled contract fixtures, so Simulator and
physical iPhone previews work without a development server. The `bSmart Local`
scheme is reserved for an explicitly configured local API.

Internal testing may call DeepSeek directly while the rest of the app continues
to use bundled data. Create `ios/Config/Secrets.xcconfig` from the example and
set `BSMART_DEEPSEEK_API_KEY`. The file is ignored by Git, but the key is still
embedded in the built app and must be treated as temporary and rotated. Remove
the local key to restore the server AI boundary or deterministic on-device
fallback.

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

The current fixture slice exercises independent Smart Account views and Smart
Money actions for locally held and watched tickers. Today does not manufacture
same-direction, opposite-direction, or divergence relationships between sources
that may operate on different horizons. It ranks the raw activities by portfolio
exposure, evidence quality, action magnitude, and recency, then shows the actor,
reason or observed action, horizon, target or position change, user context, and
auditable source evidence. Read state is local-first and persisted in
`UserDefaults`.

Portfolio entries support add, edit, delete, position/watchlist conversion,
optional cost basis, optional declared weight, and `UserDefaults` restoration.
Smart Account / Smart Money follow state and legacy aggregate signal state remain
available to their detail and research surfaces, but they do not add generic or
untracked content to Today.

Alert preferences are also local-first. `NotificationPreferencesStore` persists
important-change delivery, daily digest time, quiet-hour boundaries, and
per-ticker switches while preserving the existing local preview notification.
The production APNs service will consume the same choices after device and
anonymous-session endpoints are available.

Opportunity discovery remains available outside Today. Production candidate
qualification remains a backend responsibility; Today is limited to holdings
and watchlist activity.

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
