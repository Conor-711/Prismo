# iOS Client Architecture

bSmart iOS is the primary MVP client. It is built from scratch in SwiftUI and
shares the existing backend, database, pipeline algorithms, product contracts,
and design language. It does not embed the website with `WKWebView`.

### Home Scroll Stability (2026-09-22)

Device watchdog reports identified main-thread stalls in representative-story
Chart layout. `TodayRepresentativeChartData` prepares domains and marker dates
once per story. `TodayRepresentativeStoryChart` projects its accessible annotation
overlay from local size with explicit matching chart scales, without geometry
preferences writing back into view state. Domain scans no longer run per mark.
`BSmartCollapsingPager` owns its scroll coordinator without subscribing the entire
pager; only `BSmartCollapsingHeaderOffset` observes per-frame collapse updates.
Regression coverage checks header/page build counts, all bundled chart domains,
marker placement and navigation, repeated scrolling, paging and background return.

### Friends Chat (2026-09-22)

Friends now has Chats and Activity (unread direct messages), without a Follows tab.
Incoming follows move to Today notifications under New followers and All.
`NotificationEntryView` polls the existing social snapshot every 30 seconds only
while Today is foreground, and on inbox pull-to-refresh. It guards request/account
identity; `ActivityNotification.follower` reuses account-scoped read versions and
the existing 30-day/200-item inbox. Rows open the public profile. This reflects
current follower relationships, not immutable follow history or new APNs events.

`SocialChatView` shares a room-aware message list between Global Chat and direct
messages. `SocialChatComposer` owns local draft, focus and attachment state so
keystrokes do not rebuild the list; ImageIO resizing/JPEG encoding runs off the
main actor. Refresh merges stable IDs without replacing unchanged messages.
`SocialMessageRow` provides avatars, sender, quoted reply, image viewing and
bottom-right timestamps, with a horizontal left-swipe reply gesture and native
long-press menu. Failed sends retain the same UUID and draft for safe retry.
Server room isolation, private image URLs, upload quotas and migration order are
specified in `docs/contracts/social_chat.md`. This is not voice or E2EE messaging.

### Managed Perpetual Deposits (2026-09-22, Pending Configuration)

`ManagedDepositView` replaces the new-money receive/transfer sequence with a native
Relay deposit-address flow. `ManagedFundingClient` uses the current Supabase
session; `bsmart-funding` fixes the recipient/refund wallet from the existing
binding and targets HyperCore perps USDC. `ManagedFundingStore` discards stale
quote responses across input/account changes and displays provider-owned history.
Relay handles bridging, execution and refunds while Privy retains the owner wallet.
No bSmart signer, watcher or funding schema is introduced. Existing CCTP and wallet
funds retain their recovery entry. Provider API key and explicit server flags are
required; no mainnet transfer or end-to-end funding acceptance has occurred.
See `docs/contracts/managed_funding.md` and `docs/operations/managed-funding.md`.

### Supabase Research Delivery (2026-09-15, Opt-In)

`BSMART_CONTENT_BACKEND=supabase` selects `SupabaseContentClient`, bound to the
existing `AccountAccessStore` after composition. It uses the same verified user
session as the native Feed without exposing management credentials. Before initial
load or foreground refresh, `BSmartContentRefreshing` stages one immutable revision;
unchanged collection hashes reuse decoded arrays, and all required arrays decode
before committing. Evidence reads capture the revision and reject obsolete responses.
`SupabaseContentFreshness` commits only with a successful snapshot. Existing disk
cache and bundle bootstrap stay available; an offline failure never stamps now.
No legacy installation registration or state sync is created in this mode;
portfolio/follows/read states remain in existing local storage. Auth, trading and
native Feed clients are unchanged. The default remains legacy until manual schema
provisioning, a complete content baseline and API/device verification are done.
See `docs/operations/supabase-content.md` and `contracts/openapi/supabase-content.yaml`.

### Representative Price Stories (2026-09-15)

The homepage discovery focus uses `TodayRepresentativeStoryLoader/Card/Chart`.
Its education entry sits beside the discovery heading instead of the Top 25% label;
the existing education destination is unchanged. Peak stock appreciation replaces
the card's upper-right arrow. Only the first chart annotation shows a visible date:
the narrative prefix and chart footer dates are removed to compact the card.
It preserves the existing representative-ticker selection and loads full evidence
through `AppModel` after a 650ms portrait-selection debounce. The directory keeps
its lightweight introduction. `TodayRepresentativeStory` projects available daily
bars and source-linked calls without changing Score, settlements or API contracts.
The compact chart precedes the 14pt Dynamic Type story, uses dotted dates and at most the
earliest three bullish nodes; short leaders and 44pt targets keep clustered calls
readable. Cards and nodes use shared-element navigation through
`TodayRepresentativeOpinionDestination` to the standard `SmartAccountEvidenceDetailView`.
Resolution matches author, ticker and source URL, not a representative ID that may
refer to a different call. Marker-only summaries retain their actual horizon and
source, never invented original text, translations or settlement results; full
author evidence enriches the same screen when available.
Missing history stays absent and remains retryable.

Copy option two follows chronological price milestones, including calls after a
historical high. Prices use completed closes before publication, no more than
seven days old. The later high excludes the first publication day and cannot
include uncompleted/future bars. Returns describe stock appreciation, not fills or
investor profits. Text uses "the author" rather than names, with ticker, prices and
percentages emphasized. The initial date/price and later high are chart annotations;
marker targets avoid their bounds. Data limits and cutoff remain in an optional
price-method disclosure on the standard opinion detail; other opinion routes are unchanged.
Fixture tests cover MU, LITE and NVDA, plus source identity, deduplication, invalid
prices and node geometry; targeted accessibility tests cover layout and navigation.

`Core/Data/TodayRepresentativeStoryBundle` reads the versioned offline snapshot.
`Resources/representative-stories.plist` preloads all 342 current representative
introductions and 268 valid bullish stories, including English/Chinese copy, in
about 1.1 MB. Bearish cases retain their original direction; PLG's missing initial
price is not invented. The existing full evidence fixture remains bundled. A matching
introduction ID, price and timestamp are required before reusing a bundled story.
The loader displays it synchronously, then refreshes from complete author evidence;
partial latest-update data cannot replace the preloaded historical chart.

To regenerate after fixture/copy changes, run `make ios-generate`, then the current
scheme's `xcodebuild ... build-for-testing` for a simulator. Run:

```sh
bash scripts/export_ios_representative_stories.sh /path/to/Build/Products/bSmart_iphonesimulator26.5-arm64.xctestrun SIMULATOR_UUID
```

The explicit exporter invokes `TodayRepresentativeStoryBundleTests/testExportSnapshot`
with an output path on a temporary copy of the test manifest, then installs the binary
plist. Normal test runs skip exporting. Regenerate the project and rebuild afterward.
This reuses the production Swift projection and localization rather than duplicating
price/chronology logic in a separate generation language. Shipping this baseline does
not disable daily server updates or require app updates for refreshed evidence.

### Profile Basics (2026-09-15)

The profile defaults to the bSmart account and live holdings. External accounts,
valuation history and brokerage connections remain available. A persistent Deposit
entry in the app holdings section covers empty positions and first-time funding
without inferring deposit history from a balance or presenting a failed query as zero.
`PortfolioAppAccountView` routes to the existing sign-in, receive and transfer
destinations; it does not submit transactions. Position adjustments retain the
shared trade sheet. The Hyperliquid module remains with a compact, automatically
loaded balance presentation, omitting protocol mode, timestamps and helper copy.
Separate main-account equity and cash are not relabeled as order buying power.
Unavailable balances use a dash, not zero. Settings displays only the current account's verified wallet address and
routes address actions through the existing receive verification flow. Guest
example addresses are no longer shown in the UI.

Verification: signed simulator build and 20 targeted tests passed across the
position stores/models, balance layouts and profile/portfolio navigation. UI checks
cover the default account, reachable Deposit, settings navigation, external account
switching, profile edits, whole-page scrolling and horizontal paging. No real login,
funding, key changes or orders were performed.

### Global Search

The third root tab is `Search`, with a fixed native input above a mixed overview:
two-column ticker quotes, a horizontal investor rail, opinion summaries and public
community profiles. Query results have a fixed category order: tickers, opinions
(including Smart Money movements), authors, users. Exact ticker matches precede
prefix/substring matches. Category filters and pagination preserve this ordering.
Each result opens its existing detail destination; no separate trading UX is added.
The overview uses full-width, equal-grid ticker tiles with explicit rounded
borders, not context-dependent Dividers inside horizontal rows. Investor names
stay on one line above their published Top percentile (or known ordinal rank);
missing ranks are not inferred. `AppSearchDestination` only selects the existing
destination and exposes its navigation bar: the destination itself owns the
single `bSmartDetailPage` back control and tab-visibility token. AVAV's bundled
monochrome logo is a theme-adaptive template; colored brand logos stay original.

`Core/Data/AppSearchIndex` builds a deduplicated index of the published in-memory
research catalog, loaded author evidence and the existing merged perpetual ticker
catalog. It is not an all-time archive or internet index. `AppSearchStore` performs
background matching, debounces input by 220ms and fences obsolete responses by
request generation and account. Recent explicit searches are capped at eight and
stored per account; transient keyboard edits are not saved.

`PublicProfileSearchClient` uses `withFeedSession` and the independent, read-only
`bsmart-search/profiles` Edge Function. It searches completed public profiles from
the existing `bsmart_feed_profiles` table, with bounded, literal-escaped matching
and stable paging. Responses expose only public identity fields; stored avatars
reuse the existing signed-URL resolver. User lookup errors do not erase local
research results. Signed-out test browsing keeps research search but requires
sign-in for public users. Debug users are available only with both a fixture
scenario and `--ui-search-fixture`, never as a live-service fallback.

The new function was independently deployed to the account project on 2026-09-14;
an unauthenticated live request returned 401. No DDL or changes to deployed
authentication, wallet, profile or trading functions were performed. Contract:
`docs/contracts/app_search.md`, `contracts/openapi/supabase-search.yaml`.

Search validation (2026-09-14): ad-hoc signed simulator build and 20 native tests
passed (14 model tests, six UI tests). Coverage includes exact BTC priority,
same-name ticker collisions, aliases, cancellation/account isolation, mixed
overview, ticker/opinion/user destinations, keyboard dismissal, light/Chinese large text,
market-directory failure/retry and the existing Today-to-Smart route. Seven Edge
Function tests and Deno type checking passed; temporary Auth failures return 503,
not a 401 that would clear the app session. Architecture, terminology, strings
and whitespace checks passed. Public user lookup still needs a signed-in physical
device acceptance pass; no real profile writes, wallet changes or trades occurred.

Search UI refinement validation (2026-09-14): signed simulator build and 19 tests
passed (13 model/asset tests, six UI cases). Tests verify equal-width ticker tiles,
contained symbol/price text, published Top badges, theme-adaptive AVAV assets,
and exactly one back control for ticker, opinion, author, Smart Money, movement
and user destinations. Search state and tab visibility survive returning from
details; Chinese large text and light/dark cases remain covered. No backend or
distribution deployment was needed for these UI fixes.

### Brand assets

`BSmartWordmark` reads the approved full-color `BSmartWordmark.imageset` across onboarding, account, settings and portfolio setup. `scripts/sync_brand_assets.py` packages the user-supplied image in `ios/Brand/bsmart-logo-20260913.png` into the transparent wordmark and opaque 1024px AppIcon. No runtime font reconstruction or symbol tinting.

### Subject-attributed trades

`Core/Models/SubjectTradeStats`, `Core/Data/SubjectTradeStatsStore` and
`Features/Smart/SubjectTradeStatsSection` consume the authenticated Supabase
subject aggregate on Smart Account and Smart Money detail pages. Counts are
distinct user/source pairs, not distinct users across an author. Native UI never
sums a partial Feed page or substitutes examples for errors. The info control
holds the counting definition, without adding permanent helper text.
`SmartMoneySourceActivity` links reviewed movements to their source-aware trade
dock, forwarding the exact market coin through the existing shared trade sheet.
See `docs/contracts/subject_trade_stats.md` and `contracts/openapi/supabase-feed.yaml`.

