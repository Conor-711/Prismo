# Account Session Renewal

Pre-production extension of `trading_account.md`. These are bSmart credentials,
not Apple/Google tokens or wallet keys. Production gates remain closed until
provider revocation/deletion, operational abuse controls and real-device review.

## Contract

New sign-ins return `refreshToken` and `refreshExpiresAt` alongside the existing
account/accessToken/expiresAt. The access token lasts at most 30 minutes. Each
sign-in creates one installation-bound family, with seven-day absolute lifetime;
refresh credentials expire after 24 hours idle, clipped to that absolute limit.
These durations are product policy, not guarantees made by either provider.
Fresh interactive login replaces prior families for that same account and
installation, under an account lock; other installations stay signed in.

`POST /v1/auth/sessions/refresh` uses installation bearer plus a JSON body containing
only `refreshToken`. It atomically consumes the token and returns a new access/
refresh pair for the same account and installation. The prior access token becomes
invalid. Rotations are limited to one per minute per family (429, without consuming
an unused token); iOS normally renews within one minute of access expiry.

`POST /v1/auth/sessions/revoke` uses the same installation bearer/body. It revokes
the entire family, including an already rotated or expired supplied token. Unknown
tokens or tokens from another installation return the same no-store 204 without
altering other accounts. This enables logout after access expiry or an uncertain
rotation. It never revokes Apple/Google consent or changes/deletes a wallet.
The native client accepts logout only on the exact 204 contract response, not an
arbitrary 2xx body, and retains credentials when explicit logout fails.

Reusing a consumed refresh token with its bound installation commits revocation
of the whole family and all its access tokens before returning 401. The response
does not identify whether expiry, replay or another verification failed. Supplying
the token with a different installation must NOT revoke the legitimate family.
Fresh interactive sign-ins and other device families are unaffected.

## Storage and Concurrency

Server storage contains only random-token SHA-256 hashes, family/installation/
account associations and timestamps. Retain consumed token hashes until family
expiry to detect replay. Issuance and rotation are transactions. A failed write
must not consume the old token, publish a replacement, or change wallet bindings.
Logout serializes with refresh so no descendant can survive family revocation.
Interactive login locks/revokes prior families before deleting their access rows.
No runtime schema migration, token logging, credential URLs or response caching.

iOS keeps the pair in the existing device-only Keychain session item. Coalesce
concurrent renewals; never retry a consumed/uncertain refresh request automatically.
Record an in-progress renewal before network I/O so process death or a lost response
requires fresh interactive login, not a replay of the old credential. Clearing
session state must not clear wallet entropy, backups or funding history. This
coordinator covers the single app process; a future extension sharing this item
requires interprocess coordination before it can renew sessions. Legacy
sessions without refresh credentials remain usable only until their access expiry.

Version 3 carries an optional local-only Apple user reference in the same Keychain
write. Only completion of the exact pending pair can carry it into renewal; a fresh
sign-in never inherits it implicitly. Numeric Keychain dates preserve precision,
with old ISO dates still readable. HTTP encoding and backend identity claims are
unchanged. An Apple legacy record without its native user reference requires fresh
sign-in before wallet use. See `account_security_events.md` for native checks,
including the original continuous-clock deadline that renewal must not extend.

Renewal invalidates outstanding funding signing leases. A new login session does
not prove wallet control, extend a previously consented transfer, or establish that
funds are available. Provider revocation propagation is a separate production gate;
an app-session rotation is NOT a fresh Apple/Google authentication.

`account_security_events.md` defines signed provider notifications, per-family
authentication timestamps and native handling of rejected account requests.
Renewal preserves the original provider authentication time; it cannot move a
family past a security-event revocation barrier.

`account_deletion.md` is a separate irreversible product-account workflow, not
family logout. It requires provider authentication within five minutes, accepts a
pre-persisted status ticket and immediately revokes all families. Refresh cannot
extend this freshness window or reopen a pending deletion. Neither workflow
deletes device wallet material; deletion status grants no account/signing access.

Security basis: [RFC 9700, refresh token protection](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14)
recommends rotation or sender constraints and replay detection. Installation bearer
binding is defense in depth, not a claim to implement DPoP/device attestation.
