# Provider Security Events

Pre-production extension of `trading_account.md` and `account_session_refresh.md`.
Receiving a provider notification is not an app account-deletion request and must
never delete wallet keys, change owner-address bindings, or submit transactions.

## Receiver Contract

- `POST /v1/auth/security-events/apple`: `application/json` containing only
  `payload`, an Apple-signed JWS. Successful durable processing returns 200.
- `POST /v1/auth/security-events/google`: `application/secevent+jwt` containing
  the raw signed Security Event Token (SET). Successful durable processing returns
  empty 202. Neither receiver uses app/installation bearer authentication; trust
  derives exclusively from a verified provider signature, issuer and app audience.
- Max request body 20 KiB, max compact JWT 16 KiB, no content compression. Reject
  duplicate JSON fields, malformed envelopes, untrusted key URLs/critical headers,
  unknown algorithms, invalid subjects and future timestamps. No token/body logs.
- Verify RS256 against fixed-origin, bounded public-key retrieval. For Google,
  first read the fixed RISC discovery document and require the configured issuer
  and approved Google JWKS URL; do not follow a URI supplied by the event itself.
  Google audience is one of this project's configured iOS/server client IDs;
  Apple audience is the configured primary app ID. No cross-provider email lookup.
- These are historical events, not ID tokens: do not require `nonce` or `exp`,
  and do not discard a correctly signed old event merely because it arrived late.
  Google's event timestamp is `iat`; Apple's is the signed `events.event_time`.
  Invalid input returns redacted 400; unsupported media 415; oversized body 413;
  key/database outages or disabled pre-production configuration return 503.
  Responses are no-store. Acknowledge only after the transaction commits.

## Effects

Apple `consent-revoked` revokes affected app sessions and prevents an older identity
assertion from creating another session. `account-deleted` additionally blocks
that provider identity; it does not erase the bSmart account or wallet. Email
forwarding events are acknowledged without changing financial access; bSmart does
not send provider-email messages through this receiver.

Google `sessions-revoked`, `tokens-revoked` and `account-credential-change-required`
revoke affected app sessions. `account-disabled` blocks new Google sign-in and
revokes all sessions for that provider identity. A strictly newer `account-enabled`
may lift Google's block, but cannot restore any session: fresh login is required.
Verification events store only a state hash. Individual `token-revoked` events do
not map to an app refresh credential: bSmart does not hold Google refresh tokens.
Unknown signed event types are recorded as ignored, never guessed into a wallet
or account action; monitor this outcome before adding subscriptions.

## Ordering and Persistence

Persist a provider/subject-hash security barrier even if the account does not yet
exist. Interactive issuance locks that barrier before the account/families; a
verified ID token at or before its revocation timestamp cannot create a session.
Store its provider-issued timestamp on new session families. Late revocation
affects families authenticated at/before the event, not a later interactive login.
Families lacking this timestamp are conservatively revoked. Disabled/deleted
identity events revoke all families. Renewal does not change authentication time.

Subject state is monotonic; equal-time conflicting block/enable events favor the
block. A stale enable cannot undo a newer block, and an enable cannot restore a
deleted Apple identity. Receipt de-duplication uses provider + hashed `jti` and a
semantic fingerprint, not raw JWT/email/provider tokens. Duplicate delivery has
no second effect. A conflicting reuse of a receipt ID is rejected. Receipt writes,
state barriers, session revocation and invalidated Apple grants are atomic.

Keep receipt hashes for 30 days; bounded maintenance removes old receipts without
removing subject barriers. A periodic retention job and deployment review are
required before enabling real streams. Subject state is security-only data, not
Smart Account, analytics or portfolio input. Account/privacy deletion and wallet
recovery require a separate verified workflow.

## Native Session Response

A 401 from the fixed account API during identity restoration, wallet registration,
binding challenge or binding submission clears that exact app credential, cancels
pending renewal and invalidates its funding signing lease. No wallet-vault method
is invoked. Keychain cleanup failure still removes in-memory access and reports a
storage error. Network outages are not treated as provider revocation and do not
erase saved credentials. A response for a replaced access token cannot clear the
new login or invalidate its new lease, even for the same account. After learning
of revocation, a late renewal cannot restore credentials.

