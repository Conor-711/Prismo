import { dexNames, HLMarket, object, parseHL, tickerInput } from "../supabase/functions/bsmart-markets/routing.ts";
import { readJSON } from "../supabase/functions/bsmart-markets/providers.ts";
import { Asset, Network, NETWORKS, parseAsset } from "../supabase/functions/bsmart-equities/assets.ts";
export { parseAsset };
export type { Asset };

// Editorial research candidates, not a measured popularity ranking or live allowlist.
export const CANDIDATES = "OUST ALAB AEHR IONQ RGTI QBTS QUBT SOUN BBAI SMR OKLO ASTS RKLB RDW LUNR ACHR JOBY SERV HIMS DUOL TEM NBIS CRWV PATH U HOOD SOFI UPST AFRM ON CLS VRT ANET NET GTLB MDB SNOW DDOG PLTR APP CELH CAVA RBRK IREN CIFR WULF MARA RIOT HUT CORZ BTDR TSM ASML ARM MU NVDA AAPL TSLA".split(" ");
const SYNTHETIC_ACCOUNT = "0x0000000000000000000000000000000000000001";
export type Quote = { sellAmount: string; buyAmount: string; feeAmount: string; verified: boolean; observedAt: string };
type Probe = { network: Network; token: string; variant: string; amountUSDC: number; buy?: Quote; sell?: Quote; roundTripDifferencePct?: number; error?: string; executable: false };

