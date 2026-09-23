import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { resolveAvatars } from "../bsmart-profile/avatars.ts";
import { profileSearchFilter } from "../bsmart-search/handler.ts";
import { handleChat } from "./chat.ts";

const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;

async function input(req: Request): Promise<Record<string, unknown>> {
  if (req.headers.get("content-type")?.split(";")[0] !== "application/json") throw Error("invalid_input");
  const text = await req.text();
  if (text.length > 8200) throw Error("invalid_input");
  const value = JSON.parse(text);
  if (!value || typeof value !== "object" || Array.isArray(value)) throw Error("invalid_input");
  return value;
}

async function snapshotPayload(client: SupabaseClient, data: any) {
  for (const conversation of data?.conversations ?? []) {
    if (!conversation.lastMessage.text) conversation.lastMessage.text = "Photo";
  }
  return await resolveAvatars(client, data);
}

export async function handleSocial(req: Request, client: SupabaseClient): Promise<Response> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorization) || authorization.length > 16400) {
    return reply({ error: "unauthorized" }, 401);
  }
  try {
    const { data: { user }, error } = await client.auth.getUser(authorization.slice(7));
    if (error) return [400, 401, 403].includes(error.status ?? 0)
      ? reply({ error: "unauthorized" }, 401) : reply({ error: "social_unavailable" }, 503);
    if (!user || user.is_anonymous || !user.identities?.some(i => ["google", "apple"].includes(i.provider))) {
      return reply({ error: "unauthorized" }, 401);
    }
    const url = new URL(req.url);
    const path = url.pathname.split("/").filter(Boolean);
    if (path[0] !== "bsmart-social") return reply({ error: "not_found" }, 404);
    if (path[1] === "chat" && path.length === 3) return await handleChat(req, client, user.id, path[2]);

    if (path.length === 1 && req.method === "GET") {
      const { data, error } = await client.rpc("bsmart_social_snapshot", { p_actor: user.id });
      return error ? reply({ error: "social_unavailable" }, 503) : reply(await snapshotPayload(client, data));
    }
    if (path[1] === "people" && path.length === 2 && req.method === "GET") {
      const q = (url.searchParams.get("q") ?? "").normalize("NFKC").trim().replace(/^@/, "");
      if (Array.from(q).length > 80 || /[\x00-\x1f\x7f]/.test(q)) return reply({ error: "invalid_query" }, 422);
      let request = client.from("bsmart_feed_profiles")
        .select("public_id,nickname,handle,avatar_url").gt("revision", 0).neq("account_id", user.id);
      if (q) request = request.or(profileSearchFilter(q));
      const { data, error } = await request.order(q ? "nickname" : "updated_at", { ascending: !!q })
        .order("public_id").limit(20);
      if (error) return reply({ error: "social_unavailable" }, 503);
      const people = (data ?? []).map(p => ({ id: p.public_id, nickname: p.nickname,
        handle: p.handle, avatarURL: p.avatar_url }));
      return reply(await resolveAvatars(client, { people }));
    }
    const peer = path[2];
    if (!peer || !idPattern.test(peer) || path.length !== 3) return reply({ error: "not_found" }, 404);
    if (path[1] === "follows" && req.method === "POST") {
      const body = await input(req);
      if (typeof body.follow !== "boolean") return reply({ error: "invalid_input" }, 422);
      const { error } = await client.rpc("bsmart_social_follow", {
        p_actor: user.id, p_peer_public: peer, p_follow: body.follow,
      });
      if (error) return reply({ error: error.code === "P0001" ? "invalid_peer" : "social_unavailable" },
        error.code === "P0001" ? 422 : 503);
      const { data, error: readError } = await client.rpc("bsmart_social_snapshot", { p_actor: user.id });
      return readError ? reply({ error: "social_unavailable" }, 503) : reply(await snapshotPayload(client, data));
    }
    if (path[1] === "messages" && req.method === "GET") {
      const at = url.searchParams.get("beforeAt"), id = url.searchParams.get("beforeID");
      if (!!at !== !!id || (at && (!datePattern.test(at) || !Number.isFinite(Date.parse(at)))) ||
          (id && !idPattern.test(id))) return reply({ error: "invalid_query" }, 422);
      const { data, error } = await client.rpc("bsmart_social_messages_page", {
        p_actor: user.id, p_peer_public: peer, p_before_at: at, p_before_id: id,
      });
      return error ? reply({ error: error.code === "P0001" ? "invalid_peer" : "social_unavailable" },
        error.code === "P0001" ? 422 : 503) : reply(data);
    }
    if (path[1] === "messages" && req.method === "POST") {
      const body = await input(req);
      if (typeof body.text !== "string" || !body.text.trim() || body.text.trim().length > 2000) {
        return reply({ error: "invalid_input" }, 422);
      }
      const { data, error } = await client.rpc("bsmart_social_send", {
        p_actor: user.id, p_peer_public: peer, p_text: body.text,
      });
      if (error) return reply({ error: error.message === "rate_limited" ? "rate_limited" :
        error.code === "P0001" ? "invalid_peer" : "social_unavailable" },
        error.message === "rate_limited" ? 429 : error.code === "P0001" ? 422 : 503);
      return reply(data);
    }
    return reply({ error: "not_found" }, 404);
  } catch (error) {
    return error instanceof SyntaxError || (error instanceof Error && error.message === "invalid_input")
      ? reply({ error: "invalid_input" }, 422) : reply({ error: "social_unavailable" }, 503);
  }
}