This is response-driven, not an iOS push revocation guarantee. Foreground restore
rechecks the backend; an offline device cannot learn a server event instantly.
Invalidating a local signing lease cannot reverse an already submitted transaction.

## Apple Native Credential State

The system authorization result's opaque `user` identifier is local-only metadata.
After backend verification, persist it atomically with that account's app session
in the device-only Keychain envelope. Never send it as a new backend identity
claim, derive wallet keys from it, put it in diagnostics, or infer it from email.
Renewal carries it only from the exact pending session of the same account. Fresh
Google sign-in and logout remove the Apple reference. The version-3 envelope uses
lossless numeric dates inside Keychain only; HTTP date encoding is unchanged.
Reference matching compares account and access/refresh credentials, not serialized
timestamp precision. Version-2/legacy records
remain readable; an Apple session without the reference requires fresh native
sign-in before use, not a fabricated identifier.

The native default queries `ASAuthorizationAppleIDProvider.getCredentialState` on
restore/sign-in and when its at-most-60-second authorization check expires. Wallet
operations require a current check; signing leases cannot outlive it. Foreground
maintenance runs every 30 seconds. System revocation notifications are delivered
to the main actor before invalidating cached checks/leases and starting a recheck.
No background or instantaneous system delivery guarantee is implied.
Only an error-free `.authorized` result permits access. Error-free `.revoked`,
`.notFound` or `.transferred` requires fresh login, clears app credentials, and
attempts to revoke that app family; never relink a transferred identity or erase
the wallet. An error (even alongside `.notFound`), unknown state or 10-second
timeout blocks wallet access without deleting saved credentials. Cancellation
and late callbacks cannot restore authorization. Remote cleanup is best-effort;
server security events and expiry remain necessary for other-device coverage.

Authorization checks and signing leases require both an unexpired wall-clock
deadline and an unexpired `ContinuousClock` deadline. The latter advances through
sleep and is never serialized or restored. A lease issued near the end of a native
check inherits its original deadline; app renewal cannot reset it. A stopped or
adjusted wall clock cannot extend cached authorization. A wall-clock rollback
before the check requires a new system lookup. All leases also retain their own
60-second maximum and background/protected-data revocation guards.

## Release Gates

Product-account deletion uses the separate `deletion_pending` barrier described
in `account_deletion.md`. Signed provider enable events cannot clear it or restore
the revoked app sessions. Accepted Apple deletions retain an encrypted revocation
snapshot even if a notification removes the normal sign-in grant. Final deletion
preserves provider security state and its revocation time, not plaintext identity
or wallet associations. Native confirmation/recovery and Google disconnect still
require integration; the server operation is not the completed app workflow.

No external stream registration, provider credentials, production DDL or funds in
this implementation phase. Operators must configure the primary Apple app endpoint
and register the Google RISC stream/verification using their own project. RISC is
not available for Google Workspace users and delivery can be permanently missed.
Stream monitoring, outage handling, consent/retention review, real-provider
verification of the implemented native Apple checks, native account deletion, production
database contention and physical-device tests remain required. Notifications alone
are not a claim of instantaneous or complete revocation coverage.

## Primary Sources

- [Apple: account changes](https://developer.apple.com/documentation/signinwithapple/processing-changes-for-sign-in-with-apple-accounts)
- [Apple: notification configuration](https://developer.apple.com/help/account/capabilities/enabling-server-to-server-notifications)
- [Apple: native credential state](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider/getcredentialstate(foruserid:completion:))
- [Apple: continuous clock](https://developer.apple.com/documentation/swift/continuousclock)
- [Google: Cross-Account Protection](https://developers.google.com/identity/protocols/risc)
- [Google: live discovery](https://accounts.google.com/.well-known/risc-configuration)
- [RFC 8935: push SET delivery](https://www.rfc-editor.org/rfc/rfc8935.html)

Checked 2026-09-11; product durations and state policy are bSmart decisions.
