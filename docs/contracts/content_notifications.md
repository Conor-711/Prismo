# Native Content Notifications

The native iOS project is `dzyitinagewdfkzjkuiz`. APNs tokens, credentials, holdings and wallets stay private.

## Product Rules (2026-10-01)

- Every production data publication selects two different followed subjects with genuinely new activity, ranked by descending tracking return. Send one latest event for each selected subject. Ties use event time then stable IDs; missing returns sort last. Score changes, baselines, historical-test/backfill publications, rollback and re-exports do not send.
- Platform returns mirror the App's full-history backtest `total_return`, synchronized privately before publication by `content_release/push_returns.py`. Subject snapshots use their published `research.meanOpenReturn`. No mock Score or minimum sample gate substitutes for an observed return.
- Followed public bSmart real-money traders send every newly verified operation and every newly published trade thesis independently, without consuming the top-two quota. One operation means the order's first server-verified execution; later partial-fill receipts do not resend. A subsequent thesis publication is a separate event. Pending/failed orders and hidden profiles do not send.
- Title: `昵称关于$TICKER的最新动态`. Nickname: at most 24 grapheme characters; original body: at most 160, with ellipsis included in each limit. Government/institution records without prose use original action, amount range and asset-description/name fields joined with ` · `, as approved by the user. No AI rewriting.
- Native bodies use verified executed notional/side, not requested amount or thesis prose. Opening long/short and closing long/short are distinguished.
- Followed author IDs, App subject follows and native server social follows qualify, with the author-notification switch. The latest enabled fresh production registration is authoritative; watch/holding-only matches no longer send. Consent and profile visibility are rechecked before claiming. The new App build unions subject IDs into account-scoped interests and observes subject follow/unfollow; older builds do not upload government/celebrity/institution follows. Native social follows work server-side without a new build.

## Delivery

Private `bsmart_activity_push_outbox` entries are unique by user/kind/event. A global identity ledger prevents replay of unselected candidates after ranking changes. Deployment seeds existing identities without enqueueing history. Transactional triggers attach to content activation, subject snapshot updates, verified execution and thesis publication.

Publication wakes pg_net. Bounded worker batches request continuation while pending work remains, with a one-minute cron fallback. There is no daily three-notice cap. Notices expire after 24 hours, with distinct collapse IDs. State moves pending to sending before the provider request and never reclaims uncertain sends; a crash can lose a notice but cannot send it twice. Invalid-token cleanup checks registration time.

Payload `type=content_update` preserves existing App behavior: refresh content and open the notification inbox. Original public text and public actor/ticker/event metadata are allowed, never private wallets or balances. The sender enforces the serialized 4 KiB limit, production HTTP/2, fixed topic and existing private 45-minute provider JWT cache. Apple acceptance is not a phone-display guarantee. Client roles cannot read delivery tables or dispatch/activate notices.

## Activation

The user manually applies `202610010002_immediate_activity_push.sql`, `202610010003_activity_push_compatibility.sql`, then `202610010004_native_social_push_follow.sql` after existing device, interest, cloud, subject and native-investor migrations. The compatibility repair corrects `payload.items`, native trigger record types and identity baseline/continuation for an earlier applied draft. Apply in order; do not reapply the repair alone after the social-follow migration. Settings start disabled. Deploy `bsmart-push`, seed metrics with `python -m services.client_api.sync_push_returns --apply`, verify schema, then enable the service-only database configure RPC and protected `BSMART_CLOUD_PUSH_ENABLED=true`.

Publisher: `BSMART_ACTIVITY_PUSH_ENABLED=true`, legacy `BSMART_UPDATE_PUSH_ENABLED=false`, dispatch mode `cloud`. Historical subject imports set transaction-local `bsmart.push_suppress=true`. Pause with the cloud master gate and database configure(false), not by revoking keys.

The former 08:00/18:00/22:00 digest and Python sender are retained only for compatibility, not used by this dispatcher. Existing device/interest endpoints and Apple/Google authentication remain unchanged. An authorized one-device temporary probe still sends once without retry and removes its function/secret.