### Account presentation

`Features/Account/AccountPresentation` contains a card-free wordmark, native
neutral Google button, account action rows and primary buttons. The login
wordmark renders the original silhouette in the adaptive brand color in dark
mode; other usages keep the full-color image. `GoogleSignInMark.imageset` contains
unmodified icons from the pinned Google SDK (provenance in
`ios/asset-sources/google-signin-mark.md`). The button calls the existing identity
authorizer, retains provider availability and busy guards, and localizes its CTA.

`Features/Portfolio/ProfileEditorPresentation` shares photo picker/menu and
focus-aware underlined fields between cloud and guest editors. Photo errors and
provider-photo selection stay explicit; both editors use the bottom save action.
Cloud validation, session fencing, first-sign-in setup and guest scope checks stay
in their original clients/stores. No new credentials, scopes or profile API.

The sign-in UI tests require an ad-hoc signed simulator build
(`CODE_SIGNING_ALLOWED=YES`, `CODE_SIGN_IDENTITY=-`): unsigned builds enter the
existing Keychain storage-protection branch. This was confirmed by accessibility
hierarchy and signed/unsigned comparison on the same simulator on 2026-09-14.

Current refinement validation (2026-09-14): `make ios-build` passed; signed
simulator tests passed all nine cloud/local profile model tests and three UI
tests (Chinese/light and English/dark sign-in; guest edit/save/cancel). Architecture,
terminology, localization syntax and whitespace checks passed. No real profile
writes or distribution build was published.

### Smart navigation

The Today investor focus gives the existing representative market story a
stronger visual entry: a restrained brand-tinted identity band emphasizes the
ticker and historical peak move, while the chart adds a low-opacity area layer
and a heavier price line. This is presentation only. The selected story, source
prices, call nodes, opinion destination and ranking logic remain unchanged.

`SmartHubView` shares Today/Discover's `BSmartCollapsingPager`: the search field
collapses above pinned underline tabs and filter controls, with horizontal paging
between Smart Account and Smart Money. `SmartHubTabs`, `SmartHubRows` and
`SmartMoneyOverview` own presentation only. Rows use existing platform ranks,
representative-work introductions and source P&L; they never synthesize returns,
holdings or new scores. Missing P&L stays unavailable, not zero. Filters retain
their separate state per section, and existing detail navigation/following and
trade flows are unchanged. Native `SmartFiltersUITests` cover combined filters,
reset, large text and swipe navigation with preserved filters.

Validation (2026-09-16): signed iPhone 16 / iOS 18.5 simulator build and all four
`SmartFiltersUITests` passed, including Chinese XXXL row bounds and opening an
author detail. Architecture, localization syntax and scoped whitespace checks
passed. No live account writes, orders or distribution upload were performed.

Opinion details use `Features/Smart/OpinionDetailLayout` with a full-width
`OpinionPortraitHeader`, matching the approved A v3 HTML prototype: a full-color
author circle lightly overlaps a smaller, diagonally offset ticker-logo circle.
The header has no visible text, extended color strip or separate gray background.
Images use existing cached/bundled components and destinations; the avatar has a
header-only symbol fallback, and the light logo mount preserves brand contrast.
The composition is capped at 390 points wide, reserves 244 points of height, and
scales both circles together up to 1.18 on pull. `SmartAccountPortraitLayout`
shares stretch/collapse mechanics without changing author-page sizing or fading.
Author name, platform mark, ranking, ticker/company and date live below the image,
with adaptive rows for narrow screens and Dynamic Type.
Only the header observes scroll geometry; the reader is not rebuilt per drag.
Trader count and its expandable list follow attribution, before the opinion
summary and original text. Original/translation, text size, supporting sources,
outcomes and price evidence remain available, with the existing source-attributed trade dock below the safe
area. Historical home chart account markers now route to this same opinion page.
No API schema or wallet behavior changes.

Compact-cover validation (2026-09-14): the ad-hoc signed iOS 26.5 simulator build
passed six layout tests and four UI regressions. These cover circle bounds and
overlap from 320 to 1024 points, pull/release and collapse, dark/light appearance,
large text, both image destinations, trader-count ordering, reader controls and
the existing trade dock. The author-page pull/history regression also passed.
No real transactions or distribution upload were performed.

The Today “Smart investors” button now pushes `SmartHubView` on the existing
Today navigation stack. SmartHub no longer owns a nested root NavigationStack;
it uses the shared detail-page back control and tab visibility token, including
returning from author/money details and filter sheets. Both Smart Account and
Smart Money, search, rankings and filters retain their existing behavior.

The root no longer instantiates a hidden Smart tab layer. The tab bar has four
equal slots: Today, Feed, Search, Profile. `.smart` is
retained only as a compatibility identifier; legacy DEBUG launch selection for
Smart falls back to Today. Platform-scoped discovery directories remain available
to education routes.

### Identity-free test login

The internal app offers an explicit Test login button in the root login screen,
including Release builds. `AccountAccessStore.isTestSession` grants browsing only,
separately from `canAccessAppContent`, which still requires a real session. Entry
requires completed restore, no active identity/session and no account operation.
No credentials, account IDs, wallet registration or cloud profile are fabricated.
Cloud Feed and wallet calls retain their existing verified-session requirements.

Test mode lives only in memory. Exit from Settings or Account unmounts content,
resets the router and returns to root login; relaunch requires another selection.
Successful Google login ends test mode and enters canonical profile setup. Research
loading/live refresh accept either a real session or the explicit test state.
This is the user-visible internal test entry, distinct from DEBUG fixture bypass.

Test-login validation (2026-09-14): simulator build and 24 selected tests passed
(22 account/access unit tests, two root UI tests). Verified explicit entry,
settings-sheet logout returning to the root, no session persistence after restart,
no identity/credential/wallet/cloud access fabrication, and verified Google login
ending the test state. No real credentials or funds were used.

### Root authentication gate

`AppSessionGate` owns access to the content tree, ahead of research bootstrap,
portfolio onboarding and all four tabs. `canAccessAppContent` requires restoration
to have completed, a matching session identity and unexpired access. A cached
Supabase identity published during restoration does not unlock content. Profile
load/setup uses the canonical cloud profile; failures offer retry and sign out.
The root editor owns onboarding completion so it cannot disappear on sign-in
before its first save. `TradingAccountView(isAppEntry: true)` only handles login;
its optional in-app account variant retains profile/wallet management.

On local logout or account change, the content subtree is destroyed and the router
resets paths, pending links and hidden-tab tokens. Startup data loading and live
refresh are login-gated; account maintenance still runs while signed out to restore
the session. OAuth callbacks remain reachable. Links received while signed out
cannot instantiate content and may be resolved after login. Wallet keys are kept.
This is a native presentation boundary; installation-auth research API contracts
and Supabase authorization are unchanged.

Only DEBUG builds with an explicitly launched bundled `DebugDataScenario` allow
existing fixture UI tests to view demo content without a real account. Live data
never uses this route; `--ui-auth-gate` exercises the actual gate with those same
fixtures, and Release contains no fixture bypass.

Root-gate validation (2026-09-14): simulator build and 65 targeted tests passed
(62 account/session/profile unit tests, three UI tests). Covered cached identity
while restore is suspended, token expiry, local logout before delayed remote
revocation, offline revocation failure, route clearing, bilingual logged-out
cold launch/relaunch and inability to swipe-dismiss the root login. No real Google
credentials, wallet operations or production profile writes were used.

### Session and account navigation

`Core/Wallet/PrivyEmbeddedWalletClient` integrates pinned Privy Swift 2.16.2 using
the current Supabase access JWT (`sub` UUID), not a second OAuth login. The app
owns one SDK instance; account revision checks reject late results and logout
cleans up the old SDK identity, including when a request was in progress.
`HybridTradingWalletVault` preserves matching device keys, resolves exact bound
Privy addresses across devices, and creates only for unbound accounts. Provider
failure never falls back to device-key creation. `HybridTradingWalletSigning`
is injected into CCTP, market orders, leverage, unified setup and withdrawals;
the existing trade sheet and durable permits/verification/broadcasting remain.
Privy uses typed signing or raw transaction-digest signing, never generic RPC
broadcasting. Account wallets have no local mnemonic and keep recoveryVerified
false; legacy keys retain their optional backup/Face ID policy. No registry DDL,
automatic legacy import or address replacement. See `embedded_wallet.md` and
`operations/privy-ios-setup.md` for dashboard configuration and live acceptance.

Supabase sessions survive transient foreground/refresh failures. Pending rotation
is recoverable using Supabase's parent-token semantics; legacy session authorities
retain their no-replay policy. Definitive refresh rejection clears credentials;
expired access never grants signing permission. Refresh uses the token endpoint's
authoritative user rather than a second request that could revoke a valid rotation.

Root slots are Today, Feed, Search, Profile; Smart opens from Today. The bSmart account holdings pane uses
`PortfolioTradingHoldingsView` and `TradingPositionsView` for real default/HIP-3
positions. Increase and reduce/close use the same exact-coin `BSmartTradeSheet` and
refresh on dismissal. Trading wallet management lives in Settings; guest/external
holdings remain separate and never substitute for real account positions.

### Smart Account Author Detail

`Features/Smart/SmartAccountDetailView` is a portrait-first, continuous native
profile, extracted from the Smart hub. `SmartAccountPortraitHeader` expands the
existing cached source image during scroll overshoot and fades only its title;
the parent changes state only at the compact-navigation threshold. No custom
drag recognizer competes with chart zoom or scrolling. Author entry points
use ordinary push navigation: the shared link's optional
`usesZoomTransition: false` avoids the system Zoom pull-to-dismiss recognizer
stealing the portrait pull. All other destinations keep their existing transition.
The fixed follow action
uses a bottom safe-area inset and the existing AppModel tracking state.
Representative works precede recent-view timelines, latest available ticker
stances, profile characteristics and `SmartAccountAboutSection`. The latter
retains benchmark scores, sample coverage, version metadata and historical misses.
`RepresentativeWorkPerformance` uses published stock returns from the exact
settlement window (or dated price-evidence window), never annualizes,
recomputes Score or treats a bearish call's stock loss as positive account ROI.
The same `BSmartPriceChart`, markers, source drilldowns and trade evidence remain.
Public calls are not labeled as verified holdings. The main representative-work
surface omits repeated reference-price, date, OHLC-source and disclaimer captions;
chart interaction and full evidence retain the data, while methodology is collapsed.
The new subject trade aggregate and money attribution are documented separately above.

### Platform Profiles

`AccountProfile` is the canonical Supabase account profile. `NativeAccountProfileClient`
uses the existing validated account session without requiring a wallet. `AccountProfileStore`
fences late responses; signed-in `UserProfileHeader` and `AccountProfileEditor` use cloud
username, unique handle, bio and private uploaded avatar. Local guest editing is unchanged;
old account-local data is imported only explicitly. Feed privacy no longer edits identity.
`FeedPublicProfile` and `OpinionTrader` carry the same handle alongside name/avatar;
legacy fixtures without a handle remain readable. Profile-only 409 errors do not trigger
wallet recovery. See `docs/contracts/account_profiles.md` and the isolated profile OpenAPI.

### Investor Education

`Features/InvestorEducation` adds an isolated native page reached through one
compact entry below the existing homepage investor focus. Shared zoom navigation,
detail tab visibility and AppModel following are reused. The offline, validated
`InvestorEducationSnapshot` and 1,289-author JPEG atlas live in `Resources`, separate
from live recommendations and scores. Only a selected positive Wey How SNDK case
is featured, with original-source access and its unchanged settlement window.
Portrait filtering has no autoplay; Swift Charts supplies price selection.
X, YouTube and Reddit have independent platform scopes, observed/ranked/Top-25
counts and identity-matched atlas tiles (881/295/113 portraits). Platform switching
also scopes live recommendations and the existing follow directory. Public avatar
enrichment is build-time only; it never changes ranks or adds invented authors.
See `docs/product/investor-education.md` for provenance and rebuild requirements.

