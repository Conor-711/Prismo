import { object, tickerInput, unavailable } from "../bsmart-markets/routing.ts";

export const NETWORKS = {
  Ethereum: { chainId: 1, api: "mainnet", usdc: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" },
  Ink: { chainId: 57073, api: "ink", usdc: "0x2d270e6886d130d724215a266106e6832161eaed" },
  Arbitrum: { chainId: 42161, api: "arbitrum_one", usdc: "0xaf88d065e77c8cc2239327c5edb3a432268e5831" },
} as const;
export type Network = keyof typeof NETWORKS;
export type Deployment = { network: Network; token: string; wrapperV2: string | null; usdc: string };
export type Asset = { id: string; symbol: string; ticker: string; name: string; halted: boolean; tradingHours: unknown; deployments: Deployment[] };
const ADDRESS = /^0x[0-9a-f]{40}$/i;

export function parseAsset(value: unknown, ticker: string): Asset {
  const a = object(value), underlying = object(a.underlying);
  if (underlying.symbol !== ticker || underlying.currency !== "USD" ||
    typeof a.id !== "string" || !/^[0-9a-f-]{36}$/i.test(a.id) ||
    typeof a.symbol !== "string" || !/^[A-Za-z0-9.-]{1,24}$/.test(a.symbol) ||
    typeof a.name !== "string" || typeof a.isTradingHalted !== "boolean" || !Array.isArray(a.deployments)) throw new Error("issuer_identity_invalid");
  const trading = a.trading == null ? null : object(a.trading);
  if (trading && typeof trading.isTradingHalted !== "boolean") throw new Error("issuer_status_invalid");
  const deployments: Deployment[] = [];
  for (const raw of a.deployments) {
    const d = object(raw);
    if (!Object.hasOwn(NETWORKS, d.network as string)) continue;
    const network = d.network as Network, chain = NETWORKS[network];
    if (typeof d.address !== "string" || !ADDRESS.test(d.address) || !Array.isArray(d.stablecoins)) throw new Error("issuer_deployment_invalid");
    const usdc = d.stablecoins.map(object).filter(s => s.symbol === "USDC");
    if (!usdc.length) continue;
    if (usdc.length !== 1 || usdc[0].decimals !== 6 || usdc[0].network !== network ||
      typeof usdc[0].address !== "string" || usdc[0].address.toLowerCase() !== chain.usdc ||
      d.address.toLowerCase() === chain.usdc || /^0x0{40}$/i.test(d.address)) throw new Error("issuer_usdc_invalid");
    if (d.wrapperAddressV2 != null && (typeof d.wrapperAddressV2 !== "string" || !ADDRESS.test(d.wrapperAddressV2) ||
      /^0x0{40}$/i.test(d.wrapperAddressV2) || d.wrapperAddressV2.toLowerCase() === chain.usdc ||
      d.wrapperAddressV2.toLowerCase() === d.address.toLowerCase())) throw new Error("issuer_wrapper_invalid");
    deployments.push({ network, token: d.address.toLowerCase(), usdc: chain.usdc,
      wrapperV2: typeof d.wrapperAddressV2 === "string" ? d.wrapperAddressV2.toLowerCase() : null });
  }
  if (new Set(deployments.map(d => d.network)).size !== deployments.length) throw new Error("issuer_duplicate_network");
  return { id: a.id, symbol: a.symbol, ticker, name: a.name,
    halted: a.isTradingHalted || trading?.isTradingHalted === true,
    tradingHours: trading?.tradingHoursMode ?? null, deployments };
}

export function parseIssuerRegistry(nodes: unknown[]): Asset[] {
  const assets: Asset[] = [], ids = new Set<string>(), tickers = new Set<string>(), symbols = new Set<string>(), tokens = new Set<string>();
  for (const raw of nodes) {
    const a = object(raw), u = object(a.underlying);
    if (typeof a.id !== "string" || !/^[0-9a-f-]{36}$/i.test(a.id) || ids.has(a.id) ||
      typeof a.symbol !== "string" || typeof u.currency !== "string" || typeof u.symbol !== "string") throw unavailable();
    ids.add(a.id);
    if (u.currency !== "USD") continue;
    const ticker = tickerInput(u.symbol), asset = parseAsset(a, ticker);
    if (tickers.has(ticker) || symbols.has(asset.symbol)) throw unavailable();
    tickers.add(ticker); symbols.add(asset.symbol);
    for (const d of asset.deployments) {
      for (const address of [d.token, d.wrapperV2].filter((v): v is string => !!v)) {
        const key = d.network + ":" + address;
        if (tokens.has(key)) throw unavailable();
        tokens.add(key);
      }
    }
    assets.push(asset);
  }
  return assets;
}
