# Smart Voice Global Algorithm

## Product Semantics

`SV_Global` does not put every platform on the same exam.

It answers:

```text
Who is unusually strong or unusually weak relative to the baseline of their own platform?
```

The product goal is to surface the strongest and weakest investors from X, YouTube, Reddit, Xueqiu, and Toss without forcing all platforms to share identical content assumptions.

## Score Layers

Smart Voice has two layers:

```text
raw call performance
-> platform-specific candidate and weight tuning
-> SV_Platform
-> confidence-adjusted platform deviation
-> SV_Global
```

## SV Platform

Each platform computes its own qualified pool.

For every qualified investor in that platform:

```text
raw_z = shrunk contribution z-score from settled calls
SV_Platform = 100 + 10 * robust_z(raw_z inside platform)
```

Baseline:

```text
100 = median qualified investor in the same platform
```

So:

```text
X investor SV_Platform 160 = 60 points above X baseline
YouTube creator SV_Platform 150 = 50 points above YouTube baseline
```

## SV Global

Global uses platform-relative deviation:

```text
platform_deviation = (SV_Platform - 100) / 100
SV_Global = 100 + 100 * platform_deviation * confidence_factor
```

Default confidence factors:

```text
high      1.00
medium    0.85
low       0.65
observing 0.35
```

Example:

```text
X investor:
  SV_Platform = 160
  confidence = high
  SV_Global = 160

YouTube creator:
  SV_Platform = 150
  confidence = medium
  SV_Global = 142.5
```

This keeps the product meaning clear: Global ranks how exceptional someone is inside their own platform, adjusted for evidence reliability.

## Bottom Investors

Bottom investors also enter Global.

If an investor is materially below their platform baseline:

```text
SV_Platform < 100
SV_Global < 100
```

Low-confidence bottom scores are pulled toward 100 by the same confidence factor.

## Platform Qualification

Default platform thresholds:

```text
X:
  n_eff >= 8
  settled_calls >= 10

YouTube:
  n_eff >= 4
  settled_calls >= 5

Reddit:
  n_eff >= 3
  settled_calls >= 4

Xueqiu:
  n_eff >= 5
  settled_calls >= 8

Toss:
  n_eff >= 5
  settled_calls >= 8
```

If a platform has fewer than eight qualified investors during early rollout, use all scoreable investors in that platform as a temporary baseline and keep confidence caps active.

## Shared Core

All platforms share:

- Structured call schema.
- US stock and ETF scope for the current phase.
- SPY benchmark for v1 settlement.
- Path-aware horizon scoring.
- Content-level evidence budget.
- Call lifecycle closure when an investor clearly reverses.
- Same-entry-day reconciliation before settlement: repeated same-direction calls share a daily evidence cap; explicit reversals keep the final call; otherwise opposite evidence is netted and ambiguous days become neutral.
- Confidence and concentration gates.

Platforms differ in:

- Candidate recall.
- Content unit.
- Sample thresholds.
- Noise filters.
- Weight tuning.
- Identity handling.

## Current Implementation Notes

The current SQLite schema still uses `tweet_id` as the physical content id field. Until a full migration is done:

```text
X:        tweet_id = tweet id
YouTube:  tweet_id = video id
Reddit:   tweet_id = post id
Xueqiu:   tweet_id = post id
Toss:     tweet_id = content id
```

Future migration should add:

```text
content_id
platform_content_id
platform_author_id
canonical_investor_id
content_type
```