### Native real trade Feed

`NativeTradeFeedClient` uses a validated Supabase session via `AccountAccessStore`,
not research installation auth. Feed has no Demo or sharing-settings UI. Migration
006 fixes activity visibility to public for existing/new profiles; legacy sharing
requests cannot hide activity or overwrite identity. Account/profile revisions
invalidate public UI records. The optional
`OpinionOrderAttributing` hook registers an immutable source before real signing,
then requests independent reconciliation without resending orders. Ordinary and
reduce-only trading remain independent of Feed. Server code lives in the isolated
`supabase/ios-account` deployment; its schema and rollout are operator-managed.
The deployed service uses a private Supabase Storage opinion catalog, not Vultr.
`publish_catalog.py` publishes reviewed real snapshots; the pg_cron/Vault worker
and native sync share `bsmart_feed_claim` leases. `inspect_feed.py` checks live
schema counts, authentication and worker heartbeat without touching funds.
See `docs/contracts/supabase_trade_feed.md`. No device receipt publishes itself.

`OpinionTradersSection` uses this same authenticated service, with a sign-in entry
when logged out. It never falls back to demo on network failure; demo is a separate
explicit sheet. Trader rows omit leverage and time, retaining timestamps only in
the contract for ordering/verification. Legacy fixtures are DEBUG UI-test-only.

Feed switches between newest executions and `PopularOpinionsView`. The latter
uses `PopularOpinionsStore` and `/popular` server aggregates, ranking opinions by
seven-day distinct verified traders rather than ordering a partial Feed page.
Account, consent, tab and scene changes fence late results and clear stale state.
`OpinionTradeSplitBar` displays counts and proportional long/short segments without
requiring the trader list to expand. Detail totals are all-time; popular totals
are seven-day counts. A person's latest eligible fill determines one direction.
Missing legacy direction fields do not become fabricated zeroes. Explicit Demo
groups only its isolated records; it is never used when live statistics fail.
Feed dollar formatting is fixed to `$`, independent of the device currency locale.

### Home component cleanup

The September 12 cleanup removes the unreferenced `TodayInterludeDeck`,
`TodayPortfolioNowModule`, `TodayAssetEditorialHero`, `TodayPortfolioSnapshotStrip`
and `TodaySmartMoneyFeature`, together with their private helpers, from
`TodayEditorialSections.swift`. Active headings, carousel progress,
`TodayEvidenceTimeline`, inline opinions, event details and their shared chart
types remain. This is dead presentation-code removal, not a change to current
home behavior, trading, account state or data contracts. See
`docs/operations/repository-cleanup-2026-09-12.md` for the audit scope.

### Appearance contrast

`BSmartTokens` owns both palettes. Light mode uses neutral page backgrounds,
white cards, darker metadata and distinct control/divider colors. Use `onAccent`
for text/icons on solid adaptive brand, pulse or trading colors; `pulseInk` is
reserved for pale `pulseFill` and consensus editorial surfaces. Smart Money's
editorial card uses `skyFill`/`skyInk`, not the darker light-mode `sky` text color
as its background. Tinted Alpha cards have an opaque light backing; their dark
backing remains transparent. Chart grid/crosshair roles preserve the dark colors
while increasing light-mode visibility. No interaction or data contract changes.

`BSmartAppearanceContrastTests` resolves real UIKit dynamic colors and composites
alpha before checking contrast. It covers metadata, tinted ranking/direction
badges, filled controls, editorial cards, charts, navigation and dark palette
regressions, without requiring screenshot tests.

### Daily X publication

The live foreground refresh also fetches Smart Account profiles, alongside updates
and signals. Cached representative evidence refreshes when profiles/views change
and at five-minute intervals while active; request identities prevent older
in-flight evidence from overwriting a newer response. Transport failures retain
the last successful snapshot and do not replace user portfolio/follow state.
HTTP uses revalidating URLSession caching; the authenticated feed, profiles,
updates and evidence endpoints support ETag/304. A concurrent publication detected
while materializing a response returns 503 instead of caching a mismatched body.
Daily package operations and the required one-time TestFlight/API rollout are in
`docs/operations/x-daily-package.md`. No background scheduling guarantee is made.

### Account and funding preparation

Wallet authentication is configurable in Settings. `DeviceWalletStore` publishes
the setting only after the vault updates the existing item's access control and
encoded policy atomically. Legacy/new wallets default to user presence. Disabling
presence retains `WhenPasscodeSetThisDeviceOnly` and no synchronization; it never
deletes/recreates or exports a key. Re-enabling restores presence on the same item.
`WalletAuthenticationSession` shares only LAContext, scoped by service/account for
60 seconds in foreground; background, protected-data lock, sign-out, authentication
failure and policy changes invalidate it. Key bytes remain temporary and wiped.

Unified USDC is now automatically prepared by the wallet/setup entry, with one
automatic attempt per setup store. Existing positions/open orders still prevent
switching, portfolio margin is untouched, and only read-back confirms success.
The compact order setup observes mode changes directly and reloads capacity. No
extra enable/confirmation step or automatic order accompanies initialization.

`LiveOrderComposer` restores the original margin amount, leverage strip, presets,
keypad/chart toggle, balance/MAX and slide-to-order presentation. Display estimates
remain in `LiveOrderEntrySummary`; `loadEntry` reads balance/leverage/fees without
signing. A slide invokes `executeMargin`, applies the selected leverage only when
no position exists, verifies its exchange value, then runs the existing fresh
order checks and one-shot submission. `HyperliquidLeverageUpdate/Codec` encode only
the fixed mainnet updateLeverage action and share the persisted owner nonce space.
There is no paper balance, synthetic liquidation price or invented fill.

For a HIP-3 market with zero directional capacity in a non-shared account,
`LiveOrderComposer` embeds the compact `UnifiedAccountSetupView`. Its existing
risk confirmation and flat-account checks remain mandatory. A verified unified
mode callback reloads the market's actual entry capacity; default-perp equity is
never substituted for `activeAssetData.availableToTrade`. Already funded separate
markets, shared accounts and reduction do not show this setup gate. The composer
also offers explicit balance refresh and six-decimal display/MAX; minimum opening
notional and fee-inclusive margin errors appear before the slide. The authoritative
order book and signing checks are unchanged.

All live order entries now present the same `BSmartTradeSheet`: opinion actions,
Feed shortcuts, the contract catalog and wallet position reduction/close. The
sheet sits above the root floating tabs; its shared composer keeps the slide
action outside the scrolling input area. There is no separate reduction form.
Reduction uses percentage input/presets and the same keypad/chart/MAX controls,
locks the position coin and leverage, and calls `executeReduction` through the
existing reduce-only pipeline. Exact-coin loading cannot fall back to a different
venue, and late market requests cannot overwrite a newer selection. Dismissing
the position sheet refreshes the wallet positions.

Funding now uses two actions: Continue prepares authorization/gas, Confirm transfer
signs and submits. Recovery happens on the same page. A saved authorization may be
reused within its original deadline with unchanged amount and fee ceiling, a fresh
simulation and fresh gas estimate. An orphan authorization whose simulation fails
is retained as `notSubmitted`, releasing the local attempt immediately; the fixed
extension requires an owner-signed source transaction, and no source record may
exist for this transition. Authorizations with unknown signer outcomes still need
chain-proven expiry. All evidence remains. Signed/source transactions
are never cleared or automatically resent. Input has no whole-screen periodic
refresh; the transfer display is computed only when the state changes.

A source signature that never received a submission permit can now finish as
`notSubmitted`, retaining its exact signature/raw bytes and permanently preventing
that intent from submitting. `beginSubmission` durably records `submitting` before
issuing the only broadcast capability; recovery and submission compete under the
same journal lock. Pre-submit failure and screen restoration use this boundary,
not a user "reviewed" flag. Missing-transaction observations do not trap recovery,
but pending/executed/conflicting observations do. Signing in progress and every
permit-issued or ambiguous submission remain reserved.

Source preflight estimates gas before calling `eth_call`, then explicitly uses
the estimated gas plus the existing budget buffer. Never send fee-bearing
`eth_call` transactions without a gas limit: the Arbitrum node's default cap can
incorrectly demand substantially more ETH than this transaction needs. RPC
failures retain classified reasons or method/error code, never raw signed payloads.

Submission rechecks compare raw gas estimates against the original approved limit,
including the final bounded estimate. The 20% headroom is applied only when quoting,
not applied again to each new estimate. Exact signed gas/fee caps and hard limits
stay unchanged; a genuine quote overrun requests a new quote and confirmation.

bSmart is a Hyperliquid builder-code frontend, not a DEX/HIP-3 deployer.
`HyperliquidBuilderFee` binds an explicitly configured public recipient and perps
fee to the immutable signed order. `HyperliquidOrderPreviewProvider` reads the
owner's `maxBuilderFee` ceiling, `userFees` and raw `l2Book`, splitting existing
venue fees from the app fee. `HyperliquidExactValue/DepthQuote` use exact BigInt
arithmetic, preserve partial coverage and reject stale depth with a five-second
wall/monotonic deadline including network time. A preview does not establish
fee-inclusive collateral, consent, signature or execution permission. No
production builder recipient/rate is configured and no fee authorization is sent.
Basic execution explicitly omits builder while this configuration is undecided;
fees/approvals must not delay the basic deposit, withdrawal and order work.

`HyperliquidExecutionReader` has a credential-free, bounded HTTPS /info transport.
`HyperliquidTradingSnapshotProvider/Snapshot` preserves mode, actual leverage,
target position and per-side capacity, with a 15-second wall/monotonic lifetime
further bounded by server position time, and mode/leverage/position fences across
reads. Metadata retains both current margin restrictions and legacy isolated-only
flags. Order constraints cannot treat paper
leverage or per-DEX withdrawable as execution authority. This observation does
not sign, move collateral, change account mode or submit an order.

`Core/Trading/Execution` is the real-order protocol boundary, independent of the
paper engine and filtered display-market list. It resolves original exchange
indices/collateral, validates exact decimal IOC intents and interprets individual
order acknowledgements. `Core/Wallet/HyperliquidOrderCodec` uses pinned MessagePack
and existing Wallet Core for fixed L1 encoding and supplied-signature validation.
The codec itself does not expose device keys or submit orders. The new
`HyperliquidMarketOrderStore` composes registration checks, current venue quotes,
the protected `FundingTransactionJournal`, `HyperliquidDeviceSigner` and a fixed
one-shot exchange broadcaster. `HyperliquidOrderJournal/Record` consume signing
and submitting permits once, preserve responses after cancellation, and block
new orders while a submitted result is unknown. An exact `orderStatus` terminal
proof may resolve that record but never invent average price or actual fees.
`Features/Trading/LiveMarketOrderView` is now the native confirmation route,
including Feed shortcuts; opening it is not a trade. It uses current venue
leverage, not an unsubmitted leverage selector. Order size and limit are immutable
after review. Authenticated registry capability gates remain enforced at every step.
The product is perpetual-only. Execution validates native/builder perpetual asset
namespaces even for archived intents; no spot trading entry or action is added.
The composer supports reducing/closing by percentage of the actual position,
with derived side and immutable reduceOnly=true. Confirm-time and post-signing
position changes require a new review. Funding still reads shared/spot USDC and
retains deposit-fallback evidence; these are collateral mechanics, not spot trading.
No real funded trade has been executed for acceptance. See
`docs/contracts/hyperliquid_execution.md`.

