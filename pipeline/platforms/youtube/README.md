# YouTube source adapter

`incremental.py` polls uploads playlists for the existing versioned creator pool using the official YouTube Data API. It saves video metadata to the existing `yt_channel_upload` table and reports channel coverage and source timestamps. Missing or unavailable channels are recorded without deleting prior content; transient API or pagination failures stop the batch. Search is not used, keeping quota predictable.

Transcript analysis, Score calculation, client projection, and publication belong to `pipeline/domain`, `pipeline/jobs/social_delivery`, and `services/client_api/content_release`. Run a bounded platform smoke check with `make social-delivery SOURCE=youtube`; see `docs/operations/social-content-delivery.md` for budgets and receipts.
