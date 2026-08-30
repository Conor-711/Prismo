# Smart Account (Score) Algorithm v1.6

> Status: proposal / execution spec
>
> Scope: X, YouTube, and Reddit posts
>
> Goal: quantify how valuable each bSmart-collected investor's public market calls are to users in the current market environment.

## 1. Definition

Smart Account is bSmart's product for discovering investors with useful public market calls. **Score** is the numeric rating attached to an account; it is not an abbreviation of the product name.

Public UI, metadata, reports, and new documentation must use `Smart Account` for the product and `Score` for the metric. Existing storage identifiers such as `sv`, `SV_Global`, `sv_investor_score`, and `smartVoice.json` are legacy compatibility names and do not define product terminology.

Score does not attempt to measure every investor in the real market. It measures the relative value of investors inside bSmart's collected investor universe.

```text
Score 100 = median qualified investor in bSmart's collected pool
Score 105 = slightly above the qualified-pool median
Score 120 = significantly above the qualified-pool median
Score 80  = significantly below the qualified-pool median
```

The core product question is not "who is famous" or "who writes the best-looking analysis". The question is:

```text
In this user context and current market environment, whose calls should the user prioritize?
```

Accuracy is the first priority. Content quality only changes the responsibility weight of a call. A simple call that is consistently accurate should rank above detailed but inaccurate analysis.

## 2. V1 Scope

V1 only covers:

```text
Platforms: X, YouTube, Reddit posts
Market: US equities
Assets: stocks and ETFs
Excluded for V1: options, futures, crypto, Toss, Xueqiu, Reddit comments, Yahoo JP, Naver, PTT
```

V1 product outputs (legacy storage keys are shown only for implementation compatibility):

```text
Global Score (`SV_Global`)
Platform Score (`SV_By_Platform`)
Horizon Score (`SV_By_Horizon`)
Narrative / Sector Score (`SV_By_Narrative`)
Ticker Score (`SV_By_Ticker`)
Investor-Type Score (`SV_By_Investor_Type`)
Portfolio Score (`SV_Portfolio`)
Confidence
```

## 3. User Needs

Score should be designed around user questions.

Primary questions:

```text
1. In the current market environment, whose calls should I prioritize?
2. In different time horizons, whom should I follow?
3. In different sectors or narratives, whom should I follow?
4. For a specific ticker, whom should I follow?
5. In different markets, whom should I follow?
6. In different investor languages, whom should I follow?
7. For my current portfolio, whom should I follow?
8. On a specific platform or community, whom should I follow?
```

Filters may be combined:

```text
semiconductor + 5D
YouTube + AI infrastructure + 20D
English + X + NVDA
portfolio holdings + short-term horizon
```

When a segment is too sparse, the system should fall back to broader segments.

Example fallback:

```text
NVDA + 5D + X
-> NVDA + 5D
-> semiconductor + 5D
-> semiconductor
-> 5D
-> Global
```

## 4. End-to-End Flow

```text
Investor posts / videos
-> thesis classification
-> structured calls
-> market settlement
-> single-call score
-> investor + segment aggregation
-> normalization inside bSmart qualified pool
-> Score outputs
```

The system input is all stock-related posts or videos by an investor.

The system output is one global Score and multiple segment SVs.

## 4.1 V1.1 Core Correction

V1.0 treated many ticker mentions too much like independent calls. This can mis-score long X posts that mention a basket of stocks, compare companies, or review a portfolio.

V1.1 changes the scoring unit:

```text
post / video
-> thesis
-> one or more calls
```

## 4.2 V1.2 Core Correction

V1.1 treated each call as if it stayed open until every configured horizon finished. This can mis-score investors who explicitly change their view later.

V1.2 adds call lifecycle:

```text
same investor + same ticker + later opposite actionable call
-> closes the older call for any horizons that have not yet naturally settled
```

Example:

```text
Day 0:  bearish A
Day 15: bullish A

Day 0 bearish call:
  1D / 5D: keep normal settled scores if already complete
  20D / 60D / 90D / 180D: settle early at Day 15 close

Day 15 bullish call:
  starts a new lifecycle and settles from Day 15 onward
```

This avoids both false punishment and false credit:

```text
Do not punish an investor for a 60D outcome after they clearly reversed on Day 15.
Do not reward an old call for a 60D outcome if the investor had already abandoned it.
```

The post or video owns a finite evidence budget. If it creates many ticker-level calls, those calls must share that budget. A post that mentions 30 tickers must not count as 30 independent high-conviction calls.