Itemized fills/history are deferred from the MVP UI. Confirmation now returns the
exchange acknowledgement without automatically reading fills. The existing
`HyperliquidOrderFills/OrderFillJournal` retain validated, deduplicated venue fills
in bounded batches within the same encrypted event journal. `LiveOrderFillView`
shows actual quantity, weighted price, fees/rebates and expandable fill rows;
incomplete history is a subtotal, absent data is not zero. Recovery uses current
journal state, handles partial acknowledgements and survives interrupted writes
without re-signing/resending. Returned evidence is preserved but not rendered
after account changes. API retention/truncation, actual positions and funded
end-to-end acceptance remain explicit boundaries, not inferred from fill totals.

`HyperliquidWithdrawalIntent` and `Core/Wallet/HyperliquidWithdrawalCodec` keep
the outbound user-signed action separate from L1 orders. `CCTPWithdrawalFeeReader`
only observes current contract configuration on fixed HyperEVM RPC, with canonical
EIP-1898 block-hash reads, a repeated canonical header check and a dual-clock
deadline. Normal later blocks are allowed; reorgs are not. Its CCTP maximum is not a total withdrawal
fee or signed cap. `HyperliquidWithdrawalPreview/Store/Permits` now connect the
default perpetual withdrawable balance, explicit native confirmation, protected
`HyperliquidWithdrawalSigner` and the shared one-shot exchange transport. Unified
withdrawals additionally require a fresh all-DEX flat-account proof, no open
orders, and zero USDC hold, and use `sourceDex=spot`. Portfolio-margin withdrawals
remain unsupported. This does not infer live margin capacity from spot totals.
`Features/Account/HyperliquidWithdrawalView` is reachable from the wallet panel;
independent registry capability gates apply. `HyperliquidWithdrawalJournal/Record` stores unsigned review, signing,
signature, submission and response phases in the existing encrypted event log.
`HyperliquidOwnerNonce` shares the owner high-water mark with orders and checks
reservations under the same file lock, including event replay. A nonce hint does
not reserve it. Only unsigned reviews can expire or cancel; signing/unknown
withdrawals cannot release due to elapsed time. An accepted action cannot be
resubmitted, but permits a new explicit withdrawal using a fresh balance and nonce.
Acceptance still does not prove destination arrival. Superseded reviews cannot revive
after clock rollback. Record-only methods issue no capability; separate permits
require a fresh validated preview. Complete protocol fees, per-transfer destination
confirmation and a small-amount funded acceptance test remain outstanding.
Python-generated public-key vectors test the exact typed digest
and wire envelope; they are not funded-transfer acceptance.

`Features/Account/CCTPTransferView/Content` composes the native amount and review
flow from `Core/Trading/Funding/CCTPTransferStore`, the existing preparation and
device journal/signer. `CCTPTransferDisplay` projects only display-safe values from
durable states, retaining the original amount, owner and fee ceilings after submission;
confirmation deadlines are visible and expired actions cannot advance.
Authorization, network-fee preparation, signing and submission remain separate
internal states, but the UI uses Continue and Confirm transfer only. Abandoned
unsigned source previews are cancelled without waiting, preserving their history.
The preparation operation gate is deny-by-default;
the live app gate checks current configuration and device-wallet identity throughout.
Saved authorization recovery runs on the same page; signed/sent source records
remain in history and are not resent or credited speculatively.
`BSmartApp` maintains account sessions across transient
inactive states, but restores again after background, so system authentication UI
does not itself reset the wallet. Physical-device authentication acceptance remains
required. Funding, trading and withdrawals retain separate registry gates.

`TradingAccountView` exposes Google login, signed-in state and logout. Google was
accepted by the user on 2026-09-12. Continue opens a separate `TradingWalletView`,
also linked from Portfolio and live orders. Wallet verification, optional protected backup,
Arbitrum receive, CCTP deposit, unified USDC setup, market directory, current
positions and withdrawals live there. `TradingPositionsStore` reads current
perpetual venues with bounded concurrency; partial failures remain visible.
`TradingPositionsView` opens reduce-only orders from actual positions, not fixtures.
`UnifiedAccountSetupStore` requires explicit confirmation and a flat account,
uses fixed-purpose `UnifiedAccountSetupCodec`, records a shared owner nonce in
the existing encrypted journal, and reads the authoritative mode after submission.
Biometric inactive transitions do not cancel wallet preparation; background does.
Apple UI and capability are enabled in the native build; the button is usable
only when Supabase Auth advertises the Apple provider. See
`docs/contracts/native_perpetual_mvp.md`.
Internal build 1.0(6) sets `BSMART_INTERNAL_OPTIONAL_WALLET_BACKUP=YES` in
`project.yml`, including Release archives. `Core/Wallet/DeviceWalletBackupPolicy`
centralizes UI/funding/order/withdrawal eligibility without changing the stored
`recoveryVerified` flag. Missing or non-YES configuration requires backup; set NO
before public distribution. Keys stay device-only and Google cannot recover them.
The optional backup control is collapsed, with a visible loss-of-key risk notice.
Leases still match the exact local wallet, authenticated account and expiry.
**Current iOS path (2026-09-12):** `SupabaseAccountAuthClient`
and `SupabaseAccountTransport` connect directly to the bSmart Supabase project,
even when research data comes from fixtures. Native Apple/Google use a hashed
nonce; the ID-token exchange sends the original nonce. Verified Supabase user IDs
scope sessions and wallet registrations, with separate project-specific Keychain
sessions and provider-preserving refresh. Offline logout clears local access but
keeps wallet keys. `supabase/ios-account` owns the isolated RLS migration and
wallet-proof Edge Function; neither signing secrets nor research data enter it.
See `docs/contracts/supabase_account.md` and `supabase/ios-account/README.md`.

The following backend-mediated path is **legacy compatibility only**, not used
by the iOS composition root. `Core/Data/AccountAuthClient` shares the legacy
composition root's
installation authorization but uses a separate ephemeral, HTTPS-only account
transport with redirects disabled. Sessions use a distinct device-only Keychain
namespace and backend verification before restoring identity.
`AccountIdentityAuthorizer` integrates system Apple authorization and the pinned
Google SDK; no provider token becomes a wallet key or app session.
The superseded backend Supabase Google admission uses the challenge's optional `providerNonce`:
validate SHA-256 locally, pass that hash to Google and send the original `nonce`
with the ID token. Missing/null retains the legacy protocol; invalid hashes fail
before the provider UI. Google IDs and reversed callback scheme are configured in
`project.yml`; Supabase's public key stays in backend environment, not Swift source.
Backend `accounts/supabase_identity` admits the same verified provider subject while
retaining the existing account UUID and wallet binding. This does not deploy the
API or enable production auth/funds. See `accounts/README.md` for current blockers.
`AccountIdentityAssertion` carries transient, redacted identity material: Apple
requires both ID token and authorization code; Google omits the code. The account
transport strips inherited credentials/cookies and validates response origin/type.
Leaving the account page cancels its sign-in task. Apple cancellation ends the
system request and rejects stale delegates; cancelled late session responses are
not saved or published, with best-effort remote session cleanup.

Backend `accounts/apple_oauth` exchanges the one-use code against Apple's fixed
endpoint. `apple_repository` atomically claims the challenge before external I/O,
then independently verifies the returned identity and commits session issuance
with an AES-256-GCM provider grant (`credential_cipher`). The operator-supplied
Apple signing key and independent encryption keyring are backend-only protected
files; no user wallet key is uploaded. `apple_grant_migration.sql` is operator-run,
never startup DDL. Configuration, lifecycle limitations and key retention are in
`services/client_api/accounts/README.md`. Signed provider notifications are handled
as described below; native deletion coordination is implemented in pre-production,
but real-provider verification remains incomplete. Offline tests are not proof of real Apple/Google sign-in.

`Core/Data/AccountSessionRenewal` coalesces app-session renewals. The existing
device-only Keychain item now stores a versioned session envelope and a durable
pending flag, written before I/O. Lost responses/process death do not replay old
credentials. `AccountAccessStore` restores on foreground entry, renews near access
expiry and before wallet reads, and uses refresh-family logout even after access
expiry. Wallet proofs remain bound to the exact access token and are not retried
across renewal. Busy/renewing identity cannot grant signing leases; old leases are
invalidated. Late responses after logout/account switch cannot restore identity.
The server rotates app credentials with 30-minute access, 24-hour idle renewal and
seven-day absolute family limits; this is not a provider consent refresh.
Schema changes require operator-reviewed `session_renewal_migration.sql`; contract
and replay/concurrency policy are in `docs/contracts/account_session_refresh.md`.

`accounts/security_event_routes/verifier/repository` accepts Apple JWS and Google
RISC SET notifications independently of client bearer credentials. Fixed-origin
`provider_http` reads strip inherited authentication, reject redirects and bound
JSON size/nesting. Events atomically persist hashed receipts and subject barriers
with affected-family revocation and invalidated Apple-grant removal. Families
retain their original provider authentication time, so late events cannot revoke
newer interactive logins; disabled identities block issuance. No keys or wallet
bindings are erased. `security_event_migration.sql` is operator-reviewed, not run
at startup. Contracts, retention and external stream gates are in
`docs/contracts/account_security_events.md`.

On an account/wallet API 401, `AccountAccessStore` clears the exact app credential,
cancels renewal and invalidates signing leases. An older request cannot sign out
a newer login. Keychain cleanup failure still stops in-memory funding access;
network outages do not erase saved credentials. No wallet-vault cleanup is called.
This is response-driven; offline devices cannot learn provider events instantly.

`Core/Data/AppleCredentialStateClient` adapts the native Apple credential-state
query with a 10-second timeout, cancellation and late-callback isolation.
`AppleCredentialMonitor` coalesces in-flight checks, not completed permissions.
Only an error-free authorized result allows wallet access; errors/timeouts block
access but retain saved credentials. Explicit missing/revoked/transferred state
clears app credentials and attempts family logout without touching the wallet.
The opaque native user reference stays local in the version-3 device-only session
envelope, bound to the exact account/access/refresh pair; it survives only a valid
pending renewal. Lossless numeric Keychain dates coexist with legacy ISO records
without changing HTTP encoding. Legacy Apple sessions without the reference must
sign in again. Restores, wallet operations and foreground maintenance check state;
`BSmartApp` dispatches native revocation notices onto the main queue for invalidation.
An in-memory authorization is valid for at most 60 seconds by both wall time and
`ContinuousClock`. Funding leases inherit that original deadline, retain their own
60-second limit and cannot be extended by app renewal or device-clock adjustments.
Native queries and notifications still require physical-device/provider validation.

Backend `accounts/deletion_routes/repository/work/service` durably accepts deletion
before revoking all sessions, retains encrypted Apple revocation material, resumes
leased work and erases account-owned data transactionally. `deletion_worker` is an
opt-in development/test lifecycle task; it performs no startup DDL. It leaves local
wallets and on-chain assets untouched. `Core/Models/AccountDeletionModels` and
`Core/Data/AccountDeletionClient` consume the closed receipt contract through the
existing HTTPS transport: account bearer for acceptance, installation bearer plus
ticket for recovery, strict status/origin/receipt checks and no automatic retries.
`AccountDeletionRecord/Storage/Coordinator` now drive the native deletion view.
The request is saved before HTTP; only never-submitted or acknowledged completed
records may be cleared. The endpoint/account cannot change. Reauthentication uses
`/sessions.expectedAccountId`, never recreates a deleted account, and does not
publish or persist temporary credentials as the app session. Pending/unreadable
records block login/restoration/signing; suspension revokes existing leases even
when session storage fails. `GoogleAccountDisconnect` holds a shared SDK-operation
gate until the real callback, including after timeout/cancellation, and only
disconnects the matching user. `DeviceAccountDeletionCleanup` erases the scoped
profile with a tombstone blocking late writes; wallet/funding and guest research
records remain separate. The view offers recovery export when the matching wallet
is unlocked; no wallet creation/restoration is required merely to delete an account.
Permanent-deletion/wallet-access risk consent is explicit. Real-provider/device
tests, expired/lost-ticket resolution and production retention remain release gates.
Operator migration/worker requirements are in
`services/client_api/accounts/README.md`; contract: `docs/contracts/account_deletion.md`.

