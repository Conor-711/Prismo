# Smart Voice YouTube Algorithm

## Scope

Source key: `youtube`.

YouTube is the long-form investor explanation source. It is best for company-level theses, valuation repair, earnings-cycle views, target-price discussion, and retail mindshare.

## Investor Pool

First production seed:

```text
subscriber_count >= 1000
has at least one collected video in the one-year window
```

Institutional media channels can enter the pool in v1. They should be typed later, but the first algorithm does not depend on channel type.

## Content Unit

The scoring evidence unit is one video.

If one video discusses multiple tickers, those ticker calls share the video-level evidence budget. Repeated discussion of the same ticker inside one video remains one ticker-level call.

## Candidate Recall

Recall should prioritize:

- Videos matched to US stock or ETF tickers.
- Videos with stance, target price, key levels, explicit horizon, or clear buy/sell framework.
- Videos with full transcript, digest, chapters, or structured `yt_analysis`.

Transcript status is processing state, not a quality factor. Missing transcript should not lower the score by itself. When full transcript is unavailable, use `yt_analysis`, `yt_digest`, `yt_judgment`, title, description, and chapter data as temporary inputs.

Implementation rule:

```text
Required tables:
  yt_video
  yt_channel

Optional enhancer tables:
  yt_analysis
  yt_digest
  yt_fulltext
  yt_judgment
```

The YouTube adapter must degrade gracefully when optional enhancer tables are missing or incomplete. A new environment should be able to build candidates from `yt_video` + `yt_channel` first, then improve extraction quality after transcript, digest, chapter, and judgment tables are filled.

Do not treat missing transcript as low quality. It only reduces available evidence for the LLM extraction step.

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

## Platform Score

`SV_Platform` is normalized only inside the YouTube qualified creator pool.

This score answers:

```text
How far above or below the median YouTube finance creator is this channel?
```
