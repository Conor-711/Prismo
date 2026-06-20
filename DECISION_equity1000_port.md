# Decision Document — Porting equity1000's Mindshare/Regime Methodology to Prismo

**For:** Prismo data-layer owner
**From:** Research lead (synthesis of 4 role reports + 4 cross-reviews)
**Date:** 2026-06-19
**Status:** Recommendation for one runnable-this-week experiment, plus a port map and signal set.

All "measured" numbers below were re-verified live against `data/prismo_snapshot.db` this session, not taken on faith from the reports.

---

## 0. The one-paragraph answer

equity1000 is two machines bolted together: a **signal-construction front-end** (per-ticker daily time series → 60–90d rolling z-scores / expanding percentiles / EMA / Gaussian smoothing → a 5-state regime label) and a **validation back-end** (forward-return Pearson by horizon, regime-conditional return separation, shuffle/permutation discipline, look-ahead-safe `shift(-N)`). **The validation back-end ports cleanly and is worth doing now. The signal-construction front-end does not fit the data we have** — Prismo's cloud has ~10 dense US days (06-05→06-15), and you cannot fit a single 60-day window on that. So the honest first move is to port the *validation methodology* and run it **cross-sectionally across ticker-days** to answer one gating question: *does any Prismo forum signal carry forward-return information at all?* Everything else (the rolling regime engine, the cross-region divergence layer, author/KOL weighting) is blocked on data that doesn't exist yet and should be sequenced after history and the multi-region forum tables land.

All four specialists and all four reviewers independently converged on this. That convergence is the strongest evidence it's right.

---

## 1. PORT MAP

### 1A. Ports cleanly (do this)

| equity1000 method | Maps to Prismo via | Note |
|---|---|---|
| **Forward-return Pearson by horizon** (`01_correlation_analysis.py`): `r(signal[t], fwd_ret_Nd[t])`, min-n gating, `shift(-N)` to kill look-ahead | Source-agnostic. Signal vector swaps Twitter metrics → Prismo columns; prices come from yfinance instead of the internal cache | The single most portable piece. Run it **pooled cross-sectionally over ticker-days**, not per-ticker-over-time |
| **Regime/bucket-conditional return separation** (`02_regime_return_analysis.py`): stratify forward returns by a discrete state, report mean/median/win-rate | Stratify by **signal terciles or median-split** instead of named regimes (too little history for regimes) | "Does state X separate forward returns" logic is identical; needs no rolling window |
| **Look-ahead-safe forward returns**: `fwd_ret = price.shift(-N)/price - 1` | Ports verbatim; prices from yfinance aligned to UTC post-days | |
| **Min-observation gating + OMIT-not-zero doctrine** | Essential given Prismo's thin tail — a 1–2 mention ticker-day must be dropped, not zero-filled | From both `add_forum_mindshare.py` and the n>20/n>50 thresholds |
| **Shannon entropy as a direction-independent consensus measure** | Computable today from `item_analysis.stance` (3-bucket bull/bear/neutral) | The *raw* value is computable; the `entropy_ma7` rolling/percentile-gated version is deferred |
| **Per-region NON-BLEND + breadth-only doctrine** (`add_forum_mindshare.py`) | Already correct for Prismo's `posts.market` us/cn split | The one piece equity1000 *literally wrote to consume Prismo's export*. Keep it — but see 1C on why cross-region can't be *tested* yet |

### 1B. Ports only with substantial adaptation

