# Reddit source adapter

`incremental.py` polls the public Arctic Shift mirror for configured US market subreddits and scored authors. It checks mirror recency, retries transient HTTP failures, bounds pagination, deduplicates by post ID, and stores raw post facts through the existing SQLAlchemy models and ticker mention extractor. The mirror has no guaranteed uptime or completeness; failed batches preserve the last published content.

Call extraction, Score calculation, client projection, and publication belong to `pipeline/domain`, `pipeline/jobs/social_delivery`, and `services/client_api/content_release`. Run a bounded platform smoke check with `make social-delivery SOURCE=reddit`; see `docs/operations/social-content-delivery.md` for source limits and receipts.
