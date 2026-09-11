# Account Deletion

Pre-production, separate from logout and provider security notifications. Production
auth/funding gates remain closed. Never delete device wallet entropy or sign a
transaction as part of account deletion.

## Request and Recovery

`POST /v1/auth/account/deletions` requires an account bearer with a live session
family authenticated interactively within five minutes. Rotation does not refresh
that timestamp. The body contains `id` (client-generated UUID), `statusToken`
(client-generated 32-256 ASCII URL-safe characters), `confirmDeletion: true` and
`walletRecoveryConfirmed: true`. Confirmation is deliberate acknowledgement, not
cryptographic proof of backup. The native workflow checks the linked wallet, offers
local recovery export when available and requires explicit acknowledgement of
permanent deletion and possible wallet-access loss. Never create a wallet merely
to delete an account or require restoration on a new device as a deletion barrier.
Never require a user to send a
private key or mnemonic to the server.

Persist the request and status secret securely on-device before sending. An accepted
request immediately revokes all account sessions and blocks new sign-in. It returns
202, including when processing has already completed. Responses contain `id`,
`status` (`pending` or `completed`), `requestedAt`, `completedAt` (nullable) and
`retryAfterSeconds` (30-3600 while pending, zero when complete). No bearer is returned.

`POST /v1/auth/account/deletions/{id}/status` uses installation bearer plus a body
containing only `statusToken`. It remains usable after the account session is
revoked. It can resume accepted work after its backoff/lease expires. A missing,
expired or mismatched ticket/installation returns the same 404. The secret grants
status access only, never login or wallet access. A lost initial response is queried
with the pre-persisted ticket, not retried as a new deletion command. All responses
are no-store; credentials must never appear in logs, URLs or validation errors.

Native deletion reauthentication sends `expectedAccountId` with the provider
assertion to `/sessions`. Issuance matches the existing provider/subject/account
under the normal transaction lock; it never creates a new account when the original
has disappeared. Wrong/missing/pending accounts fail without identity disclosure.
Normal sign-in omits this field. A fresh temporary session is never installed as
the normal app session and is revoked after the deletion attempt. Reauthentication
invalidates the old local funding permission and session.

An explicitly confirmed retry of an unacknowledged (`submitted`) request must
reauthenticate the original existing account, query the original ticket first,
then only on a 404 resend that same UUID/secret. There is no automatic command
retry, no new ticket, and no inference that a 404 means deletion succeeded.

## Transaction and Provider Boundaries

Acceptance locks the provider-subject barrier before the account and session
families, persists the request, takes a snapshot of the encrypted Apple grant,
then revokes sessions and pending wallet/Apple proofs atomically. Without a usable
matching Apple grant, require fresh native sign-in; do not pretend consent was
revoked. Google has no server-held provider refresh grant in this architecture.

Work uses a durable, bounded lease. Apple refresh-token revocation goes only to
Apple's fixed HTTPS endpoint, without inherited credentials or redirects; only its
documented 200 with an empty body is confirmation. An already invalidated token
also returns this response, allowing recovery after an uncertain result. Errors
leave the request pending with bounded backoff, not falsely completed. A crashed or
superseded worker cannot finalize another lease. No database lock spans network I/O.

After provider revocation, remove app sessions/renewal families, identity, encrypted
grants, wallet binding/proofs and installed opinion-trader profile/fill associations
in one transaction. Each domain owns its cleanup. No private keys exist in this
database. The public blockchain and assets are unchanged. The Google native SDK
must separately disconnect the *matching* Google identity; server completion alone
does not assert that this client-side consent step succeeded.

Profile/fill writers require the owning account row and serialize with deletion;
they reject pending/deleted accounts rather than recreating erased associations.
Read-only fixtures are separate from this authenticated write boundary.

