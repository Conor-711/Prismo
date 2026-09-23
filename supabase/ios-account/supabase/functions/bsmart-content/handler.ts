import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";

const collections = new Set(["smart-accounts", "smart-account-updates", "smart-account-evidence",
  "portfolio-signals", "ticker-intelligence", "smart-money", "smart-money-movements", "smart-money-evidence"]);
const reply = (body: unknown, status = 200) => Response.json(body, {
  status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
});

export async function handleContent(req: Request, client: SupabaseClient): Promise<Response> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorization)
    || authorization.length > 16400) return reply({ error: "unauthorized" }, 401);
  try {
    // Authenticate before every read, including cached/unchanged versions.
    const { data: { user }, error } = await client.auth.getUser(authorization.slice(7));
    if (error) return [400, 401, 403].includes(error.status ?? 0)
      ? reply({ error: "unauthorized" }, 401) : reply({ error: "content_unavailable" }, 503);
    if (!user || user.is_anonymous || !user.identities?.some(i => ["google", "apple"].includes(i.provider))) {
      return reply({ error: "unauthorized" }, 401);
    }
    const url = new URL(req.url);
    if (req.method !== "GET") return reply({ error: "method_not_allowed" }, 405);
    if (url.pathname.endsWith("/bsmart-content/manifest")) {
      const { data: pointer, error: pointerError } = await client.from("bsmart_content_active")
        .select("revision").eq("channel", "production").maybeSingle();
      if (pointerError || !pointer) return reply({ error: "content_unavailable" }, 503);
      const { data, error } = await client.from("bsmart_content_releases").select("manifest")
        .eq("revision", pointer.revision).maybeSingle();
      return error || !data ? reply({ error: "content_unavailable" }, 503) : reply(data.manifest);
    }
    if (!url.pathname.endsWith("/bsmart-content/page")) return reply({ error: "not_found" }, 404);
    const revision = url.searchParams.get("revision") ?? "", collection = url.searchParams.get("collection") ?? "";
    const owner = url.searchParams.get("owner") ?? "_", rawPage = url.searchParams.get("page") ?? "0";
    if (!/^[a-f0-9]{64}$/.test(revision) || !collections.has(collection)
      || !/^[0-9]{1,5}$/.test(rawPage) || Number(rawPage) > 10000
      || !owner || owner.length > 160 || /[\x00-\x1f\x7f]/.test(owner)
      || (!collection.endsWith("-evidence") && owner !== "_")) return reply({ error: "invalid_query" }, 422);
    const page = Number(rawPage);
    const { data: release, error: releaseError } = await client.from("bsmart_content_releases")
      .select("revision").eq("revision", revision).maybeSingle();
    if (releaseError) return reply({ error: "content_unavailable" }, 503);
    if (!release) return reply({ error: "unknown_revision" }, 404);
    const { data, error: pageError } = await client.from("bsmart_content_pages").select("payload")
      .eq("revision", revision).eq("collection", collection).eq("owner", owner).eq("page", page).maybeSingle();
    if (pageError) return reply({ error: "content_unavailable" }, 503);
    if (data) return reply(data.payload);
    if (collection.endsWith("-evidence") && page === 0) return reply({ revision, page: 0, pages: 1, total: 0, items: [] });
    return reply({ error: "unknown_page" }, 404);
  } catch {
    return reply({ error: "content_unavailable" }, 503);
  }
}
