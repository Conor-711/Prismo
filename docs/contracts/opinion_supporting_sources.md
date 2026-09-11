# Opinion Supporting Sources

Confirmed 2026-09-09: supporting context is not limited to official earnings or
partnerships. Company disclosures, regulatory documents, reporting, research,
datasets and other attributable factual sources are supported. No channel follow
or notification feature is introduced. Missing context produces no UI, including
no section title, placeholder, negative badge or change to Smart ranking.

`SmartAccountUpdate.supportingSources` is an optional array (old payloads remain
valid). Each item contains `id`, `eventId`, `ticker`, `publisher`, `sourceType`,
`relationship`, `status`, `title`, `summary`, `publishedAt`, `sourceURL`, `claim`,
`excerpt`, `locator`; optional `titleZH`, `summaryZH`, `contextNote` and
`contextNoteZH` carry translations and material limitations, not feature captions.
Optional `updatedAt` preserves a verified source revision timestamp, without
overwriting `publishedAt`. It cannot precede publication or be in the future.

- sourceType: company / regulatory / news / research / data / other. An issuer's
  SEC submission is attributed to the issuer, not portrayed as an SEC endorsement.
- relationship: cited / related / follow_up. `cited` requires reviewed explicit
  citation; a system match is `related`. Documents published OR revised after the
  opinion must be `follow_up`; temporal availability is max(publishedAt, updatedAt).
- Only `status=ready`, complete sources with an exact original-text `claim`, the
  same ticker, a dated document and a safe HTTPS original URL are displayable.
- The source passage must support the linked factual claim, not the author's
  forecast. Keep reported allegations, management guidance and conditions intact.
- Documents about the same event remain separately attributable; do not describe
  duplicated reporting as independent confirmations. Repeated URLs are deduped.
- The first card preview contains at most two sources; all available sources are
  reachable in a full list. Detail uses the existing shared-element navigation.
- First implementation uses a reviewed, post-scoped source catalogue. Identity
  is platform + authorId + sourcePostId + ticker, plus the exact claim span.
  This is not arbitrary keyword matching or an autonomous web-search service.
- Pipeline export and X realtime jobs enrich documents before handing them to
  the API publisher. The API only persists/serves projections and must not import
  pipeline code. ETags therefore reflect source changes. Invalid/withdrawn
  catalogue entries disappear on re-export and republish without suppressing
  the original opinion. No DB schema change.
- When only the source's publication day is known, store that UTC day's end as
  the conservative temporal boundary. Display the UTC calendar date, never a
  fabricated publication time. Do not claim historical availability for an
  earlier same-day post without a verified timestamp.

Catalogue: `pipeline/domain/opinions/data/supporting_sources.json`. Review new
entries against the dated original, preserve short excerpts and source rights.
Refresh all affected collections when correcting/removing a source; previously
delivered offline snapshots require the normal client refresh. Never infer
missing facts in Swift or add sources to unrelated calls from the same author.

The default loader also merges `data/crawled_sources.json` beside the catalogue.
This file contains verified matches from an explicitly scoped local sample
manifest, not arbitrary auto-generated claims. Crawl receipts (retrievedAt,
content hash, rule ID, claim hash) stay in the catalogue and are not exposed as
opinion text or Score. Publication keeps the same per-post identity and filters.
