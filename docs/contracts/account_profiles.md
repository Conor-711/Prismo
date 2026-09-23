# Platform Account Profiles

Supabase Auth identifies the account. The iOS account project's historical
`bsmart_feed_profiles` table is the single canonical public profile, not a second
Feed identity. Migration `202609120005_account_profiles.sql` preserves public IDs,
nicknames, avatars and consent, adds a unique handle, bio and optimistic revision,
and provisions profiles on signup/backfills existing accounts. Apply manually.

- `username` maps to the existing `nickname` column: 1-28 Unicode code points,
  trimmed; duplicates allowed.
- `handle`: 3-24 lowercase ASCII letters/digits/underscores, starts with a letter;
  unique across accounts, normalized by the service. Initial values are random,
  unrelated to auth IDs. Users may edit them.
- `bio`: 0-120 Unicode code points. Only the owner profile uses this field.
- `avatarURL`: Google provider image or a short-lived URL for a private uploaded
  JPEG. The client never supplies arbitrary remote URLs. Uploaded images are
  bounded and re-encoded; old objects are queued for service-side removal.
- `id` is the existing public UUID, never the auth ID or wallet address.

`bsmart-profile` GET/PUT requires a verified Google/Apple Supabase session.
PUT accepts username, handle, bio, revision and an explicit avatar action
(keep/remove/provider/upload). Stale revisions and taken handles return distinct
409 errors. Profile editing does not change identity/amount sharing consent.

Feed and opinion traders show avatar, username and @handle from the current
profile, not a trade-time snapshot. They do not expose bio, auth metadata, email,
or wallet address. Privacy filters and unique-person/direction totals are unchanged.
The old Feed sharing request remains accepted but no longer edits identity fields.

Signed-in iOS uses cloud profiles. Guest profiles remain local. Importing an old
device profile is explicit and limited to the matching signed-in account. A failed
cloud fetch must not silently replace or overwrite cloud data with local values.
No profile operation signs or submits a trade.

## First sign-in setup

`AppSessionGate` hosts `TradingAccountView` as the root Google sign-in entry.
After authentication, load the canonical profile before mounting formal content.
The in-app account page reuses the same editor and profile requirements. Revision zero identifies an
auto-provisioned profile that has not been saved by its owner. Present the shared
profile editor full-screen for nickname, unique username and avatar selection;
require an explicit username rather than accepting the generated handle. The
existing PUT advances revision and completes setup across devices. A provider
photo or uploaded photo is optional; initials remain the fallback.

Failed loading/saving keeps Retry available and does not mark setup complete.
Sign out is available from setup. Saving checks the original session revision,
and switching accounts must dismiss the previous setup. Existing profiles with
positive revision proceed normally. No new migration or wallet mutation is used.

The root presents required setup inline rather than as a dismissible overlay.
Only a successful canonical profile save unlocks the content tree. Signing out
removes setup/content, including nested sheets and navigation.
