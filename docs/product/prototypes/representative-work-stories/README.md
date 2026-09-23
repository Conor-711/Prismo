# Homepage Representative Work Stories

Standalone design prototype; no iOS changes, network requests, trades, ranking changes, or fixture mutations.

## Selected Design

C v2 is selected and opens in single-phone mode. A and B remain available for comparison.

- Real price trace above a compact 13px narrative; author, rank, and follow action stay in the existing identity row.
- Dates use dotted numeric formatting. Visible copy says price, not reference price.
- At most three opinion nodes per chart: strictly the earliest three bullish posts by publication time within the available case window. When fewer exist, show all of them. Nearby hit targets may be clustered, never exceeding three nodes; no middle or latest post replaces an early one.
- Clicking a node opens the full-page evidence view and highlights its original record. The footer opens the full record history.
- All known bullish and bearish counts remain available. Three selected bullish nodes do not imply that every historical opinion was bullish.
- Light/dark modes, responsive comparison, local follow state, and reduced-motion fallback are included. Surrounding homepage content is context only.

## Data Boundaries

`bundle.mjs` reads `smart-accounts.json`, `smart-account-evidence.json`, and `smart-account-updates.json` from `contracts/fixtures`. It embeds existing iOS avatar and ticker assets. Marker records are inherited only from evidence for the same author and ticker, verified against the source URL's account identifier, then deduplicated by source post ID.

The three examples are Wey How / MU, Serenity / LITE, and WallStTitan / NVDA. The author profile and ranking reflect the existing snapshot, not a reconstructed historical rank. These are locally sourced demonstration cases; this task does not independently verify the market data or corporate-action adjustments online.

Published dates use America/New_York. Prices at opinion nodes are the last completed daily close available before publication, not live quotes or verified trades. Existing `firstOpinion` prices are used only when they belong to the same source post. Other nodes use an earlier daily close, or that day's close for posts at or after 16:00 New York time.

Peak appreciation uses the maximum daily high in the available subsequent sessions. The publication day's high is excluded because it may precede the post. The cutoff is visible; the line continues through subsequent drawdowns. The price curve uses the representative record's existing candles rather than the markers' later `viewPrice`, avoiding mixing next-session prices with publication-time prices.

This is a retrospectively chosen case, not an investor return, executable strategy, or unbiased estimate of future performance. It makes no claim that the author bought, held continuously, or sold at the peak. Original posts remain original; AI marker summaries are not shown as quotes when original text is unavailable.

## Build

From the repository root, using Node 22:

```sh
node docs/product/prototypes/representative-work-stories/bundle.mjs
```

The build produces `data.js` and a self-contained `bsmart-representative-work.html`. Open the latter directly; no dev server is required. Scripts, styles, avatars, logos, and price data are embedded.

## Verification

Use browser DOM geometry and interaction checks, not screenshot-based QA. Check 320px, 390px, and desktop widths; all three cases; at most three nodes in both homepage and detail charts; text wrapping and image loading; chart pixel output; source links; node-to-record selection; close/return state; local follow state; and reduced motion.
