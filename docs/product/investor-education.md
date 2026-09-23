# Investor Education

Updated: 2026-09-15.

## Scope

The homepage keeps its existing investor controls, manual avatar queue, focus,
sector selection and following state. One compact entry shares the discovery
heading row, labeled "Questions about the rankings?" / "对排名有疑问？".
The entry no longer loads population data. `BSmartDetailNavigationLink` presents the separate native page with
the shared zoom transition. `bSmartDetailPage` owns tab visibility and back handling.
The page does not change rankings, trading, data refresh or the build number.

## Copy And Evidence

The education flow answers three newcomer questions: whose ideas are worth my time,
what did they spot before, and what will following them give me?
It uses concrete stock performance instead of algorithm terminology. The hero
displays 1000+ for the actual 1,283-person X observation pool. The platform selector switches
to 300 YouTube or 192 Reddit authors, with corresponding portraits and follow lists.
The selector order is YouTube / X / Reddit; X is the centered default.
Exact underlying counts remain in the records disclosure. These are the
latest local published observation-pool counts: the 2026-09-05 SQLite score run,
smartVoice export and education snapshot agree. Raw channel candidate pools and
available portrait counts are not substituted for this denominator.
The hero reads "Investing. Who should you follow?" / "投资，该追踪谁？",
with its original platform description. The previously removed small helper copy stays removed.
The bSmart comparison helper, qualified-ranking caption and tiny case footer are
removed; the historical-example qualification is inside the existing closed
records disclosure, rather than a persistent caption below the example.
Formal ranking and Top 25% denominators remain distinct and platform-specific:
X 234/58, YouTube 88/22, Reddit 31/7. Live recommendations and the existing directory
are filtered to the selected platform; only the published Top 25% is recommended.
The selected historical case stays explicitly attributed to X/Wey How.

Only a selected positive case is featured. Wey How's SNDK post, ID
1987365274408874017, was published on 2025-11-09 UTC. Its existing settlement is
2025-11-10 to 2026-02-05, $247 to $576.20, +133.28%, with positive contribution
1.240507433756185. The records disclosure says this is a selected positive historical example,
not typical performance, a first-ever call, actual account profit or a guarantee.
The original source is directly accessible. The Chinese sentence is a paraphrase,
not a fabricated quotation. The October MU tagging gap is not relabeled or scored.

Writing principles: put the user's purpose first, use understandable headers and
actions, and keep explanation in context. Applied from Apple's
[Writing for interfaces](https://developer.apple.com/videos/play/wwdc2022/10037/)
and NN/G's [Onboarding tutorials vs. contextual help](https://www.nngroup.com/articles/onboarding-tutorials/).
This intentionally requested education surface contains educational copy; the
homepage receives only the entry, not additional explanatory captions.

## Offline Artwork

`scripts/build_investor_education_assets.mjs` reads `data/dev.db` in read-only mode,
matches stable author IDs to each observation pool, reuses bundled portraits, and fetches
remaining public CDN images with bounded concurrency. It honors an existing HTTPS
proxy or the user's active macOS HTTPS proxy. It never opens or purchases accounts.
Requires Node 22 and `sharp` (locally resolvable or via `SHARP_PATH`).

Bundled avatar coverage after additional public-profile retrieval:

| Platform | Observed authors | Local avatars before enrichment | Local avatars now |
| --- | ---: | ---: | ---: |
| X | 1,283 | 881 | 881 |
| YouTube | 300 | 169 | 295 |
| Reddit | 192 | 13 | 113 |

`scripts/resolve_investor_education_avatars.mjs` resolves missing YouTube portraits
from public channel metadata, requiring exact channel ID matches even after handle
changes. It writes `investor-education-profiles.json`, including failures. Reddit
enrichment uses explicitly labeled `u/handle avatar` links on public profile pages,
recorded in `investor-education-reddit-profiles.json`; some are search-index snapshots,
not a claim of live freshness. Direct Reddit JSON requests were blocked. The public
original image is used when a cached CDN transformation signature is expired.
Reddit-provided default avatars are kept only when verified on that specific profile.

The 5 remaining YouTube and 79 remaining Reddit profiles have no downloaded, verified
avatar in this bundle. They are not filled with substitute faces. Portrait counts
are disclosed separately from observed author counts; all missing IDs are recorded
per platform in the generated provenance. Ranking coverage is not changed by avatar
availability. First recommendations prefer portraits within the published Top 25%.

The compressed 64px tile atlas is 1,619,518 bytes and has 21,495,808 bytes of decoded
RGBA pixels, excluding view and crop bookkeeping. No duplicate identities fill slots.
The image and curated snapshot are in `ios/BSmart/Resources/InvestorEducation*`;
`ios/asset-sources/investor-education.json` preserves URLs, identities and failures.
The plist is intentional: InternalAlpha excludes JSON resources. This historical
education snapshot is independent of the live ranked recommendations below it.

The page loads artwork on demand, not on the homepage. It uses a single atlas,
cached tile images, asynchronous Canvas drawing and one-shot animations. There is
no timer or automatic carousel. Reduce Motion disables movement. The existing
adaptive palette handles light mode. Swift Charts supplies native chart selection.

## Files And Verification

- `Core/Models/InvestorEducationSnapshot.swift`: typed offline snapshot validation.
- `Core/Data/InvestorEducationArtwork.swift`: bundled atlas access and tile decoding.
- `Features/InvestorEducation/`: entry, page, animated portrait pool, positive case.
- `InvestorEducationTests`: per-platform identities, coverage floors, asset budget, settlement consistency.
- `InvestorEducationUITests`: platform switching, entry, reveal, filter and return; Chinese/dark and English/light.
- `output/design/investor-education/`: self-contained HTML, generator and browser checks.

The HTML uses the same case and atlas, with platform switching and a homepage
entry preview. It is a design artifact, not an iOS WebView or backend source.

2026-09-12 verification after three-platform enrichment: simulator build succeeded;
4 resource/platform/settlement unit tests and 2 Chinese-dark/English-light UI flows
passed on iPhone 16 / iOS 18.5. The UI flows switch X/YouTube/Reddit and verify
population changes, the positive case, manual filtering, and return to the homepage.
HTML checks passed at 320, 390, 768 and 1440 px, including canvas pixels, the
positive-only case, platform switching, manual filtering, following and return.
Desktop headless Chrome at a 390px viewport measured ~16.8ms P95 frame intervals
during portrait filtering; this is not an iPhone hardware performance guarantee.
No TestFlight upload or backend deployment was performed.