Primary corrections:

```text
1. Classify the thesis before scoring ticker calls.
2. Distinguish primary ticker, basket member, comparison, context mention, and excluded ticker.
3. Cap total weight per source post/video.
4. Make explicit or inferred horizon the primary settlement horizon.
5. Shrink and cap ticker base rates so hot tickers do not demand unrealistic hit rates.
6. Keep directional accuracy first, but add a bounded excess-return component.
```

This is especially important for X, where high-quality investors often publish compact baskets or sector theses rather than one long single-ticker report.

## 5. Structured Call

Every actionable opinion should be converted into one or more structured calls.

Minimum fields:

```text
call_id
investor_id
source: x | youtube | reddit
content_id
created_at
ticker
market
narrative_or_sector
language
call_type:
  single_ticker_call
  basket_call
  pair_trade
  sector_call
  portfolio_update
  retrospective
  context_mention
ticker_role:
  primary
  basket_member
  context
  comparison
  excluded
ticker_relevance: 0..1
target_price_owner
evidence_span
investor_style:
  technical | fundamental | event_driven | macro | flow_momentum | mixed | unknown
call_structure:
  conviction_call | conditional_setup | invalidation_call | watchlist | risk_update | reversal_call | retrospective
lifecycle_action:
  open_call | reinforce_call | invalidate_prior_call | close_prior_call | reverse_call | no_trade_setup | retrospective | none
affected_direction:
  bull | bear | unknown
entry_status:
  active_entry | conditional_setup | watchlist_only | not_applicable
trigger_condition
invalidation_condition
direction: bull | bear | neutral
is_actionable_call: true | false
target_price
horizon_explicit: true | false
horizon_bucket: 1D | 5D | 20D | 60D | 90D | 180D | unknown
conviction_score
evidence_score
specificity_score
call_weight
status: pending | settled
```

Settlement fields:

```text
entry_price
benchmark_entry_price
ret_1d
ret_5d
ret_20d
ret_60d
benchmark_ret_1d
benchmark_ret_5d
benchmark_ret_20d
benchmark_ret_60d
excess_1d
excess_5d
excess_20d
excess_60d
hit_1d
hit_5d
hit_20d
hit_60d
score_1d
score_5d
score_20d
score_60d
```

Non-actionable content should not enter Score scoring:

```text
pure news repost
pure market commentary without direction
memes without a directional call
after-the-fact bragging without a fresh call
neutral commentary without tradable implication
context/comparison ticker mentions
portfolio lists where the ticker has no directional implication
```

Ticker role rules:

```text
primary:
  The post is mainly about this ticker, or the target/entry/thesis clearly belongs to it.

basket_member:
  The ticker is one member of a multi-name call sharing the same thesis.

context:
  The ticker is mentioned as background, ecosystem, supplier/customer, or macro context.

comparison:
  The ticker is used only as an analogy or relative comparison.

excluded:
  The ticker should not be scored.
```

Only `primary` and high-confidence `basket_member` calls enter settlement. `context`, `comparison`, and `excluded` do not affect Score.

## 6. Call Weight

Call weight changes how much responsibility a call carries. It does not replace accuracy.

Recommended range:

```text
Weak or ambiguous directional call: 0.4 - 0.7
Simple but clear call:             1.0
Explicit target or horizon:        1.2 - 1.4
Target + horizon + solid thesis:   1.5 - 1.8
```

The upper bound should stay low. Long or detailed content must not dominate accurate simple calls.

Suggested components:

```text
call_weight =
  base_weight
  * conviction_multiplier
  * evidence_multiplier
  * specificity_multiplier
  * horizon_multiplier
```

Then clamp:

```text
call_weight = clamp(call_weight, 0.4, 1.8)
```

Interpretation:

```text
If the call is correct, higher weight gives more credit.
If the call is wrong, higher weight gives more penalty.
```

This makes detailed, confident calls more accountable without allowing "well-written but wrong" analysis to outrank accurate calls.

### 6.1 Post-Level Weight Budget

A source post/video has a total scoring budget.

For each candidate call:

```text
raw_call_weight =
  call_weight
  * ticker_relevance
  * call_type_multiplier
  * ticker_role_multiplier
```

Recommended multipliers:

```text
call_type_multiplier:
  single_ticker_call  1.00
  pair_trade          0.90
  basket_call         0.75
  sector_call         0.65
  portfolio_update    0.45
  retrospective       0.25
  context_mention     0.00

ticker_role_multiplier:
  primary             1.00
  basket_member       0.75
  comparison          0.25
  context             0.00
  excluded            0.00
```

