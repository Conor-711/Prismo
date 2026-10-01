# xStocks V1 Candidate Selection

Status: expanded 30-50-asset target, 2026-10-01; the earlier five-asset proposal
below is historical. Not an execution allowlist, deployment,
funded fill, or weekend acceptance test.

## Confirmed Product Policy

- New orders always prefer an active exact-underlying HL perpetual market.
  Provider outages, unsupported collateral and quote failures do not authorize
  xStocks fallback. Existing positions keep their original instrument and venue.
- Use xStocks only for verified HL absence. Start with a small editorial selection
  of 30-50 recognizable assets, not the entire issuer catalog.
- A completed xStocks spot sale defaults to returning its USDC to the user's HL
  perpetual account. Return funding is a separately authorized, bounded-fee leg.
  Track `return_pending` until actual HL credit is reconciled. A failed return
  leaves user-owned USDC on its identified chain; do not fabricate margin, retry
  an uncertain transfer, or charge an unbounded return fee.
- Keep the trading entry available 24/7, subject to an executable live quote and
  issuer lifecycle checks. Weekend depth is a soft factor: do not require a
  weekday-sized $10,000 quote as a prerequisite for listing. Never relax minimum
  receipt, owned-token sell limits, identity checks or order-expiry protection.
- Spot is 1x and long-only. A sale is not a short. No direct issuer xChange
  onboarding is a V1 dependency; permissionless token transfers alone do not
  establish provider eligibility or compliance.

## Research Method

`supabase/ios-account/scripts/screen_xstocks.ts` reads the complete HL perpetual
catalog before and after each run, resolves exact issuer identity and addresses,
then requests unsigned public CoW sell-kind quotes. For each budget it quotes
USDC -> xStock and immediately quotes that exact output -> USDC.

Round-trip quote difference is `100 * (initial USDC - quoted returned USDC) /
initial USDC`. Buy and sale quote fees are included in the respective fixed input
budgets. Sequential price changes also affect the result; this is NOT isolated
slippage, a realized trading loss, pool TVL, or a success-rate measurement. Initial
approval gas, funding/return costs and any sponsor cost are excluded.

All successful observed quotes returned `verified=false`. The synthetic research
account has no balance/allowance proof, and every probe records `executable=false`.
No wallet, private key, signed order, transaction submission or user funds are used.

## Initial Screening

### Expanded Current Set: 50 Assets

Supersedes the earlier five-name proposal. On 2026-10-01, the complete official
registry contained 1,169 records (not all USD underlyings or tradable markets).
Intersecting verified USD/EVM assets with the product's X discussion sample and
the current complete HL catalog yielded 295 eligible research targets. The 75
most-discussed were probed on Ethereum and Ink at $100 and $1,000, using CoW
`optimal` unsigned quotes between 07:29:08 and 07:40:50 UTC.

Of those 75, 69 had at least one observed two-way pair; 68 had a $1,000 pair.
For this draft only, six names with a lowest observed $1,000 difference above
3% were put into high-cost reserves. This is an editorial research screen,
NOT an approved user fee ceiling. Of the remaining 62, take the 50 most-discussed.
The full HL catalog was checked again at finalization (07:46:49 UTC).

Popularity means distinct ticker/tweet observations in bSmart's sampled X
accounts from 2025-10-01 through 2026-09-30, not global popularity, exchange
volume or liquidity. Counts come from the committed immutable local DB snapshot;
live WAL data are excluded. SPY/QQQ/VOO are ETF exposures, not individual company
shares; do not treat an index derivative as an exact ETF market match.

The table shows the lowest **observed** round-trip difference at each size across
the two separate network runs. These are not simultaneous best-execution quotes.
Every selected asset had a $1,000 pair, but AMC/FLY did not have a $100 pair in
this run. POET's $100 pair was expensive. No selection guarantees small-order
availability, fill probability, 24/7 liquidity, sponsored gas or a funded return.

