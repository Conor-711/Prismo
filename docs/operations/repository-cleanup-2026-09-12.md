# Repository Cleanup: 2026-09-12

## Scope

Conservative local cleanup requested by the user. Preserve working-tree changes,
current product behavior and all trading-related implementation. No database
writes, deployment, account creation, signing or real transactions.

## Findings Before Cleanup

Sizes are rounded local `du` measurements, not downloadable app size.

| Area | Size | Decision |
| --- | ---: | --- |
| Repository including ignored files | 12 GB | Not all source code |
| `data` | 7.6 GB | Preserve source data and evidence |
| `data/dev.db` | 6.3 GB | Preserve primary database |
| `.git` | 2.4 GB | Preserve history; no pruning |
| `web/out` | 596 MB | Remove reproducible static export |
| `web/node_modules` | 334 MB | Preserve installed dependencies |
| `pipeline/.venv` | 473 MB | Preserve pipeline runtime |
| `roster_tweets_20260727_20260813` | 437 MB | Preserve raw research data |
| `build` | 63 MB | Preserve release archive and dSYMs |
| `ios` | 18 MB | Source/assets are not the main disk cost |

The largest maintainability hotspots include `SmartHubView.swift`,
`TodayView.swift` and `AppModel.swift`. File length alone is not evidence that
functionality is unused. Splitting these active modules is outside this cleanup.

## Changes

1. Ran the existing `make clean` target after checking no project web server was
   using the output. Removed about 596 MB of old static export. The target only
   removes `web/.next-dev`, `web/.next` and `web/out`; it does not remove the DB.
   Local static hosting requires `make site` before use again. No website was
   rebuilt or deployed.
2. Removed 1,310 lines from `TodayEditorialSections.swift` (2,022 to 712 lines).
   Repository reference searches found no callers for `TodayInterludeDeck`,
   `TodayPortfolioNowModule`, `TodayAssetEditorialHero`,
   `TodayPortfolioSnapshotStrip` or `TodaySmartMoneyFeature`. Removed their
   exclusive helpers as well. Active evidence timeline, inline opinion/event
   views, headings, progress and shared chart types remain unchanged.
3. Kept a temporary pre-cleanup source copy at
   `/tmp/bsmart-cleanup-20260912-TodayEditorialSections.swift`. This is a local
   recovery convenience, not a durable repository backup.

## Protection and Verification

- SHA-256 baseline covers 180 files under iOS Trading, Wallet, Account,
  backend accounts/opinion-trades and `supabase/ios-account`. Concurrent work
  changed six existing files and added three, so the protected tree cannot be
  reported as globally unchanged. This cleanup did not edit any of those files
  and does not revert that work. Detected changes: `HyperliquidWithdrawalPreview`,
  `HyperliquidExecutionReader`, `TradingWalletView`, `UnifiedAccountSetupCodec`,
  `HyperliquidWithdrawalRecord`, `HyperliquidWithdrawalStore`; additions:
  `UnifiedAccountSetupStore`, `HyperliquidFlatAccountCheck`,
  `UnifiedAccountSetupView`.
- Primary DB size and modification timestamp remain unchanged:
  6,779,781,120 bytes; modification time 1788623393 (Unix seconds).
- The edited source exactly matches the original with only the three intended
  unused blocks removed. No generated Xcode project change is required.
- `python3 scripts/check_architecture.py`: passed.
- `git diff --check`: passed.
- iOS Simulator build, scheme `bSmart`, signing disabled: completed successfully.
  Build log: `/tmp/bsmart-cleanup-build.log`. No UI screenshots or real trading
  tests were performed; a successful build is not live trading verification.

## Future Cleanup Rules

- Prefer `make clean` for stale web outputs; it is not a database cleanup tool.
- Do not run `make data-clean`, delete snapshot parts, runtime rollback copies,
  raw collections or research reports solely because of their size.
- Do not remove trading, signing, nonce, order persistence, wallet, account,
  privacy or settlement code merely because direct UI callers are absent.
- Keep release archives/dSYMs for symbolication and installed runtimes for
  reproducible development. Changes to retention require a separate decision.
- Require reference checks and a successful relevant build before removing
  presentation code. Preserve unrelated ongoing work.