Then cap total weight per source item:

```text
post_weight_cap =
  if n_calls <= 1: 1.8
  else: min(2.8, 1.15 + 0.35 * sqrt(n_calls))

effective_call_weight_i =
  raw_call_weight_i
  * min(1, post_weight_cap / sum(raw_call_weight_i for the post))
```

This prevents one long basket post from dominating the investor's Score.

## 7. Time Horizons

Use trading days, not calendar days.

V1 horizons:

```text
1D  = ultra short term
5D  = short term
20D = short / medium term
60D = medium term
90D = earnings-season term
180D = long-term structural term
```

Each call can be evaluated across multiple horizons, but there should be a primary horizon when the author states or implies one.

Rules:

```text
Explicit horizon:
  Use the explicit horizon as the primary settlement horizon.

Inferred horizon:
  Use the inferred horizon, but discount the call weight.

No horizon:
  Use default multi-horizon settlement, with lower weight.

Target price without horizon:
  Use target-achievement ladder. Earlier target achievement receives higher credit.
```

Suggested horizon multipliers:

```text
explicit_horizon: 1.00
inferred_horizon: 0.75
missing_horizon: 0.55
```

For calls with no horizon and no target:

```text
Use the investor-type horizon distribution in section 7.1.
Every horizon receives non-zero weight.
```

For calls with a stated or inferred horizon:

```text
primary horizon:
  100% of effective call weight

adjacent horizon:
  explicit horizon: 15%
  inferred horizon: 25%

non-adjacent horizon:
  0%
```

## 8. Target Price Without Horizon

Example:

```text
PDD cost 82.
Still looking at 140.
```

This should be parsed as:

```text
ticker: PDD
direction: bull
reference_price: 82 or market price at posting time
target_price: 140
horizon: unknown
```

If no horizon is stated, reaching the target has different value depending on speed.

Suggested target ladder:

```text
Target reached within 5D:   strong target success
Target reached within 20D:  medium-high target success
Target reached within 60D:  medium target success
Target reached within 90D:  earnings-season target success
Target reached within 180D: long-term target success
Target reached after the configured horizon: direction may count, target success should not receive strong credit
```

For V1, target price should mainly affect the call's specificity and responsibility weight. The core directional hit calculation should remain the main score.

## 9. Early vs Timely Calls

Early and timely calls should be handled through horizon-specific Score, not a separate risk or return-quality module.

Example:

```text
Investor A called bull at 50 one year ago. Price is now 100.
Investor B called bull at 80 yesterday. Price is now 100.
```

Investor A should score better in longer horizons.

Investor B should score better in short horizons.

Therefore:

```text
A may have high SV_60D / SV_120D.
B may have high SV_1D / SV_5D.
```

The product should expose this distinction instead of collapsing all skill into one unexplained number.

## 10. Market Settlement

Entry price:

```text
Use the first available trading close at or after call creation time.
```

Benchmark:

```text
Use SPY for US equities in V1.
```

For each horizon:

```text
stock_return_h = price_h / entry_price - 1
benchmark_return_h = benchmark_price_h / benchmark_entry_price - 1
excess_h = stock_return_h - benchmark_return_h
```

Directional hit:

```text
bull: hit_h = excess_h > 0
bear: hit_h = excess_h < 0
```

Neutral calls do not enter directional scoring in V1.

## 10.0.1 Horizon Window, Not Endpoint Only

V1.4 changes horizon settlement from a single endpoint snapshot to a full path-aware window.

The product still exposes clear horizon labels:

```text
1D / 5D / 20D / 60D / 90D / 180D
```

But each horizon now means:

```text
evaluate the price path from entry day to horizon end
```

not:

```text
evaluate only the final close on day H
```

This fixes cases where an investor correctly identifies a large move inside the horizon, but the ticker gives back the move near the exact endpoint.

For each call and horizon, keep endpoint fields for auditability:

```text
endpoint_excess_h
endpoint_hit_h
```

Also compute path fields inside the same window:

```text
directional_excess_t =
  bull: stock_excess_t
  bear: -stock_excess_t

max_favorable_excess_h =
  max(directional_excess_t for t in [entry, horizon_end])

time_to_peak_days_h =
  first trading-day offset where max_favorable_excess_h is reached

positive_day_share_h =
  share of trading days where directional_excess_t > 0

avg_directional_excess_h =
  average(directional_excess_t over the window)

retracement_h =
  max(0, max_favorable_excess_h - endpoint_directional_excess_h)
```

