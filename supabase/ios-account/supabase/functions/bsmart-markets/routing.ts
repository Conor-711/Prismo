import { base58 } from "npm:@scure/base@1.2.6";

export class MarketError extends Error {
  constructor(public code: string, public status = 503) { super(code); }
}
export const unavailable = () => new MarketError("catalog_unavailable");
export const USDC_MINT = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";
export const CATALOG_TTL_MS = 30_000;
export const ISSUER_REGISTRY_TTL_MS = 600_000;
export type HLMarket = { coin: string; dex: string; collateralToken: number; maxLeverage: number; delisted: boolean };
export type XStock = { ticker: string; assetId: string; symbol: string; mint: string | null; halted: boolean };
export type Snapshot<T> = { values: T[]; at: number };
export type Route = {
  ticker: string; venue: "hyperliquid" | "xstocks" | "none";
  product: "perpetual" | "spot" | "none"; status: "available" | "blocked" | "unsupported";
  reason: "hl_listed" | "hl_collateral_unsupported" | "xstocks_listed" | "xstocks_halted" | "not_listed";
  market: { coin: string; dex: string; collateralToken: number; maxLeverage: number } |
    { assetId: string; symbol: string; network: "solana-mainnet"; mint: string; maxLeverage: 1 } | null;
  observedAt: string; executionEnabled: false;
};
export type Catalogs = { hl: () => Promise<Snapshot<HLMarket>>; xstocks: () => Promise<Snapshot<XStock>>;
  xstock: (symbol: string) => Promise<Snapshot<XStock>> };
