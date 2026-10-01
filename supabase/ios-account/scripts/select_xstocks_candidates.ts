import { object, tickerInput, HLMarket } from "../supabase/functions/bsmart-markets/routing.ts";
import { Asset, hlCatalog, hlMatches, parseAsset } from "./screen_xstocks.ts";

// Daily-reset leveraged/inverse products need a separate product and risk model.
export const DEFERRED_PRODUCTS = new Set("TSLL TQQQ SQQQ NVDL SOXL SOXS UVXY TMF BITX SPXL KORU DRXL QQL MVLL MUU BWYL INTW".split(" "));
type Candidate = { ticker: string; symbol: string; assetId: string; name: string; mentions: number; authors: number; networks: string[] };

export function rankCandidates(registry: unknown, popularity: unknown, markets: HLMarket[], limit: number) {
  const r = object(registry), p = object(popularity);
  if (r.completeRegistry !== true || r.executionEnabled !== false || !Array.isArray(r.nodes) ||
    p.source !== "bsmart_x_opinion_committed_snapshot" || p.metric !== "distinct_ticker_tweet_count" ||
    !Array.isArray(p.nodes) || !Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error("invalid_selection_input");
  const assets = new Map<string, Asset>(), ids = new Set<string>(), rejected: Array<{ ticker: string; reason: string }> = [];
  for (const value of r.nodes) {
    const a = object(value), u = object(a.underlying);
    if (u.currency !== "USD") continue;
    if (typeof u.symbol !== "string") throw new Error("invalid_underlying");
    if (typeof a.id !== "string" || ids.has(a.id)) throw new Error("duplicate_issuer_identity");
    ids.add(a.id);
    const ticker = tickerInput(u.symbol);
    if (assets.has(ticker)) throw new Error("ambiguous_underlying");
    // Preserve duplicate detection even for entries that fail deployment validation.
    assets.set(ticker, { id: a.id, symbol: "", ticker, name: "", halted: true, tradingHours: null, deployments: [] });
    try { assets.set(ticker, parseAsset(a, ticker)); }
    catch { rejected.push({ ticker, reason: "issuer_validation_failed" }); }
  }
  const seen = new Set<string>(), ranked: Candidate[] = [];
  for (const value of p.nodes) {
    const metric = object(value);
    if (typeof metric.ticker !== "string") throw new Error("invalid_popularity_ticker");
    const ticker = tickerInput(metric.ticker);
    if (seen.has(ticker) || !Number.isSafeInteger(metric.mentions) || (metric.mentions as number) <= 0 ||
      !Number.isSafeInteger(metric.authors) || (metric.authors as number) < 0 || (metric.authors as number) > (metric.mentions as number)) throw new Error("invalid_popularity_metric");
    seen.add(ticker);
    const a = assets.get(ticker);
    const reason = hlMatches(ticker, markets).length ? "hl_only" : !a ? "not_in_verified_usd_registry" :
      !a.symbol ? "issuer_validation_failed" : a.halted ? "issuer_halted" :
      !a.deployments.length ? "no_supported_evm_deployment" : DEFERRED_PRODUCTS.has(ticker) ? "leveraged_or_inverse_product_deferred" : null;
    if (reason) { rejected.push({ ticker, reason }); continue; }
    if (!a) throw new Error("invalid_selection_state");
    ranked.push({ ticker, symbol: a.symbol, assetId: a.id, name: a.name, mentions: metric.mentions as number,
      authors: metric.authors as number, networks: a.deployments.map(d => d.network) });
  }
  ranked.sort((a, b) => b.mentions - a.mentions || b.authors - a.authors || a.ticker.localeCompare(b.ticker));
  return { eligibleCount: ranked.length, candidates: ranked.slice(0, limit), rejected };
}

async function main() {
  const args = new Map<string, string>();
  for (let i = 0; i < Deno.args.length; i += 2) {
    if (!["--registry", "--popularity", "--limit", "--output"].includes(Deno.args[i]) || !Deno.args[i + 1] || args.has(Deno.args[i])) throw new Error("invalid_arguments");
    args.set(Deno.args[i], Deno.args[i + 1]);
  }
  if (!args.get("--registry") || !args.get("--popularity") || !args.get("--output")) throw new Error("missing_arguments");
  const registry = object(JSON.parse(await Deno.readTextFile(args.get("--registry")!)));
  const popularity = object(JSON.parse(await Deno.readTextFile(args.get("--popularity")!)));
  const now = Date.now();
  for (const snapshot of [registry, popularity]) {
    const at = Date.parse(snapshot.observedAt as string);
    if (!Number.isFinite(at) || at > now || now - at > 86_400_000) throw new Error("research_snapshot_expired");
  }
  const result = rankCandidates(registry, popularity, await hlCatalog(), Number(args.get("--limit") ?? "75"));
  const report = { observedAt: new Date().toISOString(), executionEnabled: false, rankingBasis: "sampled_X_mentions_not_global_popularity",
    registryObservedAt: registry.observedAt, popularityObservedAt: popularity.observedAt,
    windowStart: popularity.windowStart, windowEndExclusive: popularity.windowEndExclusive,
    limitations: popularity.limitations, quoteStatus: "untested", ...result };
  await Deno.writeTextFile(args.get("--output")!, JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify({ eligibleCount: result.eligibleCount, selected: result.candidates.length,
    tickers: result.candidates.map(a => a.ticker).join(","), rejected: result.rejected.length }));
}
if (import.meta.main) await main();
