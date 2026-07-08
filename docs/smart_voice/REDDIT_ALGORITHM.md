# Smart Voice Reddit Algorithm

## Scope

Source key: `reddit`.

Reddit is the long-form and community-discussion source. It is best for DD posts, thesis debate, variant views, and early retail discovery.

## Content Unit

The scoring evidence unit is one Reddit post for v1.

Comments can be added later as separate evidence units if they contain independent directional calls. For v1, comments should not automatically inherit the post's ticker call.

## Candidate Recall

Recall should prioritize:

- Posts with ticker mentions from US stocks and ETFs.
- DD, thesis, earnings, valuation, catalyst, and risk posts.
- Posts with clear stance and enough author analysis.
- Authors with repeated ticker-relevant posting history, not one-off mentions.

Exclude:

- Pure questions with no author view.
- News reposts without author interpretation.
- Meme-only posts.
- Deleted or removed posts.

## Author Pool Gate

Reddit has a very long tail of one-off authors, so the SV author pool should use a minimum posting-history gate before call extraction.

Gate rule:

```text
repeat_pool = authors with at least 3 ticker-relevant posts
author_min_ticker_posts = max(4, median ticker-relevant post count inside repeat_pool)
```

After the July 2026 one-year Reddit backfill, the repeat-pool median is 10. For the first Reddit SV run, the operational gate is relaxed slightly to keep broader coverage while still excluding thin one-off authors:

```text
strict_median_gate = 10
operational_author_min_ticker_posts = 8
```

Authors below this gate can remain in raw Reddit data and product search, but should not enter the official Reddit SV candidate pool by default.

## Structured Call

Reddit writes into the shared `sv_call` schema:

- `source = reddit`
- `tweet_id = reddit post id` until the schema is fully renamed to `content_id`
- `investor_id = reddit:{author_id}`
- `author_handle = Reddit author id`
- `ticker`
- `direction`
- `call_type`
- `ticker_role`
- `ticker_relevance`

## Platform Tuning

Reddit can have strong but sparse posts, so the qualified threshold should be lower than X and close to YouTube.

Default qualified threshold:

```text
n_eff >= 3
settled_calls >= 4
```

Default strengths:

- Deep DD.
- Contrarian or non-consensus information.
- Rich risk discussion.

Default weaknesses:

- Lower identity reliability.
- High meme/noise risk.
- One-off authors may need strong confidence caps.

## Platform Score

`SV_Platform` is normalized only inside the Reddit qualified author pool.

This score answers:

```text
How far above or below the median Reddit investor author is this account?
```
