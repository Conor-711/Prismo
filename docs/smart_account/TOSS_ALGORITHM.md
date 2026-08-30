# Smart Account Toss Algorithm

## Scope

Source key: `toss`.

Toss is the Korean stock-community platform adapter.

## Content Unit

The scoring evidence unit is one Toss post, note, or opinion item.

If the platform exposes portfolio actions separately from posts, portfolio actions should enter only when they contain a clear US stock or ETF directional implication.

## Candidate Recall

Recall should prioritize:

- US stock and ETF mentions.
- Clear directional views, price levels, portfolio changes, or thesis updates.
- Repeated authors with enough independent calls.

Exclude:

- Pure news.
- Pure social comments.
- Crypto, futures, options-only, and non-US assets for the current phase.

## Structured Call

Toss should write into the shared `sv_call` schema:

- `source = toss`
- `tweet_id = Toss content id` until the schema is fully renamed to `content_id`
- `investor_id = toss:{author_id}`
- `author_handle = Toss display name or handle`
- `ticker`
- `direction`
- `horizon_bucket`
- `call_type`
- `ticker_role`
- `ticker_relevance`

## Platform Tuning

Default qualified threshold:

```text
n_eff >= 5
settled_calls >= 8
```

Default strengths:

- Platform-native investor behavior.
- Potentially useful portfolio/action context.
- May capture investors not active on X or YouTube.

Default weaknesses:

- Final data fields are not fixed yet.
- Need anti-spam and identity rules after the crawler lands.
- Portfolio action semantics may require a separate adapter rule.

## Platform Score

`SV_Platform` is normalized only inside the Toss qualified investor pool.

This score answers:

```text
How far above or below the median Toss investor is this account?
```
