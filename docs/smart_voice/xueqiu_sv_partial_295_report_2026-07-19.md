# Xueqiu SV Partial 295-Author Run

> Superseded by `xueqiu_sv_expanded_295_evidence_2026-07-19.md`; retained only as the pre-expansion 12-author intermediate result.

Run date: 2026-07-19
Pool version: `xueqiu-sv-pool-20260710-v2`
Scoring population: 295 completed creators out of 300 selected creators

## Scope

This is a frozen partial-pool calculation requested before the remaining five creator crawls completed. Candidate recall and scoring only include selected creator jobs whose crawl status is `done`. The result is suitable for local evaluation, but must remain labelled `295/300 partial` until the full pool is available.

## Funnel

| Stage | Posts / authors | Result |
|---|---:|---|
| Completed creator crawls | 295 authors | Five selected creators excluded |
| US-equity candidates | 3,199 / 209 authors | One-year range: 2025-07-11 to 2026-07-10 |
| Author-balanced extraction sample | 2,098 / 209 authors | Per-author budget: 20 minimum, 80 maximum where available |
| Actionable calls | 428 / 110 authors | 321 bull, 107 bear |
| Settled call-horizon rows | 1,054 | 1,154 additional rows remain pending |
| Scored authors | 105 | Authors with usable settled evidence |
| Formally qualified authors | 12 | `n_eff >= 5` and `settled_calls >= 8` |

The 86 completed creators without a recalled US-equity candidate and the 99 candidate authors without an actionable investment call are intentionally not assigned a synthetic score.

## Qualified Ranking

Ranking uses Xueqiu `SV_Platform`. `SV_Global` is the confidence-adjusted cross-platform representation and is not the platform ranking field.

| Rank | Author | SV Platform | SV Global | Confidence | n_eff | Settled calls | Tickers | Main ticker | raw_z |
|---:|---|---:|---:|---|---:|---:|---:|---|---:|
| 1 | 永不褪色的信笺 | 115 | 110 | low | 67.4 | 32 | 9 | NVDA | 0.866 |
| 2 | 熊猫Ming | 109 | 103 | observing | 17.8 | 11 | 5 | MU | 0.942 |
| 3 | 正因不完美而完美 | 108 | 103 | observing | 15.7 | 12 | 8 | MU | 0.560 |
| 4 | 投研魅励 | 106 | 102 | observing | 13.6 | 8 | 4 | MU | 0.450 |
| 5 | Lynne927 | 100 | 100 | low | 30.8 | 17 | 5 | MU | 0.205 |
| 6 | 李团长复盘 | 100 | 100 | observing | 9.2 | 13 | 5 | MU | 0.224 |
| 7 | Charles_Capital | 97 | 99 | observing | 20.6 | 10 | 5 | TSM | 0.065 |
| 8 | 陆家嘴幽灵 | 95 | 98 | observing | 18.2 | 14 | 8 | GOOGL | -0.028 |
| 9 | 股市马斯克 | 94 | 96 | low | 40.7 | 18 | 5 | QQQ | -0.079 |
| 10 | 阿企笔记 | 93 | 95 | low | 10.6 | 23 | 8 | META | -0.091 |
| 11 | 摩拉克思 | 92 | 97 | observing | 6.8 | 10 | 7 | NVDA | -0.161 |
| 12 | 大局观市 | 81 | 93 | observing | 7.0 | 8 | 4 | AMD | -0.629 |

## Interpretation Limits

- Qualification and confidence are separate. Qualification controls platform ranking eligibility; confidence controls how strongly `SV_Platform` deviates from 100 when converted to `SV_Global`.
- Only 12 authors currently qualify, so percentile groups are statistically thin and should not yet be presented as a mature Xueqiu leaderboard.
- Pending settlements will mature over time and can change scores without any new post collection.
- The five incomplete creator jobs are excluded from candidate recall and scoring rather than treated as authors with zero performance.
