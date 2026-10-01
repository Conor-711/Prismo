import { MarketError } from "../supabase/functions/bsmart-markets/routing.ts";
import { equityProviders } from "../supabase/functions/bsmart-equities/providers.ts";
import { resolveEVMRoute } from "../supabase/functions/bsmart-equities/routing.ts";

// Public metadata only. Never use a user token, wallet, order or transaction.
if (Deno.args.length !== 1) throw new Error("usage: output-json-path");
const catalogs = equityProviders(), startedAt = new Date().toISOString(), results = [];
for (const ticker of ["NVDA", "ASTS", "SPY", "JPM", "OUST"]) {
  const started = Date.now();
  try {
    const route = await resolveEVMRoute(ticker, catalogs);
    results.push({ ticker, durationMs: Date.now() - started, route });
    console.log(JSON.stringify({ ticker, venue: route.venue, reason: route.reason, networks: route.instruments.map(i => i.network) }));
  } catch (error) {
    const code = error instanceof MarketError ? error.code : "equities_unavailable";
    results.push({ ticker, durationMs: Date.now() - started, error: code });
    console.log(JSON.stringify({ ticker, error: code }));
  }
}
await Deno.writeTextFile(Deno.args[0], JSON.stringify({ startedAt, completedAt: new Date().toISOString(),
  executionEnabled: false, metadataOnly: true, authenticatedHTTPTest: false, results }, null, 2) + "\n");
if (results.some(r => "error" in r)) Deno.exit(1);
