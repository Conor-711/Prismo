# Privy iOS setup

## Current integration

The app retains Google -> Supabase authentication. Privy Swift 2.16.2 consumes
the current Supabase access JWT and manages user-owned Ethereum wallets. No
Privy App Secret belongs in the app, its configuration, or this document.
There is no new server or SQL migration for this integration.

- App ID: `cmtyhnhcb01190cl08a0cvk3x`
- iOS App Client ID: `client-WY6d9D7yhHLpUUw6b6DmnMooHJQW2AsgPE2M58DFRHVht`
- iOS bundle ID: `today.bsmart.ios`
- SDK source: <https://github.com/privy-io/privy-ios/tree/2.16.2>
- SDK revision: `71dd5fe9eb20a8dfaa411b219f856c108473f909`

These public identifiers are configured in `ios/project.yml`; generate the
Xcode project with `make ios-generate`. First package resolution needs GitHub
access and Xcode with Swift 6 support (the app remains in Swift 5 language mode).

## Dashboard

The operator confirmed Custom authentication and the following JWT configuration
were saved on 2026-09-12. This confirmation is not a successful app-login test.

| Setting | Value |
| --- | --- |
| Integrations / Built-in / Custom authentication | On |
| Authentication / JWT integration / JWT-based authentication | On |
| User ID claim | `sub` |
| Sub-user ID claim | Empty |
| Verification | JWKS endpoint |
| JWKS endpoint | `https://dzyitinagewdfkzjkuiz.supabase.co/auth/v1/.well-known/jwks.json` |
| Authentication environment | Client side only |
| JWT aud claim | `authenticated` (add the value) |
| Additional claim key | `iss` |
| Additional claim value | `https://dzyitinagewdfkzjkuiz.supabase.co/auth/v1` (add the pair) |
| Require aud or an additional claim | On |

In Basics / Clients, verify this client is an iOS client for the bundle ID above.
On 2026-09-13 the public application response had an empty
`allowed_native_app_ids` list despite Custom JWT being enabled. After the
operator saved the iOS identifier, a second read confirmed `["today.bsmart.ios"]`.
App-client restrictions must also allow this identifier. This fixes a missing
native-app configuration prerequisite; live user wallet creation is still not
proven by a public configuration read.
Keep signing user-owned; do not add server authorization keys or automatic funding
policies for this MVP. App secret, Google client ID and Supabase publishable key
are not JWT verification keys. The Supabase JWKS endpoint returned an ES256 key
in the read-only configuration check. Tokens must actually use that asymmetric
signing key; if an older session still uses HS256, refresh/re-authenticate it.

The supplied dashboard identifies development mode (150 users) and marks Custom
authentication as a Scale feature, free in development. Confirm production
eligibility/pricing with Privy before distribution beyond that mode; base-plan
wallet allowances do not establish Custom Auth production entitlement.

## Expected flow

1. Google login establishes the existing Supabase UUID and renewable session.
   The dedicated account entry loads the cloud profile; first-time users choose
   their nickname, unique username and avatar before continuing. A successful
   existing profile PUT (positive revision) completes this step across devices.
2. Open the trading wallet (Settings or the account's missing-wallet entry).
3. With no registered address, resolve the existing Privy EVM wallet or create
   one if absent. Prove address ownership to the existing wallet registry.
4. Show Account wallet / Privy without mnemonic or device-key Face ID controls.
5. Receive native USDC and gas ETH on Arbitrum, then use the existing CCTP,
   unified-USDC, perpetual order and withdrawal flows. Signing uses Privy;
   transaction validation, confirmation and broadcasting remain in bSmart.
6. On a second device, the same Supabase UUID resolves the same registered Privy
   address without creating an additional wallet or requiring a mnemonic.

Temporary provider failures show retry and never generate a fallback local key.
Switching/logging out clears the provider session and revokes transaction leases;
backgrounding locks transaction access but does not force a new Google login.

## Existing wallets

A matching local device key always takes precedence. This rollout does not
upload that key to Privy, replace its registry address or move its funds.
Such accounts still show Device wallet and retain their existing backup setting.
A lost legacy key is not recoverable merely by logging in to Google/Privy.
Test new embedded-wallet creation with a separate test account that has no
legacy wallet binding. Migration of funded accounts is a separate explicit flow.
Native Apple login is enabled when the Supabase Apple provider is configured.
Its verified Supabase user must bind to the same wallet identity; do not match
email strings or create another wallet identity implicitly.

Deleting the Supabase account can destroy account-based recovery. Move funds to
an independently accessible wallet before account deletion. This release does
not implement independent Privy private-key export or automatic legacy imports.

## Acceptance

- Build with `make ios-build`; run wallet/session/signing tests and regression tests.
- New Google test account: Account wallet is shown and public address matches
  the Privy dashboard and Supabase registry. Do not share access/refresh tokens.
- Logout/relogin and a second device: the exact address remains unchanged.
- Existing funded device account: address, holdings and original trading UI stay
  unchanged; do not uninstall or erase its Keychain to test cloud recovery.
- User-controlled small-value Arbitrum funding, perpetual open/reduce/close and
  withdrawal are still required for live acceptance. Automated tests sign only
  public disposable test vectors, never broadcast or transfer real funds.

## Local verification (2026-09-12)

- Official Swift package 2.16.2 resolved at the revision above; simulator build
  passed with both arm64 and x86_64 slices.
- Generic iOS device build also passed with `CODE_SIGNING_ALLOWED=NO`;
  physical-device installation and distribution signing are not included.
- The complete `BSmartTests` suite passed on iPhone 16 / iOS 18.5: 940 tests,
  6 skipped, 0 failures. Skips are five opt-in mainnet read checks and one
  physical-device file-protection check, not embedded-wallet unit tests.
- The simulator test app needs ad-hoc signing for real Keychain tests. An
  unsigned run failed the Google Keychain lifecycle test; rerunning with
  `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` passed without changing that
  test or weakening session storage. Reproduce with:

```bash
xcodebuild -project ios/bSmart.xcodeproj -scheme bSmart \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO -only-testing:BSmartTests test
```

- Architecture boundaries, terminology, and whitespace checks passed.
- Google -> Supabase -> Privy live login, second-device recovery and real funds
  remain user acceptance steps. This local verification is not a TestFlight
  upload, an account migration, or evidence of a completed on-chain transfer.

2026-09-13 follow-up: the profile-onboarding and SDK-error-mapping changes passed
the full signed simulator unit suite (943 tests, 6 skipped, 0 failures). The
native-app identifier was confirmed through a public configuration read after
the operator changed it; actual user wallet creation is still a separate check.

2026-09-13 connection follow-up: the physical-device Xcode console reported
`Privy stage=restoring status=429` twice. The unconditional user refresh was
blocking resolution before creation, independently of the native identifier fix.
Resolution now uses the authenticated wallet inventory, refreshing only for a
missing registered address or uncertain creation. HTTP 429 starts an in-process
60-second cooldown, increasing to at most 300 seconds after repeated failures;
taps during cooldown do not send requests. This does not claim to change Privy's
server-side limit or automatically replay wallet operations. The signed simulator
suite passed with 950 tests, 6 skipped, 0 failures. Install the new build through
Xcode, wait for the indicated cooldown if necessary, then retry once. Live wallet
creation and cross-device recovery still require user verification.

References: [Privy Supabase integration](https://docs.privy.io/recipes/authentication/using-supabase-for-custom-auth),
[JWT configuration](https://docs.privy.io/authentication/user-authentication/jwt-based-auth/setup),
[Swift setup](https://docs.privy.io/basics/swift/setup).
