# App Search

The third native tab is Search. Smart Account / Smart Money discovery remains
accessible from Today. Search does not grant trading or wallet permissions.

## Scope and ordering

- Tickers: existing merged research/portfolio/Hyperliquid perpetual directory.
- Opinions: published Smart Account updates plus already loaded author evidence;
  Smart Money movements are included in this group, labelled as movements.
- Authors: Smart Account and Smart Money directory entries, including names,
  handles, specialties, styles and covered tickers.
- Users: completed public bSmart profiles from the account Supabase project,
  fetched from `bsmart-search/profiles`, not inferred from the visible Feed page.

All results always use ticker, opinion, author, user group order. Exact ticker
matches precede name/prefix/body matches. Text search is case/width/diacritic
insensitive on the native content index, accepts `$BTC`, `@handle`, multiple
terms and major asset aliases (e.g. Bitcoin / 比特币). Matching does not recalculate
Score. Within equal relevance, recent opinions precede older ones.

The native index covers the app's currently published content snapshot and loaded
evidence, not an unbounded historical archive or external web search. No fake
results, prices, users, search-volume statistics or wallet data are introduced.

## Interaction and isolation

The empty search page combines popular ticker rows, recent opinion summaries,
an author portrait rail and public community profiles. Local recent queries are
saved only on explicit submit/result selection, scoped to the signed-in account,
clearable, and limited to eight. No server analytics are added.

Typing uses a 220 ms debounce and a background index, with cancellation/request
generations preventing stale results. Public user queries fail independently
from local results, support retry/paging, and are cleared on account changes,
backgrounding and leaving the tab. No database migrations are required.
Market-directory loading/failure stays distinct from an empty result. Temporary
Supabase Auth outages return 503 rather than a credential-rejection 401, so
search availability cannot itself revoke a valid app login.

## Validation

The independent search function is deployed. Its unauthenticated live endpoint
returns 401. Seven handler tests, Deno type checking, fourteen native model tests
and six signed simulator UI tests passed on 2026-09-14. Real-account user lookup
requires a signed-in device acceptance pass; fixture identities never enter the
live service. No migrations, real trades or profile writes were performed.

## Design references

- [X Explore/trends](https://help.x.com/en/using-x/x-trending-faqs): combine directed
  search with browsable current topics.
- [Robinhood lists/cards](https://robinhood.com/us/en/support/articles/lists/):
  separate asset scanning from contextual activity.

The native layout adapts these patterns without copying their promotional cards
or changing the user's requested cross-category priority.
