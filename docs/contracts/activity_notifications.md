# Application Activity Inbox

## Scope

Native in-app inbox, opened by the home bell. Settings remain in Profile.
No new endpoint, database migration, APNs registration, or background delivery is introduced.

## Projection

- Sources: current Smart Account updates, already loaded author evidence, and Smart Money movements.
- Match tracked account IDs (case insensitive), with same-platform legacy handle fallback for Smart Account.
- Match declared holdings (`heldPositions`, excluding watchlist) and actual nonzero perpetual positions fetched using the current account's registered public wallet address.
- Never create/unlock a wallet or sign to read positions. Test login has no live-wallet privileges.
- Keep each distinct event, not only the latest event per investor. Stable IDs are source-prefixed UUIDs.
- An event matching both tracking and holdings is one notification with both reasons.
- Newest timestamp first, stable ID tie-break; last 30 days inclusive, reject future timestamps; at most 200 events.
- This is a projection of available research data, not a complete server-side notification history. Content refreshes through existing application refresh and inbox pull-to-refresh. Partial/failed holdings reads surface an error and retain the current account's last in-memory holding matches until a successful refresh; account changes discard these matches.

## Read State And Navigation

- Read timestamps persist locally in UserDefaults, partitioned by Supabase account UUID (test/guest have separate scopes). No cross-device read synchronization.
- Opening evidence marks that event version read; a newer timestamp for the same ID is unread again. Mark-all applies to the entire current inbox, not only the visible filter.
- Filter by all/tracked/holdings and optionally unread. Zero matches show discovery and add-holding actions.
- Rows open the existing Smart Account evidence or Smart Money movement detail, not the investor bio. Detail navigation hides the bottom tab bar.
- UI uses semantic light/dark tokens and localized strings. The bell shows a dot only while matching unread events exist.

## Verification

`ActivityNotificationTests` covers matching, deduplication, namespaces, date bounds, ordering/cap, legacy matching and account-scoped read persistence. `NotificationInboxUITests` covers entry, filters, evidence navigation, empty state and settings access using fixtures without signing or funds.
