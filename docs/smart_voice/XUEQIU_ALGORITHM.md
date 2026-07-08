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
- Pure chat or emotional reaction without tradable implication.
- A-share-only, Hong Kong-only, crypto, futures, and options-only calls for the current phase.

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