Client IDs/capabilities and server setup remain required. Production auth/deposits
are off pending `docs/product/arbitrum-usdc-funding.md` gates. The native
`ArbitrumReceiveView/Content` is available from the wallet panel, but cannot reveal
an address while deposits are disabled. `Core/Trading/Funding/ArbitrumReceiveStore`
checks a recovery-verified wallet against fresh account registration and explicit
network confirmation, expires after 60 seconds on wall and continuous clocks, and
rejects stale lifecycle/account completions. `Core/Wallet/WalletReceiveAddress`
provides Wallet Core checksum encoding; `WalletReceiveQRCode` generates a local
Core Image bitmap. `WalletReceiveClipboard` copies that exact public address with
device-local, five-minute expiry. None creates/signs a wallet or implies HyperCore
credit. No fake balance or transaction-success state is introduced.
`ArbitrumDepositPolicy` validates exact integer amounts only; PaperTradingEngine is
not a real balance source.

`Core/Wallet` owns local wallet lifecycle, cryptography and protected storage.
`DeviceWalletCryptography` adapts pinned Wallet Core 4.8.1 binary artifacts via
`ios/Packages/WalletCore`; it uses OS-generated 256-bit entropy, BIP39 and fixed
Ethereum derivation `m/44'/60'/0'/0/0`. `KeychainDeviceWalletVault` keeps entropy in
passcode-required, device-only, user-presence-protected Keychain and offers no
delete, overwrite or generic signing method. A separately recovered bound-address
slot preserves any unbound key created by a losing concurrent device setup.
`DeviceWalletStore` reconciles authoritative account registration before creation,
rejects account-switch/background completions, and resolves missing registered
keys through recovery. Only fixed, session-bound EIP-191 binding proofs go to the
API; mnemonic/private key never does. `Features/Account/DeviceWallet*` adds backup
and recovery pages, full-phrase verification, inactive-scene concealment and
recording detection. Device-passcode, multi-device and capture behavior still need
physical-device validation; screenshot prevention and complete Swift-memory wiping
are not claimed. Fixed-purpose CCTP signing and submission adapters are implemented
behind pre-production gates. Complete receive/deposit UI, withdrawals and real
order signing/execution remain incomplete; see the funding report for boundaries.

### Opinion reading

`Features/Smart/OpinionReaderView` renders the existing localized bSmart summary
separately from the full author text. Original and translation are selectable
reading versions, not two consecutive full-text blocks. The unframed reader uses
17pt body text with Dynamic Type, paragraph/line spacing, a bounded line width,
three persisted size choices, verbatim copy and the original-source link.
`OpinionReadingDocument` preserves paragraphs and lists and breaks dense prose
only at system sentence boundaries. It never rewrites, drops or synthesizes text.
Exact (whitespace-equivalent) evidence matches are emphasized only in the original,
including their conditions/negations; no sentence is inferred in a translation.
Missing translation falls back to the original; a partial excerpt stays explicitly
partial when full text is unavailable. Supporting sources, settlement, price
context, author navigation and the existing trade dock are unchanged.

Reading regression (2026-09-09): 13 model tests and 4 native UI cases passed,
covering verbatim long-post preservation, conditional evidence, localized version
switching, text size and supporting-source navigation. Final Debug build passed;
the Chinese UI case passed after retrying a Simulator launch failure. No API or
TestFlight deployment is part of this reader change.

## Product boundary

Opinion evidence has an `OpinionTradersSection` with distinct real trader count,
consented profile rows and live offset pagination. Core models and API own its
read contract; Features never derive counts from button taps or paper fills.
The detail trade dock and explicit Feed quick actions carry `OpinionTradeSource`
into their own execution flow; ticker navigation does not inherit attribution. It is
not yet a verified order binding: the real executor must establish that server
binding before submission. On dismissal the section reloads the API, and 503 or
missing coverage remains unavailable rather than zero. Debug fixture rows need
the explicit `--ui-opinion-traders-fixture` launch flag. See
`docs/contracts/opinion_trades.md` for privacy and outstanding release gates.

The first iOS release owns four user-facing scenes:

1. `Today`: latest independent Smart Account views and Smart Money actions tied
   to the user's holdings or watchlist.
2. `My profile` (internal route `Portfolio`): editable local avatar, nickname and
   bio above the existing shared asset summary and valuation chart with custom
   underline tabs (`Favorites / Holdings / All tickers`). The summary scrolls
   away with the page; only the tabs pin, giving lists the full reading height.
   Lists page horizontally and retain independent vertical positions. External holdings and in-app
   equity have separate histories; missing history stays empty or a single
   observed point. The searchable directory retains the full supported universe;
   its first section reuses Today's trending selection, then shows the remaining
   catalog without duplicates. Search covers both sections and scrolls the summary
   away for the keyboard; ending search keeps the reading position.
3. `Smart`: parallel Smart Account and Smart Money discovery, ranking, tracking,
   and evidence.
4. `Feed`: newest-first public trades through high-score authors’ opinions, with
   independent user, author, opinion and ticker navigation. `Mr Collie` opens from
   the profile’s lower-right circular launcher as a full-screen research assistant.

The root tab order is `Today / Feed / Search / My profile`. The last tab uses
a person icon and preserves the `portfolio` route and accessibility IDs. Local
profile data lives in `Core/Data/LocalUserProfileStore`, separated by authenticated
account UUID (or guest); it does not alter authentication or wallet identity.
`Features/Portfolio/UserProfileHeader` and `UserProfileEditor` own presentation,
photo downsampling and edits. A matching verified device wallet can supply its
public address. Otherwise an explicitly labeled, non-copyable example is shown
with a no-transfer warning; opening this page never creates or binds a wallet.
Smart Account and Smart Money remain parallel sources across the product.
`Mr Collie` is an interpretation layer over portfolio, signal, Smart Account, Smart
Money, and ticker-intelligence models; it must not become a parallel source of
market facts.

The app is portfolio-first. Generic dashboards are not copied into iOS unless
they directly support one of these scenes.

### Trade Feed and profile assistant

The 2026-09-22 AI layout uses the same compact native navigation as other detail
pages. `AIAssistantWelcome`, `AIAssistantAnswer` and `AIAssistantComposer` keep
presentation inside `Features/AI`; the parent retains conversation orchestration.
Suggested questions are divider-separated rows, answers use full-width body text
with collapsible evidence, and the keyboard-aware composer is a bottom safe-area
inset. Status decorations and redundant helper subtitles are removed. Source data
times and actual service-failure notices remain. Requests, grounded fallback,
conversation context and evidence navigation use their existing implementations.

Validation: simulator build and four UI regression cases pass (Chinese light-mode
large text, typed submission/reset, evidence round trip, repeated profile opening
and tab restoration), along with the existing grounded-answer unit case.
Architecture, terminology and diff whitespace checks pass.

`ProfileAssistantLauncher` owns the circular avatar, full-screen presentation and
one tab-visibility token. The existing `AIAssistantView` accepts a close action;
its composer no longer reserves root-tab space. Native zoom expands from the
launcher on supported iOS versions. Dismissal releases only the assistant token,
so nested detail navigation cannot accidentally reveal the root tabs.

`Core/Models/TradeFeed`, `Core/Data/TradeFeedStore` and `Features/Feed` consume the
new `/v1/trade-feed` and `/v1/public-traders/{profileId}` read APIs. Each event is
one verified, opinion-attributed order; partial fills aggregate without changing
event identity/time. Views use original opinion text, separately labelled summary
fallback, and existing author/opinion/ticker destinations. Public profiles show
only their current consented trades. Pagination de-duplicates, refresh replaces,
and failed refresh or leaving the tab clears public rows. Debug examples require
`--ui-trade-feed-fixture`; production never substitutes example users for 503.
Production no longer has a Demo toolbar entry. Debug layout tests can explicitly
use `--ui-feed-layout-preview`; the isolated `FeedLayoutPreview` is excluded from
Release builds. `TradeFeedDemoData` supplies labelled examples, and test quick
actions open `FeedDemoTradePreview` without contacting an execution service.

`FeedQuickTradeBar` now exposes only asset logo/ticker, Long and Short. The shared
`BSmartTradeSheet` receives the exact market, direction and opinion source but no
preset amount; opening a sheet does not execute an order. Demo cards show only
the chosen direction/ticker without an execution service. `Core/Trading/FeedQuickTrade`
remains a legacy paper-only regression helper, not the live Feed's action model.
The server only exposes Top 25% author contexts and separately consented public
amounts. The real reconciler and authenticated consent service remain required;
`feed_migration.sql` is prepared but unapplied. See `docs/contracts/trade_feed.md`.

### Today home navigation

`TodayHomeContent` hosts `TodayInvestorDiscoveryModule` above three scene pages,
replacing the home price/opinion chart. The header discovers people only; opinions
remain in the lower home sections. Clicking the text-only discovery heading opens
`TodayInvestorDiscoveryPage` with shared zoom navigation and detail tab hiding.
Its search, platform, specialty and following filters retain the complete published
platform Top 25% cohort; homepage filters are hidden. Education reuses the same
directory content within its platform-scoped modal. `TodayInvestorPool` arranges
three visible circular portraits with a larger centered selection and actual
platform percentile. Every portrait retains its source mark. The existing X identity for @aleabitoreddit
is the initial focus only when eligible; three eligible YouTube authors with images
are placed beside it as editorial discovery, not a new ranking.
`TodayInvestorDiscoveryPeople` uses a native horizontal ScrollView with center
snapping and three equal-width slots. Paging is manual only, with no autoplay or
page counter. Reduce Motion suppresses tap-to-center animation. No Score is
recalculated and no candidate is removed. Portraits use the shared circular `BSmartAvatar`.
The focus card hides raw Score and repeated platform text. In roughly 94pt it shows
the ticker logo, ticker, direction/date/reference price and **stock** return. The
pipeline keeps cumulative ticker contribution ranking, but anchors each work to
its earliest settled positive-contribution call. All figures refer to that same
call. `representativeWork` is an optional lightweight profile field so homepage and
directory render without fetching every author's full text/candles. Only older
profiles without it use the 650ms debounced evidence fallback; failed requests are
not permanently cached as empty. `TodayInvestorDiscoveryWork` exposes the exact
publication time, prior completed close and settlement entry/window in a receipt.
The daily close is explicitly a reference, not a historical execution price.
`TodayInvestorDiscoveryHighlight` validates platform identity and consumes this
projection without recalculating Score. Missing work falls back to actual coverage.
Profile browsing snapshots the current sector/search cohort and reuses
`SmartAccountDetailView`, including representative works and persisted tracking.
Empty portfolios do not block discovery. See `docs/product/investor-discovery-home.md`.
Directly below it, the text-only market heading introduces three custom scene tabs:

- Holdings & Tracking: holdings-related activity and tracked accounts.
- Market overview: two Trending Tickers and two Alpha Tickers with full-list links.
- Smart updates: investor-grouped activity across Smart Account and Smart Money.

The three basic scene tabs remain on Today; nested source pickers do not. Holdings and Smart updates
heading links open their existing collections, where source/ticker/search filters
remain available. `BSmartCollapsingPager` / `BSmartCollapsingScrollState` preserve the
shared collapsing header, scene scroll offsets and horizontal page swipes. Detail
return retains selection; the portrait gesture changes only the chosen investor.
Preview cards are vertical, avoiding an inner horizontal carousel. Market discovery
and Smart updates remain accessible without a portfolio. Bottom clearance keeps the
final row above the floating root navigation. No data contracts or scoring change.
See `docs/product/today-home-navigation.md` for the confirmed interaction boundary.

### Holdings-related activity

Today places `TodayHoldingsActivityModule` in the first section, above Tracked activity.
Its pure `TodayHoldingsActivity` projection consumes existing
`AppModel.positions`, `smartAccountUpdates`, and `smartMoneyMovements`; it performs
no requests or Smart score calculations. Only declared external/manual positions
are in scope, including weight-only positions. Watchlists and local sandbox
trading positions are not treated as actual holdings.

