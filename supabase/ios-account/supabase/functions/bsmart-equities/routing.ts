import { CATALOG_TTL_MS, fresh, HLMarket, hlRoute, ISSUER_REGISTRY_TTL_MS, Route, Snapshot, tickerInput, unavailable } from "../bsmart-markets/routing.ts";
import { Asset, NETWORKS } from "./assets.ts";
import { EXECUTION_NETWORKS, V1_TICKERS } from "./inventory.ts";

export type EVMCatalogs = { hl: () => Promise<Snapshot<HLMarket>>; registry: () => Promise<Snapshot<Asset>>;
  asset: (symbol: string) => Promise<Snapshot<Asset>> };
export type EVMInstrument = { assetId: string; symbol: string; network: "Ethereum" | "Ink"; chainId: number;
  token: string; usdc: string; tokenVariant: "raw"; maxLeverage: 1 };
export type EVMRoute = Omit<Route, "market" | "reason"> & {
  reason: Route["reason"] | "not_in_v1" | "no_evm_deployment";
  market: { coin: string; dex: string; collateralToken: number; maxLeverage: number } | null;
  instruments: EVMInstrument[]; gasCoverage: "unverified"; defaultSaleProceedsDestination: "hyperliquid_perps";
};
const policy = { executionEnabled: false, gasCoverage: "unverified", defaultSaleProceedsDestination: "hyperliquid_perps" } as const;
const identity = (asset: Asset) => JSON.stringify([asset.id, asset.ticker, asset.symbol,
  asset.deployments.toSorted((a, b) => a.network.localeCompare(b.network)).map(d => [d.network, d.token, d.usdc, d.wrapperV2])]);

function instruments(asset: Asset): EVMInstrument[] {
  return asset.deployments.filter(d => (EXECUTION_NETWORKS as readonly string[]).includes(d.network)).map(d => ({
    assetId: asset.id, symbol: asset.symbol, network: d.network as "Ethereum" | "Ink", chainId: NETWORKS[d.network].chainId,
    token: d.token, usdc: d.usdc, tokenVariant: "raw", maxLeverage: 1,
  }));
}
async function currentAsset(ticker: string, catalogs: EVMCatalogs, now: () => number) {
  const registry = await catalogs.registry();
  fresh(registry, now(), ISSUER_REGISTRY_TTL_MS);
  const matches = registry.values.filter(a => a.ticker === ticker);
  if (matches.length > 1) throw unavailable();
  if (!matches[0]) return { registry, detail: null };
  const detail = await catalogs.asset(matches[0].symbol);
  fresh(registry, now(), ISSUER_REGISTRY_TTL_MS);
  fresh(detail, now());
  if (detail.values.length !== 1 || identity(matches[0]) !== identity(detail.values[0])) throw unavailable();
  return { registry, detail };
}
// Exit discovery never migrates a user's token because a new HL market appears.
// The caller must verify sufficient on-chain ownership before requesting a sell quote.
export async function resolveExitInstruments(input: string, catalogs: EVMCatalogs, now: () => number = Date.now) {
  const { detail } = await currentAsset(tickerInput(input), catalogs, now);
  if (!detail || detail.values[0].halted) throw unavailable();
  return { at: detail.at, instruments: instruments(detail.values[0]) };
}

function hyperliquid(ticker: string, snapshot: Snapshot<HLMarket>): EVMRoute | null {
  const route = hlRoute(ticker, snapshot);
  if (!route) return null;
  if (!route.market || !("coin" in route.market)) throw unavailable();
  return { ...route, market: route.market, instruments: [], ...policy };
}
function unsupported(ticker: string, reason: EVMRoute["reason"], at: number): EVMRoute {
  return { ticker, venue: "none", product: "none", status: "unsupported", reason,
    market: null, instruments: [], observedAt: new Date(at).toISOString(), ...policy };
}
export async function resolveEVMRoute(input: string, catalogs: EVMCatalogs, now: () => number = Date.now): Promise<EVMRoute> {
  const ticker = tickerInput(input);
  let hl = await catalogs.hl();
  fresh(hl, now());
  const initial = hyperliquid(ticker, hl);
  if (initial) return initial;
  if (!V1_TICKERS.has(ticker)) return unsupported(ticker, "not_in_v1", hl.at);
  const { registry, detail } = await currentAsset(ticker, catalogs, now);
  // Slow issuer discovery never turns a new HL listing into xStocks permission.
  if (now() - hl.at >= CATALOG_TTL_MS) hl = await catalogs.hl();
  fresh(hl, now());
  fresh(registry, now(), ISSUER_REGISTRY_TTL_MS);
  const latest = hyperliquid(ticker, hl);
  if (latest) return latest;
  if (!detail) return unsupported(ticker, "not_listed", hl.at);
  fresh(detail, now());
  const live = detail.values[0], observedAt = new Date(Math.min(hl.at, detail.at)).toISOString();
  const found = instruments(live);
  if (!found.length) return unsupported(ticker, "no_evm_deployment", Math.min(hl.at, detail.at));
  return { ticker, venue: "xstocks", product: "spot", status: live.halted ? "blocked" : "available",
    reason: live.halted ? "xstocks_halted" : "xstocks_listed", market: null, instruments: found, observedAt, ...policy };
}