export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw unavailable();
  return value as Record<string, unknown>;
}
export function tickerInput(value: string | null): string {
  if (!value || !/^[A-Za-z][A-Za-z0-9.-]{0,15}$/.test(value)) throw new MarketError("invalid_ticker", 422);
  return value.toUpperCase();
}
export function amountInput(value: string | null): string {
  if (!value || !/^(0|[1-9][0-9]{0,5})(\.[0-9]{1,6})?$/.test(value)) throw new MarketError("invalid_amount", 422);
  const [whole, fraction = ""] = value.split(".");
  const raw = BigInt(whole) * 1_000_000n + BigInt(fraction.padEnd(6, "0"));
  if (raw <= 0n || raw > 100_000_000_000n) throw new MarketError("invalid_amount", 422);
  return raw.toString();
}
export function dexNames(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 100 || value[0] !== null) throw unavailable();
  const names = value.map((entry, i) => {
    if (i === 0) return "";
    const name = object(entry).name;
    if (typeof name !== "string" || !/^[a-z][a-z0-9]{0,19}$/.test(name)) throw unavailable();
    return name;
  });
  if (new Set(names).size !== names.length) throw unavailable();
  return names;
}
export function parseHL(dexes: string[], value: unknown): HLMarket[] {
  if (!Array.isArray(value) || value.length !== dexes.length) throw unavailable();
  const markets: HLMarket[] = [];
  const coins = new Set<string>();
  value.forEach((entry, i) => {
    const meta = object(entry), dex = dexes[i];
    if (!Number.isSafeInteger(meta.collateralToken) || (meta.collateralToken as number) < 0 ||
      !Array.isArray(meta.universe) || meta.universe.length > 10_000 || (i === 0 && meta.universe.length === 0)) throw unavailable();
    for (const raw of meta.universe) {
      const asset = object(raw), coin = asset.name, leverage = asset.maxLeverage;
      if (typeof coin !== "string" || !coin || coin.length > 100 || coins.has(coin) ||
        (dex ? !coin.startsWith(dex + ":") : coin.includes(":")) ||
        !Number.isSafeInteger(leverage) || (leverage as number) < 1 || (leverage as number) > 1000 ||
        (asset.isDelisted !== undefined && typeof asset.isDelisted !== "boolean")) throw unavailable();
      coins.add(coin);
      markets.push({ coin, dex, collateralToken: meta.collateralToken as number,
        maxLeverage: leverage as number, delisted: asset.isDelisted === true });
    }
  });
  return markets;
}
export function parseXStocks(nodes: unknown[]): XStock[] {
  const stocks: XStock[] = [], ids = new Set<string>(), tickers = new Set<string>();
  for (const raw of nodes) {
    const asset = object(raw), underlying = object(asset.underlying);
    if (typeof asset.id !== "string" || !/^[0-9a-f-]{36}$/i.test(asset.id) || ids.has(asset.id) ||
      typeof asset.symbol !== "string" || !/^[A-Za-z0-9.-]{1,24}$/.test(asset.symbol) ||
      typeof asset.isTradingHalted !== "boolean" || !Array.isArray(asset.deployments) ||
      typeof underlying.currency !== "string" || typeof underlying.symbol !== "string") throw unavailable();
    ids.add(asset.id);
    if (underlying.currency !== "USD") continue;
    if (!/^[A-Za-z][A-Za-z0-9.-]{0,15}$/.test(underlying.symbol)) throw unavailable();
    const ticker = underlying.symbol.toUpperCase();
    if (tickers.has(ticker)) throw unavailable();
    tickers.add(ticker);
    const deployments = asset.deployments.map(object).filter(d => d.network === "Solana");
    if (deployments.length > 1) throw unavailable();
    let mint: string | null = null;
    if (deployments.length) {
      const address = deployments[0].address;
      if (typeof address !== "string" || address.length > 44) throw unavailable();
      try { if (base58.decode(address).length !== 32) throw unavailable(); } catch { throw unavailable(); }
      if (address === USDC_MINT) throw unavailable();
      mint = address;
    }
    const trading = asset.trading == null ? null : object(asset.trading);
    if (trading && typeof trading.isTradingHalted !== "boolean") throw unavailable();
    stocks.push({ ticker, assetId: asset.id, symbol: asset.symbol, mint,
      halted: asset.isTradingHalted || trading?.isTradingHalted === true });
  }
  if (new Set(stocks.filter(s => s.mint).map(s => s.mint)).size !== stocks.filter(s => s.mint).length) throw unavailable();
  return stocks;
}
export function fresh<T>(snapshot: Snapshot<T>, now: number, ttl = CATALOG_TTL_MS): void {
  if (!Number.isFinite(snapshot.at) || snapshot.at > now || now - snapshot.at >= ttl) throw unavailable();
}
export function hlRoute(ticker: string, hl: Snapshot<HLMarket>): Route | null {
  const matches = hl.values.filter(m => !m.delisted && m.coin.split(":").at(-1)?.toUpperCase() === ticker);
  matches.sort((a, b) => Number(b.dex === "xyz") - Number(a.dex === "xyz") ||
    (a.coin < b.coin ? -1 : a.coin > b.coin ? 1 : 0));
  const market = matches.find(m => m.collateralToken === 0) ?? matches[0];
  if (market) {
    const { delisted: _delisted, ...identity } = market;
    return { ticker, venue: "hyperliquid", product: "perpetual", market: identity,
      status: market.collateralToken === 0 ? "available" : "blocked",
      reason: market.collateralToken === 0 ? "hl_listed" : "hl_collateral_unsupported",
      observedAt: new Date(hl.at).toISOString(), executionEnabled: false };
  }
  return null;
}
export async function resolveRoute(ticker: string, catalogs: Catalogs, now: () => number = Date.now): Promise<Route> {
  let hl = await catalogs.hl();
  fresh(hl, now());
  const initial = hlRoute(ticker, hl);
  if (initial) return initial;
  const xs = await catalogs.xstocks();
  fresh(xs, now(), ISSUER_REGISTRY_TTL_MS);
  const stock = xs.values.find(s => s.ticker === ticker);
  let live = stock;
  let liveAt = now();
  if (stock?.mint) {
    const detail = await catalogs.xstock(stock.symbol);
    fresh(detail, now());
    live = detail.values[0]; liveAt = detail.at;
    if (detail.values.length !== 1 || !live || live.assetId !== stock.assetId || live.ticker !== ticker ||
      live.mint !== stock.mint || live.symbol !== stock.symbol) throw unavailable();
  }
  // A slow cold registry read must not allow a newly listed HL market to fall back.
  if (now() - hl.at >= CATALOG_TTL_MS) hl = await catalogs.hl();
  fresh(hl, now());
  const latest = hlRoute(ticker, hl);
  if (latest) return latest;
  if (stock?.mint && now() - liveAt >= CATALOG_TTL_MS) throw unavailable();
  const observedAt = new Date(Math.min(hl.at, liveAt)).toISOString();
  if (!stock?.mint) return { ticker, venue: "none", product: "none", status: "unsupported",
    reason: "not_listed", market: null, observedAt, executionEnabled: false };
  return { ticker, venue: "xstocks", product: "spot", status: live!.halted ? "blocked" : "available",
    reason: live!.halted ? "xstocks_halted" : "xstocks_listed", observedAt, executionEnabled: false,
    market: { assetId: stock.assetId, symbol: stock.symbol, network: "solana-mainnet", mint: stock.mint, maxLeverage: 1 } };
}
