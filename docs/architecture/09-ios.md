# iOS Client Architecture

bSmart iOS is the primary MVP client. It is built from scratch in SwiftUI and
shares the existing backend, database, pipeline algorithms, product contracts,
and design language. It does not embed the website with `WKWebView`.

## Product boundary

The first iOS release owns four user-facing scenes:

1. `Today`: latest independent Smart Account views and Smart Money actions tied
   to the user's holdings or watchlist.
2. `Smart`: parallel Smart Account and Smart Money tracking.
3. `Portfolio`: a single portfolio workspace with `Holdings`, `Watchlist`, and
   `All tickers` contexts. `All tickers` is the searchable directory of every
   ticker in the supported intelligence universe.
4. `AI`: a portfolio-aware research interface grounded in the evidence already
   available through the client read models.

The root tab order is `Today / Smart / Portfolio / AI`. All four tabs use the
same native tab-bar treatment; `AI` is the final tab and acts as an interpretation layer over existing
portfolio, signal, Smart Account, Smart Money, and ticker-intelligence models.
It must not become a parallel source of market facts.

The app is portfolio-first. Generic dashboards are not copied into iOS unless
they directly support one of these scenes.

## Directory boundary

```text
ios/
├── project.yml                 # XcodeGen source of truth
├── BSmart/
│   ├── App/                    # lifecycle, root tabs, dependency assembly
│   ├── Core/
│   │   ├── Models/             # API contract representations
│   │   ├── Data/               # HTTP/fixture clients and local persistence
│   │   ├── DesignSystem/       # native tokens and reusable primitives
│   │   └── Notifications/      # permission, preview, and local alert preferences
│   └── Features/
│       ├── Today/
│       ├── Portfolio/
│       ├── Research/          # Reusable all-tickers directory and ticker detail
│       ├── Smart/
│       ├── AI/
│       └── Settings/
├── BSmartTests/
└── BSmartUITests/
```

Feature views may depend on `Core`. `Core` must not depend on a feature.
Features must not import each other to reuse UI; move genuinely shared UI to
`Core/DesignSystem` and shared domain types to `Core/Models`.

## Data boundary

- The app consumes the versioned contract in `contracts/openapi/bsmart-v1.yaml`.
- Development fixture files in `contracts/fixtures` implement the same shape.
- `BSmartClientFactory` is the only data-source composition root. Unflagged
  Debug builds use `BundleBSmartAPIClient`; `--use-live-api` opts Debug into the
  configured API. Release builds always use `HTTPBSmartAPIClient`.
- Fixture JSON is a development asset and must not exist in a Release archive.
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
  the observable action, side and notional amount; safely additive nearby
  opening or closing fills may be grouped before presentation. Actor and source
  metadata must never be used as a generic activity headline.
- Today read state is keyed by the underlying activity UUID and persisted
  locally. The Today tab badge and page summary both count unread holding
  activities from this same projection.
- `AppModel.opportunitySignals` is a secondary, local presentation filter over
  important covered-universe signals that are not held, watched, or ignored.
  The iOS app must not broaden this into a generic market feed or decide which
  raw platform activity qualifies as a production opportunity.
- Portfolio signals carry explicit `smartMoneyCoverage`, `dataStatus`,
  `limitations`, and `nextStep` fields.
  The client never infers coverage from a missing evidence row.
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
  The detail presentation is split into `Overview / Views / Track record`.
  Overview puts the published specialty, strongest horizon, investment style,
  coverage and the latest 30-day ticker views before ranking provenance. For a
  current ticker view, iOS may select the newest published Call per ticker and
  omit a newest `closed` or `invalidated` Call, but it must not infer a sector,
  style, direction or score that is absent from the read models. `Views` is
  limited to that same 30-day publication window; older settled evidence stays
  under `Track record`.
  Representative works are the three tickers with the author's highest summed
  positive settled Score contribution. Each ticker chart uses real daily OHLC
  and up to ten contributing Call markers; the client displays this projection
  and must not rerank tickers from price return or hit count.