Interpretation:

```text
endpoint_excess captures whether the call persisted to the horizon end.
max_favorable_excess captures whether the call created a real opportunity.
positive_day_share captures whether the opportunity was readable and persistent.
retracement prevents one-day spikes from being scored like clean sustained calls.
```

## 10.1 Call Lifecycle and Early Close

A call should not remain open after the author clearly reverses or withdraws that view.

V1.2 deterministic rule:

```text
For each actionable call:
  find the first later actionable call with:
    same investor
    same ticker
    opposite direction

If the later opposite call occurs before a horizon's natural exit:
  use the first available trading close at or after the later opposite call
  as the exit price for the older call on that horizon.

If the horizon already naturally settled before the later opposite call:
  keep the original horizon settlement.
```

This is an early close, not a deletion:

```text
old_call.exit_reason = superseded
old_call.superseded_by_candidate_id = later_opposite_call_id
```

Scoring uses the same formula as normal settlement, but with the early-close exit price.

Examples:

```text
Day 0:  bull A
Day 5:  still bull A
Day 15: bear A

Day 0 bull:
  1D and 5D are unchanged.
  20D and 60D settle at Day 15.

Day 5 bull:
  20D and 60D settle at Day 15 if not already complete.

Day 15 bear:
  starts a new call lifecycle.
```

Non-reversal updates should not close a call:

```text
same direction update
information update without direction change
short-term bounce comment while long-term thesis remains unchanged
```

In V1.2, the production implementation uses the conservative deterministic proxy of "later opposite actionable call" for X data. A future LLM-based classifier can refine this into:

```text
explicit close
partial trim
target reached
thesis invalidated
short-term tactical reversal
long-term thesis unchanged
```

## 4.3 V1.3 Core Correction

V1.2 can still let a single-ticker specialist dominate the global leaderboard if one ticker contributes almost all of their positive score.

V1.3 adds a global concentration gate:

```text
An investor can still rank very highly inside a ticker-specific leaderboard.
But Global Score requires diversified evidence across more than one ticker.
```

This is meant to prevent a user from gaining a large Global Score simply by repeatedly making one directional call on one ticker.

The concentration gate is only applied to:

```text
SV_Global
```

It should not cap:

```text
SV_By_Ticker
SV_By_Narrative
SV_By_Horizon
```

Therefore:

```text
A GME specialist can still rank highly on GME.
But they should not become a top global investor purely through GME.
```

## 4.4 V1.4 Core Correction

V1.3 still scored a horizon mostly from the exact close at the horizon endpoint.

This can mis-score useful calls:

```text
Day 0:  investor is bullish
Day 59: ticker is +100% versus entry
Day 60: ticker crashes below entry
```

An endpoint-only 60D score would punish the investor heavily, even though the call produced a major tradable opportunity inside the stated horizon.

V1.4 changes each horizon score to combine:

```text
endpoint persistence
window opportunity
path persistence
giveback penalty
```

Score should therefore be continuous in computation and segmented in product display:

```text
Computation: continuous price path inside each horizon window
Display: discrete 1D / 5D / 20D / 60D scores before V1.5 extends the displayed set
```

## 4.5 V1.5 Core Correction

V1.4 fixed endpoint-only scoring, but the longest production horizon was still 60D.

60D is useful for swing and medium-term calls, but it is not enough for:

```text
earnings-cycle calls
valuation-repair calls
institutional repricing calls
sector trend calls
long-term structural theses
```

V1.5 adds two longer windows:

```text
90D  = full earnings-season window
180D = long-term structural window
```

90D is part of the core Score horizon set because it matches how many users think about a complete reporting cycle.

180D is included with a lower default responsibility weight because half-year results are more exposed to unrelated macro, rate, index-style, and sector-regime changes.

For calls with no explicit horizon, default responsibility is:

```text
5D   15%
20D  25%
60D  25%
90D  25%
180D 10%
```

Rationale:

```text
Users value fast validation, so 5D receives meaningful weight.
20D / 60D / 90D remain the main evidence base for repeatable investment judgment.
180D is visible and useful, but should not dominate global Score by default.
```

The computation remains path-aware:

```text
Computation: continuous price path inside each horizon window
Display: discrete 1D / 5D / 20D / 60D / 90D / 180D scores
```

## 4.6 V1.6 Core Correction

V1.5 still treated all calls as if they should share one neutral horizon distribution.

