import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { fresh, ISSUER_REGISTRY_TTL_MS, MarketError, object, type Snapshot } from "../bsmart-markets/routing.ts";
import { parseIssuerRegistry, type Asset } from "./assets.ts";

export const EQUITY_CATALOG_BUCKET = "bsmart-equity-catalog";
const LIMIT = 4 * 1024 * 1024;
export type CatalogManifest = { schema: 1; sha256: string; observedAt: string; nodeCount: number; assetCount: number };
export type SnapshotStorage = { read: (path: string, limit: number) => Promise<Uint8Array>;
  writeImmutable: (path: string, bytes: Uint8Array) => Promise<void>; activate: (manifest: CatalogManifest) => Promise<void> };
const bad = () => new MarketError("catalog_snapshot_unavailable");
const encode = (v: unknown) => new TextEncoder().encode(JSON.stringify(v));
const parse = (bytes: Uint8Array, limit: number) => {
  if (!bytes.length || bytes.length > limit) throw bad();
  try { return object(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes))); } catch { throw bad(); }
};
export async function contentHash(bytes: Uint8Array) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)))].map(b => b.toString(16).padStart(2, "0")).join("");
}
function manifest(value: unknown, now: number): CatalogManifest {
  const m = object(value);
  if (Object.keys(m).toSorted().join(",") !== "assetCount,nodeCount,observedAt,schema,sha256" || m.schema !== 1 ||
    typeof m.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(m.sha256) ||
    typeof m.observedAt !== "string" || !Number.isFinite(Date.parse(m.observedAt)) ||
    !Number.isInteger(m.nodeCount) || (m.nodeCount as number) < 1 || (m.nodeCount as number) > 10000 ||
    !Number.isInteger(m.assetCount) || (m.assetCount as number) < 1 || (m.assetCount as number) > (m.nodeCount as number)) throw bad();
  fresh({ at: Date.parse(m.observedAt), values: [] }, now, ISSUER_REGISTRY_TTL_MS);
  return m as CatalogManifest;
}
export async function buildCatalogSnapshot(nodes: Snapshot<unknown>, now: number = Date.now()) {
  fresh(nodes, now, ISSUER_REGISTRY_TTL_MS);
  if (!nodes.values.length || nodes.values.length > 10000) throw bad();
  const assets = parseIssuerRegistry(nodes.values);
  if (!assets.length) throw bad();
  // Keep every registry identity, but omit bulky issuer documents and unrelated
  // deployments. Parse the entire source first; never build from a shortlist.
  const byId = new Map(assets.map(a => [a.id, a]));
  const compact = nodes.values.map(value => {
    const r = object(value), a = byId.get(r.id as string), u = object(r.underlying);
    if (!a) return { id: r.id, symbol: r.symbol, underlying: { symbol: u.symbol, currency: u.currency } };
    return { id: a.id, symbol: a.symbol, name: a.name, isTradingHalted: a.halted,
      underlying: { symbol: a.ticker, currency: "USD" }, deployments: a.deployments.map(d => ({
        network: d.network, address: d.token, wrapperAddressV2: d.wrapperV2,
        stablecoins: [{ symbol: "USDC", network: d.network, address: d.usdc, decimals: 6 }],
      })) };
  });
  const bytes = encode({ schema: 1, at: nodes.at, nodes: compact });
  if (bytes.length > LIMIT) throw bad();
  const result: CatalogManifest = { schema: 1, sha256: await contentHash(bytes), observedAt: new Date(nodes.at).toISOString(),
    nodeCount: nodes.values.length, assetCount: assets.length };
  return { bytes, manifest: result };
}
export async function decodeCatalogSnapshot(m: CatalogManifest, bytes: Uint8Array, now: number): Promise<Snapshot<Asset>> {
  manifest(m, now);
  if (bytes.length > LIMIT || await contentHash(bytes) !== m.sha256) throw bad();
  const p = parse(bytes, LIMIT);
  if (Object.keys(p).toSorted().join(",") !== "at,nodes,schema" || p.schema !== 1 || p.at !== Date.parse(m.observedAt) ||
    !Array.isArray(p.nodes) || p.nodes.length !== m.nodeCount) throw bad();
  const values = parseIssuerRegistry(p.nodes);
  if (values.length !== m.assetCount) throw bad();
  fresh({ at: p.at as number, values }, now, ISSUER_REGISTRY_TTL_MS);
  return { at: p.at as number, values };
}
export function snapshotRegistry(storage: Pick<SnapshotStorage, "read">, now: () => number = Date.now) {
  let active: { manifest: CatalogManifest; checked: number; snapshot: Snapshot<Asset> } | undefined;
  let pending: Promise<Snapshot<Asset>> | undefined;
  return async (): Promise<Snapshot<Asset>> => {
    const t = now();
    if (active && t >= active.checked && t - active.checked < 15_000 && t >= active.snapshot.at && t - active.snapshot.at < ISSUER_REGISTRY_TTL_MS) return structuredClone(active.snapshot);
    if (!pending) pending = (async () => {
      const m = manifest(parse(await storage.read("active.json", 4096), 4096), now());
      if (active?.manifest.sha256 === m.sha256 && (active.manifest.observedAt !== m.observedAt ||
        active.manifest.nodeCount !== m.nodeCount || active.manifest.assetCount !== m.assetCount)) throw bad();
      const snapshot = active?.manifest.sha256 === m.sha256 ? active.snapshot :
        await decodeCatalogSnapshot(m, await storage.read(m.sha256 + ".json", LIMIT), now());
      // Revalidate even when a pointer reuses the same immutable object; no TTL extension.
      if (snapshot.at !== Date.parse(m.observedAt) || snapshot.values.length !== m.assetCount) throw bad();
      fresh(snapshot, now(), ISSUER_REGISTRY_TTL_MS);
      active = { manifest: m, checked: now(), snapshot };
      return snapshot;
    })().finally(() => { pending = undefined; });
    try { return structuredClone(await pending); } catch { throw bad(); }
  };
}
export async function publishCatalogSnapshot(storage: SnapshotStorage, nodes: Snapshot<unknown>, now: () => number = Date.now) {
  const built = await buildCatalogSnapshot(nodes, now());
  await storage.writeImmutable(built.manifest.sha256 + ".json", built.bytes);
  // Never update the pointer before immutable content has been read back and validated.
  await decodeCatalogSnapshot(built.manifest, await storage.read(built.manifest.sha256 + ".json", LIMIT), now());
  await storage.activate(built.manifest);
  const current = manifest(parse(await storage.read("active.json", 4096), 4096), now());
  if (current.sha256 !== built.manifest.sha256) throw bad();
  return built.manifest;
}
export function storageSnapshot(client: SupabaseClient): SnapshotStorage {
  const bucket = client.storage.from(EQUITY_CATALOG_BUCKET);
  const read: SnapshotStorage["read"] = async (path, limit) => {
    const { data, error } = await bucket.download(path);
    if (error || !data || data.size > limit) throw bad();
    return new Uint8Array(await data.arrayBuffer());
  };
  return { read,
    writeImmutable: async (path, bytes) => {
      const { error } = await bucket.upload(path, bytes, { contentType: "application/json", upsert: false, cacheControl: "0" });
      if (error) {
        // Retry after an unknown upload is safe only for identical content, never overwrite.
        const existing = await read(path, LIMIT);
        if (await contentHash(existing) !== await contentHash(bytes)) throw bad();
      }
    },
    activate: async m => {
      const { error } = await bucket.upload("active.json", encode(m), { contentType: "application/json", upsert: true, cacheControl: "0" });
      if (error) throw bad();
    },
  };
}
