# Smart Voice Xueqiu Algorithm

## Scope

Source key: `xueqiu`.

Xueqiu is the Chinese-language investor discussion source. It is best for Chinese retail and semi-professional investor views on US stocks, ETFs, and cross-market sentiment.

## Content Unit

The scoring evidence unit is one Xueqiu post or long-form article.

If a post covers multiple tickers, ticker calls share the post-level evidence budget.

## Candidate Recall

Recall should prioritize:

- US stock and ETF mentions.
- Clear buy/sell/hold thesis.
- Valuation, earnings, business model, position update, or target-price discussion.
- Author posts with original interpretation, not copied news.

Exclude:

- Pure news forwarding.
- Reposts whose raw payload links to an upstream `retweeted_status`.
- Pure chat or emotional reaction without tradable implication.
- A-share-only, Hong Kong-only, crypto, futures, and options-only calls for the current phase.

## Author Discovery Pool

The first version uses a two-stage pool instead of treating popularity as SV:

1. Recall accounts with at least 500 followers (or verified) and at least 300 lifetime statuses.
2. Separate obvious media, official institutions, and automated news publishers.
3. Rank the remaining creators only to prioritize one-year timeline backfill; select the Top 300 and keep the rest as a warm reserve.
4. After the one-year backfill, require at least 8 US-equity-relevant posts, 8 settled calls, and `n_eff >= 5` for formal SV qualification.

Followers, verification, lifetime statuses, and discovery rank must not enter `SV_Platform`.

The production candidate adapter defaults to a complete-pool gate: all selected creator timeline
jobs for the configured pool version must be `done` before candidate recall starts. Partial recall
is available only through an explicit diagnostic flag and must not be used for a published score.

## Structured Call

Xueqiu should write into the shared `sv_call` schema:

- `source = xueqiu`
- `tweet_id = Xueqiu post id` until the schema is fully renamed to `content_id`
- `investor_id = xueqiu:{author_id}`
- `author_handle = Xueqiu display name or handle`
- `language = zh`
- `ticker`
- `direction`
- `horizon_bucket`
- `target_price`
- `evidence_score`
- `specificity_score`

## Platform Tuning

Default qualified threshold:

```text
n_eff >= 5
settled_calls >= 8
```

Default strengths:

- Chinese investor perspective.
- Longer-form position and valuation discussion.
- Cross-region information asymmetry.

Default weaknesses:

- Reposts and copied news can be common.
- Ticker mapping must distinguish US, Hong Kong, and China listings.
- Some posts may discuss portfolio philosophy without a tradable call.

## Platform Score

`SV_Platform` is normalized only inside the Xueqiu qualified investor pool.

This score answers:

```text
How far above or below the median Xueqiu investor is this account?
```
