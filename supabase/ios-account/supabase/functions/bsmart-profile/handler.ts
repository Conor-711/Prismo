import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { avatarBucket, providerAvatar, resolveAvatars } from "./avatars.ts";
import { profileInput, readProfileBody } from "./input.ts";

const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
const present = (p: any) => ({ id: p.public_id, username: p.nickname, handle: p.handle, bio: p.bio,
  avatarURL: p.avatar_url, revision: p.revision });

export async function handleProfile(req: Request, client: SupabaseClient) {
  const auth = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(auth) || auth.length > 16400) return reply({ error: "unauthorized" }, 401);
  try {
    const { data: { user }, error } = await client.auth.getUser(auth.slice(7));
    if (error || !user || user.is_anonymous || !user.identities?.some(i => ["google", "apple"].includes(i.provider))) return reply({ error: "unauthorized" }, 401);
    if (!/\/bsmart-profile\/?$/.test(new URL(req.url).pathname) || !["GET", "PUT"].includes(req.method)) return reply({ error: "not_found" }, 404);
    const { data: current, error: profileError } = await client.rpc("bsmart_profile_ensure", { p_account: user.id });
    if (profileError || !current) throw Error("unavailable");
    if (req.method === "GET") return reply(await resolveAvatars(client, present(current)));
    const input = profileInput(await readProfileBody(req));
    if (input.revision !== current.revision) return reply({ error: "profile_conflict" }, 409);
    let avatar = current.avatar_url, uploaded: string | null = null;
    if (input.action === "remove") avatar = null;
    if (input.action === "provider") {
      avatar = providerAvatar(user);
      if (!avatar) return reply({ error: "provider_avatar_unavailable" }, 422);
    }
    if (input.image) {
      uploaded = `${current.public_id}/${crypto.randomUUID()}.jpg`;
      const { error } = await client.storage.from(avatarBucket).upload(uploaded, input.image, { contentType: "image/jpeg", upsert: false, cacheControl: "300" });
      if (error) throw Error("unavailable");
      avatar = "storage:" + uploaded;
    }
    // A timeout may hide a successful commit. Never delete the new image on an ambiguous response.
    const { data: saved, error: saveError } = await client.from("bsmart_feed_profiles").update({
      nickname: input.username, handle: input.handle, bio: input.bio, avatar_url: avatar,
      revision: input.revision + 1, updated_at: new Date().toISOString(),
    }).eq("account_id", user.id).eq("revision", input.revision).select("*").maybeSingle();
    if (saveError || !saved) {
      if (uploaded && (!saveError || saveError.code === "23505")) {
        await client.from("bsmart_profile_avatar_cleanup").insert({ path: uploaded });
      }
      if (saveError?.code === "23505") return reply({ error: "handle_taken" }, 409);
      if (!saveError) return reply({ error: "profile_conflict" }, 409);
      throw Error("unavailable");
    }
    return reply(await resolveAvatars(client, present(saved)));
  } catch (error) {
    return error instanceof Error && error.message === "invalid_profile"
      ? reply({ error: "invalid_profile" }, 422) : reply({ error: "profile_unavailable" }, 503);
  }
}
