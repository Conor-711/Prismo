# Trading account identity

**Legacy compatibility only (2026-09-12):** current iOS login and wallet binding
use Supabase directly. Do not deploy this service or apply the migrations below
just to enable iOS Google/Apple login. Current setup is documented in
`supabase/ios-account/README.md`; this module remains for existing compatibility
tests and legacy clients, not as a required fallback.

Pre-production only. `BSMART_ACCOUNT_AUTH_DEVELOPMENT=1` enables configured
providers in development/test, never production. This module cannot receive funds
or sign transactions. Complete the release gates in
`docs/product/arbitrum-usdc-funding.md` before enabling production.

Operator setup (no migration has been applied):

1. Review `migration.sql`, `wallet_migration.sql`, `apple_grant_migration.sql`, then
   `session_renewal_migration.sql`, `security_event_migration.sql`, then
   `deletion_migration.sql`. The renewal migration requires the account and
   Apple exchange tables; it invalidates only unfinished Apple exchanges rather
   than guessing their installations. Apply only to the Client API state database,
   never content `data/dev.db`, with auth traffic paused and a verified backup.
   The account repository performs no runtime DDL. Existing access-only sessions
   expire normally; clients receive renewal credentials on their next sign-in.
   The security-event migration invalidates unfinished Apple exchanges and leaves
   legacy authentication timestamps NULL; affecting notifications conservatively
   revoke those families rather than inventing a provider authentication time.
2. Provide `BSMART_APPLE_CLIENT_ID` (iOS bundle ID),
   `BSMART_GOOGLE_SERVER_CLIENT_ID` and `BSMART_GOOGLE_IOS_CLIENT_ID`. Apple also
   requires `BSMART_APPLE_TEAM_ID`, `BSMART_APPLE_KEY_ID`,
   `BSMART_APPLE_PRIVATE_KEY_FILE` and `BSMART_ACCOUNT_CREDENTIAL_KEY_FILE` as
   described below. An Apple client ID alone does not enable that provider.
3. On iOS set matching `BSMART_GOOGLE_*` build settings and
   `BSMART_GOOGLE_REVERSED_CLIENT_ID`; add Apple Sign In entitlement to an approved
   profile before setting `BSMART_APPLE_SIGN_IN_ENABLED=YES`. Client IDs are public
   configuration; Apple signing/revocation private keys must stay on the backend.
4. Use HTTPS, including development OAuth exchange. Plain HTTP research API
   configuration is deliberately rejected by the account transport.
5. Apply ingress body-size limits and IP/installation rate limits. The five-live-
   challenge cap and JWKS cooldown are defense-in-depth, not complete public abuse
   controls. Never log auth bodies or authorization headers.

Access sessions expire in 30 minutes. Installation-bound app refresh credentials
rotate on each use, with 24-hour idle and seven-day absolute family limits.
See `docs/contracts/account_session_refresh.md` for HTTP and failure behavior.
Product-session tokens, nonces and internal exchange capabilities are stored as
hashes; Apple refresh credentials are stored separately as authenticated ciphertext.
Identity is provider + subject, not email. Transactional consumption prevents
challenge replay. Signed notification receivers are implemented below, but real
provider delivery and device/expired-ticket deletion recovery remain unverified/incomplete;
production login, deposits and trading stay disabled.

Tests use generated keys and disposable databases, not provider logins or funds.

## Supabase Google integration (2026-09-12)

The configured bSmart project is `dzyitinagewdfkzjkuiz`; its public Auth settings
confirmed Google enabled and Apple disabled. Native Google client IDs and the
reversed iOS callback scheme are in `ios/project.yml`. Configuration supplied by
the operator is saved in ignored `services/client_api/.env`; no service-role key,
Google client secret or Supabase admin credential is needed by this adapter.
`supabase.env.example` lists the environment variables without live key values.