That is unfair because investors express market views through different analytical modes:

```text
technical investors:
  mostly test price-action setups, triggers, supports, resistance, breakouts, and invalidations

fundamental investors:
  mostly express company-level conviction based on earnings, margins, valuation, guidance, demand, and cash flow
```

V1.6 adds investor-type-aware scoring.

The classification starts at the call level:

```text
call_analysis_type:
  technical
  fundamental
  event_driven
  macro
  flow_momentum
  mixed
  unknown
```

The investor profile is derived from historical call composition:

```text
technical_share
fundamental_share
dominant_investor_type
```

This profile is not a reputation label. It only describes the evidence style collected by bSmart.

Global Score remains one shared pool:

```text
technical calls and fundamental calls are not ranked in separate universes.
Each call is scored with the horizon distribution appropriate to its analysis type.
All call contributions are then aggregated into one Global Score and normalized inside the same qualified investor pool.
```

V1.6 also adds:

```text
SV_By_Investor_Type
```

Examples:

```text
technical Score
fundamental Score
mixed Score
```

These segment scores explain where an investor is strong without splitting the global leaderboard.

## 7.1 Investor-Type Horizon Weights

Every horizon must have non-zero weight. Short-term validation matters for fundamental investors, and long-term validation still matters for technical investors, but the distributions differ.

Default horizon distributions:

```text
technical:
  1D   10%
  5D   30%
  20D  28%
  60D  18%
  90D   9%
  180D  5%

fundamental:
  1D    3%
  5D    7%
  20D  20%
  60D  27%
  90D  28%
  180D 15%

event_driven:
  1D    8%
  5D   20%
  20D  28%
  60D  24%
  90D  14%
  180D  6%

macro:
  1D    4%
  5D   10%
  20D  22%
  60D  28%
  90D  24%
  180D 12%

flow_momentum:
  1D   12%
  5D   32%
  20D  28%
  60D  16%
  90D   8%
  180D  4%

mixed:
  1D    6%
  5D   15%
  20D  23%
  60D  25%
  90D  21%
  180D 10%

unknown:
  1D    5%
  5D   15%
  20D  25%
  60D  25%
  90D  20%
  180D 10%
```

If a call states an explicit horizon, the stated horizon receives the majority of the responsibility, while all other horizons still receive a non-zero spillover weight based on the call's investor type:

```text
explicit horizon:
  primary horizon = 65% + 35% * type_weight(primary)
  other horizons  = 35% * type_weight(h)

inferred horizon:
  primary horizon = 45% + 55% * type_weight(primary)
  other horizons  = 55% * type_weight(h)

missing horizon:
  use full type_weight(h)
```

This preserves horizon intent while keeping every period represented.

## 11. Ticker Base Rate

The algorithm should not reward investors merely for being bullish on stocks that naturally outperform during the evaluation window.

For each ticker and horizon:

```text
ticker_base_rate_h =
  probability that the ticker outperforms SPY over horizon h
  across the historical evaluation window
```

Expected hit:

```text
if direction == bull:
  expected_hit_h = ticker_base_rate_h

if direction == bear:
  expected_hit_h = 1 - ticker_base_rate_h
```

V1.1 shrinks and caps the base rate:

```text
shrunk_base_rate =
  (historical_wins + 0.5 * prior) / (historical_trials + prior)

prior = 20
ticker_base_rate_h = clamp(shrunk_base_rate, 0.40, 0.65)
```

This keeps hot tickers from requiring unrealistic 80-95% hit rates, while still preventing the system from rewarding investors merely for buying naturally strong tickers.

Single-call contribution:

```text
contribution_h =
  call_weight * (actual_hit_h - expected_hit_h)
```

This keeps the score centered around "better than a zero-skill investor facing the same ticker and same market environment."

## 11.1 Single-Call Contribution V1.1

Accuracy remains first priority, but return magnitude should matter when the call is directionally correct or wrong by a large amount.

Directional excess:

```text
bull:
  directional_excess_h = stock_return_h - benchmark_return_h

bear:
  directional_excess_h = benchmark_return_h - stock_return_h
```

Bounded return component:

```text
return_component_h =
  clamp(directional_excess_h / return_normalizer_h, -1, 1)

return_normalizer:
  1D  = 3%
  5D  = 8%
  20D = 18%
  60D = 35%
  90D = 45%
  180D = 70%
```

Endpoint score:

```text
endpoint_component_h =
  0.75 * (actual_hit_h - expected_hit_h)
  + 0.25 * return_component_h
```

