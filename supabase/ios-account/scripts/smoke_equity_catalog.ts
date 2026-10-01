import { snapshotRegistry } from "../supabase/functions/bsmart-equities/catalog_snapshot.ts";
import { V1_TICKERS } from "../supabase/functions/bsmart-equities/inventory.ts";

if (Deno.args.length !== 4 || Deno.args[0] !== "--directory" || Deno.args[2] !== "--output")
  throw new Error("Usage: smoke_equity_catalog.ts --directory directory --output report.json");
let reads = 0;
const registry = snapshotRegistry({ read: async (path, limit) => {
  reads++;
  const bytes = await Deno.readFile(Deno.args[1] + "/" + path);
  if (bytes.length > limit) throw new Error("oversized_snapshot");
  return bytes;
} });
const started = performance.now(), cold = await registry(), coldMs = performance.now() - started;
const warmStart = performance.now(), warm = await registry(), warmMs = performance.now() - warmStart;
const found = new Set(cold.values.map(a => a.ticker)), missing = [...V1_TICKERS].filter(t => !found.has(t));
if (missing.length || warm.at !== cold.at) throw new Error("catalog_inventory_mismatch");
const report = { status: "local_snapshot_validated", observedAt: new Date(cold.at).toISOString(),
  checkedAt: new Date().toISOString(), assetCount: found.size, inventoryCount: V1_TICKERS.size, missing, reads,
  coldLocalReadMs: coldMs, warmLocalReadMs: warmMs, productionStorageTest: false,
  authenticatedHTTPTest: false, executionEnabled: false, fundsMoved: false };
await Deno.writeTextFile(Deno.args[3], JSON.stringify(report, null, 2));
console.log(JSON.stringify(report));
