import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { uuid } from "./verification.ts";

export const catalogBucket = "bsmart-feed-catalog";

export function storageCatalog(client: SupabaseClient) {
  let active: { release: string; loaded: number } | undefined;
  const items = new Map<string, any>();
  async function read(path: string, limit: number) {
    const { data, error } = await client.storage.from(catalogBucket).download(path);
    if (error && path !== "active.json" && String(error.statusCode) === "404") throw new Error("opinion_unavailable");
    if (error || !data || data.size > limit) throw new Error("catalog_unavailable");
    return JSON.parse(await data.text());
  }
  return async (opinionId: string, authorId: string) => {
    if (!uuid(opinionId)) throw new Error("invalid_input");
    if (!active || Date.now() - active.loaded > 15000) {
      const manifest = await read("active.json", 4096);
      if (manifest.schema !== 1 || !/^[0-9a-f]{64}$/.test(manifest.release)) throw new Error("invalid_catalog");
      active = { release: manifest.release, loaded: Date.now() };
    }
    const path = `${active.release}/${opinionId.toLowerCase()}.json`;
    let item = items.get(path);
    if (!item) {
      item = await read(path, 65536);
      if (items.size >= 256) items.delete(items.keys().next().value!);
      items.set(path, item);
    }
    if (item.id?.toLowerCase() !== opinionId.toLowerCase() || item.authorId !== authorId) {
      throw new Error("invalid_catalog");
    }
    return item;
  };
}