| Priority | Underlying | Sample mentions | $100 reference difference | $1,000 reference difference |
| ---: | --- | ---: | --- | --- |
| 1 | SPY | 56,293 | 2.856% (Ethereum) | 0.620% (Ethereum) |
| 2 | QQQ | 32,462 | 0.652% (Ink) | 0.630% (Ethereum) |
| 3 | ASTS | 16,134 | 1.069% (Ink) | 0.922% (Ethereum) |
| 4 | IWM | 10,194 | 0.855% (Ink) | 0.753% (Ethereum) |
| 5 | ONDS | 7,984 | 1.105% (Ink) | 0.905% (Ethereum) |
| 6 | SLV | 6,548 | 0.910% (Ink) | 0.862% (Ethereum) |
| 7 | GLD | 6,505 | 0.670% (Ink) | 0.614% (Ethereum) |
| 8 | MARA | 5,137 | 1.098% (Ink) | 1.097% (Ink) |
| 9 | NVO | 5,060 | 0.995% (Ink) | 0.903% (Ethereum) |
| 10 | OPEN | 4,368 | 1.674% (Ink) | 1.608% (Ethereum) |
| 11 | AMC | 3,431 | No pair | 2.097% (Ethereum) |
| 12 | CLSK | 3,053 | 1.372% (Ink) | 1.372% (Ink) |
| 13 | OKLO | 2,920 | 1.288% (Ink) | 1.223% (Ethereum) |
| 14 | APP | 2,880 | 1.231% (Ink) | 1.231% (Ink) |
| 15 | SOXX | 2,790 | 1.071% (Ink) | 1.070% (Ink) |
| 16 | WULF | 2,672 | 1.822% (Ink) | 1.666% (Ethereum) |
| 17 | APLD | 2,546 | 1.278% (Ink) | 1.268% (Ethereum) |
| 18 | CRM | 2,537 | 2.610% (Ink) | 2.293% (Ethereum) |
| 19 | XOM | 2,432 | 1.297% (Ink) | 1.296% (Ink) |
| 20 | SNOW | 2,389 | 1.904% (Ink) | 1.904% (Ink) |
| 21 | PYPL | 2,373 | 1.288% (Ink) | 1.188% (Ethereum) |
| 22 | ALAB | 2,261 | 2.491% (Ink) | 2.397% (Ethereum) |
| 23 | UBER | 2,187 | 0.981% (Ink) | 0.981% (Ink) |
| 24 | UNH | 2,162 | 1.180% (Ink) | 1.180% (Ink) |
| 25 | ADBE | 2,086 | 1.132% (Ink) | 1.132% (Ink) |
| 26 | POET | 2,081 | 4.078% (Ethereum) | 1.906% (Ethereum) |
| 27 | PL | 2,060 | 1.555% (Ink) | 1.414% (Ethereum) |
| 28 | GDX | 2,039 | 1.369% (Ink) | 1.369% (Ink) |
| 29 | HUT | 1,987 | 1.921% (Ink) | 1.921% (Ink) |
| 30 | VRT | 1,919 | 1.144% (Ink) | 1.144% (Ink) |
| 31 | RIOT | 1,811 | 2.138% (Ink) | 2.138% (Ink) |
| 32 | NEM | 1,806 | 1.320% (Ink) | 1.320% (Ink) |
| 33 | WMT | 1,799 | 1.198% (Ink) | 1.198% (Ink) |
| 34 | UUUU | 1,759 | 2.426% (Ink) | 2.426% (Ink) |
| 35 | JPM | 1,731 | 1.159% (Ink) | 1.159% (Ink) |
| 36 | PATH | 1,690 | 2.822% (Ink) | 2.822% (Ink) |
| 37 | NKE | 1,679 | 0.977% (Ink) | 0.977% (Ink) |
| 38 | CVNA | 1,584 | 2.390% (Ink) | 2.215% (Ethereum) |
| 39 | PANW | 1,548 | 1.762% (Ink) | 1.586% (Ethereum) |
| 40 | VOO | 1,533 | 0.920% (Ink) | 0.747% (Ethereum) |
| 41 | MP | 1,532 | 2.868% (Ink) | 2.692% (Ethereum) |
| 42 | DDOG | 1,500 | 1.915% (Ink) | 1.744% (Ethereum) |
| 43 | CORZ | 1,479 | 2.960% (Ink) | 2.783% (Ethereum) |
| 44 | GS | 1,478 | 1.536% (Ink) | 1.536% (Ink) |
| 45 | FCX | 1,414 | 1.648% (Ink) | 1.547% (Ethereum) |
| 46 | FLY | 1,358 | No pair | 1.781% (Ethereum) |
| 47 | SMR | 1,320 | 1.333% (Ink) | 1.222% (Ethereum) |
| 48 | QURE | 1,276 | 1.733% (Ink) | 1.618% (Ethereum) |
| 49 | CAT | 1,254 | 1.564% (Ink) | 1.441% (Ethereum) |
| 50 | LULU | 1,237 | 1.730% (Ink) | 1.565% (Ethereum) |