Path-aware components:

```text
opportunity_component_h =
  clamp(max_favorable_excess_h / return_normalizer_h, -1, 1)

persistence_component_h =
  positive_day_share_h - expected_hit_h

retracement_penalty_h =
  if max_favorable_excess_h > 0:
    clamp(
      retracement_h / max(max_favorable_excess_h, return_normalizer_h * 0.5),
      0,
      1
    )
  else:
    0
```

Final V1.4+ contribution:

```text
contribution_h =
  score_weight_h
  * (
      0.40 * endpoint_component_h
    + 0.30 * opportunity_component_h
    + 0.20 * persistence_component_h
    - 0.10 * retracement_penalty_h
    )
```

Interpretation:

```text
Endpoint accuracy still matters.
A major tradable move inside the window is credited.
A fleeting spike is discounted by low persistence and high retracement.
A call that is wrong for most of the window remains weak even if it briefly works.
```

## 12. Duplicate and Independence Rules

The unit of evidence is not the raw number of posts or videos. It is the number of independent, settled, directional effective calls.

X rules:

```text
Same investor + same ticker + same direction + same day:
  count as one effective call, or merge into one call with capped weight.

Repeated pumping in the same direction:
  should not linearly increase evidence.
```

YouTube rules:

```text
One video may produce multiple ticker calls.
Repeated discussion of the same ticker inside one video remains one ticker-level call.
```

Effective sample size:

```text
n_eff = (sum(weight))^2 / sum(weight^2)
```

Use `n_eff` for confidence and shrinkage, not raw post count.

## 13. Segment Score

Every Score is computed from the same settled call table, filtered by segment.

Examples:

```text
Global
X
YouTube
1D
5D
20D
60D
semiconductor
AI infrastructure
MU
NVDA
semiconductor + 5D
YouTube + semiconductor + 20D
English + X + NVDA
```

For any segment:

```text
z_segment =
  sum(w_i * (hit_i - expected_i))
  / sqrt(sum(w_i^2 * expected_i * (1 - expected_i)))
```

Shrinkage:

```text
z_shrunk =
  z_segment * n_eff / (n_eff + K)
```

Suggested `K`:

```text
Global:        30
Platform:      25
Horizon:       25
Narrative:     20
Ticker:        10
Mixed segment: 15 - 30
```

## 14. bSmart Pool Normalization

Score should be normalized inside the qualified bSmart investor pool.

Qualified investor pool for Global Score:

```text
settled_calls >= 30
n_eff >= 30
active_days >= 10
covered_tickers >= 3
```

For each segment, compute raw segment scores for qualified investors, then normalize:

```text
robust_z =
  (raw_score - median(raw_score_pool)) / robust_scale
```

Where `robust_scale` can be:

```text
MAD * 1.4826
or winsorized standard deviation
```

Output:

```text
SV_segment = 100 + 10 * robust_z
```

Global display clamping is handled by confidence and concentration gates.

## 14.1 Global Concentration Gate

Global Score should answer:

```text
Across the current bSmart investor universe, whose public calls are broadly valuable?
```

It should not answer:

```text
Who repeatedly called one ticker correctly?
```

Ticker-specific skill remains valuable, but it belongs in ticker leaderboards.

For each investor, compute concentration metrics from settled Global Score rows:

```text
top_ticker_weight_share =
  max(sum(score_weight for ticker)) / sum(score_weight)

top_positive_contribution_share =
  max(sum(max(contribution, 0) for ticker)) / sum(max(contribution, 0))

effective_tickers_by_weight =
  (sum(ticker_weight))^2 / sum(ticker_weight^2)

effective_tickers_by_positive_contribution =
  (sum(ticker_positive_contribution))^2
  / sum(ticker_positive_contribution^2)

effective_tickers =
  min(effective_tickers_by_weight, effective_tickers_by_positive_contribution)

concentration_share =
  max(top_ticker_weight_share, top_positive_contribution_share)
```

Apply a display cap to Global Score:

```text
if concentration_share >= 75% or effective_tickers < 2:
  global_sv_cap = 118

elif concentration_share >= 60% or effective_tickers < 3:
  global_sv_cap = 126

elif concentration_share >= 50% or effective_tickers < 4:
  global_sv_cap = 135

else:
  global_sv_cap = 180
```

Final Global Score:

```text
SV_Global =
  min(
    normalized_global_sv,
    confidence_cap,
    concentration_cap
  )
```

Interpretation:

```text
Score 118 still means clearly above average.
But a one-ticker account should not rank as a top global investor.
```

This gate is intentionally not applied to ticker-level Score:

```text
If a user asks "who should I follow for GME?",
the GME specialist should still rank highly on GME.
```

```text
SV_display = clamp(SV_segment, 40, 180)
```

Important:

```text
100 means bSmart qualified-pool median, not all-market average.
```

## 15. Global Score and Current Market Relevance

SV_Global should reflect the investor's value in the current market environment.

Do not build a new market-environment pipeline for V1. Reuse the existing narrative rotation output.

Current market relevance comes from:

```text
web/lib/data/narrativeRotation.json
```

Use the narrative rotation module's existing results:

```text
current narrative share
narrative rank
narrative rank change
narrative discussion share
narrative sentiment
```

Create narrative weights:

```text
narrative_weight =
  normalized function of current narrative share, heat, and rank change
```

Then:

```text
current_market_relevant_sv =
  sum(narrative_weight_j * investor_sv_in_narrative_j)
```

Final Global Score:

```text
SV_Global =
  0.70 * investor_all_market_sv
  + 0.30 * current_market_relevant_sv
```

This means if semiconductors or AI infrastructure are currently hot, investors who are accurate in those narratives receive higher Global Score.

## 16. Platform Fitting

Score semantics must be consistent across platforms:

```text
100 = bSmart median
120 = significantly better
80  = significantly worse
```

But extraction and confidence fitting should be platform-specific.

### X

Characteristics:

```text
many posts
short text
more repetition
more short-term calls
less explicit reasoning
```

Rules:

```text
Strong deduplication.
Post-level weight cap is mandatory.
Default simple clear call weight can be 1.0.
Do not penalize short calls merely because they are short.
Prioritize 1D / 5D / 20D settlement.
Repeated calls in the same direction should not inflate n_eff.
Long basket posts should be treated as basket or sector calls, not many independent full-weight calls.
```

### YouTube

Characteristics:

```text
fewer videos
higher information density
more explicit reasoning
more medium-term calls
```

Rules:

```text
One video may split into multiple ticker calls.
Prioritize 20D / 60D / 90D settlement.
High-specificity calls may receive higher weight.
Apply stronger shrinkage when sample size is small.
Do not let one or two successful videos dominate the leaderboard.
```

## 17. Portfolio Score

Portfolio Score is one of the highest-value product applications.

For a user's portfolio:

```text
NVDA 40%
MU   25%
AMD  15%
NFLX 20%
```

Calculate:

```text
SV_Portfolio(investor) =
  0.40 * SV_for_NVDA_or_fallback
  + 0.25 * SV_for_MU_or_fallback
  + 0.15 * SV_for_AMD_or_fallback
  + 0.20 * SV_for_NFLX_or_fallback
```

Fallback:

```text
ticker
-> narrative / sector
-> market
-> platform/global
```

This answers:

```text
For my current holdings, whose opinions should I prioritize?
```

## 18. Confidence

Confidence should be displayed separately from Score. It should not be hidden inside the score.

Suggested confidence levels:

```text
Observing:  n_eff < 10
Low:        10 <= n_eff < 30
Medium:     30 <= n_eff < 80
High:       n_eff >= 80
```

Additional confidence signals:

```text
settled call count
active days
covered tickers
covered narratives
explicit-horizon ratio
target-call ratio
platform coverage
```

Main leaderboards should default to Medium and High confidence.

Low-confidence investors may appear in detail views or "emerging voices" modules.

## 19. Suggested Data Tables

### `sv_call`

One row per structured ticker call candidate. Non-actionable or excluded ticker roles may be retained for auditability but must not enter settlement.

```text
call_id TEXT PRIMARY KEY
investor_id TEXT NOT NULL
source TEXT NOT NULL
content_id TEXT NOT NULL
created_at TEXT NOT NULL
ticker TEXT NOT NULL
market TEXT NOT NULL
narrative TEXT
language TEXT
direction TEXT NOT NULL
is_actionable_call INTEGER NOT NULL
call_type TEXT
ticker_role TEXT
ticker_relevance REAL
target_price_owner TEXT
evidence_span TEXT
target_price REAL
horizon_explicit INTEGER NOT NULL
horizon_bucket TEXT
conviction_score REAL
evidence_score REAL
specificity_score REAL
call_weight REAL NOT NULL
scoring_version TEXT
dedupe_key TEXT
status TEXT NOT NULL
model TEXT
tagged_at TEXT
```