`BSMART_SUPABASE_URL` + `BSMART_SUPABASE_PUBLISHABLE_KEY` select Supabase admission.
Partial/invalid configuration disables providers, never falls back to legacy auth.
The existing development/test gate remains required. Do not change production
data mode to fixture or disable HTTPS just to get a login button to appear.

`providerNonce` in the challenge is SHA-256 hex of the raw nonce. iOS supplies the
hash to Google and the original nonce to `/sessions`. The server checks raw nonce
against the installation-bound challenge, verifies Google's signature and native
audience/authorized party, then requires successful Supabase ID-token admission
with the same Google identity. Fixed HTTPS origin, no inherited auth/cookies,
no redirects/retries, bounded response and redacted failures apply. Never enable
"Skip nonce checks" in Supabase. Older clients cannot complete the new challenge.

This is identity-provider delegation, not a wallet/account migration. Existing
provider+subject account UUIDs and immutable wallet bindings are retained. Supabase
access/refresh tokens are discarded; existing bSmart session rotation/logout stays
unchanged. Linking Google/Apple via email is not implemented. Supabase account
deletion/ban propagation to existing bSmart sessions is not implemented; the
deletion-acceptance route refuses new requests in this mode rather than reporting
success while leaving a Supabase user behind. Keep production auth/funds disabled
until those lifecycle decisions and actual provider/device tests are complete.

### Deployment handoff

- The internal endpoint `https://api.158-247-196-93.sslip.io/v1/auth/configuration`
  returned 404 on September 11. Local code/configuration does not update that server.
- SSH with the existing dedicated Vultr key was rejected. No server files, auth
  settings, live database, funds or real accounts were changed during this work.
- Operator must first grant working SSH access, review/apply the existing account
  migrations to the **state** database, and deploy the updated Client API with the
  Supabase environment variables. No new schema is introduced by this adapter.
- For an already migrated development API, load the ignored file explicitly with
  uvicorn `--env-file services/client_api/.env`. Do not run it against `data/dev.db`.
- Verify configuration reports Google, then perform a real Google login in the
  rebuilt app. Confirm the Supabase user and stable bSmart account/wallet identity;
  repeat login/logout before evaluating any deposit/market-order/withdrawal gates.

Offline verification: the final auth test selection passed 95 Python tests.
Full Client API suite: 287 passed, 14 failures in changed content fixtures/digest/
notifications/AI expectations; no authentication tests failed. iOS build succeeds;
native nonce/transport, account and revocation tests pass. The initial unsigned
simulator run hit Keychain storage failures; rerunning with an ad-hoc signed
simulator host passed all 42 selected tests, including Apple credential persistence.
Real Google sign-in remains unverified.

## App session renewal

`session_renewal` issues and rotates opaque token pairs transactionally. Only token
hashes are persisted; Apple provider refresh tokens are a different encrypted
credential. Refresh and family logout require the original installation bearer,
not an account bearer. A consumed-token replay commits revocation before returning
401. A mismatched installation cannot revoke someone else's family. A fresh login
replaces that account's prior families on the same installation, not other devices.

Account creation serializes same-account sign-ins; family revocation locks before
deleting access rows. Rotation/logout share family locks, including a SQLite
no-op write. Production PostgreSQL contention, deadlock/recovery and retention
must still be exercised before release. Do not delete consumed credential rows
while their family can be active; expired-family cleanup is an operational gate,
not implemented as an automatic startup task.

iOS writes a pending-renewal Keychain envelope before I/O, shares concurrent
requests and never automatically retries an uncertain response. Restart after an
unfinished attempt requires interactive login and best-effort family revocation.
Logout accepts an old/expired family credential; neither logout nor pending-state
cleanup erases wallet keys or funding history. Restoring/renewing identity blocks
funding signing, and renewal invalidates prior signing leases. A renewal does not
check fresh provider consent; revocation propagation is still a release gate.

## Provider security events