The preview shows up to three distinct holding tickers before repeating a ticker.
The full collection supports intersecting source/ticker filters. Both views
rebuild on source/holding changes and foreground entry, using a real rolling
30-day cutoff, never a cutoff anchored to stale fixtures. Latest evidence per
source, actor, ticker (and market for money) survives deduplication. Recency bands
precede known position weights; missing weights are not invented and the valuation
denominator includes holdings without Smart coverage.

Account rows open `SmartAccountEvidenceDetailView`; money rows open
`Features/Smart/SmartMoneyMovementDetailView`, which retains the selected action,
market, observation time and notional before/after even if its account is no
longer on the leaderboard. No financial confirmation or execution intent is
inferred across sources. Research and product rules are in
`docs/product/holdings-related-activity.md`.

### Investor-grouped Smart updates

`TodayInvestorActivity` replaces the standalone-opinion home feed with an
investor-first projection of the current Smart Account and Smart Money read
models. It keeps a real rolling 30-day window, excludes future records, dedupes
event IDs within source/actor identity, and groups by platform + author ID or
wallet account ID. Names never merge identities, and different sources never
merge merely because their identifiers match. All source events, tickers,
lifecycle changes and markets remain available in the investor timeline.

`TodayInvestorActivityModule` occupies the third scene, even without positions.
Its home preview shows three investors ordered by newest event and two events
per investor. The full collection supports source filtering and investor/ticker
search; a ticker match selects the investor, retaining their cross-ticker context.
`TodayInvestorActivityCard` uses a single identity header with existing ranking,
platform mark and persisted tracking action. Identity opens the profile, each
event opens its exact evidence, and All activity opens the investor timeline.
The projection rebuilds when source data changes or the app resumes. No new
requests, fabricated aggregate financial conclusions or client-side scoring are
introduced. Holdings relevance remains in the separate holdings module.

## Directory boundary

```text
ios/
├── project.yml                 # XcodeGen source of truth
├── BSmart/
│   ├── App/                    # lifecycle, root tabs, dependency assembly
│   ├── Core/
│   │   ├── Models/             # API contract representations
│   │   ├── Data/               # HTTP/fixture clients and local persistence
│   │   ├── Trading/            # Hyperliquid public market data and local execution sandbox
│   │   ├── DesignSystem/       # native tokens and reusable primitives
│   │   └── Notifications/      # permission, preview, and local alert preferences
│   └── Features/
│       ├── Today/
│       ├── Portfolio/
│       ├── Research/          # Reusable all-tickers directory and ticker detail
│       ├── Trading/           # Trade-first ticker workspace and market picker
│       ├── Smart/
│       ├── AI/                # Profile-launched Mr Collie and deterministic fallback
│       ├── Feed/              # Public trades, profile destinations and quick actions
│       └── Settings/
├── BSmartTests/
└── BSmartUITests/
```

Feature views may depend on `Core`. `Core` must not depend on a feature.
Features must not import each other to reuse UI; move genuinely shared UI to
`Core/DesignSystem` and shared domain types to `Core/Models`. `Features/Trading`
is the one cross-feature capability surface: Today, Smart, Portfolio, and
Research may invoke its shared trade button, trade dock, or trade sheet, but
must not duplicate order state, market loading, or execution logic.

## Data boundary

The Portfolio value header separates external brokerage/manual positions from
the in-app trading account. External rows use their own stored equity price,
quantity, and cost basis, not a same-symbol derivative quote. In-app total equity
is available cash + isolated margin + unrealized P&L; leveraged notional is
displayed only as position size. `PortfolioHoldingSnapshot` keeps missing cost,
quantity, and price unavailable rather than inventing zero returns. No deposit
integration or real execution is introduced: the account still consumes the
existing local trading engine. A catalog refresh marks only matching held coins.
Market rows use 16pt symbols and 17pt prices; venue identity stays in the model
but is not displayed alongside the ticker.

Portfolio lists share `BSmartMarketRow`: logo/ticker/24h notional volume on the
left, unit price/daily percentage change on the right. Volume, change, leverage,
and venue follow the same winning market quote in `AppTickerCatalogEntry`;
missing market fields stay unavailable, never substituted with cost-basis P&L.
`BSmartMoneyFormat.bSmartDollars` fixes dollar-symbol rendering across UI locales
without changing the source currency or rewriting original posts.

Ticker logos are bundled under `Assets.xcassets/Ticker_*.imageset`. Source URLs
and hashes live in `ios/asset-sources/ticker-logos.json`; the bounded download
script `scripts/sync_ios_ticker_logos.py` regenerates the asset registry. Special
HIP-3 codes use issuer/venue assets instead of guessing US equity ticker aliases.
New, unbundled symbols retain the existing remote/fallback path until audited.

Author avatars share `BSmartAvatar` across all scenes. `AuthorAvatarRegistry`
maps the SHA-256 of the **complete public image URL** to a bundled 256px asset;
no name/handle matching, ranking data, or HTML prototype data enters the bundle.
`scripts/sync_ios_author_avatars.py` reads only avatar URLs from supplied read
models and retains source/hash provenance in `ios/asset-sources/author-avatars.json`.
Its explicit `--fallback-proxy` option allows a public image relay during asset
preparation only. The app never sends requests, API tokens, or user state to that relay.
Run the script when releasing a changed author catalog; missing source URLs stay
missing and changed URLs do not inherit another image. This is an asset snapshot,
not a live avatar refresh service.

For unbundled URLs, `Core/Data/AvatarImageStore` coalesces simultaneous requests,
limits downloads to four, decodes/downsamples off the main actor, and uses a
24 MB memory cache plus a 32 MB / 512-entry / 30-day cache under iOS Caches.
Valid compressed thumbnails persist across launches; HTML, invalid responses,
oversized images and failures do not. Transient connections retry once, repeated
failed requests have a cooldown, and 429 numeric Retry-After is respected. View
cancellation cannot cancel another cell's shared download or install a stale
URL's image. Returning to foreground retries unbundled avatars. No fade transition
is introduced; scores, feed layout and data-source composition are unchanged.

- The app consumes the versioned contract in `contracts/openapi/bsmart-v1.yaml`.
- Development fixture files in `contracts/fixtures` implement the same shape.
- `BSmartClientFactory` is the only data-source composition root. Unflagged
  Debug builds use `BundleBSmartAPIClient`; `--use-live-api` opts Debug into the
  configured API. Release builds always use `HTTPBSmartAPIClient`.
- Release retains the 12 offline bootstrap snapshots, Reddit avatar lookup,
  ticker descriptions and the explicitly selected trade-feed preview. Six
  contract-only fixtures (auth configuration, deletion status, opinion traders,
  subject trade stats, trade feed and wallet registration) are excluded by the
  Release build settings. `check_ios_release_bundle.py` enforces this allowlist.
  Feature code must never select a fixture or live client directly.
- Before account login exists, the app persists a stable installation UUID in
  `UserDefaults`, exchanges it at `POST /v1/installations`, stores the opaque
  Bearer token in Keychain, and retries once after a `401`. Feature code must
  never read or persist this token.
- Manual holdings may be persisted on-device before account sync exists.
- `AppModel.portfolioSignals` filters server signals to current local positions
  and watchlist entries, then prioritizes them by severity, position weight, and
  event time. This is client relevance ranking; Score and signal generation
  remain backend responsibilities.
- `TodayActivity` is a presentation projection over the versioned Smart Account
  update and Smart Money movement read models. It preserves each source as an
  independent fact, scopes activities to holdings or watchlist entries, and
  ranks them using portfolio exposure plus already-published evidence metadata.
  It must not infer confirmation, opposition, or divergence between sources.
- Smart Account updates publish localized `activityTitleZH` and
  `activityTitleEN` from the pipeline. These titles summarize the actual Call
  conclusion, lifecycle change, key level or reason. iOS uses the structured
  Call fields only as a compatibility fallback. Smart Money titles summarize
  the observable action, side and notional amount; safely additive nearby fills
  may be grouped before presentation. Actor and source metadata must never be
  used as a generic activity headline.
- Trending Tickers and Alpha Tickers use `TodaySourceHeadlines` to present
  independent attributed source summaries (up to two per card), with source names
  and dates adjacent to each summary. They do not synthesize shared convictions
  or infer discovery/uncrowdedness in headlines. Complete summaries retain later
  conditions; legacy truncated titles fall back to complete source text.
- Today read state is keyed by the underlying activity UUID and persisted
  locally. The Today tab badge and page summary both count unread holding
  activities from this same projection.
- `AppModel.opportunitySignals` is a secondary, local presentation filter over
  important covered-universe signals that are not held, watched, or ignored.
  The iOS app must not broaden this into a generic market feed or decide which
  raw platform activity qualifies as a production opportunity.
- Portfolio signals carry explicit `smartMoneyCoverage`, `dataStatus`,
  `limitations`, and `nextStep` fields. The client never infers coverage from a
  missing evidence row.
- `NotificationPreferencesStore` owns local delivery, digest schedule, quiet
  hours, and per-ticker choices. Production APNs scheduling remains a backend
  responsibility and must consume these choices through the versioned API.
- `BSmartSyncCoordinator` is the sole mutation boundary. Portfolio, signal
  state, notification preferences, and APNs registration are persisted locally
  first, coalesced in a durable outbox, and retried without blocking the UI.
- Portfolio mutations use client-generated UUIDs with idempotent
  `PUT /v1/portfolio/{id}`. A network failure must never roll back an accepted
  local edit.
- `BSmartAppDelegate` may receive APNs device tokens, but it forwards only a
  normalized registration object to `BSmartSyncCoordinator`; it never reads
  session tokens or constructs authenticated requests.
- The Client API notification planner applies priority, current-data, ticker,
  mute, local digest time, and quiet-hours policy before enqueueing. A separate
  APNs worker owns HTTP/2 provider authentication, delivery leases, retry audit,
  and invalid-token removal. Notification payload deep links route to either a
  concrete signal or the native Today daily digest.
- Product telemetry uses the same durable outbox but a separate enumerated
  contract. It records anonymous interaction IDs needed for MVP value testing;
  views must never attach source text, URLs, search queries, cost basis, shares,
  position weights, or free-form properties.
- `services/client_api` owns the HTTP implementation of the versioned contract.
  It may consume a materialized read model and persist client-owned state, but
  it must not import or invoke ingestion, AI analysis, Score settlement, or
  pipeline job orchestration.
- Pipeline materialization publishes a complete content-addressed release to the
  Read Model database, then atomically changes the active pointer. API requests
  only read an active immutable release and expose collection ETags; incomplete
  pipeline output must never be activated. Previous releases are retained for
  explicit rollback.
- SQLite, raw platform payloads, prompts, ranking, Score settlement, and wallet
  scoring stay in the backend/pipeline.
- The iOS Smart Account collections are projections of the existing web ranking
  truth (`sv_investor_score`) and Call evidence (`sv_call`). The projection may
  filter for product eligibility, but it must never create a parallel author
  pool or recalculate Score.
- Smart Account author detail loads `smart-account-evidence` lazily through
  `GET /v1/smart-accounts/{accountId}/evidence`. This bounded historical read
  model covers every formally ranked author and is separate from the Top 25%
  realtime `smart-account-updates` pool. Views keep structured interpretation,
  exact source evidence, settlement benchmarks, and audit provenance visually
  distinct; the client never derives historical performance from chart pixels.
  The detail presentation is now a continuous portrait/representative-work profile,
  followed by recent views, ticker stances, characteristics and collapsed methodology.
  For a
  current ticker view, iOS may select the newest published Call per ticker and
  omit a newest `closed` or `invalidated` Call, but it must not infer a sector,
  style, direction or score that is absent from the read models. Recent views are
  limited to that same 30-day publication window; older settled evidence stays
  available in the historical evidence disclosure.
  Representative works are the three tickers with the author's highest summed
  positive settled Score contribution. Each ticker chart uses real daily OHLC
  and up to ten contributing Call markers; the client displays this projection
  and must not rerank tickers from price return or hit count.