| equity1000 assumption | Why it breaks on Prismo | Adaptation |
|---|---|---|
| **Fixed 12,400-person circle** normalizes `penetration_rate` | Prismo is **post-first**, has no universe denominator and no follower circle | Use **relative attention**: weighted-mention market-share within the day (`mindshare` logic from `rollups.py`), recomputed per day from raw. Drop the circle constant entirely |
| **Per-ticker 60–90d rolling z-scores / expanding percentiles / EMA / causal Gaussian σ=2** | Only ~10 dense US days exist (measured: US posts start 06-05, real density 06-06→06-15). A 60d window cannot fit; expanding percentile with `min_periods=14` yields **zero valid rows** for every US ticker | Pivot to a **cross-sectional panel of ticker-days**. Defer all rolling/percentile machinery until ≥60–90 days of daily history accrue |
| **Direction = rolling z-score / expanding percentile of `(bull_ratio − bear_ratio)`** | The z-score/percentile *wrapper* needs history we lack | Keep the **raw core** `raw_dir = (bull − bear) / total` (computable today). Defer the normalization layer |
| **Smart-engagement gate `se_z60`** = retweet-graph weighted KOL interaction | Forums have no retweet graph | Replace with **content/venue weight** = `quality_score × subreddit_weight × (1+ln(1+score))`. See 1C — this is NOT a person-influence proxy |
| **Sentiment bucketed at 0.6/0.4** (Twitter LLM, 0..1 scale) | Prismo `item_analysis.sentiment_score` is **−1..1** (verified MIN=−1.0, MAX=1.0). Bucketing −1..1 at 0.6/0.4 would label the entire negative half + mild positives as "bear" — a silent units bug that inverts entropy/direction | Use `item_analysis.stance` (already a 3-class label) directly, after the COALESCE fix below |
| **`tag_retail.py` 10-signal retail-concentration score** | 6 of 10 signals need price/volume/fundamentals not in cloud | Only the social half (mention volume, sentiment extremity) + theme membership (`item_analysis.themes[]`) is computable now. Treat the rest as a yfinance/fundamentals-dependent extension |

### 1C. Does NOT transfer (and why) — be honest about these

1. **Smart-follower / KOL weighting (the single most predictive equity1000 family).** There is no follower graph. **Measured: `authors.comment_karma` and `authors.link_karma` are 0 for all 9,767 authors** (the author-library crawl never ran; `crawled_at` is NULL everywhere). So `sf_weighted`, `tier(SF≥500)`, `sq_avg_smart_follower`, `se_z60` have **no working analog**. The "credible-voice" substitute (`voice_weight`) that NLP proposed collapses — with karma off and the verified-holder flag off — to exactly `quality_score × subreddit_weight × (1+ln(1+score))`, which is the same content/venue weight everyone else proposes under simpler names. **Do not market this as a KOL substitute; it is a quality filter, and its incremental value over raw counts is itself unproven.** True influence weighting requires the author crawl to run first.

2. **The rolling regime classifier itself** (`classify_v20` / `classify_lowliq`, `att_60d`, `vel_zscore`, `dir_smooth`, `entropy_ma7`, `sent_pctile`, the v25/v26/v27 paths). Every one of these is a function of a long daily series. **Not computable on ~10 days.** This is deferred, not adapted — pretending otherwise produces all-NaN or degenerate output.

3. **Cross-region consensus/divergence as a *regional* signal.** **Measured: only 6 tickers carry both us≥10 and cn≥5** (BABA us=11/cn=314, NVDA 148/20, GOOGL 135/17, TSLA 86/18, AMZN 73/10, 2020.HK 15/15). Critically, **`cn` is Reddit-scraped, not Xueqiu**, and is filtered to the curated `ticker_meta.market='cn'` dictionary. So "us-vs-cn divergence" measures *dictionary-curation differences within one English-Reddit corpus*, not two independent regional crowds. The real JP/KR/TW/Xueqiu forum tables (`asia_*`, `gr_*`) **do not exist in the snapshot or cloud** (verified: no such tables). The non-blend/breadth doctrine is correct *architecture* to keep — but the cross-region *signal* is untestable and should be a hard NO-RUN until those tables are persisted.

