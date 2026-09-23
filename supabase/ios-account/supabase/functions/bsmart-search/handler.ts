import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { resolveAvatars } from "../bsmart-profile/avatars.ts";

const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });

export function profileSearchFilter(query: string): string {
  // Quote the PostgREST literal separately from LIKE escaping. User text is never filter syntax.
  const pattern = JSON.stringify("%" + query.replace(/[\\%_]/g, "\\$&") + "%");
  return `nickname.ilike.${pattern},handle.ilike.${pattern}`;
}

export async function handleSearch(req: Request, client: SupabaseClient): Promise<Response> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorization) || authorization.length > 16400) {
    return reply({ error: "unauthorized" }, 401);
  }
  try {
    const { data: { user }, error } = await client.auth.getUser(authorization.slice(7));
    // Only credential rejection is a 401. An Auth outage must not sign the app out.
    if (error) return [400, 401, 403].includes(error.status ?? 0)
      ? reply({ error: "unauthorized" }, 401) : reply({ error: "search_unavailable" }, 503);
    if (!user || user.is_anonymous || !user.identities?.some(i => ["google", "apple"].includes(i.provider))) {
      return reply({ error: "unauthorized" }, 401);
    }
    const url = new URL(req.url);
    if (req.method !== "GET" || !url.pathname.endsWith("/bsmart-search/profiles")) return reply({ error: "not_found" }, 404);
    const q = (url.searchParams.get("q") ?? "").normalize("NFKC").trim().replace(/^[@$#]+/, "").trim();
    const offset = Number(url.searchParams.get("offset") ?? "0"), limit = Number(url.searchParams.get("limit") ?? "20");
    if (q.length > 160 || Array.from(q).length > 80 || /[\x00-\x1f\x7f]/.test(q) ||
        !Number.isSafeInteger(offset) || offset < 0 || offset > 10000 ||
        !Number.isSafeInteger(limit) || limit < 1 || limit > 20) return reply({ error: "invalid_query" }, 422);
    let request = client.from("bsmart_feed_profiles").select("public_id,nickname,handle,avatar_url")
      .eq("visible", true).eq("feed_visible", true).gt("revision", 0);
    if (q) request = request.or(profileSearchFilter(q));
    request = q ? request.order("nickname") : request.order("updated_at", { ascending: false });
    const { data, error: readError } = await request.order("public_id").range(offset, offset + limit);
    if (readError || !Array.isArray(data)) return reply({ error: "search_unavailable" }, 503);
    const items = data.slice(0, limit).map(p => ({ id: p.public_id, nickname: p.nickname, handle: p.handle, avatarURL: p.avatar_url }));
    return reply(await resolveAvatars(client, {
      items, nextOffset: data.length > limit && offset + limit <= 10000 ? offset + limit : null,
    }));
  } catch {
    return reply({ error: "search_unavailable" }, 503);
  }
}
