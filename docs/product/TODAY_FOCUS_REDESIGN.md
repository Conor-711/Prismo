# Today Focus Redesign

## Objective

Today answers one question before anything else:

> Have any Smart Accounts or Smart Money accounts acted on a stock I hold or
> watch, and what exactly did they say or do?

It is a portfolio-aware smart-activity inbox, not a generic market feed. Smart
Account and Smart Money operate on different horizons, so Today preserves them
as parallel, independent evidence instead of manufacturing agreement,
opposition, or divergence labels. A bounded Smart Alpha section is the only
untracked discovery surface: it appears after Smart Consensus, contains at most
one Smart Account and one Smart Money candidate, and never enters the portfolio
alert queue.

## Information order

1. **Scope**: switch between holdings and watchlist without mixing the two.
2. **Activity summary**: show affected tickers, unread count, and the independent
   Smart Account / Smart Money source counts.
3. **Most relevant activity**: identify the exact author or public capital
   account, ticker, action, time, reason or observed position change, horizon,
   target or invalidation where available, and the user's position context.
4. **Recent activity**: scan compact rows and filter only by source or unread
   state.
5. **Evidence expansion**: reveal original and translated text or public account
   facts, timestamps, and the source link without navigating away first.
6. **Smart Alpha discovery**: surface one or two under-covered tickers newly
   mentioned or acted on by top sources, with a dedicated evidence detail page.

## Activity headline contract

An activity headline communicates the new information, not the existence of a
post or transaction:

- Smart Account: ticker plus the author's conclusion, changed conviction,
  target or decisive level, and the main reason when available.
- Smart Money: open/add/reduce/close/flip, ticker, side, and observable notional
  change. Nearby fills from the same account may be combined when their amounts
  are safely additive.
- Author, account, platform, rank and time stay in the metadata line. They must
  not replace the headline with copy such as “Author published a view on X.”
- The pipeline publishes localized `activityTitleZH` and `activityTitleEN`.
  Clients may construct a deterministic fallback from structured Call fields,
  but must never invent a reason that is absent from source evidence.

## Ranking rule

Today consumes published Smart Account and Smart Money read models. It does not
recalculate Score or wallet quality. Presentation relevance combines:

1. known portfolio exposure;
2. published author percentile or public account score;
3. specificity or action magnitude;
4. lifecycle importance and recency.

## States

- **No recent activity**: show a calm empty state and last successful check. Do
  not fill the space with generic market content.
- **One activity**: use that activity as the only primary object.
- **Several activities**: show the most relevant activity and the remaining
  source-filterable queue.
- **No portfolio**: keep the current setup entry and do not show generic market
  events as personalized content.

## Acceptance criteria

- The first viewport contains one and only one primary activity object.
- A user can identify who acted, the affected ticker, what happened, and why the
  view exists after scanning the page for five seconds.
- Every visible activity headline contains a decision-relevant conclusion or
  capital action; generic author/ticker templates are rejected.
- No agreement, opposition, divergence, or causality is inferred between Smart
  Account and Smart Money activity.
- Untracked content appears only in the explicitly labeled Smart Alpha section;
  it never replaces the primary portfolio activity or enters portfolio alerts.
- Original evidence is reachable from the expanded activity in one interaction.