4. **`posts.upvote_ratio` as a consensus/disagreement axis.** **Measured (US): mean 0.979, 4,411 of 4,740 posts (93%) exactly 1.0, only 221 (4.7%) below 0.9.** Reddit vote-fuzzing has crushed it to a spike at 1.0. Behavioral's Miller-disagreement proxy (`1 − mean(upvote_ratio)`) and NLP's `crowd_entropy`/`agreement` axis both have **near-zero cross-sectional variance** and cannot rank tickers. This is the single largest unfounded claim in the role reports — drop every upvote_ratio-derived signal.

5. **Intraday velocity ratios (24h/7d/30d)** from `add_30d_kol_mentions.py`. Prismo `created_utc` is sec-level but volume is far too thin for intraday buckets. Daily only.

---

## 2. Forum-data-specific signal set worth building

These are the signals to **pre-register** for the experiment. All are computed **per (ticker, day) from raw `mentions JOIN posts JOIN item_analysis`** — never from `ticker_rollup` (see feasibility note below). All require the stance COALESCE fix first.

| Signal | Computation (Prismo columns) | equity1000 analog |
|---|---|---|
| **attention_share** | `Σ confidence·(1+ln(1+posts.score))·subreddit_weight` for the ticker that day ÷ same summed over all tickers that day. Columns: `mentions.confidence`, `posts.score`, subreddit weight (from `subreddits.yml`/`subreddits` table), grouped by `substr(created_utc,1,10)` | `penetration_rate` (look-ahead-free, no fixed circle) |
| **raw_dir** | `(bull − bear) / (bull + bear + neutral)` from `item_analysis.stance` joined to mentions per ticker-day. Range ≈ [−1,1] | `filt_bullish_ratio − filt_bearish_ratio` (un-normalized core) |
| **mean_sentiment** | `AVG(item_analysis.sentiment_score)` over the day's mentions (−1..1 scale) | `filt_sentiment_avg` / `product_sentiment` (pre-normalization) |
| **quality_weighted_dir** | `Σ(stance_sign · quality_score) / Σ(quality_score)`, stance_sign ∈ {+1 bull, −1 bear, 0 neutral}. Columns: `item_analysis.stance`, `item_analysis.quality_score` | Quality/venue substitute for smart-engagement-weighted direction (NOT a follower proxy) |
| **engagement** | `Σ(posts.score + posts.num_comments)` over the ticker's posts that day | `smart_engagement` / `daily_se` (venue-quality-weighted, not retweet-graph) |
| **consensus_entropy** | Shannon `−Σ pᵢ·log₂(pᵢ)` over `[bull_frac, bear_frac, neutral_frac]` from `item_analysis.stance`. **Gate to ticker-days with stance-n ≥ 8** | `entropy_ma7` (raw, un-smoothed) |
| **squeeze_flag** *(stratifier, not a continuous signal)* | `item_analysis.themes` contains `逼空` or `Meme`. **Measured: 481 posts carry it** | Pre-labels the short-sale-constraint cohort for free |

**Mandatory pre-aggregation fix (the stance bug):** `item_analysis.stance` has **3770 neutral / 1245 bull / 842 bear PLUS 23 'bearish' / 2 'bullish'** (verified). `rollups.py` matches only `'bull'`/`'bear'`, so those 25 rows are currently mis-bucketed into `neutral_count` in the materialized rollup. **COALESCE `bullish→bull`, `bearish→bear` (e.g. `lower(stance) LIKE 'bull%'`) before any ratio/entropy computation.**

**Signals explicitly excluded from the build** (measured-dead or non-computable now): anything from `upvote_ratio` (degenerate); `att_pctile`/`dir_pctile`/`sent_pctile` via expanding percentile + EMA + Gaussian (need ≥14-day series — yields zero valid rows); cross-region divergence/breadth (cn is not an independent region); any karma-weighted "voice"/KOL term (karma = 0).

---

## 3. THE RECOMMENDED FIRST EXPERIMENT