- Smart Money detail lazily loads `smart-money-evidence` through
  `GET /v1/smart-money/{accountId}/evidence`. The server selects at most three
  exact Hyperliquid markets by cumulative observed opened/increased/flipped
  exposure and attaches at most ten entry markers plus exact-contract 4h OHLC.
  The client must not rerank markets, substitute stock/ETF prices, or describe a
  snapshot difference as a guaranteed executable fill.
- The app never calls X, YouTube, Reddit, Xueqiu, or Toss directly. Smart Account
  and scored Smart Money read models always come through the versioned bSmart
  Client API.
- Public, unsigned market data is the single exception: `Core/Trading` may call
  Hyperliquid's official `/info` endpoint for `perpDexs`, `metaAndAssetCtxs`, and
  `candleSnapshot`. Feature views must depend on `HyperliquidMarketDataClient`
  and may not construct endpoint requests themselves.
- `Mr Collie` first attempts the configured DeepSeek client in controlled
  internal builds or the authenticated `POST /v1/mr-collie/query` Client API in
  live builds. Both paths consume bounded, already-published read models and
  preserve evidence IDs and data timestamps.
- If remote AI is unavailable, `AIResearchAssistant` provides the original
  deterministic local answer from the already loaded client models and routes
  users back to auditable event or ticker detail. It must not manufacture
  unsupported market facts or recalculate Score.
- A temporary direct DeepSeek key may be injected only through the ignored
  `ios/Config/Secrets.xcconfig`. It is an internal testing exception; wider
  distribution must use the server AI gateway.
- `PaperTradingEngine` remains an isolated legacy/test sandbox; ordinary market
  entry and Feed shortcuts no longer invoke it. The app-account area uses verified
  HyperCore balances or an unavailable state, never the sandbox's US$10,000,
  positions or PnL. Do not reintroduce a paper fallback when a live route fails.
- The native real-money adapter requires wallet signing, explicit confirmation,
  fresh protocol data and durable one-shot exchange submission. Capability gates
  stay disabled pending end-to-end acceptance and independent review. No implicit
  Builder Code fee is applied; future configured fees require separate approval.
- While the scene is active, non-demo builds refresh live intelligence through
  the Client API every 60 seconds; returning to the foreground starts a fresh
  cycle immediately. Pull-to-refresh invokes the same API boundary. This is a
  presentation refresh only: Hyperliquid streaming, scoring and relationship
  materialization remain backend responsibilities.

## Native UI rules

### Shared price charts

Every native OHLC surface uses `Core/DesignSystem/BSmartPriceChart` and the single
`BSmartCandlestick` renderer, including Trading, compact order charts, opinion
evidence, representative works, Smart Money entries and Today evidence timelines.
Features adapt their existing data and navigation only; they must not duplicate
candle marks, axes, or gesture/coordinate calculations. The shared series validates
OHLC without inventing missing data; bounded viewport helpers own zoom/pan and
visible-price autoscaling. UIKit gestures distinguish horizontal navigation from
vertical page scrolling. Tap/hold inspects OHLC; pinch and accessible controls zoom;
double-tap/reset restores the full loaded window. Markers outside the window are
not clamped to its edges. Source prices, call semantics and Score remain unchanged.
See `docs/operations/ios-market-charts.md` for coverage and validation.

`--ui-evidence-chart-fixture` only works through the explicit Debug data client,
providing deterministic Smart Money candles for native interaction tests. It is
not a production fallback and never writes read models or databases.

### Native funding boundary

`Core/Trading/Funding` owns the fixed mainnet Arbitrum USDC CCTP route, exact
six-decimal fee math, fee-request lifecycle and immutable self-deposit plan.
The public-query exception covers Circle's fixed fee endpoint and the fixed
mainnet Arbitrum RPC for source preflight; a separate one-shot broadcaster owns
the sole write method. No installation/account bearer, mnemonic or key is sent.
The fee endpoint receives no wallet identifier; source simulation discloses the
public owner and verified EIP-3009 authorization, and an authorized submission
sends only the journaled signed transaction. URLs and contracts cannot come from Feature
views. Errors/expired quotes do not become zero fees; no legacy Bridge2 fallback.

`ArbitrumFundingRPC` is bounded, HTTPS-only, no-redirect and read-only. Batch
results are matched by unique ID, not response order. `ArbitrumSourceReads` and
`ArbitrumSourcePreflight` pin balances and contract reads to an EIP-1898 canonical
block hash, verify fixed route configuration, restrictions and EOA code, then
recheck the block. Exact-call simulation/gas requires the matching plan signature,
checks funds, allowance/burn limits, used authorization and pending nonce, and
applies bounded gas/price ceilings. Results expire in at most 30 seconds and never
constitute a nonce reservation, a source receipt or HyperCore credit. Native
uint256 money uses `FundingQuantity` with exact BigInt 5.7.0, not Double or UInt64
ETH truncation. `Core/Wallet/CCTPSourceReadCodec` owns static ABI words/selectors.

`CCTPSourceGasBudget` owns the single simulation/encoding gas ceiling formula.
`Core/Wallet/CCTPSourceTransaction` constructs only a type-2 Arbitrum envelope
from a fresh preflight; it rechecks the embedded USDC authorization, full calldata,
funds, nonce, timing and exact gas budget. Wallet Core compiles a recovered-owner,
low-s signature into immutable raw bytes/local transaction hash. Shared
`FundingEthereumSignature` distinguishes EIP-3009 v=27/28 from transaction parity
0/1. Neither codec exposes key access, a generic signing API or RPC broadcast.
Independent Python vectors verify the signing hash, RLP, sender and transaction
hash. Production signing/submission must consume durable journal permissions;
the native funding flow remains disabled until all release gates pass.

`FundingTransactionJournal` is an actor over a separate device SQLite ledger,
not UserDefaults, the research database or an API read model. `FundingJournalRecord`
owns immutable intent and legal transitions; `FundingJournalAnchor` owns AES-GCM,
hash-chain checkpoints and a separate device-only Keychain key; `FundingJournalDatabase`
owns bounded event replay and durable SQLite commits; `FundingJournalFiles` owns
file protection, backup exclusion, permissions and the cross-instance filesystem
lock. No wallet entropy is written to SQLite. No new third-party database library.
Before SQLite opens a ledger, `FundingJournalFiles.databasePath` resolves only its
parent using POSIX `realpath` and preserves the resulting string. This supports
iOS `/var` container aliases without removing `SQLITE_OPEN_NOFOLLOW` on the
database file or resetting the ledger/Keychain anchor.

`FundingJournalInstallation` binds the production journal to an installation-scoped
Keychain service. The protected, backup-excluded `FundingJournalInstallation.json`
marker lives beside (not inside) the ledger directory, and is read/created under
the ledger lock. Existing legacy databases keep their legacy service. A container
with neither marker nor database receives a fresh namespace without deleting or
rewriting surviving Keychain anchors. This also handles the one-time legacy case
where only an orphan anchor remains; pre-marker versions cannot distinguish a
reinstall from loss of all local journal files. This does not restore lost history
or reconcile old orders. Fresh user intent and authoritative venue checks remain
required; no archived transaction is replayed. Once the marker exists, a missing
database with a committed anchor still fails closed. Corrupt/symlinked markers
cannot trigger rotation. Wallet keys and wallet registration are unaffected.

Only fresh preflight can reserve/sign/submit. Already-created signatures and node
results can be archived after expiry/task cancellation, but cannot produce another
submission permit. Historical verification reconstructs the quote/plan/authorization
and canonical transaction, not a newly usable signing request. Keychain pending
checkpoints bracket SQLite commits; recovery must match the committed or exact
pending head. Missing/rolled-back/corrupt storage pauses transfers rather than
resetting history. Physical iOS reads back complete protection and backup exclusion;
the corresponding device test is explicitly skipped on Simulator.

`FundingConsentRecord` and `FundingJournalEvent` extend the same ledger to the
pre-authorization review without discarding older source-only events. A matching
consent is atomically linked to its source intent by ID. `FundingDeviceSigner`
limits protected Keychain use to the fixed authorization and source envelope;
legacy permits lacking recorded consent cannot reach keys. `AccountAccessStore`
issues revocable, account-session-bound signing leases (at most 60 seconds).
Logout/reload/sign-in, background and protected-data lock revoke them. The native
`CCTPDepositPreparation` coordinator verifies registration and source balances
before authorization, requires separate authorization and network-fee confirmations,
and archives signatures before discarding cancelled results. A further explicit
submission action rechecks registration/lease and source state, persists a submit
permission, invokes the broadcaster and archives the result before cancelled UI
checks. It is not yet connected to a production transfer-screen entry point.

`ArbitrumSourceSubmissionCheck` repeats preflight after signing, rejects changed
nonce/code, an older head or a different hash at the same height, then simulates
and estimates the exact approved envelope. It never bumps fees or renews a quote;
the hash/account-bound result expires within 10 seconds or the original deadline.
`FundingSubmissionPermit` is a single-use, locked reference with private raw bytes.
Its synchronous start checks the fresh result and foreground/account lease before
resuming one URLSession task; legacy source-only permits cannot reach transport.
`ArbitrumFundingBroadcaster` fixes `eth_sendRawTransaction` and the endpoint, strips
credentials/cookies/cache, rejects redirects, bounds replies to 16 KiB and times
out within 15 seconds. No retry or fallback. Only a correlated exact local hash
is acknowledged; errors/timeouts/mismatches are uncertain. A started network task
finishes independently of UI cancellation so its bounded response can be archived.
No RPC acknowledgement is a source receipt, finality or HyperCore credit. Tests
use a URLProtocol stub and isolated journal, never send a mainnet transaction.

`FundingHistoryEntry/Store` expose a minimal, signature-free projection from a
single verified snapshot. Linked consent/source records appear once; protected
history reads and unsigned review cancellations recheck account registration.
`ArbitrumSourceObserver` queries only the recorded local hash on the fixed RPC.
`FundingReceiptCodec` matches every signed field and receipt/log location;
`Core/Wallet/CCTPSourceMessage` validates the exact source message and owner hook,
not an offchain attestation. A fresh canonical head anchors nonce/authorization
reads; historical receipt blocks remain readable after signing expiry. Final
reads reject mixed snapshots, changed receipts or canonical hashes. The RPC
finalized tag is data-finality evidence, not rollup settlement or HyperCore credit.
`FundingSourceObservation` appends independently of submission state, chained to
the previous observation and immutable intent. Replay verifies it; stale concurrent
queries cannot overwrite new evidence. No observation releases the nonce or owner,
and a previously observed signed transaction cannot obtain a new broadcast permit.
`Features/Account/FundingHistoryView/Row` provide the wallet-panel history entry,
expandable fees/hash, a manual source check, explicit cancellation confirmation and error/empty states;
they clear on departure/background/account changes. Only consent review or source
prepared can be cancelled after the ledger's current-state recheck. Neither an
expired quote nor a stale view can release an issued signature/submit permission.
Opening history never automatically queries chain data. Already verified query
results are persisted before discarding a cancelled/obsolete UI completion.
Source execution, revert, pending, missing, reorg and conflict remain distinct;
actual source gas is separate from fee ceilings. HyperCore
reconciliation and safe terminal nonce release remain required; the page does not
provide a transfer retry or claim credit. Full replay/
retention is bounded and still needs long-history performance acceptance. Never
interpret persisted `submitted` as final execution or spendable USDC.

`CCTPMessageClient` fetches only the recorded source hash from Circle's fixed mainnet
endpoint. `Core/Wallet/CCTPAttestedMessage` checks the source bytes, mutable fields,
low-S recovery and sorted unique signatures. `HyperEVMAttesterReader` uses the
fixed chain-999 RPC and transmitter, obtains the exact onchain quorum and enabled
signers, and brackets latest-only contract reads by identical fresh blocks. Shared
`FundingRPCProviding`/private transport preserves the existing Arbitrum API and
strict batch matching without introducing a generic URL or write method.
`CCTPAttestationObservation` is a separate journal event linked to the exact source
observation; latest valid verifier state survives pending replies for regression
checks. UI projections hide stale certification after any newer source observation.
The manual history action revalidates registration and refreshes source first;
returned validated evidence is persisted before clearing a cancelled view. It shows
waiting/verified/expired/paused/processed status and attested fees, never signatures
or raw messages. Circle's transaction association and RPC state are provider trust
assumptions, not a light-client proof; proxy audit and per-deposit HyperCore receipt
reconciliation remain release gates. No automatic reads, re-attestation or sends.

