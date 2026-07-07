# Reddit Smart Voice First Run Report

Date: 2026-07-07

## Scope

This is the first Reddit-only SV run after expanding the Reddit author history pool.

- Author-pool gate: relaxed from `10` to `8` ticker-relevant Reddit posts.
- Candidate author pool: 288 authors used in recall.
- Recalled Reddit candidates: 11,003 posts.
- Structured Reddit calls written: 2,580.
- Actionable Reddit calls: 1,154.
- Reddit authors covered by structured extraction: 287.
- Reddit authors with settled SV score: 257.
- Remaining pending Reddit candidates: 8,423.

The extraction was stopped after Qwen returned account-side `Access denied` errors near the end of the second extraction batch. Already committed rows were kept and used for this first run.

## Is 258 Authors Enough?

Yes, 258 authors is enough for a first Reddit SV MVP because it gives a meaningful cross-author distribution instead of a small hand-picked sample. But it is not enough by itself to produce high-confidence SV if each author only has a few settled calls.

After relaxing the threshold to `8`, the recall pool expanded from 258 authors to about 288 eligible authors. This is a reasonable first-run compromise:

- It still excludes thin authors with only 1-7 ticker-related posts.
- It adds coverage without returning to low-confidence long-tail noise.
- It keeps the minimum evidence requirement above the "at least 3" floor.

## Score Distribution

All Reddit authors are currently still in `observing` confidence. The global SV range is therefore intentionally narrow because the platform score is shrunk by confidence.

| SV bucket | Authors |
|---|---:|
| <92 | 2 |
| 92-94 | 9 |
| 95-97 | 24 |
| 98-100 | 136 |
| 101-103 | 86 |

Summary:

- Min SV: 90
- Median SV: 100
- Max SV: 103
- Confidence: 257 observing / 257 total

## Data Quality

| Metric | Value |
|---|---:|
| Structured calls | 2,580 |
| Actionable calls | 1,154 |
| Bull calls | 962 |
| Bear calls | 192 |
| Settled Reddit calls | 1,122 |
| Settlement rows | 3,821 |
| Settled authors | 257 |

Settled call depth per author:

| Settled calls per author | Authors |
|---|---:|
| <4 | 101 |
| 4-7 | 128 |
| 8-14 | 28 |
| 15+ | 0 |

This is the main reason the first-run scores are conservative. The author pool is broad enough, but per-author extraction depth needs to grow before Reddit SV can move from observing to medium/high confidence.

## Content Mix

Actionable Reddit calls by investor style:

| Investor style | Calls |
|---|---:|
| Fundamental | 471 |
| Event driven | 409 |
| Technical | 127 |
| Flow / momentum | 60 |
| Mixed | 50 |
| Macro | 18 |
| Unknown | 19 |

Actionable calls by horizon:

| Horizon | Calls |
|---|---:|
| 90D | 324 |
| 60D | 201 |
| 180D | 175 |
| 20D | 165 |
| 5D | 117 |
| 1D | 87 |
| Unknown | 85 |

## Top 10 Reddit SV Authors

Because all authors are still observing, many top authors tie at SV 103. The meaningful difference is in their raw platform SV, n_eff, coverage, and ticker concentration.

| Rank | Author | SV | Platform SV | Raw Platform SV | n_eff | Settled calls | Main tickers | Reason |
|---:|---|---:|---:|---:|---:|---:|---|---|
| 1 | TOPS-VIDEO | 103 | 109 | 124 | 17.35 | 6 | TQQQ | Strong short-horizon TQQQ outcomes, but still capped by single-ticker concentration and observing confidence. |
| 2 | Rose-n-Chosen | 103 | 109 | 114 | 16.40 | 8 | SPCE, RKLB, PL, LUNR | Event-driven space basket calls performed well enough across several tickers, but active days are concentrated. |
| 3 | NumerousFloor9264 | 103 | 109 | 118 | 15.49 | 8 | TQQQ, RKLB | Mixed setup calls show positive short-term contribution, with moderate ticker breadth. |
| 4 | tomato241 | 103 | 109 | 137 | 13.78 | 8 | RDDT | Strong raw platform score, but highly concentrated in RDDT and one active day, so capped. |
| 5 | StrikingNobody5894 | 103 | 109 | 114 | 12.39 | 5 | SPCE | Event-driven calls benefited from favorable path returns, but sample is thin and concentrated. |
| 6 | aresna33 | 103 | 109 | 132 | 12.25 | 9 | ELF | Fundamental calls show high raw platform score, but single-ticker concentration limits global SV. |
| 7 | UNCLEJASSY | 103 | 109 | 116 | 12.06 | 8 | APLD, AMD, NBIS, NEXT | Better ticker breadth than most top names; event-driven calls are the main source of positive contribution. |
| 8 | ThetaHedge | 103 | 109 | 109 | 11.27 | 5 | SEDG, KTOS, RKLB, FLNC | Broad event-driven coverage, but only 5 settled calls. |
| 9 | alpha247365 | 103 | 109 | 109 | 11.26 | 9 | QQQ, TQQQ, SOXL | Technical ETF calls are positive on short horizons, but concentrated in leveraged index exposure. |
| 10 | No_Turnip_1023 | 103 | 108 | 108 | 9.95 | 6 | NVDA, GOOGL, TSLA | Fundamental calls have modest positive contribution across large-cap tech names. |