**Cross-sectional forward-return predictivity probe on Reddit US single-names.** This is the design all four specialists converged on, with the three reviewer-verified corrections folded in (recompute-from-raw not rollup; 4-name dense core not 7; T+3/T+5 horizons not T+7/T+14). It is a **methodology go/no-go + effect-size probe — explicitly NOT a backtest and NOT validated alpha.**

### 3.1 Setup (one-time)
- **DB:** `data/prismo_snapshot.db` (present, 25 MB, contains us+cn Reddit only). **No `.env` exists in this checkout** (verified) — the cloud path is unavailable; use the snapshot. It is current through 06-16.
- **Deps:** fresh venv, `pip install yfinance pandas scipy numpy` (verified: none currently installed — this is a real setup step, not a one-liner to gloss).

### 3.2 Universe (verified by direct query)
- **Primary (dense core): NVDA, GOOGL, TSLA, AMZN.** These are the *only* US single-names clearing `≥8 mentions on ≥5 distinct days` in 06-06→06-15 (SPCX also clears but is pre-IPO with no yfinance price). Verified counts: NVDA 9 days, GOOGL 7, TSLA 6, AMZN 5.
- **Secondary (wider/thinner tier, report separately): +MSFT, HOOD, MU, AVGO, RKLB, META, AMD, ADBE, ORCL, ASTS, NBIS, GOOG** — single-names with ≥20 total mentions in the window. ~16 names total. Treat as a robustness check, not the headline.
- **Controls only (NOT predicted): SPY, QQQ, VOO** — for market-beta stripping.
- **Hard-exclude: SPCX** (pre-IPO, no price; it is 814/4,740 ≈ 17% of US mentions and would silently break the join or bias the universe) and all ETFs from the predicted set.

### 3.3 Signals
Recompute the six signals from §2 **from raw `mentions JOIN posts (source='scan') JOIN item_analysis`, COALESCE bullish/bearish first**, grouped by `(ticker, substr(created_utc,1,10))`. Each signal is timestamped at `created_utc` (point-in-time).

