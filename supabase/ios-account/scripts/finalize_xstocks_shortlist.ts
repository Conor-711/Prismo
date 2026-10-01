import { object, HLMarket } from "../supabase/functions/bsmart-markets/routing.ts";
import { hlCatalog, hlMatches } from "./screen_xstocks.ts";

// This research screen is not a user fee limit or an execution allowlist.
const RESEARCH_DIFFERENCE_PCT = 3;
type Observation = { network: string; token: string; amountUSDC: number; roundTripDifferencePct: number; observedAt: string };

export function finalizeShortlist(selection: unknown, reports: unknown[], markets: HLMarket[], limit = 50) {
  const s = object(selection);
  if (s.executionEnabled !== false || !Array.isArray(s.candidates) || !Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error("invalid_shortlist_input");
  const rows: Record<string, unknown>[] = [];
  for (const input of reports) {
    const r = object(input);
    if (r.executionEnabled !== false || r.syntheticQuoteAccount !== true || !Array.isArray(r.results)) throw new Error("invalid_research_report");
    rows.push(...r.results.map(object));
  }
  const candidates = [], reserves = [], seen = new Set<string>();
  for (const value of s.candidates) {
    const c = object(value), ticker = c.ticker as string;
    if (typeof ticker !== "string" || seen.has(ticker) || typeof c.assetId !== "string" || typeof c.symbol !== "string") throw new Error("invalid_candidate_identity");
    seen.add(ticker);
    const observations: Observation[] = [];
    for (const row of rows.filter(r => r.ticker === ticker && r.disposition === "two_way_indicative")) {
      const a = object(row.asset);
      if (a.id !== c.assetId || a.symbol !== c.symbol || a.ticker !== ticker || a.halted !== false || !Array.isArray(a.deployments) || !Array.isArray(row.probes)) throw new Error("quote_identity_mismatch");
      for (const value of row.probes) {
        const p = object(value);
        if (p.error || !Number.isFinite(p.roundTripDifferencePct)) continue;
        const buy = object(p.buy), sell = object(p.sell);
        if (p.executable !== false || p.variant !== "raw" || typeof p.network !== "string" || typeof p.token !== "string" ||
          ![100, 1000].includes(p.amountUSDC as number) || typeof buy.observedAt !== "string" || typeof sell.observedAt !== "string" ||
          typeof buy.verified !== "boolean" || typeof sell.verified !== "boolean" ||
          !a.deployments.some(d => object(d).network === p.network && object(d).token === p.token)) throw new Error("invalid_quote_observation");
        observations.push({ network: p.network, token: p.token, amountUSDC: p.amountUSDC as number,
          roundTripDifferencePct: p.roundTripDifferencePct as number, observedAt: sell.observedAt });
      }
    }
    const large = observations.filter(p => p.amountUSDC === 1000);
    const best = large.toSorted((a, b) => a.roundTripDifferencePct - b.roundTripDifferencePct)[0];
    const reason = hlMatches(ticker, markets).length ? "hl_only" : !best ? "no_1000_two_way_observation" :
      best.roundTripDifferencePct > RESEARCH_DIFFERENCE_PCT ? "high_reference_difference" : null;
    const entry = { ...c, ticker, executable: false, observations, best1000: best ?? null };
    if (reason) reserves.push({ ...entry, reason });
    else candidates.push(entry);
  }
  return { executionEnabled: false, defaultSaleProceedsDestination: "hyperliquid_perps", returnTransferImplemented: false,
    rankingBasis: s.rankingBasis, windowStart: s.windowStart, windowEndExclusive: s.windowEndExclusive,
    researchDifferenceScreenPct: RESEARCH_DIFFERENCE_PCT, eligibleCount: candidates.length,
    candidates: candidates.slice(0, limit), reserves,
    additionalQualifiedCandidates: candidates.slice(limit), weekendObserved: false,
    limitations: ["sampled_X_mentions_not_global_popularity", "synthetic_unsigned_quotes_not_fills", "initial_approval_funding_return_and_sponsor_costs_excluded", "sequential_quotes_not_simultaneous_route_comparison", "research_screen_not_execution_authority"] };
}

if (import.meta.main) {
  if (Deno.args.length !== 4) throw new Error("usage: selection ethereum-report ink-report output");
  const inputs = await Promise.all(Deno.args.slice(0, 3).map(async path => JSON.parse(await Deno.readTextFile(path))));
  for (const input of inputs) {
    const at = Date.parse(input.completedAt ?? input.observedAt);
    if (!Number.isFinite(at) || at > Date.now() || Date.now() - at > 86_400_000) throw new Error("research_snapshot_expired");
  }
  const result = { observedAt: new Date().toISOString(), ...finalizeShortlist(inputs[0], inputs.slice(1), await hlCatalog()) };
  if (result.candidates.length !== 50) throw new Error("insufficient_qualified_candidates");
  await Deno.writeTextFile(Deno.args[3], JSON.stringify(result, null, 2) + "\n");
  console.log(JSON.stringify({ selected: result.candidates.length, qualified: result.eligibleCount, reserves: result.reserves.length,
    tickers: result.candidates.map(c => c.ticker).join(",") }));
}
