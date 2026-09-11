# Native Supabase Accounts

## Authentication

- Google login was accepted by the user on 2026-09-12. Login still does not
  require wallet preparation or a research API. Apple remains disabled.
  After login, Continue opens the separate trading-wallet destination.
- Native Google SDK / AuthenticationServices obtain an ID token using SHA-256
  of a cryptographically random, one-use, five-minute nonce.
- iOS posts `{provider, id_token, nonce}` (original nonce) to Supabase
  `/auth/v1/token?grant_type=id_token`. No research API or installation token.
- Supabase verifies the provider assertion. iOS verifies the returned user via
  `/auth/v1/user`, including its provider identity against the native subject.
- Sessions use a project-specific device-only Keychain namespace, separate from
  legacy account sessions. Supabase access JWTs and opaque refresh tokens are
  not private keys. Refresh is coalesced; interrupted rotation requires sign-in.
- The local refresh restoration limit is 30 days since the last successful
  exchange, not a claim about Supabase's server-side session lifetime.
- Logout revokes this Supabase session when online, clears local access even if
  offline, locks the wallet, and never deletes its keys or another device session.

## Wallet Registry

Base URL: `<project>/functions/v1/bsmart-wallet`. All requests require a verified
Supabase user bearer plus the public publishable key. Never accept `accountId`
from request input as authentication. Responses are JSON, no-store.

| Method | Path | Input | Response |
| --- | --- | --- | --- |
| GET | `/` | none | `{accountId, address: string or null}` |
| POST | `/challenges` | `{address}` | `{id, accountId, address, nonce, issuedAt, expiresAt}` |
| PUT | `/` | `{challengeId, signature}` | `{accountId, address}` |

Successful registry GET/PUT additionally returns optional `capabilities` with
`depositsEnabled`, `tradingEnabled`, and `withdrawalsEnabled`. All default false;
missing capabilities never grant access. They are controlled independently by
Edge Function environment flags `BSMART_DEPOSITS_ENABLED`,
`BSMART_TRADING_ENABLED`, and `BSMART_WITHDRAWALS_ENABLED` (exact value `true`).
Only a bound wallet receives enabled flags. iOS applies them only to the current
verified Supabase account, rechecks registration before signing/submitting, and
clears flags on logout or failed wallet verification. They do not replace local wallet
policy, device authentication, collateral checks or user consent. Orders omit builder fees.

Only a successful registry read may return null. Missing function/table is an
error, never permission to replace a wallet. Addresses are nonzero lowercase
20-byte Ethereum addresses. The existing `TradingWalletChallenge.message` v1
format is retained exactly; its audience is a domain-separation string, not a
network request to the legacy API. EIP-191 verification uses viem.

Challenges expire after five minutes and bind account, address and SHA-256 of the
verified access token. One pending challenge per account; one successful consume.
The database commits consume and registration atomically. Registrations are
immutable and unique by account and address. Clients cannot insert/update/delete
them; RLS permits reading only one's own public address. Only the Edge Function
service role calls the challenge/commit RPCs after authenticated proof validation.

Supabase stores no mnemonic, private key, signing transaction or provider token.
Device-only Keychain protection and explicit transfer/order confirmation remain
unchanged. Internal build 1.0(6) makes backup optional through a build-time policy,
without changing the stored verification flag or enabling Google key recovery.
Signing is not performed by the Edge Function. See `native_perpetual_mvp.md`.

Legacy account IDs are not silently mapped to Supabase IDs; existing keys stay
untouched. A new account is not a recovered old wallet. Existing funded users must
retain their original recovery phrase and complete an explicit migration before
using a newly created address. Never infer identity from matching email/name.

## Release Boundary

Google provider configuration is an operator action. Apple is postponed.
`supabase/ios-account/supabase/migrations` and the Edge Function must be deployed to the
new bSmart auth project, not the legacy content project. No startup DDL. Remote
account deletion is not part of this basic implementation and must be completed
before public App Store release. Production funding/trading gates remain closed
pending real-device and funded-flow acceptance, independent of login readiness.