### 3.4 Returns (yfinance)
- Pull daily closes for the 4 dense names + SPY over **2026-06-04 → 2026-06-19** (covers signal days + the forward window; prices through ~06-19 exist as of today).
- `fwd_ret_Nd = close.shift(-N)/close − 1` for **N ∈ {3, 5}** only. **Do NOT use N=7/14/30** — US data ends 06-15, so a clean non-overlapping T+7 cannot exist on a ~10-day span (verified: the prompt's 05-03 start is CN-only; US starts 06-05).
- Compute the **SPY-relative** version `fwd_ret_Nd − SPY_fwd_ret_Nd` to strip market beta (the `analyze_earnings_drift.py` rel-drift trick) — essential because a single mid-June week is dominated by market beta.
- cn names are out of scope for this experiment (no independent-region claim; ADR vs `.HK`/`.SS` suffix mapping would silently drop rows). US-only keeps it honest.

### 3.5 The look-ahead guard that matters most (verified, and it reshapes the design)
**`item_analysis` is a batched AI pass, not a streaming one.** Verified: analysis dates are 06-10 (2,571 rows), 06-11, 06-13, 06-14, 06-15, 06-16 — and the **06-10 batch covers posts created from 05-03 through 06-10**. `analyzed_at` never precedes `created_utc` (so there's no negative-lag look-ahead), but for backtest realism the *signal was not computable in production until its analysis batch ran*.

**Decision:** restrict signal anchor dates to **06-10 → 06-12**, where `created_utc` and the analysis batch are plausibly contemporaneous. This (a) removes the batch-contamination concern the behavioral reviewer correctly raised, and (b) still leaves room for T+3 (and T+5 as a stretch) within the price data. Pool signals across these anchor days (accept and disclose the overlapping-window caveat). The 4 dense names have adequate per-day mention counts on these dates (verified: NVDA 7–23/day, GOOGL 7–26, TSLA 5–16, AMZN 4–10 across 06-10→06-12).

### 3.6 Test & guardrails (mandatory at this tiny N)
1. **Pooled Pearson r(signal, fwd_rel_ret)** per (signal × horizon), with **n reported beside every r**. With ~4 dense names × 3 anchor days, pooled n is ~12 ticker-days — small. **Report it as hypothesis-generation, never significance.**
2. **Median-split high/low bucket**: mean fwd_ret + win-rate per half (deciles/terciles collapse to halves given N). The `02_regime_return_analysis.py` separation logic.
3. **1000× shuffle null**: permute the signal→return pairing, report where the real r sits in the permutation distribution. Judge against the joint null, not nominal p. **This is the primary defense against mining a spurious |r|>0.3 cell across the signal×horizon surface.**
4. **Per-ticker sign-consistency**: does `sign(r)` agree across the 4 names, or is it driven by one (NVDA)? A signal driven by a single name is not a signal.
5. **DO NOT emit annualized Sharpe.** `mean/std·√(252/h)` on ~4 correlated names over one overlapping window is uninterpretable; reviewers unanimously flag it. Drop it entirely, don't caveat it.
6. **Stratify by `squeeze_flag`** (481-post 逼空/Meme cohort) as a secondary cut — the one behavioral idea that survives measurement.

### 3.7 Success / failure criterion (pre-registered, judged on the joint null)
- **GO (methodology carries signal, worth backfilling history to build the full engine):** at least one of `attention_share` / `raw_dir` / `quality_weighted_dir` / `mean_sentiment` shows |r| beyond the **95th percentile of its shuffle null** at N=3 (SPY-relative) **AND** sign-consistent across ≥3 of 4 names **AND** monotonic high/low bucket-return ordering.
- **NO-GO / inconclusive (the likely and acceptable outcome):** no signal clears the joint null. This is a *legitimate, useful result* — it says "don't invest in the rolling regime engine yet; the social signal may need 60+ days of history, comment-level attribution, or the author crawl before it's detectable."
- **Explicitly NOT a criterion:** raw `|r|>0.3` (at n~12 that's near-certain by chance across the cell grid — the exact false-keep trap the engineer's original threshold would have triggered).

### 3.8 Deliverable
A single standalone Python script (reads the snapshot, yfinance for prices, scipy for r) emitting to stdout:
- a **signal × horizon r-table** (raw + SPY-relative), with n and shuffle-null percentile beside each cell;
- a **median-split bucket-return + win-rate table**;
- the **per-ticker sign-consistency** line per signal;
- the **squeeze-cohort** stratified cut.

The script *is* the reusable substrate: as daily history backfills over the coming weeks, the same harness becomes a real per-bucket panel and eventually supports the rolling engine.

### 3.9 Why this one, over the alternatives
- **Behavioral's Miller-disagreement test** was the most theoretically interesting but is built on the dataset's lowest-variance column (`upvote_ratio` ~93% = 1.0); its 2×2 sort splits ~22 names into ~5/cell. Demoted — `squeeze_flag` is the salvageable piece and is kept as a stratifier.
- **NLP's percentile-engine pilot** (`att_pctile`/`dir_pctile`/`sent_pctile` via expanding percentile, EMA, Gaussian) is internally non-computable: `min_periods=14` on ~10 dense days yields zero valid rows. Deferred to the post-backfill phase.
- **The engineer's single-anchor (t0=06-09) design** is fragile (one cross-sectional draw, one mover flips it) and originally sourced signals from `ticker_rollup` — which (verified) has only `hour` (311 rows, ~48h, bull/bear/sentiment zeroed) and `window` (69 rows, one all-time snapshot) buckets, **no `day` bucket**. Reading rollup columns "as of 06-09" either returns nothing or silently injects 06-15 data. **Recompute from raw** is non-negotiable.

---

## 4. Honest caveats

1. **6 weeks is not enough for the thing equity1000 actually is.** equity1000's value is in *per-ticker time-series regime classification* validated over 60–90 day windows. Prismo has ~10 dense US days. This experiment tests the *validation methodology and signal content*, not the regime engine. A GO result means "worth building toward," not "we have a working regime classifier."

2. **Effective sample is single-digit, not the nominal n.** ~4 dense names × ~3 anchor days, all mega-cap US tech that co-move with AI/market beta, with overlapping forward windows. The "effective independent observations" are closer to 1–2 names than to nominal ticker-day count. SPY-relative returns + the shuffle null reduce but do not eliminate false discovery. **Any single result is hypothesis-generating only. Do not greenlight a strategy on it.**

3. **The post-first universe is attention-conditioned (selection bias).** Prismo only sees a ticker once it's discussed (169 of 250 dict tickers ever appear). We cannot study names that crashed silently and were never posted about. Every correlation overstates the tradeability of "attention" relative to equity1000's universe-first design. State this on every result.

4. **The single most predictive equity1000 family is unreproducible.** No follower graph, and author karma is 0 for all 9,767 authors. The smart-follower-weighted direction and `se_z60` — equity1000's best signals — have no analog until the author-library crawl runs. The quality/venue substitute is unvalidated.

5. **Cross-region is a roadmap item, not a current capability.** JP/KR/TW/Xueqiu forum data (`asia_*`, `gr_*`) has *never been persisted to cloud* — verified absent from the snapshot. The `cn` market is Reddit-scraped from a curated dictionary, not an independent regional crowd (only 6 us/cn-overlap tickers). Any roadmap promising cross-region consensus/divergence must label it "needs ingestion + cloud-sync of the multi-region forum tables," not "this week." The non-blend doctrine is the right architecture to *keep ready*; it just has nothing real to run on yet.

6. **Stance/sentiment are a single un-calibrated LLM pass.** `item_analysis` is simultaneously the ground truth and the signal — there is no independent check that `quality_score` or `stance` is well-calibrated, and cross-ticker comparability is assumed, not validated. A small hand-labeled audit (50–100 posts) should precede trusting these as alpha inputs. Neutral dominates (3770/5882), so the direction signal partly measures "how opinionated," not just "how bullish."

7. **Forum mentions likely LAG price.** People post *after* a stock moves. Forward-return correlation may be weak even if the signal is "real-time accurate." The experiment should ideally also report concurrent and lagged correlation to diagnose lead/lag — a weak forward-r is not necessarily a dead signal, it may be a coincident one.

8. **Comment corpus is unused.** Mentions are post-only (the 14,457-comment sentiment corpus is not linked to tickers). This experiment discards most of the crowd's reaction depth; attributing comment sentiment back to a post's tickers is a future enrichment, with its own attribution-error cost.

---

## 5. Sequencing (what unlocks what)

| Phase | Prerequisite | What it unlocks |
|---|---|---|
| **Now** | snapshot + yfinance + pip install | The §3 cross-sectional effect-size probe. Go/no-go on whether any forum signal carries forward-return info |
| **+4–8 weeks of daily pipeline runs** | ≥60 days of daily mentions history | The rolling/expanding-percentile regime front-end (`att_60d`, `dir_pctile`, `entropy_ma7`, `vel_zscore`); the same harness becomes a real per-bucket time-series panel |
| **After author-library crawl** | `make crawl-authors` populates karma | A *real* influence-weighted direction signal — the closest analog to equity1000's smart-follower family |
| **After `asia_*`/`gr_*` cloud-sync** | JP/KR/TW/Xueqiu forum tables persisted to cloud | The non-blend cross-region breadth/divergence layer (which `add_forum_mindshare.py` was already written to consume) — JP 5-level native sentiment, TW push-count, verified-holder weighting |
| **After fundamentals/price ingestion** | per-ticker OHLC + fundamentals in cloud | The full `tag_retail.py` 10-signal score; in-cloud return validation without external yfinance pulls |
