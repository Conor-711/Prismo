import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { amountInput, Catalogs, MarketError, resolveRoute, tickerInput } from "./routing.ts";
import { preview } from "./providers.ts";

type Options = { catalogs: Catalogs; previewsEnabled: boolean; apiKey?: string; fetcher?: typeof fetch; now?: () => number };
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
export async function handleMarkets(req: Request, client: SupabaseClient, options: Options): Promise<Response> {
  const auth = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(auth) || auth.length > 16400) return reply({ error: "unauthorized" }, 401);
  try {
    const { data: { user }, error } = await client.auth.getUser(auth.slice(7));
    if (error || !user || user.is_anonymous || !user.identities?.some(i => ["google", "apple"].includes(i.provider))) return reply({ error: "unauthorized" }, 401);
    const url = new URL(req.url), match = url.pathname.match(/\/bsmart-markets\/(route|preview)\/?$/);
    if (!match || req.method !== "GET") return reply({ error: "not_found" }, 404);
    const allowed = match[1] === "preview" ? ["ticker", "amountUSDC"] : ["ticker"];
    if ([...url.searchParams.keys()].some(k => !allowed.includes(k) || url.searchParams.getAll(k).length !== 1)) throw new MarketError("invalid_query", 422);
    const ticker = tickerInput(url.searchParams.get("ticker"));
    const amount = match[1] === "preview" ? amountInput(url.searchParams.get("amountUSDC")) : null;
    if (amount && (!options.previewsEnabled || !options.apiKey)) throw new MarketError("preview_disabled");
    const route = await resolveRoute(ticker, options.catalogs, options.now);
    return reply(amount ? await preview(route, amount, options.apiKey!, options.fetcher, options.now) : route);
  } catch (error) {
    return error instanceof MarketError ? reply({ error: error.code }, error.status) : reply({ error: "markets_unavailable" }, 503);
  }
}