Reserves requiring new observations: USO, CAR, OUST, AEHR, LUNR, OSCR had no
pair in this run; RDW had only a $100 pair. Some Ethereum detail reads failed
transiently, so these are unresolved routes, not proof of issuer absence. OUST
had quotes in earlier probes; neither observation establishes stable coverage.
High-cost reserves: GLXY (3.134%), RBRK (8.850%), URA (4.144%), SHOP (3.641%),
CELH (3.118%), MRK (3.558%) at the lowest observed $1,000 route.

Generated evidence: `expanded-registry.json`, `popularity.json`,
`expanded-selection.json`, `expanded-quotes.json`, `expanded-ink-quotes.json`
and `expanded-shortlist.json` under `data/reports/xstocks/20261001/`.
`top50-selection.json` is the popularity-only target list before quote screening,
not this final 50-name draft. Twelve additional qualified reserves remain in the
final report. `scripts/finalize_xstocks_shortlist.ts` recreates it and checks live
HL absence; this report does not enable App or backend trading.

Official sources: [asset catalog](https://docs.xstocks.fi/apis/openapi/assets/list_public_assets),
[CoW API](https://docs.cow.fi/cow-protocol/integrate/api).

### Historical Initial Probe

2026-10-01 07:02:51-07:05:19 UTC, Ethereum, $100, CoW `fast` quotes:

- 58 editorial candidates examined; this is not an exhaustive catalog or measured
  popularity ranking.
- 18 had active HL markets and were excluded, including IONQ, RKLB, HIMS, SOFI,
  NBIS, CRWV, PLTR, TSM, ASML, ARM, MU, NVDA, AAPL and TSLA.
- 26 had a pair of indicative quotes. AEHR had insufficient liquidity for this
  probe. Thirteen issuer lookups could not be verified; they remain unresolved,
  rather than being classified as definitively absent from xStocks.
- A raw-token quote alone does not establish that an AMM pool exists: CoW solvers
  can source liquidity through other routes. Do not infer weekend depth from it.

Local generated evidence: `data/reports/xstocks/20261001/initial.json`.

## Earlier Narrow Probe (Superseded)

Focused observations: 2026-10-01 07:07:21-07:09:11 UTC, CoW `optimal`, Ethereum
official raw tokens. These seven were all absent from the active HL catalog in
the final check. The earlier five-asset proposal and two reserves are preserved
here as historical evidence, not the current coverage target.

| Candidate | Exposure | $100 difference | $1,000 difference | $10,000 difference | Selection |
| --- | --- | ---: | ---: | ---: | --- |
| SMR | NuScale / nuclear | 1.464% | 0.748% | 0.688% | First set |
| QUBT | Quantum Computing | 1.339% | 0.741% | 0.681% | First set |
| ASTS | AST SpaceMobile / satellite | 1.444% | 0.869% | 0.811% | First set |
| VRT | Vertiv / data-center infrastructure | 1.445% | 0.868% | 0.810% | First set |
| OKLO | Oklo / nuclear | 2.881% | 1.203% | 1.142% | First set, cost-sensitive |
| OUST | Ouster / lidar | 2.549% | 1.583% | 1.406% | Reserve |
| ALAB | Astera Labs / connectivity | 3.273% | 2.037% | 1.916% | Reserve |

The dollar tiers are research probes, not approved order limits or a guaranteed
capacity. Smaller Ethereum orders have higher percentage costs. Do not advertise
HL-like costs based on the larger tiers. Single snapshots cannot establish
stability, fill probability, or price fairness versus the underlying stock.

Ink raw-token quotes were also available at all three tiers for SMR, ASTS, VRT,
OKLO and ALAB; their $1,000 differences were approximately 1.082%, 1.083%, 1.081%,
1.412% and 1.808%, respectively. QUBT and OUST had no raw-token quote there in
that run. Ethereum and Ink are research routes, not a finalized execution chain.

Local generated evidence: `data/reports/xstocks/20261001/depth.json`.

## Chain And Instrument Follow-Up

A second $1,000 `optimal` probe at 07:10:20-07:11:55 UTC checked official raw
tokens and the issuer's listed current V2 wrapper addresses on Ethereum, Ink and
Arbitrum. Ethereum raw-token difference was 0.859% for SMR, 0.728% for QUBT,
0.859% for ASTS, 0.857% for VRT, 1.206% for OKLO, 1.332% for OUST and 1.616%
for ALAB. Changes from the earlier run are a reminder that quoted costs vary;
keep OUST/ALAB as reserves rather than treating one improved sample as stability.

None of the tested registered Arbitrum deployments returned a quote. SMR/VRT
had no Arbitrum deployment in the verified supported-network metadata; the other
five returned `NoLiquidity` for both variants. This is evidence about CoW routes
at that time, not proof that no liquidity exists anywhere on Arbitrum.

Every tested V2 wrapper lacked a buy quote (`InsufficientLiquidity` or
`NoLiquidity`). Only raw-token routes produced the successful pairs. A solver
quote does not establish its underlying venue or an independent AMM reserve.
Do not enable raw-token execution without checking corporate-action accounting
and settlement compatibility, and do not substitute a legacy V1 wrapper.

Local evidence: `data/reports/xstocks/20261001/route-check.json`.

Unsigned Across `/swap/approval` funding probes also returned native-USDC quotes
with matching chain/token identities. Each direction independently used a $1,000
input; these are not a funded round-trip or a HyperCore funding test:

| Route | Input less expected output | Provider fill-time estimate |
| --- | ---: | ---: |
| Arbitrum -> Ink | $0.100284 | 2 seconds |
| Ink -> Arbitrum | $0.107733 | 2 seconds |
| Arbitrum -> Ethereum | $0.125798 | 9 seconds |
| Ethereum -> Arbitrum | $0.107733 | 2 seconds |

Summing the equal-sized directional reference quotes gives about $0.208 (0.0208%)
for Ink or $0.234 (0.0234%) for Ethereum. These numbers exclude source gas,
initial approvals, stock swaps and the HL funding legs. Source transaction gas
estimation was skipped for the synthetic account; a zero gas field is NOT
evidence of gasless service. Provider fill-time estimates are not observed latency
or end-to-end trading times. Funding quote requests used no provider API key,
signature or broadcast; returned transaction data were neither saved nor executed.

Local evidence: `data/reports/xstocks/20261001/funding-quotes.json`.

Ethereum currently provides broader tested quote coverage. Ink is a prospective
lower-source-gas alternative for some instruments, not an approved route. Select
on net user receipt after all fees and gas sponsorship, not chain fees alone.

## Before Enabling A Candidate

1. Revalidate the full current HL catalog, registered underlying, issuer halt
   status and exact chain/token identity at order time. Failed reads block.
2. Verify a real user-owned EVM wallet, token decimals and corporate-action
   accounting. For wrappers, verify the current version and on-chain `asset()`;
   never use legacy V1 or treat a conversion rate as a stock price.
3. Validate funded quotes, allowance and decoded EIP-712 orders with exact input,
   minimum receipt, recipient, chain, expiry and trusted settlement addresses.
   Reconcile confirmed fills without duplicate submissions.
4. Validate stock price/deviation controls against an independent timely reference.
   Outside underlying market hours, use an explicit staleness/premium policy;
   wider spreads do not justify silently accepting an arbitrary bad price.
5. Implement verified HL funding, sponsored approval/source gas, confirmed sale
   receipt and bounded return funding. Supported chains and public quote endpoints
   are not proof of end-to-end gasless operation or receipt in HL perps.
6. Collect repeated market-open, overnight and weekend samples. Weekend evidence
   is currently untested. Size down or show a no-quote state rather than accepting
   an unprotected order. No monitoring automation has been configured.
7. Enable one bounded real buy/sale/return acceptance flow before general release,
   with the user performing the financial confirmation. The research scripts
   never enable these actions.

## Sources

- [CoW public API and quote integration](https://docs.cow.fi/cow-protocol/integrate/api).
- [xStocks secondary 24/7 versus primary 24/5](https://docs.xstocks.fi/docs).
- [Official asset discovery](https://docs.xstocks.fi/apis/openapi/assets/list_public_assets).
- [Current wrappers and pricing controls](https://docs.xstocks.fi/developers/wrapped-xstocks).
- [Across supported chains](https://docs.across.to/chains-and-contracts).
- [Across fees and source-gas distinctions](https://docs.across.to/introduction/fees).

Execution contract: `docs/contracts/equity_routing.md`.
Repeatable probe commands: `docs/operations/equity-routing.md`.