### `sv_call_settlement`

One row per call per horizon.

```text
call_id TEXT NOT NULL
horizon TEXT NOT NULL
entry_day TEXT
settle_day TEXT
entry_price REAL
settle_price REAL
benchmark_entry_price REAL
benchmark_settle_price REAL
stock_return REAL
benchmark_return REAL
excess_return REAL
hit INTEGER
expected_hit REAL
contribution REAL
max_favorable_excess REAL
peak_day TEXT
time_to_peak_days INTEGER
positive_day_share REAL
avg_directional_excess REAL
retracement REAL
endpoint_component REAL
opportunity_component REAL
persistence_component REAL
retracement_penalty REAL
settled_at TEXT
PRIMARY KEY (call_id, horizon)
```

### `sv_investor_segment`

One row per investor per segment.

```text
investor_id TEXT NOT NULL
segment_type TEXT NOT NULL
segment_key TEXT NOT NULL
source TEXT
horizon TEXT
raw_z REAL
shrunk_z REAL
sv REAL
n_eff REAL
settled_calls INTEGER
active_days INTEGER
covered_tickers INTEGER
confidence TEXT
updated_at TEXT
PRIMARY KEY (investor_id, segment_type, segment_key)
```

### `sv_investor_daily`

Daily snapshot for trend display.

```text
day TEXT NOT NULL
investor_id TEXT NOT NULL
sv_global REAL
confidence TEXT
n_eff REAL
settled_calls INTEGER
updated_at TEXT
PRIMARY KEY (day, investor_id)
```

## 20. Pipeline Commands

Suggested pipeline stages:

```text
sv-extract-calls
  Extract structured calls from X, YouTube, and Reddit posts.

sv-settle-calls
  Attach prices and calculate horizon-level call results.

sv-score
  Aggregate call scores into segment SVs.

sv-export
  Export web-ready JSON or build-time DB tables.
```

The extraction layer should reuse existing data where possible:

```text
X:
  x_opinion
  kol_refined
  kol_judgment
  kol_relevance
  kol_quality

YouTube:
  yt_video
  yt_analysis
  yt_judgment
  yt_creator_view
  kol_relevance
  kol_quality

Reddit:
  authors
  posts
  mentions
  item_analysis
  sv_call_candidate(source='reddit')

Reddit Score v1 scope:
  only posts enter Score scoring
  comments are excluded from investor ranking
  author pool uses a Top-N quality / engagement / ticker-coverage filter
  author history is crawled cross-site first, then filtered by ticker and finance quality
  public author profile storage uses account age, link karma, comment karma, local post count, and local influence score
  Reddit has no stable public follower-count field, so follower count is not required for Reddit Score

Prices:
  price_daily

Narrative weights:
  web/lib/data/narrativeRotation.json
```

## 21. V1 Acceptance Criteria

V1 is complete when:

```text
1. X, YouTube, and Reddit post content can be converted into structured calls.
2. Each call can be settled over 1D / 5D / 20D / 60D / 90D / 180D.
3. Single-call contribution uses endpoint hit, window opportunity, path persistence, and retracement penalty.
4. Investor Global Score can be computed.
5. Platform, horizon, narrative, and ticker Score can be computed.
6. Score 100 is aligned to the bSmart qualified investor pool median.
7. Global Score uses existing narrative rotation weights for current-market relevance.
8. Each investor Score can be traced back to underlying calls.
9. Confidence is displayed separately from Score.
10. Portfolio Score can rank investors for a user-selected portfolio.
```

## 22. Core Principles

```text
Accuracy determines score.
Quantity determines confidence.
Content quality determines call responsibility weight.
Platform differences are handled by extraction, deduplication, horizon preference, and shrinkage.
Current narrative heat determines how much each segment matters to Global Score.
Score is relative to bSmart's collected investor universe, not the entire real-world market.
```

## 23. Regression Watchlist

Every scoring algorithm update must rerun and report Score data plus rationale for this fixed account watchlist:

```text
@cyrilxuq
@0xSleepinRain
@Punk9277
@aleabitoreddit
@jukan05
@mdzzi
@jimcramer
@Mr_Derivatives
```

The report should include at minimum: Global Score, rank, confidence, effective sample size, settled calls, active days, covered tickers, horizon Score, narrative Score, ticker Score, concentration cap status, and top positive/negative ticker contribution drivers. If an account has no Score, the report must state whether the account is absent from raw data or present but not converted into settled actionable stock calls.