export function hlMatches(ticker: string, markets: HLMarket[]): string[] {
  return markets.filter(m => !m.delisted && m.coin.split(":").at(-1)?.toUpperCase() === ticker).map(m => m.coin);
}
function rawAmount(value: unknown): string {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]{0,77})$/.test(value) || BigInt(value) >= 2n ** 256n) throw new Error("quote_amount_invalid");
  return value;
}
export function parseQuote(value: unknown, sellToken: string, buyToken: string, input: string): Quote {
  const r = object(value), q = object(r.quote);
  if (typeof q.sellToken !== "string" || q.sellToken.toLowerCase() !== sellToken.toLowerCase() ||
    typeof q.buyToken !== "string" || q.buyToken.toLowerCase() !== buyToken.toLowerCase() || q.kind !== "sell" ||
    typeof r.verified !== "boolean" || typeof r.from !== "string" || r.from.toLowerCase() !== SYNTHETIC_ACCOUNT) throw new Error("quote_identity_invalid");
  const sellAmount = rawAmount(q.sellAmount), buyAmount = rawAmount(q.buyAmount), feeAmount = rawAmount(q.feeAmount);
  if (BigInt(sellAmount) <= 0n || BigInt(buyAmount) <= 0n || BigInt(sellAmount) + BigInt(feeAmount) !== BigInt(input)) throw new Error("quote_budget_invalid");
  return { sellAmount, buyAmount, feeAmount, verified: r.verified, observedAt: new Date().toISOString() };
}
export function roundTripDifference(input: string, returned: string): number {
  const initial = BigInt(rawAmount(input)), output = BigInt(rawAmount(returned));
  if (initial <= 0n) throw new Error("invalid_budget");
  return Number((initial - output) * 100_000_000n / initial) / 1_000_000;
}
export async function hlCatalog(): Promise<HLMarket[]> {
  const info = (type: string) => readJSON("https://api.hyperliquid.xyz/info", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ type }),
  });
  const before = dexNames(await info("perpDexs")), metas = await info("allPerpMetas"), after = dexNames(await info("perpDexs"));
  if (JSON.stringify(before) !== JSON.stringify(after)) throw new Error("hl_catalog_changed");
  return parseHL(before, metas);
}
async function quote(network: Network, sellToken: string, buyToken: string, input: string, quality: string): Promise<Quote> {
  const response = await fetch(`https://api.cow.fi/${NETWORKS[network].api}/api/v1/quote`, {
    method: "POST", headers: { "Content-Type": "application/json" }, signal: AbortSignal.timeout(20000), redirect: "error",
    body: JSON.stringify({ sellToken, buyToken, sellAmountBeforeFee: input, kind: "sell", from: SYNTHETIC_ACCOUNT, priceQuality: quality }),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => null);
    const type = error?.errorType;
    throw new Error(`cow_${response.status}_${typeof type === "string" && /^[A-Za-z]{1,40}$/.test(type) ? type : "unavailable"}`);
  }
  return parseQuote(await response.json(), sellToken, buyToken, input);
}
function message(error: unknown): string {
  return error instanceof Error && /^[A-Za-z0-9_]+$/.test(error.message) ? error.message : "provider_unavailable";
}
async function main(): Promise<void> {
  const args = new Map<string, string>();
  for (let i = 0; i < Deno.args.length; i += 2) {
    if (!["--tickers", "--amounts", "--networks", "--quality", "--variants", "--output"].includes(Deno.args[i]) || !Deno.args[i + 1]) throw new Error("invalid_argument");
    args.set(Deno.args[i], Deno.args[i + 1]);
  }
  const tickers = [...new Set((args.get("--tickers")?.split(",") ?? CANDIDATES).map(t => tickerInput(t)))];
  const amounts = (args.get("--amounts") ?? "100,1000").split(",").map(Number);
  const networks = (args.get("--networks") ?? "Ethereum").split(",") as Network[];
  const quality = args.get("--quality") ?? "fast", variants = args.get("--variants") ?? "raw";
  if (tickers.length > 100 || amounts.length > 5 || amounts.some(a => !Number.isSafeInteger(a) || a < 1 || a > 100000) ||
    networks.some(n => !Object.hasOwn(NETWORKS, n)) || !["fast", "optimal"].includes(quality) || !["raw", "all"].includes(variants)) throw new Error("invalid_options");
  const startedAt = new Date().toISOString(), initial = await hlCatalog();
  const results: Array<{ ticker: string; disposition: string; hlMarkets: string[]; asset?: Asset; probes: Probe[]; error?: string }> = [];
  for (const ticker of tickers) {
    const listed = hlMatches(ticker, initial);
    const row = { ticker, disposition: listed.length ? "hl_only" : "research", hlMarkets: listed, probes: [] as Probe[],
      asset: undefined as Asset | undefined, error: undefined as string | undefined };
    results.push(row);
    if (listed.length) continue;
    try {
      row.asset = parseAsset(await readJSON(`https://api.xstocks.fi/api/v2/public/assets/${encodeURIComponent(ticker + "x")}`), ticker);
      if (row.asset.halted) { row.disposition = "issuer_halted"; continue; }
      for (const deployment of row.asset.deployments.filter(d => networks.includes(d.network))) {
        const tokens = [{ token: deployment.token, variant: "raw" }];
        if (variants === "all" && deployment.wrapperV2) tokens.push({ token: deployment.wrapperV2, variant: "wrapper_v2" });
        for (const { token, variant } of tokens) for (const amountUSDC of amounts) {
          const probe: Probe = { network: deployment.network, token, variant, amountUSDC, executable: false };
          row.probes.push(probe);
          try {
            const input = String(amountUSDC * 1_000_000);
            probe.buy = await quote(deployment.network, deployment.usdc, token, input, quality);
            probe.sell = await quote(deployment.network, token, deployment.usdc, probe.buy.buyAmount, quality);
            probe.roundTripDifferencePct = roundTripDifference(input, probe.sell.buyAmount);
          } catch (error) { probe.error = message(error); }
          await new Promise(resolve => setTimeout(resolve, 150));
        }
      }
      row.disposition = row.probes.some(p => p.buy && p.sell) ? "two_way_indicative" : "no_two_way_quote";
    } catch (error) { row.disposition = "issuer_unavailable"; row.error = message(error); }
    console.error(JSON.stringify({ ticker, disposition: row.disposition,
      quotes: row.probes.map(p => ({ chain: p.network, variant: p.variant, amount: p.amountUSDC, difference: p.roundTripDifferencePct, error: p.error })) }));
  }
  // Screening is historical evidence; a new HL listing still overrides every candidate.
  const finalCatalog = await hlCatalog();
  for (const row of results) {
    row.hlMarkets = hlMatches(row.ticker, finalCatalog);
    if (row.hlMarkets.length) row.disposition = "hl_only";
    else if (row.disposition === "hl_only") row.disposition = "hl_changed_recheck_required";
  }
  const report = { startedAt, completedAt: new Date().toISOString(), executionEnabled: false,
    defaultSaleProceedsDestination: "hyperliquid_perps", returnTransferImplemented: false,
    priceQuality: quality, syntheticQuoteAccount: true, weekendObserved: [0, 6].includes(new Date(startedAt).getUTCDay()),
    weekendDepthPolicy: "soft_selection_factor", hlActiveMarketCount: finalCatalog.filter(m => !m.delisted).length,
    limitations: ["unsigned_indicative_quotes_only", "no_balance_or_allowance_proof", "no_funding_or_approval_costs", "not_realized_returns", "not_an_execution_allowlist", "weekendObserved_is_calendar_only_not_proof_of_market_closure", "xStock_symbol_discovery_requires_exact_issuer_identity"], results };
  const output = args.get("--output");
  if (output) {
    await Deno.writeTextFile(output, JSON.stringify(report, null, 2) + "\n");
    console.error(`Research report: ${output}`);
  } else console.log(JSON.stringify(report, null, 2));
}
if (import.meta.main) await main();
