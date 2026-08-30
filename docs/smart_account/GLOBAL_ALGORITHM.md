# Smart Account Global Algorithm

## Product Semantics

`SV_Global` does not put every platform on the same exam.

It answers:

```text
Who is unusually strong or unusually weak relative to the baseline of their own platform?
```

The product goal is to surface the strongest and weakest investors from X, YouTube, Reddit, Xueqiu, and Toss without forcing all platforms to share identical content assumptions.

## Score Layers

Smart Account has two layers:

```text
raw call performance
-> dual-benchmark integral settlement
-> point-in-time time decay
-> platform-specific candidate and weight tuning
-> SV_Platform
-> confidence-adjusted platform deviation
-> SV_Global
```

## Dual-Benchmark Integral Settlement

Each actionable call is evaluated on two independent ability axes:

```text
market selection = directional stock return - SPY return
industry selection = directional stock return - mapped industry ETF return
```

The SPY axis measures whether the author can find a winning stock or industry
across the whole market. The industry ETF axis measures whether the author can
find a standout stock inside that industry. Industry mapping is explicit and
auditable: ticker override, narrative ETF, then sector ETF. An unmapped ticker
does not silently fall back to SPY and contributes only to market selection.

For each tradable close after the first tradable open strictly following the
call, calculate the cumulative directional excess-return path `E(t)`. The
integral at a horizon is the trapezoidal area under that path:

```text
A(H) = integral from 0 to H of E(t) dt
mean_A(H) = A(H) / H
integral_component = clip(mean_A(H) / horizon_normalizer, -1, 1)
terminal_component = clip(E(H) / horizon_normalizer, -1, 1)
call_score = 0.70 * integral_component + 0.30 * terminal_component
```

Therefore an early, persistent correct judgment scores above a late jump with
the same endpoint. `A(20D)` is the accumulated prefix of `A(5D)`, not another
independent experiment.

Only one primary horizon per call has nonzero evidence weight. An explicit
valid horizon wins; otherwise the default is selected by analysis style
(`technical/flow=5D`, `event/mixed/unknown=20D`, `macro=60D`,
`fundamental=90D`). Other horizons remain diagnostic integral snapshots. This
prevents one post from being counted as six independent observations.

The two ability axes are normalized separately inside each platform. Industry
selection receives a gradually increasing blend weight based on its effective
sample and is capped below 50%; missing industry evidence does not lower an
author's score.

## Time Decay

Current Score is a measure of current, demonstrated judgment quality rather than a
permanent career score. Only outcomes known before the score's `as_of_day` are
eligible. A result that settles on `as_of_day` is first available on the next
day, which keeps historical score reconstruction free of look-ahead leakage.

Decay starts from `exit_day`, not content publication time:

```text
age_days_i = as_of_day - exit_day_i
decay_i = 0.5 ^ (age_days_i / half_life_days[horizon_i])
```

Default half-lives:

```text
1D    60 calendar days
5D    75 calendar days
20D  150 calendar days
60D  300 calendar days
90D  450 calendar days
180D 675 calendar days
```

Long-horizon theses therefore remain relevant longer than short-term trading
calls. These moderate half-lives make recency a secondary adjustment rather
than a dominant exclusion mechanism: recent settled evidence still matters
more, while older valid calls retain enough weight to support author
qualification. The same schedule is used across platforms; platform
normalization still happens after decay.

Decay is applied as fractional evidence:

```text
decayed_contribution = sum(decay_i * contribution_i)
decayed_variance = sum(
  decay_i * score_weight_i^2 * expected_hit_i * (1 - expected_hit_i)
)
z_recent = decayed_contribution / sqrt(decayed_variance)
```

The effective sample size also decays:

```text
evidence_mass = sum(score_weight_i * decay_i)
decayed_n_eff =
  evidence_mass^2 / sum(score_weight_i^2 * decay_i)
```

The existing sample shrinkage then remains active:

```text
raw_z = z_recent * decayed_n_eff / (decayed_n_eff + k)
```

This combination has three intended properties:

- Recent outcomes affect current Score more than old outcomes.
- A small number of fresh wins cannot overwhelm the sample-size prior.
- An inactive investor gradually returns toward the platform baseline and can
  eventually leave the qualified pool as `decayed_n_eff` falls.

Concentration metrics use the same decay weights so an old single-ticker record
does not permanently dominate a currently diversified author profile.

## Score Platform

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

## Score Global

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
- SPY market baseline and mapped industry ETF baseline.
- Integral path scoring with one evidence-bearing primary horizon per call.
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