`security_event_routes`, `security_event_verifier` and `security_event_repository`
receive Apple JSON/JWS and Google's raw `application/secevent+jwt` SET. No bearer
authorizes these requests. Verify the provider signature, audience, issuer and
event shape before touching session state. Google discovery and both providers'
JWKS use bounded, credential-free `provider_http` requests to fixed origins.

The receipt, subject barrier, family revocation and invalidated Apple grant removal
commit together before acknowledgement. Unknown signed events are recorded as
ignored. Subject state and hashed receipts are security-only data; never publish
them to analytics or Smart Account pipelines. The per-family `authenticated_at`
comes from the verified provider ID token, not session renewal time. A stale
notification cannot revoke a newer login; disabled/deleted identities cannot
continue using any family or create a new one. Wallet registration is preserved.

Before release, register the Apple primary-app endpoint and Google RISC stream
in the operator's own projects. Verify their real delivery and state checks; neither
the local test endpoint nor a generated test signature proves this. RISC can miss
events and does not cover Google Workspace users. Monitor delivery failures and
ignored `kind` values without logging token bodies or subjects. Use the stored
verification-state hash for controlled stream verification, not a public lookup.
Ingress size/rate limits and per-worker JWKS cooldown remain required.

Receipt cleanup removes at most 1000 rows older than 30 days per new delivery or
`SecurityEventRepository.prune_receipts()` call. Operators must schedule bounded
periodic cleanup even when no notifications arrive; automatic startup maintenance
is not provided. Subject barriers are retained separately, pending the verified
account/privacy-deletion workflow. Review backup retention and Google security-only
data-use terms. Verification of native Apple checks and outbound revocation against
real providers, native account deletion, production PostgreSQL contention and physical-device validation
remain release gates. Full HTTP/order policy: `docs/contracts/account_security_events.md`.

The iOS client now queries native Apple credential state on restore and before
wallet access when its 60-second check expires. SDK errors or a 10-second timeout
block wallet use without deleting stored app credentials. Explicit revocation
clears the current app session and attempts family logout; server events remain
necessary for other devices. The native opaque user reference lives only inside
the device's version-3 Keychain session record. It is not an API identity field or
a wallet-key input. Renewal preserves the reference but never extends the native
check's original wall/continuous-time deadline. No backend schema change is needed
for this local record upgrade; legacy Apple records require fresh native login.

## Account deletion and provider disconnect

`deletion_routes/repository/work/service` implements durable acceptance, leased
provider revocation and transactional personal-data erasure. A live account bearer
alone is insufficient: its original provider authentication must be within five
minutes, and both deletion and wallet-recovery acknowledgements must be true.
Rotation does not refresh that authentication time. Native recovery verification
and the exit/export path must precede this command; neither boolean proves backup.

The client creates and securely persists a UUID and status secret before sending.
Acceptance stores only its hash and installation binding, sets a distinct
`deletion_pending` subject barrier and revokes every session/proof for the account.
The separate status endpoint uses installation bearer plus the saved secret, not
the revoked account session. A lost response is queried, never replayed as a new
deletion request. No bodies, tickets, provider subjects or exception SQL in logs.
Full HTTP semantics: `docs/contracts/account_deletion.md`.

Apple work keeps a copy of the context-bound encrypted refresh grant until the
fixed `/auth/revoke` endpoint confirms 200 with an empty body. A security event may
remove the normal sign-in grant without losing this pending revocation material.
Timeouts, corrupt ciphertext and persistence failures leave work pending with
backoff. Leases expire after 60 seconds, and a superseded worker cannot finalize.
The final transaction erases the identity, credentials, wallet binding and
installed opinion-profile/fill associations. Late profile/fill writes serialize
against deletion and cannot resurrect them. Provider security barriers remain;
completed receipts remove account/grant references and expire after 30 days.

For development/test explicitly enable `BSMART_ACCOUNT_DELETION_WORKER=1` alongside
account auth. The application-lifecycle worker processes up to 10 due requests per
pass, sleeps 30 seconds and prunes up to 1000 expired receipts. It needs an
operator-migrated state database; it does not create tables. Cancellation leaves
leases recoverable, and multiple processes share them. Production cannot be enabled
with this flag. Worker health/pending-age alerts, PostgreSQL concurrency and backup/
retention review must be verified before production acceptance can be offered.

