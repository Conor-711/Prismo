# Opinion Cover Options

Open `opinion-cover-options.html` directly. It is self-contained and works offline.
This is a design comparison, not an iOS implementation or trading client.

- A (revised): two complete circles staggered diagonally, with a smaller neutral
  logo mount overlapping only the edge of the full-color portrait. No extension,
  tinted strip or gray header block. Height is 244 points; photo/logo circles use
  40% / 34% of the canvas width, with neither image enlarged to fill empty space.
- B: equal optical axis, full-color circular portrait and unframed logo.
- C: author-led portrait with a smaller asset seal outside the face.
- All covers contain images only, no author name, ticker, caption or ranking.
- Opens in single-view mode on A; the other two concepts remain available for comparison.
- Author identity, date and asset name appear below the cover; trader count precedes the opinion.
- Includes dark/light themes, three real project examples, grouped/single previews,
  selection via URL hash, pull-to-stretch, trader expansion, original text and text size.
- Trader counts and participants are explicitly labeled layout samples. No live APIs or wallets.

Run `node docs/product/prototypes/opinion-cover-options/bundle.mjs` from the repo root
to rebuild `data.js` and the standalone HTML. Source data comes from the three UUIDs
listed in the bundler, logos/avatars from the existing iOS asset catalog, and icons
from the repository's vendored Lucide build. Photos retain their original colors.

Header titles in the article body are editorial paraphrases for this design preview;
the opinion summaries and original text are preserved from the fixture snapshot.