The optional `BSMART_ACCOUNT_DELETION_WORKER=1` process-lifecycle worker checks up to
10 due requests per pass, then sleeps 30 seconds. It also removes up to 1000 expired
completed receipts. It starts only with explicitly enabled development/test account
auth; production cannot activate it merely by setting this flag. Multiple processes
share durable leases. Shutdown cancels the task without marking unfinished work as
complete, and the next process can reclaim expired leases. Database failures log
only a fixed redacted message and retry; operators must monitor worker health and
pending age. No schema is created by startup or worker processing.

The subject barrier retains its existing security-only hash and a revocation time,
not the plaintext provider subject or wallet address. A completed request removes
its account/provider/grant references; a status receipt is retained for 30 days.
Fresh interactive login after completion creates a new product account. It must
not silently attach an old device wallet; recovery must prove its address anew.
Retained provider security barriers are subject to the existing security/retention
review and do not feed analytics. Guest installation data is not silently deleted
because it may belong to other local identities.

## Release Gates

### Native durable workflow

The native pending request is a separate, device-only Keychain item, scoped to the
exact account and configured account API endpoint. It contains no access/refresh
session, mnemonic or signing payload. A random 32-byte status secret and request
UUID are written before transmission. The stages are `prepared`, `submitted`,
`accepted`, `serverCompleted`, and `completed`. Only a prepared (never submitted)
request or an acknowledged completed record may be removed. A corrupt/unreadable
record is an error, never an empty state or permission to start again.

Submission is recorded before HTTP; a crash at that boundary is intentionally
uncertain. Recovery queries the same ticket, never automatically submits another
command. A 404 is not proof that a request was never accepted or that deletion
completed. Server completion is persisted before local account-data cleanup and
independent Google disconnect; those steps must be idempotent and retryable. Local
profiles are erased even when Google disconnect remains unavailable. A minimal
account-UUID tombstone blocks stale profile editors from recreating the file; it
is not an identity credential or analytics input. Wallet keys/funding logs and
other accounts/guest research preferences are not removed.
An accepted/completed receipt cannot regress to an earlier stage, change its request time,
or switch to another UUID. Caller cancellation may stop presentation but cannot
discard durable evidence already received. No in-memory callback or saved ticket
authorizes funds, wallet deletion or a fresh account session.

The native `AccountDeletionClient` now implements the typed HTTPS requests using
the existing credential-isolated transport. It requires exact 202 acceptance or
200 status, validates all five receipt fields and pending/completed chronology,
matches the request UUID and rejects unknown fields, oversized responses and
unexpected origins. Confirmation, reauthentication and missing-ticket errors are
distinct; malformed responses never become a completed state. Request secrets are
redacted from diagnostics and travel only in JSON bodies. It does not retry or
alter account/wallet state by itself. `AccountDeletionCoordinator` owns those state
changes; the view is available within the gated account flow. The Google user
reference stays local and out of HTTP bodies. Its shared operation gate stays
locked after timeout/cancellation until the real SDK callback. Reconfirmation
after restart explicitly selects the original Google user without creating a
backend account. Only SDK success is persisted as disconnected, never a timeout
or missing currentUser. Local records use WhenUnlockedThisDeviceOnly, no Keychain
synchronization, bounded size, monotonic transitions and redacted diagnostics.
Corrupt/unreadable records cannot be overwritten as a new request.

Operator-reviewed migration only; no startup DDL. Native coordination, Google
disconnect and scoped cleanup are implemented with test doubles; real provider/
device tests, worker monitoring, production database contention, backup and
financial/legal retention review, and independent security review remain required.
Expired/lost status secrets still need a separately authenticated resolution path:
after server receipt expiry, never discard the journal or treat 404 as completion.
Also validate Apple grant-exchange/deletion races against real provider revocation
semantics. Do not describe this lifecycle as production-delivered until these gates
are connected and verified.

## Sources

- [Apple: account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Apple: token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens)
- [Apple: deletion and tokens](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
- [Google: disconnect on iOS](https://developers.google.com/identity/sign-in/ios/disconnect)

Checked 2026-09-11. Ticket retention, backoff and freshness are bSmart policies.
