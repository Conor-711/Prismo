# Congress Score Contract

## Purpose

Congress Score compares the disclosed investment timing of U.S. House and Senate filing households. It is a separate research domain from Smart Account author Score. The target user is deciding whether a member's public transaction history contains repeatable evidence of investment timing skill.

The score does **not** estimate a member's precise account return, accuse a member of wrongdoing, or claim that the member personally selected each household transaction.

## Atomic field decomposition

Content unit: one official periodic-transaction line item, collapsed for analysis to one member + ticker + transaction date + direction event.

| Field | Type | Source | Use |
|---|---|---|---|
| `trade_id` | string | normalized official filing | traceability |
| `member_id`, `name` | string | filing + member index | group/display |
| `chamber`, `party`, `state`, `office` | enum/string | member index | filter/group/display |
| `transaction_date` | date | official filing | event time |
| `filing_date`, `days_to_file`, `is_late` | date/int/bool | official filing/derived | followability and disclosure quality |
| `owner` | nullable enum | official filing | household attribution caveat |
| `ticker`, `asset_name`, `asset_type` | string | filing + normalization | resolve/filter/display |
| `transaction_type` | purchase/sale/exchange | official filing | direction/filter |
| `amount_low`, `amount_high` | nullable integer | official range | evidence only |
| `evidence_url` | URL | House Clerk or Senate eFD | source verification |
| `entry_date`, `exit_date` | date | market calendar | no-lookahead settlement |
| `asset_return`, `benchmark_return` | percentage points | adjusted prices | evidence |
| `directional_excess` | percentage points | derived | score input |
| `decision_days` | integer | derived | qualification/confidence |
| `score_percentile`, `rank`, `confidence`, `status` | numeric/enum | derived | sort/display |

Raw filing facts and derived return/score fields remain separate. The amount midpoint is never presented as an exact trade size.

## Eligibility and settlement

- Universe: House and Senate filers with at least one transaction in the inclusive one-year window.
- Priceable assets: listed stocks and ETFs with a resolvable ticker.
- Exclusions: options, bonds, municipal securities, crypto, exchanges, and unresolved tickers.
- Duplicate control: multiple filing rows on the same member/ticker/date/direction collapse to one event.
- Entry: next trading-session adjusted close after the transaction date.
- Horizons: 20 and 60 further trading sessions.
- Benchmark: SPY over the exact same entry and exit dates.
- Purchase evidence: `asset_return - SPY_return`.
- Sale evidence: `SPY_return - asset_return`, reported separately and excluded from the primary score.

## Score and ranking

All tickers traded by one member on one date are averaged into one decision-day observation before scoring. Each decision-day excess is capped to +/-50 percentage points and small samples shrink toward zero with a five-day prior.

The composite uses 65% 20-day and 35% 60-day evidence when at least three settled 60-day decision days exist. The public score is the qualified-cohort percentile of that composite.

- `ranked`: at least five settled purchase decision days.
- `observation`: one to four settled purchase decision days.
- `unscored`: no settled purchase decision day.

The CSV must always include all members in the window, including observation and unscored rows.

## Required outputs

- `congress_member_scores_1y.csv`: complete member universe, status, metrics, rank, and score.
- `congress_trade_evidence_1y.csv`: every settled event/horizon with official source URLs.
- `source_manifest.json`: source hash, date window, coverage, price failures, and policy versions.
- `congress_score_report_1y.md`: readable methodology, ranking, limits, and concrete success/failure evidence.
