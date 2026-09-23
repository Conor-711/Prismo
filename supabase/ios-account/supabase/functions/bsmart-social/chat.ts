import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { resolveAvatars } from "../bsmart-profile/avatars.ts";

const bucket = "bsmart-chat-images";
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const response = (body: unknown, status = 200) => Response.json(body, {
  status, headers: { "Cache-Control": "no-store" },
});
const failure = (error: { code?: string; message?: string }) => response({ error:
  error.message === "rate_limited" ? "rate_limited" : error.code === "P0001" ? "invalid_message" : "social_unavailable",
}, error.message === "rate_limited" ? 429 : error.code === "P0001" ? 422 : 503);

async function boundedJSON(req: Request): Promise<Record<string, unknown>> {
  if (req.headers.get("content-type")?.split(";")[0] !== "application/json" || !req.body) throw Error("invalid_input");
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 3 * 1024 * 1024) throw Error("invalid_input");
      chunks.push(value);
    }
  } finally { await reader.cancel(); reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const value = JSON.parse(new TextDecoder().decode(bytes));
  if (!value || typeof value !== "object" || Array.isArray(value)) throw Error("invalid_input");
  return value;
}

export function jpegImage(value: unknown): { bytes: Uint8Array; width: number; height: number } | null {
  if (value == null) return null;
  if (typeof value !== "string" || value.length > 2_796_204 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw Error("invalid_input");
  let bytes: Uint8Array;
  try { bytes = Uint8Array.from(atob(value), c => c.charCodeAt(0)); } catch { throw Error("invalid_input"); }
  if (bytes.length < 16 || bytes.length > 2_097_152 || bytes[0] !== 255 || bytes[1] !== 216 ||
      bytes.at(-2) !== 255 || bytes.at(-1) !== 217) throw Error("invalid_input");
  let offset = 2;
  while (offset + 4 < bytes.length) {
    if (bytes[offset++] !== 255) break;
    while (bytes[offset] === 255) offset++;
    const marker = bytes[offset++];
    if (marker === 218 || marker === 217) break;
    const length = bytes[offset] * 256 + bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) break;
    if ([192, 193, 194].includes(marker) && length >= 8) {
      const height = bytes[offset + 3] * 256 + bytes[offset + 4];
      const width = bytes[offset + 5] * 256 + bytes[offset + 6];
      if (width < 1 || height < 1 || width > 2048 || height > 2048) break;
      return { bytes, width, height };
    }
    offset += length;
  }
  throw Error("invalid_input");
}

export function sharedContent(value: unknown): Record<string, unknown> | null {
  if (value == null) return null;
  if (!value || typeof value !== "object" || Array.isArray(value)) throw Error("invalid_input");
  const item = value as Record<string, unknown>;
  const keys = ["kind", "id", "title", "detail", "summary", "ticker", "publishedAt", "avatarURL"];
  const avatar = typeof item.avatarURL === "string" && item.avatarURL.length <= 1024
    ? URL.parse(item.avatarURL) : null;
  if (Object.keys(item).some(key => !keys.includes(key)) ||
      !["opinion", "investor", "ticker"].includes(String(item.kind)) ||
      typeof item.id !== "string" || item.id.length < 1 || item.id.length > 128 ||
      typeof item.title !== "string" || item.title.length < 1 || item.title.length > 100 ||
      typeof item.detail !== "string" || item.detail.length > 120 ||
      (item.summary != null && (typeof item.summary !== "string" || item.summary.length > 300)) ||
      (item.ticker != null && (typeof item.ticker !== "string" || !/^[A-Z0-9:._-]{1,64}$/.test(item.ticker))) ||
      (item.publishedAt != null && (typeof item.publishedAt !== "string" ||
        !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(item.publishedAt) ||
        !Number.isFinite(Date.parse(item.publishedAt)))) ||
      (item.avatarURL != null && (!avatar || avatar.protocol !== "https:" || !avatar.hostname ||
        avatar.username !== "" || avatar.password !== "")) ||
      (item.kind === "opinion" && (!uuid.test(item.id) || !item.ticker || !item.publishedAt)) ||
      new TextEncoder().encode(JSON.stringify(item)).length > 4096) throw Error("invalid_input");
  return item;
}

async function resolveChat(client: SupabaseClient, payload: any) {
  const items = payload.items ?? [payload];
  const images = items.map((item: any) => item.image).filter(Boolean);
  if (images.length) {
    const paths = images.map((image: any) => image.path);
    const { data, error } = await client.storage.from(bucket).createSignedUrls(paths, 3600);
    if (error) throw Error("storage_unavailable");
    const signed = new Map((data ?? []).map(item => [item.path, item.signedUrl]));
    for (const image of images) {
      const url = signed.get(image.path);
      if (!url) throw Error("storage_unavailable");
      image.url = url;
      delete image.path;
    }
  }
  return await resolveAvatars(client, payload);
}

export async function handleChat(req: Request, client: SupabaseClient, actor: string, room: string): Promise<Response> {
  if (room !== "global" && !uuid.test(room)) return response({ error: "not_found" }, 404);
  if (req.method === "GET") {
    const params = new URL(req.url).searchParams;
    const at = params.get("beforeAt"), id = params.get("beforeID");
    if ((at === null) !== (id === null) || (at !== null &&
      (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/.test(at) || !Number.isFinite(Date.parse(at)))) ||
      (id !== null && !uuid.test(id))) return response({ error: "invalid_query" }, 422);
    const { data, error } = await client.rpc("bsmart_chat_page", {
      p_actor: actor, p_room: room, p_before_at: at, p_before_id: id,
    });
    return error ? failure(error) : response(await resolveChat(client, data));
  }
  if (req.method !== "POST") return response({ error: "not_found" }, 404);
  const body = await boundedJSON(req);
  if (typeof body.id !== "string" || !uuid.test(body.id) || typeof body.text !== "string" ||
    [...body.text.trim()].length > 2000 || (body.replyToID != null &&
      (typeof body.replyToID !== "string" || !uuid.test(body.replyToID)))) throw Error("invalid_input");
  const image = jpegImage(body.imageBase64);
  const share = sharedContent(body.share);
  if (!body.text.trim() && !image && !share) throw Error("invalid_input");
  const hash = image ? Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", Uint8Array.from(image.bytes).buffer)))
    .map(b => b.toString(16).padStart(2, "0")).join("") : null;
  if (image) {
    const { error: reserveError } = await client.rpc("bsmart_chat_reserve_image", {
      p_actor: actor, p_room: room, p_id: body.id, p_hash: hash,
    });
    if (reserveError) return failure(reserveError);
    // Content-addressed immutable uploads make lost-response retries safe.
    const { error } = await client.storage.from(bucket).upload(`${body.id.toLowerCase()}-${hash}.jpg`, image.bytes,
      { contentType: "image/jpeg", upsert: false, cacheControl: "3600" });
    if (error && String((error as any).statusCode) !== "409" && (error as any).error !== "Duplicate") {
      return response({ error: "image_upload_failed" }, 503);
    }
  }
  const sendArgs: Record<string, unknown> = {
    p_actor: actor, p_room: room, p_id: body.id, p_text: body.text.trim(),
    p_reply_id: body.replyToID ?? null, p_image_hash: hash,
    p_image_width: image?.width ?? null, p_image_height: image?.height ?? null,
  };
  if (share) sendArgs.p_share = share;
  const { data, error } = await client.rpc("bsmart_chat_send", sendArgs);
  // Do not delete an upload after an uncertain commit; retries reuse this ID.
  return error ? failure(error) : response(await resolveChat(client, data));
}