- Smart Money detail lazily loads `smart-money-evidence` through
  `GET /v1/smart-money/{accountId}/evidence`. The server selects at most three
  exact Hyperliquid markets by cumulative observed opened/increased/flipped
  exposure and attaches at most ten entry markers plus exact-contract 4h OHLC.
  The client must not rerank markets, substitute stock/ETF prices, or describe a
  Hyperdash snapshot difference as a guaranteed executable fill.
- The app never calls X, YouTube, Reddit, Xueqiu, Toss, or Hyperliquid directly.
- The first AI assistant implementation is deterministic and local: it organizes
  the already loaded client read models, exposes their evidence and timestamps,
  and routes users back to auditable event or ticker detail. A future remote
  model may improve language and synthesis, but it must consume a versioned
  server-provided context and preserve evidence references; feature views must
  never send raw platform credentials or manufacture unsupported market facts.
- Internal-only builds may inject a temporary DeepSeek key through the ignored
  `ios/Config/Secrets.xcconfig` and use `DirectDeepSeekMrCollieClient`. This is an
  explicit test distribution exception, not the production security boundary.
  The client submits only bounded portfolio and published evidence read models,
  preserves citation IDs, and falls back to the deterministic local answer.
  Public/TestFlight distribution must return to the server AI gateway before the
  key is shared beyond the controlled internal tester group.
- While the scene is active, non-demo builds refresh live intelligence through
  the Client API every 60 seconds; returning to the foreground starts a fresh
  cycle immediately. Pull-to-refresh invokes the same API boundary. This is a
  presentation refresh only: Hyperliquid streaming, scoring and relationship
  materialization remain backend responsibilities.

## Native UI rules

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
- Smart Account and Smart Money remain parallel. The hub uses one visible
  filter summary and a native sheet for stackable filters; individual filter
  chips must not consume the default viewport.
- Smart Money presents a stable pseudonymous consumer identity, never a raw
  account address or an inferred real owner. The backend owns deterministic
  `displayName` and `avatarVariant` fields; the iOS hash implementation is only
  a compatibility fallback for older read models. Display names are single
  given names and the backend guarantees uniqueness inside each published
  Smart Money account pool. Every Smart Money identity
  uses the shared left-facing border collie character in a non-realistic,
  geometric editorial illustration style. Six stable professional variants
  use strongly differentiated coat and medallion palettes: black/emerald,
  chocolate/amber, blue-merle/blue, red-merle/coral, sable/violet, and
  silver/cyan. Large central accessories provide a second recognition layer
  while preserving the same subject and direction.
  Nine accent-ring colors combine with the six images into 54 unique account
  avatars in the current published pool.
  The raw public account identifier remains available only in the
  original-record audit action.
- User-facing Smart Money size language maps protocol-native tiers into familiar
  capital-account categories. `Whale` / `巨鲸` and `PNL` remain valid because
  they are established in both active US-equity and crypto markets; Kraken,
  Shark, Dolphin, Fish, Crab, and Shrimp must not leak into the consumer UI.
- Ticker research uses `Overview / Smart Activity` contexts tied to one ticker.
  The overview price line may combine Smart Account Call bubbles and Smart Money
  action bubbles, but every marker and feed row preserves its original source,
  timestamp and source-specific metadata. Unavailable Smart Money coverage must
  remain explicit and may not be interpreted as neutral activity.
  Expensive ticker projections (price-evidence candle merging, marker mapping,
  and unified activity sorting) must be built once outside SwiftUI `body` and
  reused across context changes. Long activity feeds use lazy containers; tab
  changes must not animate the full chart or feed subtree.
- The Portfolio `All tickers` context enumerates the complete server-provided
  `TickerIntelligence` universe before applying client search. It shares the
  Portfolio navigation stack, and features must not maintain a second
  hard-coded list of supported symbols.
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
- The second `Smart` tab uses the same native icon and selected-state treatment
  as the other tabs. Do not place a custom control over a native tab item.
- `Smart`, `Smart Account`, and `Smart Money` are untranslated product terms in
  every locale. Localized explanatory sentences may translate the surrounding
  copy, but must preserve these exact English names.

## Build and test

```bash
make ios-generate
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
