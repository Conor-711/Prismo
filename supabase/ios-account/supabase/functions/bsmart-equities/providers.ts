import { catalogCache, providers, readJSON } from "../bsmart-markets/providers.ts";
import { ISSUER_REGISTRY_TTL_MS, MarketError, object, tickerInput, unavailable } from "../bsmart-markets/routing.ts";
import { parseAsset, parseIssuerRegistry } from "./assets.ts";
import { EVMCatalogs } from "./routing.ts";
import type { Asset } from "./assets.ts";
import type { Snapshot } from "../bsmart-markets/routing.ts";

export async function readIssuerNodes(fetcher: typeof fetch = fetch, now: () => number = Date.now): Promise<Snapshot<unknown>> {
  const nodes: unknown[] = [], started = now();
  // Two attempts apply only to fixed-domain metadata GETs, never a submission.
  async function metadata(url: string, deadline: number, errorCode: string): Promise<unknown> {
    for (let attempt = 0; attempt < 2; attempt++) {
      if (now() >= deadline) break;
      try { return await readJSON(url, {}, fetcher); }
      catch { if (attempt === 1) break; }
    }
    throw new MarketError(errorCode);
  }
  for (let page = 0; page < 200; page++) {
    if (now() < started || now() - started >= 90_000) throw unavailable();
    const url = new URL("https://api.xstocks.fi/api/v2/public/assets");
    url.search = new URLSearchParams({ page: String(page), pageSize: "50" }).toString();
    const payload = object(await metadata(url.toString(), started + 90_000, "issuer_registry_unavailable")), pagination = object(payload.page);
    if (pagination.currentPage !== page || typeof pagination.hasNextPage !== "boolean" ||
      !Array.isArray(payload.nodes) || payload.nodes.length > 50 ||
      (pagination.hasNextPage && payload.nodes.length === 0)) throw unavailable();
    nodes.push(...payload.nodes);
    if (now() < started || now() - started >= 90_000) throw unavailable();
    if (!pagination.hasNextPage) {
      parseIssuerRegistry(nodes);
      return { at: started, values: nodes };
    }
  }
  throw unavailable();
}

export function equityProviders(fetcher: typeof fetch = fetch, now: () => number = Date.now,
  registrySource?: () => Promise<Snapshot<Asset>>): EVMCatalogs {
  return {
    hl: providers(fetcher, now).hl,
    registry: registrySource ?? catalogCache(async () => parseIssuerRegistry((await readIssuerNodes(fetcher, now)).values), now, ISSUER_REGISTRY_TTL_MS),
    asset: async symbol => {
      if (!/^[A-Za-z0-9.-]{1,24}$/.test(symbol)) throw unavailable();
      const at = now(); let raw: unknown;
      for (let attempt = 0; attempt < 2; attempt++) {
        if (now() < at || now() - at >= 20_000) break;
        try { raw = await readJSON("https://api.xstocks.fi/api/v2/public/assets/" + encodeURIComponent(symbol), {}, fetcher); break; }
        catch { /* Only retry a metadata read. */ }
      }
      if (!raw) throw new MarketError("issuer_detail_unavailable");
      const u = object(object(raw).underlying);
      if (typeof u.symbol !== "string") throw unavailable();
      return { at, values: [parseAsset(raw, tickerInput(u.symbol))] };
    },
  };
}
