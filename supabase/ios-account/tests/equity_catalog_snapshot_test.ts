import { strict as assert } from "node:assert";
import { buildCatalogSnapshot, contentHash, decodeCatalogSnapshot, publishCatalogSnapshot, snapshotRegistry,
  type SnapshotStorage } from "../supabase/functions/bsmart-equities/catalog_snapshot.ts";
import { NETWORKS } from "../supabase/functions/bsmart-equities/assets.ts";
import { equityProviders } from "../supabase/functions/bsmart-equities/providers.ts";

const at = Date.parse("2026-10-01T00:00:00Z"), now = () => at;
const nodes = () => ({ at, values: [{ id: "12345678-1234-1234-1234-123456789abc", symbol: "ASTSx", name: "ASTS",
  isTradingHalted: false, underlying: { symbol: "ASTS", currency: "USD" },
  deployments: [{ network: "Ethereum", address: "0x1111111111111111111111111111111111111111", stablecoins: [
    { symbol: "USDC", network: "Ethereum", address: NETWORKS.Ethereum.usdc, decimals: 6 }] }] }] });
function storage() {
  const files = new Map<string, Uint8Array>(), writes: string[] = [], reads: string[] = [];
  const s: SnapshotStorage = {
    read: async (path, limit) => { reads.push(path); const bytes = files.get(path); if (!bytes || bytes.length > limit) throw new Error("unavailable"); return bytes.slice(); },
    writeImmutable: async (path, bytes) => { writes.push(path); if (files.has(path)) assert.equal(await contentHash(files.get(path)!), await contentHash(bytes)); else files.set(path, bytes.slice()); },
    activate: async m => { writes.push("active.json"); files.set("active.json", new TextEncoder().encode(JSON.stringify(m))); },
  };
  return { s, files, writes, reads };
}
Deno.test("catalog snapshot binds complete parsed identities, content hash, counts and observation time", async () => {
  const built = await buildCatalogSnapshot(nodes(), at);
  const decoded = await decodeCatalogSnapshot(built.manifest, built.bytes, at);
  assert.equal(decoded.at, at); assert.equal(decoded.values[0].ticker, "ASTS");
  assert.equal(built.manifest.assetCount, 1); assert.equal(built.manifest.nodeCount, 1);
  for (const patch of [{ schema: 2 }, { sha256: "../active" }, { nodeCount: 2 }, { assetCount: 2 },
    { observedAt: new Date(at + 1).toISOString() }]) {
    await assert.rejects(() => decodeCatalogSnapshot({ ...built.manifest, ...patch } as any, built.bytes, at));
  }
  const corrupt = built.bytes.slice(); corrupt[20] ^= 1;
  await assert.rejects(() => decodeCatalogSnapshot(built.manifest, corrupt, at));
  await assert.rejects(() => buildCatalogSnapshot({ ...nodes(), at: at - 600000 }, at));
  await assert.rejects(() => buildCatalogSnapshot({ at, values: [] }, at));
  await assert.rejects(() => buildCatalogSnapshot({ at, values: [...nodes().values, ...nodes().values] }, at));
});
Deno.test("catalog publisher reads immutable payload back before activating and can retry exact content", async () => {
  const { s, writes, files } = storage();
  const m = await publishCatalogSnapshot(s, nodes(), now);
  assert.deepEqual(writes, [m.sha256 + ".json", "active.json"]);
  await publishCatalogSnapshot(s, nodes(), now); assert.equal(files.size, 2);
  let activated = false;
  await assert.rejects(() => publishCatalogSnapshot({ ...s, read: async () => new Uint8Array([1]), activate: async () => { activated = true; } }, nodes(), now));
  assert.equal(activated, false);
});
Deno.test("snapshot registry coalesces reads, isolates mutations and checks original TTL on every hit", async () => {
  const { s, reads } = storage(); await publishCatalogSnapshot(s, nodes(), now); reads.length = 0;
  let t = at;
  const registry = snapshotRegistry(s, () => t);
  const results = await Promise.all([registry(), registry(), registry()]);
  assert.equal(reads.length, 2);
  results[0].values[0].ticker = "SPY"; assert.equal(results[1].values[0].ticker, "ASTS");
  t += 1000; assert.equal((await registry()).values[0].ticker, "ASTS"); assert.equal(reads.length, 2);
  t += 15000; await registry(); assert.equal(reads.length, 3);
  t = at + 600000; await assert.rejects(registry);
  t = at - 1; await assert.rejects(registry);
});
Deno.test("snapshot cache never accepts reused hash with forged time or counts", async () => {
  const { s, files } = storage(); const m = await publishCatalogSnapshot(s, nodes(), now);
  let t = at; const registry = snapshotRegistry(s, () => t); await registry(); t += 16000;
  for (const patch of [{ observedAt: new Date(at + 1).toISOString() }, { nodeCount: 2 }]) {
    files.set("active.json", new TextEncoder().encode(JSON.stringify({ ...m, ...patch })));
    await assert.rejects(registry);
  }
});
Deno.test("configured snapshot failure does not trigger issuer pagination fallback", async () => {
  let fetches = 0;
  const provider = equityProviders((() => { fetches++; throw new Error("unexpected fetch"); }) as any, now,
    snapshotRegistry({ read: async () => { throw new Error("storage outage"); } }, now));
  await assert.rejects(provider.registry); assert.equal(fetches, 0);
});
Deno.test("warm snapshot still rechecks fresh HL and live asset status", async () => {
  const { s } = storage(); await publishCatalogSnapshot(s, nodes(), now);
  const calls: string[] = [];
  const provider = equityProviders((async (url: string, init: RequestInit) => {
    calls.push(url);
    if (url.includes("hyperliquid")) {
      const type = JSON.parse(init.body as string).type;
      return Response.json(type === "perpDexs" ? [null] : [{ collateralToken: 0, universe: [{ name: "BTC", maxLeverage: 40 }] }]);
    }
    assert.match(url, /\/assets\/ASTSx$/);
    return Response.json({ ...nodes().values[0], isTradingHalted: true });
  }) as typeof fetch, now, snapshotRegistry(s, now));
  await provider.registry(); await provider.hl(); const live = await provider.asset("ASTSx");
  assert.equal(live.values[0].halted, true); assert.equal(calls.length, 4);
  assert.equal(calls.some(url => url.includes("pageSize")), false);
});
