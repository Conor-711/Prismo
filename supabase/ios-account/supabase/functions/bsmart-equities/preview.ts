import { MarketError } from "../bsmart-markets/routing.ts";
import { address, type ChainState, type CowQuoteMaterial, type PreviewInput, quoteRequest, type QuoteRequest, validateQuoteArtifacts, validateState } from "./quote.ts";
import { type EVMCatalogs, type EVMInstrument, resolveEVMRoute, resolveExitInstruments } from "./routing.ts";

export type PreviewPorts = {
  state: (instrument: EVMInstrument, owner: string) => Promise<ChainState>;
  quote: (instrument: EVMInstrument, request: QuoteRequest) => Promise<unknown>;
};
async function selected(input: PreviewInput, catalogs: EVMCatalogs, now: () => number) {
  if (input.side === "sell") return (await resolveExitInstruments(input.ticker, catalogs, now)).instruments;
  const route = await resolveEVMRoute(input.ticker, catalogs, now);
  if (route.venue !== "xstocks" || route.status !== "available") throw new MarketError("xstocks_route_required", 409);
  return route.instruments;
}
export async function previewEquityArtifacts(input: PreviewInput, account: string, boundOwner: string,
  catalogs: EVMCatalogs, ports: PreviewPorts, now: () => number = Date.now) {
  const owner = address(boundOwner), instruments = await selected(input, catalogs, now);
  if (!instruments.length || instruments.length > 2) throw new MarketError("instrument_unavailable", 409);
  const candidates: Awaited<ReturnType<typeof validateQuoteArtifacts>>["preview"][] = [], materials: CowQuoteMaterial[] = [];
  const failures: { network: EVMInstrument["network"]; error: string }[] = [];
  for (const instrument of instruments) {
    try {
      const state = await ports.state(instrument, owner);
      const request = quoteRequest(instrument, owner, input, state, now());
      const result = await ports.quote(instrument, request);
      // Re-read current balance/rebase state, without caching, after the provider competition.
      const latest = await ports.state(instrument, owner);
      validateState(latest, instrument, owner, now());
      quoteRequest(instrument, owner, input, latest, now());
      if (latest.multiplier !== state.multiplier || latest.multiplierNonce !== state.multiplierNonce ||
        BigInt(latest.block) < BigInt(state.block)) throw new MarketError("corporate_action_changed");
      const artifact = await validateQuoteArtifacts(result, request, instrument, input, latest, account, now());
      candidates.push(artifact.preview); materials.push(artifact.material);
    } catch (error) {
      failures.push({ network: instrument.network, error: error instanceof MarketError ? error.code : "preview_unavailable" });
    }
  }
  // A quote is not permission to ignore a newly listed HL market or changed issuer identity.
  const current = await selected(input, catalogs, now);
  if (JSON.stringify(current) !== JSON.stringify(instruments)) throw new MarketError("instrument_changed");
  const fresh = candidates.filter(c => Date.parse(c.expiresAt) > now() + 5000 && now() - Date.parse(c.observedAt) < 30_000);
  for (const c of candidates.filter(c => !fresh.includes(c))) failures.push({ network: c.instrument.network, error: "quote_expired" });
  if (!fresh.length) throw new MarketError("preview_unavailable");
  return { preview: { ticker: input.ticker, side: input.side, candidates: fresh, failures, executionEnabled: false as const,
    gasCoverage: "unverified" as const, defaultSaleProceedsDestination: "hyperliquid_perps" as const, returnTransferImplemented: false as const },
    materials: materials.filter(m => fresh.some(c => c.instrument.network === m.instrument.network)) };
}
export async function previewEquity(input: PreviewInput, account: string, boundOwner: string,
  catalogs: EVMCatalogs, ports: PreviewPorts, now: () => number = Date.now) {
  return (await previewEquityArtifacts(input, account, boundOwner, catalogs, ports, now)).preview;
}
