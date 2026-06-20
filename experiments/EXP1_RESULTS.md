# Experiment 1 — Forum-signal forward-return predictivity probe (results)

**Date:** 2026-06-19 · **Status:** go/no-go probe complete · **Data:** `data/prismo_snapshot.db` (Reddit us, snapshot of cloud) + yfinance prices (cached `experiments/prices_cache.json`)
**Script:** `experiments/exp1_fwd_return_probe.py` · **Design doc:** `DECISION_equity1000_port.md`

## What this is / isn't
Ports equity1000's **validation methodology** (forward-return correlation by horizon + regime/bucket separation + shuffle-null discipline) to Prismo forum data, run **cross-sectionally** because the cloud has only ~6 weeks / ~10 dense US days — far too short for equity1000's 60–90d rolling regime engine. **Hypothesis-generating only. Not a backtest. Not validated alpha.**

## Setup
- Universe: dense US single-names **NVDA, GOOGL, TSLA, AMZN, MSFT** (SPCX leads mentions but is pre-IPO → no price → excluded). SPY = beta benchmark.
- 6 signals per (ticker, ET-session-day), recomputed from raw `mentions ⋈ posts ⋈ item_analysis` (NOT `ticker_rollup`): `attention_share, raw_dir, mean_sentiment, qw_dir (quality-weighted direction), engagement, consensus_entropy`.
- Stance COALESCEd (`bullish→bull`, `bearish→bear`). Entropy gated at stance-n≥8. Cell inclusion n≥5.
- **Leak controls (added after an adversarial code audit found a critical look-ahead):** (1) `item_analysis` is a *batched* AI pass (analyzed_at lags created_utc 0–2d) → **entry lagged to next trading day (D+1)** so the overnight batch is available; as-of filter drops posts analyzed after D+1. (2) **ET session date** (UTC−4), not UTC date, to avoid misanchoring after-hours posts.
- Forward return = `close[D+1+N]/close[D+1] − 1`, **SPY-relative**, N∈{3,5}. Adversary = **1000× shuffle null** (+ a day-block-permutation null for the within-day check).

## Headline result
**Pre-registered verdict: NO-GO** — but only because per-ticker sign-consistency is unevaluable (each name has just 2 clean anchor days). The signal content is **more interesting than NO-GO suggests:**

Pooled N=3 (n=10), SPY-relative:
| signal | r | shuffle-null pct | p (1-sided) |
|---|---:|---:|---:|
| **qw_dir** | 0.72 | **97.8%** | 0.022 |
| **raw_dir** | 0.68 | **96.3%** | 0.037 |
| mean_sentiment | 0.60 | 93.7% | 0.063 |
| engagement | 0.51 | 89.8% | 0.102 |
| attention_share | 0.34 | 63.5% | 0.365 |
| consensus_entropy | −0.34 | 59.0% | 0.410 |

**Robustness — within-day demeaned (removes the "which day" effect, day-block null):** the direction/sentiment family *survives*:
| signal | within-day r | null pct | p |
|---|---:|---:|---:|
| **qw_dir** | 0.81 | **98.7%** | 0.013 |
| **mean_sentiment** | 0.73 | **96.1%** | 0.039 |
| **raw_dir** | 0.71 | **95.6%** | 0.044 |
| attention_share | 0.40 | 71% | 0.289 |
| engagement | 0.45 | 81% | 0.187 |
| consensus_entropy | −0.26 | 45% | 0.547 |

**Read:** Among mega-caps discussed on the same day, the one with more **quality-weighted-bullish** forum direction tended to outperform over the next 3 days. It's the *what-people-think* family (direction × post quality), **not** the *how-much-they-talk* family (attention/engagement/volume), that carries the signal. Squeeze/meme stratification is inconclusive (r≈0.77 both sides, n=4–6 — noise).

## Why this is NOT trustworthy yet (load-bearing caveats)
1. **2 effective anchor days** (06-10, 06-15), 5 **co-moving** mega-caps → tiny, non-independent sample. p≈0.01–0.04 is real *within this sample* but cannot generalize.
2. **N=5 unevaluable** — entry-lag pushes the window past available prices (US data ends 06-15).
3. **Contemporaneous-continuation confound** — "next 3 days" may extend an in-progress move that also drove the bullish posting (signal may be coincident, not leading).
4. **Single un-calibrated LLM tagging** — `item_analysis` is both ground truth and signal; a 50–100 post hand audit should precede trusting stance/sentiment.
5. **Attention is selection-biased** (post-first universe never sees silently-crashing names).
6. Earlier leaky run (n=24, no entry-lag) inflated estimates ~2–6%; the audit caught it.

## Recommendation / next steps
- **Do NOT build the rolling regime engine yet** (confirmed). But the gating question now has a *specific, leak-free, robustness-checked candidate*: **cross-sectional quality-weighted direction → 3-day relative return.** Track it.
- **Accrue ≥60 daily obs** (keep the pipeline running) → re-run as a true time-series panel; only then the equity1000 regime/percentile machinery becomes computable.
- **Broaden the cross-section** beyond 5 co-moving mega-caps (more names per day = more independent within-day dispersion = the cleaner test) — needs more ticker coverage per day.
- **Hand-audit LLM stance** on ~100 posts before trusting direction.
- Re-run this exact harness weekly; it's the reusable substrate.
