# Smart Voice YouTube Algorithm

## Scope

Source key: `youtube`.

YouTube is the long-form investor explanation source. It is best for company-level theses, valuation repair, earnings-cycle views, target-price discussion, and retail mindshare.

## Investor Pool

The first production pool is versioned and reproducible. Discovery eligibility is:

```text
subscriber_count >= 1000
has at least one collected video in the one-year window
```

The pool builder classifies obvious institutional media and high-volume publishers separately. The production creator pool targets 500 selected channels; media channels stay available for discovery but do not enter creator SV normalization.

Followers and lifetime upload count are discovery inputs only. They never increase prediction accuracy or final SV directly.

## Content Unit

The scoring evidence unit is one video.

If one video discusses multiple tickers, those ticker calls share the video-level evidence budget. Repeated discussion of the same ticker inside one video remains one ticker-level call.

## Candidate Recall

Recall should prioritize:

- Videos matched to US stock or ETF tickers.
- Videos with stance, target price, key levels, explicit horizon, or clear buy/sell framework.
- Videos with full transcript, digest, chapters, or structured `yt_analysis`.

Metadata may recall a candidate, but a formal YouTube call requires a complete `yt_fulltext` transcript. Missing transcript is a processing state: keep the candidate pending and do not create a production call. Title, description, digest, judgment, and chapters must not substitute for transcript evidence.

Implementation rule:

```text
Supported normalized sources (at least one path must exist):
  legacy: yt_video + yt_channel
  author pool: yt_author_pool + yt_channel_upload
               + yt_channel_upload_ticker

Optional enhancer tables:
  yt_analysis
  yt_digest
  yt_fulltext
  yt_judgment
```

The author-pool path reads each channel's uploads playlist for a rolling one-year window. It then maps videos to tickers using the versioned `youtube-title-v3` rules and hydrates only mapped videos with duration, view, like, and comment metadata.

Mapping precision rules:

- Title cashtags are strongest evidence.
- Bare tickers must be in the active US price universe and pass the ambiguity stoplist.
- Company names require finance context in the title.
- Description company names are never used because sponsor boilerplate creates false matches.
- Description cashtags are fallback evidence only when the title already proves finance context and contains no ticker match.
- Ambiguous words such as `NEXT`, `GOLD`, and `HBM` require a cashtag or unambiguous company name.
- `APP`, `NET`, `SMR`, and similar symbols can also match an explicit phrase such as `NET stock`.

Legacy and author-pool rows are deduplicated by `(video_id, ticker)`. Candidate extraction and scoring only consume mappings from the current mapping version at confidence `>= 0.90`.

The YouTube adapter degrades gracefully only at recall time. It may build a resumable transcript queue from metadata, but settlement rejects calls that lack the current transcript extraction version and transcript provenance.

Call extraction reads every speech segment. Long transcripts are chunked with overlap, extracted per ticker, and merged back to one `(video_id, ticker)` evidence unit. Summaries and chapters are product reading features and are not SV prerequisites.

YouTube-specific labels distinguish prediction or position actions from education, news, retrospective narration, risk management, and option strategies. Protective puts, covered calls, cash-secured puts, and generic risk warnings are non-actionable unless the speaker separately states an explicit direction for the underlying stock.

Call ownership is mandatory. A guest thesis, reported analyst target, whale trade, or third-party position does not increase the channel's SV. It becomes a channel call only when the host personally states it or explicitly endorses the same direction; otherwise `call_owner` remains `named_guest` / `quoted_third_party` and the call is excluded from channel settlement.

## Author-balanced Extraction

LLM extraction uses the current selected author pool and allocates evidence per author before giving extra depth to high-frequency channels:

```text
per_author_min = 20
per_author_max = 40
```

This is a collection budget, not a qualification rule. An author qualifies only after enough directional calls can be settled.

Titles where the mapped company is only a benchmark are deterministically excluded from settlement. Examples include "the next Nvidia", "missed Palantir", and "bigger than GameStop". The actual recommended comparison target can still be scored.

## Structured Call

YouTube writes into the shared `sv_call` schema:

- `source = youtube`
- `tweet_id = video_id` until the schema is fully renamed to `content_id`
- `investor_id = youtube:{channel_id}`
- `author_handle = channel handle or channel title`
- `ticker`
- `direction`
- `horizon_bucket`
- `target_price`
- `evidence_score`
- `specificity_score`
- `investor_style`

## Platform Tuning

YouTube has fewer items per creator than X, so sample thresholds should be lower.

Default qualified threshold:

```text
n_eff >= 4
settled_calls >= 5
```

Default strengths:

- Long-form reasoning.
- Clearer fundamental and valuation evidence.
- Better target-price and risk-condition extraction.

Default weaknesses:

- Lower posting frequency.
- More delayed commentary.
- More multi-ticker recap videos.

## Production Runbook

```bash
python -m pipeline.manage youtube-author-pool --target-size 500 --since-days 365
python -m pipeline.manage youtube-author-backfill --since-days 365 --workers 8
python -m pipeline.manage youtube-author-map --force
python -m pipeline.manage youtube-author-hydrate --min-confidence 0.90
python -m pipeline.manage sv-v0 --source youtube --stage candidates --candidate-limit 0
python -m pipeline.manage sv-v0 --source youtube --stage transcripts \
  --extract-mode author-balanced --extract-limit 10000 \
  --per-author-min 20 --per-author-max 40 --workers 4
python -m pipeline.manage sv-v0 --source youtube --stage extract \
  --extract-mode author-balanced --extract-limit 10000 \
  --per-author-min 20 --per-author-max 40
python -m pipeline.manage sv-v0 --source youtube --stage settle
python -m pipeline.manage sv-v0 --source youtube --stage score
python -m pipeline.manage sv-v0 --source youtube --stage export
```

See `youtube_author_pool_audit_2026-07-10.md` for the first production run and measured coverage.

## Platform Score

`SV_Platform` is normalized only inside the YouTube qualified creator pool.

This score answers:

```text
How far above or below the median YouTube finance creator is this channel?
```

Product Top/Bottom bands also use the qualified creator pool and `SV_Platform`:

```text
qualified: n_eff >= 4 and settled_calls >= 5
Top 10% / 25%: lowest platform percentile
Bottom 10% / 25%: highest platform percentile
```

Observing authors retain a score but do not enter formal Top/Bottom bands. The export contract is `platformBands.youtube`; `platformRank` and `platformScores.youtube` are authoritative inside the YouTube view.

Any leaderboard produced before `v1.8-transcript-lifecycle` is historical and must not be mixed with transcript-backed scores.
