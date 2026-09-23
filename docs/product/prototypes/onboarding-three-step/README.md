# bSmart Onboarding Prototype

Open `bsmart-onboarding.html` directly. It is a self-contained offline artifact,
with embedded Lucide icons, project avatars, brand assets and chart data.

Three pages demonstrate discovery, following and a read-only trade preview.
The sidebar (or small profile icon on mobile) opens username-only profile setup.
Theme switching, page navigation, chart nodes, source details, follow state,
notification invitation, amount/leverage preview and profile validation work locally.
No authentication, notification permission, wallet, order or profile API is called.
Only an explicitly clicked source link opens the original X post in a separate tab.
Reloading clears prototype choices; the username check validates format only,
not server-side uniqueness. Photo selection stays in page memory.

Data: the shipped `representative-stories.plist` projection for Serenity
(`@aleabitoreddit` on X) / AAOI; the latest included AAOI update is dated
2026-08-24 from `smart-account-updates.json`. Current rank and profile assets come
from `smart-accounts.json`. The two included bullish nodes are 2026-02-27 / $53.69
and 2026-03-04 / $95.34; the period high is $128.96 on 2026-03-11, through 2026-04-02.
The displayed Chinese summary is a concise paraphrase of that source, not a quote
from bSmart's live API. The quoted sentence is a translation of the original.
Historical price maxima are not investor returns. Chart nodes show at most the
earliest three bullish calls, and close prices are separate from the intraday high.

Build: `node docs/product/prototypes/onboarding-three-step/bundle.mjs` (Node 22;
Python 3 standard-library plist parser).
The builder stops if the selected update changes, so source copy must be reviewed.
The main iOS implementation and existing onboarding flow are not changed here.
