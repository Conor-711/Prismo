import { NETWORKS } from "../supabase/functions/bsmart-equities/assets.ts";
import { relayFundingQuote } from "../supabase/functions/bsmart-equities/relay_funding.ts";
import type { BridgeRequest } from "../supabase/functions/bsmart-equities/funding_types.ts";
import { MarketError } from "../supabase/functions/bsmart-markets/routing.ts";

// Address from Relay's public integration example. No ownership or signer is implied.
const owner = "0xf3d63166f0ca56c3c1a3508fce03ff0cf3fb691e";
async function main() {
  if (Deno.args.length !== 0 && (Deno.args.length !== 2 || Deno.args[0] !== "--output")) throw Error("invalid_argument");
  const start = Date.now(), routes: unknown[] = [], quote = relayFundingQuote();
  for (const network of ["Ethereum", "Ink"] as const) {
    for (const direction of ["funding", "return"] as const) {
      const request: BridgeRequest = direction === "funding" ? { owner, source: "HyperCorePerps", destination: network, amountRaw: "10000000000" }
        : { owner, source: network, destination: "HyperCorePerps", amountRaw: "100000000" };
      try { routes.push({ network, chainId: NETWORKS[network].chainId, direction, amountUsdc: "100", quote: await quote(request) }); }
      catch (error) { routes.push({ network, direction, error: error instanceof MarketError ? error.code : "smoke_unavailable" }); }
    }
  }
  const report = { startedAt: new Date(start).toISOString(), completedAt: new Date().toISOString(), elapsedMs: Date.now() - start,
    publicDocumentationOwnerWithoutSigner: true, authenticatedHTTPTest: false, fundedQuoteTest: false,
    fundsMoved: false, orderSubmitted: false, executionEnabled: false, gasCoverage: "unverified", routes };
  if (Deno.args[1]) await Deno.writeTextFile(Deno.args[1], JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify(report, null, 2));
}
if (import.meta.main) await main();