## Bottom 10 Reddit SV Authors

| Rank | Author | SV | Platform SV | Raw Platform SV | n_eff | Settled calls | Main tickers | Reason |
|---:|---|---:|---:|---:|---:|---:|---|---|
| 248 | Available-Adagio6197 | 94 | 82 | 82 | 9.18 | 5 | NVDA, SPCE | Negative short-horizon outcomes, especially in concentrated high-volatility names. |
| 249 | RequirementSalty197 | 94 | 84 | 84 | 6.97 | 10 | FIG, UMAC | Repeated calls had weak early-window performance despite enough call count for observing. |
| 250 | self-fix2 | 94 | 84 | 84 | 6.81 | 5 | HBM, NVDA, SMCI | Fundamental semi calls had negative short-window contribution. |
| 251 | mojolakota | 93 | 80 | 80 | 13.18 | 8 | GOOGL, NVDA, GOOG, MSFT | Large-cap fundamental calls underperformed benchmark on the settled windows. |
| 252 | dxiao | 93 | 80 | 80 | 10.73 | 6 | NVDA, GRRR | Concentrated calls produced weak 5D/20D scores. |
| 253 | Soft-Dragonfly7929 | 93 | 81 | 81 | 7.94 | 6 | SPCE | Event-driven SPCE calls had poor endpoint outcomes despite some favorable path movement. |
| 254 | Scenari01 | 92 | 78 | 78 | 11.09 | 7 | XLF | Technical calls were concentrated and weak across 1D/5D/20D windows. |
| 255 | saboteursolotario | 92 | 78 | 78 | 9.31 | 7 | UPST, MU | Mixed macro/technical calls produced negative short/mid-window contribution. |
| 256 | East-Chance-6402 | 91 | 75 | 75 | 11.44 | 8 | UPST | Highly concentrated UPST calls were weak across all horizons. |
| 257 | HomeHedgeFund | 90 | 70 | 70 | 14.34 | 8 | BYND, MU, PLTR, HOOD | Worst first-run raw platform score; multiple calls underperformed despite broader ticker coverage. |

## Ticker-Level Notes

Most frequent settled Reddit call tickers:

| Ticker | Settled rows | Bull | Bear | Avg excess return | Avg max favorable excess |
|---|---:|---:|---:|---:|---:|
| NVDA | 230 | 193 | 37 | -1.42% | 2.60% |
| TQQQ | 218 | 173 | 45 | 6.53% | 8.59% |
| SPCE | 152 | 110 | 42 | -21.64% | 5.67% |
| QQQ | 130 | 81 | 49 | 1.06% | 1.16% |
| GOOGL | 113 | 102 | 11 | 3.01% | 5.78% |
| MSFT | 98 | 58 | 40 | -3.02% | 2.66% |
| MU | 94 | 80 | 14 | 10.60% | 13.06% |
| TSLA | 82 | 51 | 31 | -1.24% | 7.45% |
| PLTR | 77 | 59 | 18 | -7.26% | 6.42% |
| META | 77 | 62 | 15 | -1.88% | 6.00% |

## First-Run Conclusion

The first Reddit SV run is usable as an MVP signal layer, but it should be labeled conservative / observing.

Key interpretation:

- Author count is sufficient after relaxing the gate to `8`.
- Score confidence is not sufficient yet because per-author settled calls are still thin.
- The ranking can show early relative signals, but should not be treated as final production-quality Reddit SV.
- Next run should continue extracting the remaining 8,423 candidates in smaller batches or switch to a more reliable batch LLM path.
