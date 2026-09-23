# Native content notifications

The native iOS Supabase project (`dzyitinagewdfkzjkuiz`) owns device registrations and private notification interests. APNs tokens and holding tickers never enter public research pages.

## Device and interests

- `PUT /functions/v1/bsmart-notifications/device` registers an installation with a verified, non-anonymous Apple/Google Supabase JWT. `DELETE` disables only the authenticated user's installation. The server derives the user ID from Auth, never from request JSON.
- `PUT /functions/v1/bsmart-notifications/interests` replaces the current installation's bounded author IDs, Smart Money account IDs, watched tickers, held tickers, and three category switches. The RPC can update only a registered, enabled installation owned by that JWT user. Device token reassignment to another account clears the previous interests.
- The iOS master switch and OS permission control device registration. Author, watched-ticker, and holding switches control category matching. Manual follows and positions are snapshotted per account on device; live trading positions are refreshed using the verified account's registered public wallet address, never a signing key. A failed holdings read preserves the last successful snapshot instead of asserting no position. Offline trading or changes on another device may leave the last server snapshot stale until this App reconnects.

## New content and de-duplication

- A non-baseline content publication compares stable IDs in `smart-account-updates` and `smart-money-movements` with the preceding published revision. Score edits, changed timestamps, re-exports, rollback, and opinions already seen as representative evidence do not count as new items.
- A new opinion matches a followed author, watched ticker, or held ticker; a new movement matches a followed Smart Money account, watched ticker, or held ticker. The protected event ledger has primary key `(user_id,event_kind,event_id)`. The same opinion can therefore enter a user's queue only once across matching reasons, devices, and later releases.
- The fixed timezone is `Asia/Shanghai` (UTC+8). At 08:00, 18:00, and 22:00, the worker groups all pending eligible events for each user into at most one digest for that slot. `(user_id,slot_at)` is unique and only those three local hours are valid, so the hard cap is three APNs requests per user per local day. A slot has a 30-minute dispatch window; if the worker misses it before sending, the events move to the next slot. Content published after a slot cutoff waits for the next slot. Empty slots send nothing.
- One active device per user receives each digest, chosen from the most recently refreshed matching registrations. The APNs payload contains only a count and generic text, not the author's private account, positions, balances, or wallet. Tapping opens the native notifications inbox and refreshes content.
- The outbox changes `pending → sending` before the APNs request and never reclaims `sending`. An ambiguous timeout or worker crash can lose an alert but cannot dispatch that user/slot a second time. Apple accepting a request does not prove delivery or exact on-device presentation; its best-effort service can delay/coalesce alerts. The application guarantees at most one provider request per user/slot and one ledger entry per user/content ID, not a device-display guarantee.

## Activation

Apply `202609230001_interest_push.sql` manually in the native Supabase project, deploy the updated `bsmart-notifications` Edge Function, install a new signed iOS build, and configure a continuous content-push worker with protected `BSMART_CONTENT_DATABASE_URL` and APNs credentials. Only then set `BSMART_UPDATE_PUSH_ENABLED=true` for both publisher and worker. Do not run schema DDL in the agent. A local three-hour content scheduler alone does not dispatch at the three notification slots.