`CCTPForwardReceipt` isolates one nonce's synchronous receive-to-forward log
interval even inside a relayer batch. `Core/Wallet/CCTPForwardEventCodec` validates
fixed-emitter ABI evidence for message body, owner, USDC transfer, actual DEX route,
net amount and optional new-account fee; HyperCore 8-decimal amounts remain exact.
`CCTPForwardObserver` checks fixed chain 999 before sending the recorded hash,
rereads the canonical receipt/block, and brackets the nonce read with one fresh
head. `CCTPForwardObservation` extends the encrypted journal, linked to current
source/attestation/previous forwarding IDs. Conflicting or missing receipts cannot
erase previously accepted HyperBFT inclusion. History queries append evidence
before dismissing obsolete UI, hide stale projections and distinguish perps
requests from spot fallback. These events are NOT proof of HyperCore credit or
HIP-3 collateral. Ledger correlation, lifecycle release, deployed implementation
audit and live acceptance remain necessary; no balance mutation or sends are added.
Fee previews now label CCTP-only net rather than guaranteed/minimum HyperCore
credit. Destination contract fees and protocol activation must be checked separately.

`ArbitrumWalletBalanceStore` rejects stale/account-mismatched/older completions;
`Features/Account/ArbitrumWalletBalanceView` exposes a manual read for a verified
device wallet, clears it on background/page departure/account changes, and shows
unknown rather than zero on failure. It never displays a receiving QR or enables
funding/trading. The mainnet read-only smoke test is explicitly opt-in; offline
tests inject RPC responses, never a production balance or key. A production RPC
SLA, verified proxy implementation manifest and independent audit remain required.

`HyperCoreBalanceClient/Provider/Snapshot/Store` add explicit public reads to the
verified wallet panel. The transport pins the mainnet `/info` endpoint, removes
credentials/cookies, rejects redirects, bounds responses to 256 KiB and cancels
outstanding requests. Registration is rechecked before disclosing the owner.
Mode queries bracket the reads: unified account and portfolio margin use spot
USDC, while default/disabled/DEX abstraction show spot and default perps separately.
USDC token 0 and 8-decimal string amounts are checked; signed perps equity is not
cash. No field is summed, converted to HIP-3 buying power or copied into paper
trading. Unknown/malformed data is an error, not zero.
`Features/Account/HyperCoreBalanceView` provides a manual refresh, mode-specific
rows, check time and expiry; all text supports Dynamic Type and light/dark mode.
Snapshots expire in at most 30 seconds and disappear on session expiry, wallet
lock/change, background or page departure. Spot has no server timestamp; this is
a short-lived multi-request API observation, not an atomic snapshot. The opt-in
`HyperCoreBalanceLiveTests` use public probes only and never the device vault.
HyperCore ledger hashes differ from EVM transaction hashes. Exact per-deposit
system-action/nonce correlation remains a separate release gate; successful EVM
forwarding and increased balance cannot replace it. No production sends enabled.

`Core/Wallet/CCTPDepositCodec` uses pinned Wallet Core for EIP-712 and ABI, verifies
the authorization belongs to the owner, and encodes one fixed burn message to
that same owner's default HyperCore perps account. It does not access Keychain,
sign, broadcast or establish spendable balance. The prior 5-USDC minimum was a
legacy-bridge rule; the new guard is a disclosed product residual requirement
after the fee ceiling, not an invented CCTP protocol minimum.

`Features/Account/CCTPDepositEstimateView` consumes that boundary and may show
fee/net-credit estimates even before login because no address is queried. It
clears pending/visible quotes on leaving the page or backgrounding. It cannot
enable receiving or trading. Native regression vectors live in the unit-test
bundle only, independently verified by Python `eth-account`/`eth-abi`; they are
not runtime fixtures or an alternate funding route. Full lifecycle gates remain
in `docs/contracts/trading_account.md` and the funding research document.

- SwiftUI and Apple navigation conventions are the default.
- Use SF Symbols and system typography. SF Pro is the native equivalent of the
  web typography, and `monospacedDigit()` is required for changing market data.
- Colors, spacing, and radii map from `design/tokens/bsmart.tokens.json`.
- Dark and light appearances are both supported. Feature views must use the
  semantic roles in `BSmartColor`; fixed dark surfaces, white labels, and black
  shadows are allowed only inside intentionally branded artwork whose contrast
  is independent of the system appearance. Dense charts use the dedicated
  `chart*` roles instead of copying RGB values.
- Do not use WebView as a migration shortcut.
- Screens must support Dynamic Type and VoiceOver labels for icon-only actions.

### Signal Pulse presentation layer

The primary iOS presentation language is `Signal Pulse`. It changes hierarchy
and interaction, not the data or ranking contracts:

- `BSmartTokens.swift` owns the near-black neutral scale and the lime `pulse`
  accent. Pulse is reserved for selected navigation, primary actions, live
  state, and the edge of the single highest-priority object. It is not a page
  background or a generic bullish color.
- `BSmartComponents.swift` owns shared page titles, circular icon actions,
  metric strips, section titles, and paired evidence cells. Feature folders
  must reuse these primitives instead of copying local variants.
- Today presents one most-relevant activity before source and unread filters or
  secondary rows. The activity must identify the actor or public account and
  explain its view or observed action; generic synthesized headlines are not a
  substitute. A weight-only portfolio shows position and declared-allocation
  context and never fabricates a zero market value.
- Smart Account and Smart Money remain parallel. The hub uses one visible filter
  summary and a native sheet for stackable filters; individual filter chips must
  not consume the default viewport.
- Smart Money presents a stable pseudonymous consumer identity, never a raw
  account address or an inferred real owner. The backend owns deterministic
  `displayName` and `avatarVariant`; the iOS hash implementation is only a
  compatibility fallback. All identities use the shared six-variant border
  collie editorial avatar system plus a stable accent ring. The raw account
  identifier remains available only in the original-record audit action.
- Ticker research uses `Trade / Smart Account / Smart Activity` contexts tied to
  one ticker, with `Trade` as the default. Trade shows official Hyperliquid
  market context and the trading account; Smart Account and Smart Activity remain
  evidence contexts and do not duplicate a generic social feed. The overview
  price line may combine Smart Account Call bubbles and Smart Money action
  bubbles; every marker and feed row preserves its source, actor, timestamp,
  horizon, and source-specific evidence.
  Expensive ticker projections (price-evidence candle merging, marker mapping,
  and unified activity sorting) must be built once outside SwiftUI `body` and
  reused across context changes. Long activity feeds use lazy containers; tab
  changes must not animate the full chart or feed subtree.
- Every executable Smart context uses the same Trading-owned surface:
  research cards do not expose trading buttons. The Feed has the explicitly
  requested direction-only Long / Short actions described in the Feed section. Ticker, consensus, alpha, price-evidence,
  Call-evidence, and event detail pages expose a pinned Short / Long dock.
  The market page is chart-first, with timeframe/style controls beneath the
  chart and account/market statistics in the secondary context.
  `TradeOrderComposer` owns the focused amount/keypad/preset/leverage surface;
  `TradeLeveragePicker` provides a horizontally snapping integer leverage ruler.
  Entry direction comes from the detail dock; the composer only communicates
  direction through its confirmation action, not a second side selector.
  The keypad and compact candlestick chart share one switchable input region
  and intentional slide-to-submit action; it delegates all fills to the
  existing engine. Fees, exposure and liquidation estimates remain visible.
  A sheet uses a separate market-store session with the same provider so
  switching its market/range cannot overwrite the presenting page.
  `--ui-trading-fixture` is a Debug-only, explicit UI-test market provider,
  never a fallback for unavailable production prices.
- Portfolio `All tickers` merges server intelligence, holdings, Smart evidence,
  account coverage and the Hyperliquid market catalog through `AppTickerCatalog`.
  It normalizes and deduplicates symbols, retaining unavailable quotes as nil.
  `TickerDestinationView` gives every ticker an isolated market session and
  opens a market/evidence detail when no intelligence snapshot exists.
  Opt-in logo links use the same destination and shared zoom presentation;
  selection controls and decorative logos remain non-navigating.
- Portfolio history is a separate optional valuation contract. The client may
  chart server or brokerage snapshots, but must show an unavailable state
  instead of synthesizing a historical path from current value or cost basis.
- Event detail reads in the order `change -> bSmart conclusion -> position
  impact -> paired evidence -> audit`. Original evidence and limitations remain
  reachable; visual compression must not remove them.
- Visual uppercasing must not alter VoiceOver labels. Stable accessibility
  identifiers are part of the UI test contract and survive layout refactors.
- Tab badges may expose unread portfolio-event counts. They must not represent
  raw platform-post volume.
- The third `Search` tab uses the same native icon and selected-state treatment
  as the other tabs. Do not place a custom control over a native tab item.
- `Smart`, `Smart Account`, and `Smart Money` are untranslated product terms in every locale.
  Localized explanatory sentences may translate the surrounding copy, but must
  preserve these exact English names.

## Build and test

```bash
make ios-generate
make ios-resolve
make ios-build
make ios-test
```

For end-to-end development against the real HTTP boundary, start
`make client-api-dev`, then launch the Debug app with `--use-live-api` and
`BSMART_API_BASE_URL=http://127.0.0.1:8081`. Fixture-backed reads are permitted
only in this development service mode; production refuses to start with the
fixture read model.

`ios/project.yml` is the project source of truth. Generated
`ios/bSmart.xcodeproj` is committed so contributors can open the project without
installing XcodeGen, but structural target changes must be made in `project.yml`
and regenerated.

## Distribution and collaboration

- Bundle IDs, signing teams, capabilities, and Store Connect identifiers are
  environment/release configuration, not hard-coded feature behavior.
- Secrets never enter `.xcconfig` files committed to Git. Anonymous installation
  tokens are issued by the bSmart API and stored in Keychain; later account
  authentication must use the same secure-storage boundary.
- TestFlight is the default internal distribution channel.
- Feature work uses normal pull requests in the same repository, allowing API,
  pipeline, and iOS contract changes to be reviewed together.

## Trade theses (2026-09-22, backend deployed)

`Core/Models/TradeThesis` and `Core/Data/NativeTradeThesisClient` extend verified
trade activity with original reasoning and per-user like state. UI stays in
`Features/Feed/TradeThesisComposer`, `TradeThesisActions`,
`Features/Trading/TradeThesisAfterFill` and `Features/Portfolio/ProfileTradeActivity`.
The fill screen reads verified activity first, requesting independent verification only while pending;
my profile also lists owned verified trades for later publication. Existing
`TradeFeedRow` quotes the registered opinion beneath the user text and is shared
by Discover and public profiles. No signer, balance or order execution changes.
See `docs/contracts/trade_thesis.md` and `supabase-feed.yaml`. The operator confirmed
the manual migration; a read-only projection check returned 200 and bsmart-feed
was deployed. No production thesis or real order was created during verification.

## Supabase content activation (2026-09-22)

Build 1.0 (9) defaults to SupabaseContentClient. The main run scheme opts into live
content; bSmart Local explicitly keeps legacy for localhost development. Fixture
arguments for automated UI tests still take precedence. A successful authenticated
snapshot commit writes a non-sensitive Application Support/ContentVerification.json
receipt containing revision, verification time and collection counts. It does not
contain account IDs, tokens, wallet data or content bodies. Foreground polling stays
at 60 seconds; the separate local delivery queue publishes supplied packages every
three hours when the host and Codex are available.
