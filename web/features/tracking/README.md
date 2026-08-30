# Tracking Feature

`web/features/tracking` is the personalized watchlist workspace.

Ticker, author, and narrative follows are stored in `bsmart:tracking:v1` on the
current device. The payload version is `2`; reading an older payload drops the
retired community-follow rows while preserving every ticker, author, and
narrative row. `FavoritesProvider` keeps O(1) state, cross-tab sync, and the
one-time merge of historical account follows. Post and comment bookmarks remain
account data.

The page uses a fixed three-pane workspace:

- tracked objects define the personalization scope;
- a compact opinion feed applies period, stance, source, and ranking controls;
- the right pane switches between watchlist overview and lazily loaded full text.

Component boundaries:

- `components/TrackingView.tsx` owns filters, selection state, and page orchestration;
- `components/TrackingRail.tsx` renders tracked ticker, author, and narrative collections;
- `components/TrackingFeed.tsx` renders the ranked feed and watchlist overview.

Keep ranking and filtering rules outside presentational components. New tracking
sources should extend the feature model and feed query contract instead of adding
source-specific branches to the page shell.

`/data/tracking-feed/[symbol]` exports a bounded preview pool. Full post or video
content is fetched only after a feed item is opened. Reddit remains a content
source filter, but communities are no longer trackable.
