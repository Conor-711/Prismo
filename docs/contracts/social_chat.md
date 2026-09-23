# Native Social Chat

The existing `bsmart-social` edge function authenticates Google/Apple Supabase
sessions. No friendship or follow permission is required. `global` is one shared
room visible to all signed-in users; a UUID room identifies the other public
profile, never an auth account ID. Direct messages remain private to their two
participants. Existing `/messages/{peer}` routes remain available.

## Rich Chat API

- `GET /chat/{room}`: up to 50 messages, ascending within a descending cursor page.
  Optional `beforeAt` and `beforeID` must be provided together. Response uses
  `items`, `nextBeforeAt`, `nextBeforeID`.
- `POST /chat/{room}`: `{id, text, replyToID?, imageBase64?}`. Client-generated UUID
  is an idempotency key. Text is at most 2,000 characters; text or one JPEG is
  required. JPEG maximum 2 MB, maximum side 2,048 px. Request maximum 3 MB.
  Server enforces 60 messages/hour per account across rooms and serializes sends.
  Image upload reservations have a separate 60/hour limit, including failed sends.
  Retrying the same ID/payload returns the same message; different payload is 422.
- Messages include `id`, `isMine`, `text`, `sentAt`, `sender` (public profile),
  optional `image` (`url`, `width`, `height`), optional `reply` (`id`, `senderName`,
  `text`, `hasImage`). Replies must reference a message in the same room.
- Images are stored in private `bsmart-chat-images`, keyed by message UUID and SHA-256, not
  email or private account ID. Only service-role edge code accesses storage.
  Signed image URLs last one hour and are issued only after conversation access
  is checked. Profile avatars use existing short-lived signing. Images are not
  exposed through a public bucket or caller-supplied URL.
- Failed requests never clear drafts; uncertain send retries reuse the ID. A
  successful message commits immutable contents. New page polling merges by ID
  and updates URL refreshes without rebinding the text editor.

## Release

Apply `202609220002_social_chat.sql` manually to the iOS account project, then
deploy `bsmart-social`. On 2026-09-22 the operator confirmed the migration applied
and the function deployment succeeded. This migration extends the existing message table without
deleting conversations. No app-startup DDL. Before public launch, add abuse
moderation/retention and load-test polling. Failed or cancelled photo sends can
leave private orphan uploads; retention cleanup must compare storage objects to
committed messages before deleting them, never delete on an ambiguous send result.
This feature does not include voice,
push delivery, or end-to-end encryption.

## Verification (2026-09-22)

- 12 edge-function tests passed (mocked storage/RPC), plus TypeScript checking.
- SQL and PL/pgSQL parsing passed; schema application was confirmed by the operator.
- Seven native unit tests and two simulator UI tests passed. UI coverage includes
  Global Chat navigation, swipe reply, long-press menu, typing, keyboard dismissal
  and fixture-only send. No test messages were sent to production.
- The deployed unauthenticated chat endpoint returned HTTP 401 as expected.
- Two-account authenticated text/photo delivery and physical-device typing
  performance still require validation with the updated app.
