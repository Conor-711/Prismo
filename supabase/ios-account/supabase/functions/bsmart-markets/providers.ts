import { CATALOG_TTL_MS, Catalogs, dexNames, ISSUER_REGISTRY_TTL_MS, MarketError, object, parseHL, parseXStocks, Route, Snapshot, unavailable, USDC_MINT } from "./routing.ts";

type Fetcher = typeof fetch;
export async function readJSON(url: string, init: RequestInit = {}, fetcher: Fetcher = fetch): Promise<unknown> {
  const response = await fetcher(url, { ...init, redirect: "error", signal: AbortSignal.timeout(8000) });
  const reader = response.body?.getReader();
  try {
    if (!response.ok || !/application\/json/i.test(response.headers.get("content-type") ?? "") || !reader) throw unavailable();
    const chunks: Uint8Array[] = []; let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 2_097_152) throw unavailable();
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } finally { await reader?.cancel().catch(() => {}); }
}
// Cache complete observations only. Failed refreshes never return expired data.
export function catalogCache<T>(load: () => Promise<T[]>, now: () => number = Date.now, ttl = CATALOG_TTL_MS): () => Promise<Snapshot<T>> {
  let cache: Snapshot<T> | undefined, pending: Promise<Snapshot<T>> | undefined;
  return () => {
    const time = now();
    if (cache && time >= cache.at && time - cache.at < ttl) return Promise.resolve(cache);
    if (pending) return pending;
    pending = load().then(values => {
      if (now() < time || now() - time >= ttl) throw unavailable();
      return cache = { values, at: time };
    }).finally(() => { pending = undefined; });
    return pending;
  };
}
export function providers(fetcher: Fetcher = fetch, now: () => number = Date.now): Catalogs {
  const info = (type: string) => readJSON("https://api.hyperliquid.xyz/info", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ type }),
  }, fetcher);
  return {
    hl: catalogCache(async () => {
      const before = dexNames(await info("perpDexs"));
      const metas = await info("allPerpMetas");
      const after = dexNames(await info("perpDexs"));
      if (JSON.stringify(before) !== JSON.stringify(after)) throw unavailable();
      return parseHL(before, metas);
    }, now),
    xstocks: catalogCache(async () => {
      const nodes: unknown[] = [], startedAt = now();
      for (let page = 0; page < 100; page++) {
        if (now() - startedAt >= 90_000) throw unavailable();
        const url = new URL("https://api.xstocks.fi/api/v2/public/assets");
        url.search = new URLSearchParams({ network: "Solana", stablecoin: "USDC", page: String(page), pageSize: "100" }).toString();
        const payload = object(await readJSON(url.toString(), {}, fetcher)), pagination = object(payload.page);
        if (pagination.currentPage !== page || typeof pagination.hasNextPage !== "boolean" ||
          !Array.isArray(payload.nodes) || payload.nodes.length > 100 ||
          (pagination.hasNextPage && payload.nodes.length === 0)) throw unavailable();
        nodes.push(...payload.nodes);
        if (!pagination.hasNextPage) return parseXStocks(nodes);
      }
      throw unavailable();
    }, now, ISSUER_REGISTRY_TTL_MS),
    xstock: async symbol => {
      const at = now();
      const asset = await readJSON("https://api.xstocks.fi/api/v2/public/assets/" + encodeURIComponent(symbol), {}, fetcher);
      return { at, values: parseXStocks([asset]) };
    },
  };
}
export async function preview(route: Route, amount: string, apiKey: string, fetcher: Fetcher = fetch, now: () => number = Date.now) {
  if (route.venue !== "xstocks" || route.status !== "available" || !route.market || !("mint" in route.market)) throw new MarketError("xstocks_route_required", 409);
  const at = now(), mint = route.market.mint;
  const url = new URL("https://api.jup.ag/swap/v2/order");
  url.search = new URLSearchParams({ inputMint: USDC_MINT, outputMint: mint, amount }).toString();
  try {
    const quote = object(await readJSON(url.toString(), { headers: { "x-api-key": apiKey } }, fetcher));
    if (quote.inputMint !== USDC_MINT || quote.outputMint !== mint || quote.inAmount !== amount ||
      typeof quote.outAmount !== "string" || !/^[1-9][0-9]{0,38}$/.test(quote.outAmount) ||
      !["metis", "jupiterz", "dflow", "okx"].includes(quote.router as string) ||
      quote.transaction != null || quote.errorCode != null || quote.errorMessage != null ||
      now() < at || now() - Date.parse(route.observedAt) >= CATALOG_TTL_MS) throw unavailable();
    return { route, inputAmountRaw: amount, outputAmountRaw: quote.outAmount, router: quote.router,
      observedAt: new Date(at).toISOString(), executable: false, gasCoverage: "unverified" };
  } catch { throw new MarketError("quote_unavailable"); }
}
