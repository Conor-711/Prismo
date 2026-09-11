# Hyperliquid Trading Frontend Pivot

> Status: active product and engineering decision
> Confirmed: 2026-09-01
> Scope: iOS ticker detail, market data, internal execution sandbox, future Builder Code execution

## Current execution scope (2026-09-11)

User-confirmed: **perpetual contracts only**, not spot trading, delivery futures,
options or outcome markets. The initial funding asset is native Arbitrum USDC;
only USDC-collateral perpetual markets enter this execution flow. bSmart is a
Hyperliquid frontend using existing markets, not an exchange or HIP-3 deployer.
Builder recipient/rate are undecided, so initial orders omit builder fees.

Internal HyperCore spot/shared USDC reads and CCTP fallback reconciliation are
funding mechanics, not a spot-trading feature. Do not remove them or relabel a
spot fallback as verified perpetual collateral. Do not show a spot trading tab.

Native live review includes opening/adding and explicit reduce-only reduction/
closure. Closing direction comes from the actual position, not the last selected
Long/Short button. Position changes require a new review. Small residual positions
retain their exact quantity; never round up to the opening minimum or imply that
the exchange will necessarily fill them. Production execution remains disabled
until the complete funding, withdrawal and settlement acceptance is verified.
The sandbox slice below is historical, not the live account balance or execution.
Latest navigation/state: `ARCHITECTURE.md`; implementation contract:
`docs/contracts/hyperliquid_execution.md`.

## Product decision

bSmart becomes a trade-first Hyperliquid frontend without discarding its
Smart Account advantage. The ticker page starts with price, chart, position,
long/short and leverage. Smart Account evidence stays next to execution so the
product does not become another undifferentiated social feed.

The iOS root is `Today / Portfolio / Smart / Mr Collie`, with Smart Money and
AI restored by subsequent product decisions. Trading is a ticker-level
workspace, not another root tab.

## First internal slice

The first slice uses a persistent local US$10,000 execution sandbox:

- live Hyperliquid mark, oracle, impact bid/ask, funding, volume and open interest;
- line and candlestick charts across `1H / 4H / 1D / 1W / 1M`;
- discovery of all active markets across the main perp DEX and HIP-3 DEXes;
- market long/short orders with per-market size precision and maximum leverage;
- isolated margin, simulated taker fee, realized/unrealized PnL and hourly funding;
- liquidation when position equity reaches maintenance margin;
- local persistence and a bounded simulated fill history.

This is not a testnet wallet and does not submit an Exchange action. The closed
TestFlight cohort uses the final account, position, fill, and order vocabulary
without repeated sandbox badges. It must not be distributed as live execution
until the signed adapter is active or the account mode is disclosed at product
level.

## Hyperliquid boundary

`HTTPHyperliquidMarketDataClient` is the only direct public market-data adapter.
It calls the official Info endpoint and normalizes external DTOs into domain
models. `HyperliquidTradingStore` owns refresh, selected market and chart state.
`PaperTradingEngine` owns balances and execution; SwiftUI owns neither.

The future live adapter is a separate implementation. It must:

1. obtain explicit wallet authorization and order confirmation;
2. sign the canonical Hyperliquid Exchange action;
3. attach `{b, f}` only after the user has approved the builder's maximum fee;
4. reconcile orders and fills from authoritative exchange state;
5. keep Score, market discovery and evidence ranking independent of revenue.

Hyperliquid documents a maximum builder fee of 0.1% for perpetuals, user-side
fee approval, and a minimum builder account value requirement. These values are
external protocol rules and must be read from current official documentation
before live launch, not duplicated as product constants.

## Competitive product decisions

The 2026-09-06 reference is the memecoin trading app at `fomo.family`, including
the user's SKHYNIX perpetual-market screenshot, not similarly named products.
Adopt its large unframed price chart, compact price/open-interest header,
below-chart timeframe controls and pinned Short / Long actions. Entry opens a
focused amount surface with a numeric keypad, $10/$50/$100/$300 presets,
an integer leverage ruler that snaps horizontally beneath the amount, and deliberate slide confirmation.
Direction is inherited from the initiating Long/Short action with no duplicate
side selector in the composer. A central icon control switches between keypad
and compact candlesticks without clearing the amount or leverage.
Available balance and MAX sit above confirmation. The asset navigation header
combines logo, ticker, company/venue and leverage without repeating identity
above the chart. Market orders remain the only supported order type.
Account statistics and
fills remain in the secondary area; no trading buttons on feed cards.
Keep bSmart's own colors and Smart Account evidence. Do not fabricate holders,
remove fee/liquidation visibility, or adopt urgency mechanics.

From Invo, adopt rapid movement from a public judgment to an executable market
and visible account performance. Do not make copy-trading the first primitive.

From Legend, adopt entry/current/liquidation visibility, social proof beside a
position and clear ranking context. Do not expose leverage without liquidation
consequences.

## Sources

- [Hyperliquid Builder Codes](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/builder-codes)
- [Hyperliquid Info endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint)
- [Hyperliquid Exchange endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint)
- [Hyperliquid WebSocket subscriptions](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions)
- [Hyperliquid liquidations](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/liquidations)
- [Fomo official app](https://fomo.family/)
- [Fomo official navigation guide](https://fomo.family/blog/learn/navigating-your-fomo-app)
- [Invo](https://invo.trade/)
- [Legend](https://legend.trade/)

## Acceptance boundary

- A supported ticker opens into live Hyperliquid market context without waiting
  for a bSmart intelligence refresh.
- Local account math is covered by deterministic unit tests.
- If a ticker has no matching market, the user can open the full market picker.
- Network or decoding failure produces a market-unavailable state, never a fake
  price or simulated live label.
- Smart Account evidence remains available without Smart Money or AI surfaces.
