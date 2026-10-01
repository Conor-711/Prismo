import { equityProviders } from "../supabase/functions/bsmart-equities/providers.ts";
import { previewEquity } from "../supabase/functions/bsmart-equities/preview.ts";
import { cowQuote } from "../supabase/functions/bsmart-equities/cow.ts";
import { chainReader } from "../supabase/functions/bsmart-equities/chain.ts";
import { MarketError } from "../supabase/functions/bsmart-markets/routing.ts";

// Fixed public synthetic address, no signer or user ownership. Existing public balances
// at this address do not prove a real user's funded quote or allowance.
const owner = "0x0000000000000000000000000000000000000001";
async function main() {
  if (Deno.args.length !== 0 && (Deno.args.length !== 2 || Deno.args[0] !== "--output")) throw Error("invalid_argument");
  const startedAt = new Date().toISOString(), start = Date.now();
  let result: unknown, failed = false;
  try {
    result = await previewEquity({ ticker: "ASTS", side: "buy", amount: "100", slippageBps: 50, maxNetworkFeeBps: 1000 },
      "synthetic-public-smoke", owner, equityProviders(), { state: chainReader(), quote: cowQuote() });
  } catch (error) {
    failed = true;
    result = { error: error instanceof MarketError ? error.code : "smoke_unavailable" };
  }
  const report = { startedAt, completedAt: new Date().toISOString(), elapsedMs: Date.now() - start,
    syntheticOwnerWithoutSigner: true, authenticatedHTTPTest: false, fundedQuoteTest: false,
    orderSubmitted: false, fundsMoved: false, executionEnabled: false, result };
  if (Deno.args[1]) await Deno.writeTextFile(Deno.args[1], JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify(report, null, 2));
  if (failed) Deno.exitCode = 1;
}
if (import.meta.main) await main();