Google has no server-held provider refresh token here. Its matching native SDK
identity must use `disconnect`, not sign-out followed by disconnect. This step,
native confirmation/persistent ticket coordination and scoped cleanup are connected
in pre-production. Native completion requires server receipt, profile erasure and
matching SDK disconnect, not only backend completion. Deletion reauthentication
uses optional `/sessions.expectedAccountId`: verified provider/subject must already
belong to that account, with no insertion. Missing/mismatched/deletion-pending
identities receive the same 401. Ordinary sign-in omits this field; old servers
reject the new field rather than silently creating another account. No wallet
entropy, recovery material, funding journal or on-chain assets are erased by this
server operation. A later fresh login creates a new account, never implicitly
reassigning a device wallet to it.

## Apple native code exchange

iOS sends both the native ID token and the single-use authorization code. Older
Apple clients that send only `idToken` now receive a redacted 422 and must update;
Google's ID-token request is unchanged and must omit `authorizationCode`, including
null. There is no fallback that issues an Apple session using only an ID token.

`apple_oauth` posts once to Apple's fixed HTTPS token endpoint, using a five-minute
ES256 client secret. It does not inherit HTTP credentials/cookies or follow redirects.
`apple_repository` consumes the installation-bound challenge before that request;
the exchanged ID token must independently pass issuer/audience/nonce/subject checks.
The account session is published only after encrypted grant persistence commits.
Timeouts and lost responses require a new challenge and new native authorization;
do not retry the consumed code. Failed persistence leaves prior sessions, grants
and wallet mappings unchanged. No code, provider ID token or provider access token
is written to the database. The provider refresh token never returns to iOS.

The Apple `.p8` signing key and the grant keyring must be absolute paths to regular,
non-symlink files, owned by the service UID, with no group/other permissions (for
example 0600). Mount them outside the repo, content database and app bundle.
The `.p8` must be a P-256 private key. The keyring is a JSON object containing only
`active` (a key ID) and `keys` (1-8 key ID to base64-encoded 32-byte key entries).
Key IDs contain 1-32 ASCII letters, digits, `_` or `-`; `active` must exist in `keys`.
Operators generate and provision these independent random encryption keys through
their secret-management system. No actual keys or sample usable credentials are
provided here. Invalid files disable Apple sign-in without exposing their contents.

`credential_cipher` uses AES-256-GCM with a fresh 12-byte nonce, authenticating the
account ID, Apple subject, client ID and key ID. Keep retired decryption keys for
every live ciphertext and retained encrypted database backup. A new active key
only changes future writes; bulk re-encryption, rotation/restore exercises and
real-provider/native deletion acceptance are still outstanding release gates. These are
provider credentials, not wallet private keys; user wallet keys stay on-device.

Reference: Apple's [native authentication flow](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple)
and [token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens).

## Device wallet binding

`wallet_routes`, `wallet_repository`, `wallet_proof` verify only the fixed EIP-191
binding message documented in `docs/contracts/trading_account.md`. The pinned
`eth-account==0.14.0` dependency recovers signatures; the backend never creates,
imports, stores or exports user private keys. There is no generic signing API.
Signature challenges contain public random nonces and expire in five minutes.
They are account-session-bound and atomically consumed; account/address uniqueness
is enforced by database constraints. Existing mappings cannot be replaced.

Revoked sessions cannot submit wallet proofs. GET resolves uncertain bind results;
do not treat outages as an unbound account. Auth request bodies, signature proofs
and authorization headers must remain excluded from logs and telemetry. Client
input containing mnemonic/private-key fields is rejected with a redacted 422.
Production stays disabled, including wallet endpoints, until all release gates
are satisfied. Neither address registration nor a local backup flag enables funds.
