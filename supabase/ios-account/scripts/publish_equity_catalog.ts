import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { readIssuerNodes } from "../supabase/functions/bsmart-equities/providers.ts";
import { buildCatalogSnapshot, publishCatalogSnapshot, storageSnapshot } from "../supabase/functions/bsmart-equities/catalog_snapshot.ts";

const args = [...Deno.args];
const publish = args[0] === "--publish";
if (publish) args.shift();
if (args.length !== 2 || args[0] !== "--output" || !args[1]) throw new Error("Usage: publish_equity_catalog.ts [--publish] --output directory");
const started = Date.now(), nodes = await readIssuerNodes(), built = await buildCatalogSnapshot(nodes);
await Deno.mkdir(args[1], { recursive: true });
await Deno.writeFile(args[1] + "/" + built.manifest.sha256 + ".json", built.bytes);
await Deno.writeTextFile(args[1] + "/active.json", JSON.stringify(built.manifest, null, 2));
if (publish) {
  const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key || !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url)) throw new Error("Trusted Supabase configuration required");
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  await publishCatalogSnapshot(storageSnapshot(client), nodes);
}
console.log(JSON.stringify({ status: publish ? "published" : "prepared", ...built.manifest,
  bytes: built.bytes.length, elapsedMs: Date.now() - started, executionEnabled: false }));
