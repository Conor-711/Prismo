import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { MarketError, tickerInput } from "../bsmart-markets/routing.ts";
import { EVMCatalogs, resolveEVMRoute } from "./routing.ts";
import { previewInput } from "./quote.ts";
import { previewEquity, type PreviewPorts } from "./preview.ts";
import { jsonBody } from "./http.ts";
import { boundWallet, handleIntent } from "./intent_handler.ts";
import type { Ledger } from "./intents.ts";
import type { FundingPorts } from "./funding_types.ts";
import type { PreparationLedger } from "./preparations.ts";

const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
export async function handleEquities(req: Request, client: SupabaseClient, options: {
  catalogs: EVMCatalogs; discoveryEnabled: boolean; now?: () => number; previewEnabled?: boolean; previewPorts?: PreviewPorts;
  ledgerEnabled?: boolean; ledger?: Ledger;
  fundingPreviewEnabled?: boolean; fundingPorts?: FundingPorts;
  preparationEnabled?: boolean; preparationLedger?: PreparationLedger;
}): Promise<Response> {
  const auth = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(auth) || auth.length > 16400) return reply({ error: "unauthorized" }, 401);
  try {
    const { data: { user }, error } = await client.auth.getUser(auth.slice(7));
    if (error || !user || user.is_anonymous || !user.identities?.some(i => ["google", "apple"].includes(i.provider))) return reply({ error: "unauthorized" }, 401);
    const url = new URL(req.url);
    const intent = await handleIntent(req, user.id, client, options);
    if (intent !== undefined) return reply(intent);
    if (req.method === "POST" && /\/bsmart-equities\/preview\/?$/.test(url.pathname)) {
      if (!options.previewEnabled || !options.previewPorts) throw new MarketError("preview_disabled");
      const input = previewInput(await jsonBody(req)), owner = await boundWallet(client, user.id);
      return reply(await previewEquity(input, user.id, owner, options.catalogs, options.previewPorts, options.now));
    }
    if (req.method !== "GET" || !/\/bsmart-equities\/route\/?$/.test(url.pathname)) return reply({ error: "not_found" }, 404);
    if ([...url.searchParams.keys()].some(k => k !== "ticker" || url.searchParams.getAll(k).length !== 1)) throw new MarketError("invalid_query", 422);
    const ticker = tickerInput(url.searchParams.get("ticker"));
    if (!options.discoveryEnabled) throw new MarketError("discovery_disabled");
    return reply(await resolveEVMRoute(ticker, options.catalogs, options.now));
  } catch (error) {
    return error instanceof MarketError ? reply({ error: error.code }, error.status) : reply({ error: "equities_unavailable" }, 503);
  }
}
