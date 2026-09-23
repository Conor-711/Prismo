import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { uuid } from "./verification.ts";

export function thesisInput(input: unknown, like: boolean): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("invalid_input");
  const value = input as Record<string, unknown>;
  if (Object.keys(value).join() !== (like ? "liked" : "body")) throw new Error("invalid_input");
  if (like) {
    if (typeof value.liked !== "boolean") throw new Error("invalid_input");
    return { p_liked: value.liked };
  }
  if (typeof value.body !== "string") throw new Error("invalid_input");
  const body = value.body.trim();
  if (!body || [...body].length > 1000 || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/u.test(body)) {
    throw new Error("invalid_input");
  }
  return { p_body: body };
}

export async function mutateThesis(path: string, input: unknown, client: SupabaseClient, actor: string) {
  const match = path.match(/^\/(trades|theses)\/([^/]+)\/(thesis|like)$/);
  if (!match || !uuid(match[2]) || !["trades/thesis", "theses/like"].includes(`${match[1]}/${match[3]}`)) {
    throw new Error("invalid_input");
  }
  const like = match[3] === "like";
  const { data, error } = await client.rpc(like ? "bsmart_thesis_like" : "bsmart_thesis_publish", {
    p_actor: actor, p_trade: match[2], ...thesisInput(input, like),
  });
  if (error?.code === "PGRST202") return { body: { error: "thesis_not_ready" }, status: 503 };
  if (error || !data) return { body: { error: "feed_unavailable" }, status: 503 };
  const statuses: Record<string, number> = { not_found: 404, trade_pending: 409, thesis_exists: 409, own_thesis: 422, invalid_input: 422 };
  return { body: data, status: data.error ? (statuses[data.error] ?? 503) : 200 };
}
