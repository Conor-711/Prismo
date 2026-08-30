# Smart Account Twitter Algorithm

## Scope

Source key: `x`.

Twitter is the high-frequency, short-form Smart Account source. It is best for timely calls, tactical reversals, flow/momentum setups, and direct ticker commentary.

## Content Unit

The scoring evidence unit is one tweet.

If one tweet creates multiple ticker calls, those calls share the tweet-level evidence budget. Repeated same-day same-direction posts by the same investor and ticker should not linearly increase evidence.

## Candidate Recall

Recall should prioritize:

- US stock and ETF cashtags.
- Directional language such as long, short, buy, sell, target, support, resistance, breakout, breakdown.
- Posts with explicit target, horizon, entry, invalidation, or position update.
- Substantive posts with enough reasoning text.

Exclude:

- Pure news reposts.
- Memes without tradable implication.
- Retrospective victory laps without a new call.
- Crypto, futures, options-only calls, and non-US assets for the current phase.

## Structured Call

Twitter uses the shared `sv_call` schema:

- `source = x`
- `tweet_id = platform tweet id`
- `investor_id = X author id`
- `author_handle = X handle`
- `ticker`
- `direction`
- `horizon_bucket`
- `conviction_score`
- `evidence_score`
- `specificity_score`
- `call_type`
- `ticker_role`
- `ticker_relevance`

## Platform Tuning

Twitter has many small posts, so it can use a higher sample threshold than long-form sources.

Default qualified threshold:

```text
n_eff >= 8
settled_calls >= 10
```

Default strengths:

- Fast reaction to market events.
- Good short-term and medium-term evidence.
- Strong lifecycle signals because investors often update or reverse calls.

Default weaknesses:

- High noise.
- More promotional posts.
- More basket/watchlist posts that need weight caps.

## Platform Score

`SV_Platform` is normalized only inside the X qualified investor pool.

This score answers:

```text
How far above or below the median X investor is this X account?
```

It does not directly compare the account against YouTube, Reddit, Xueqiu, or Toss.
