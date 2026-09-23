import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2.116.0";

export const avatarBucket = "bsmart-profile-avatars";
const storagePath = /^[a-f0-9-]{36}\/[a-f0-9-]{36}\.jpg$/;

export function providerAvatar(user: User): string | null {
  const data = user.identities?.find(i => i.provider === "google")?.identity_data;
  const value = data?.avatar_url ?? data?.picture;
  if (typeof value !== "string" || value.length > 2048) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password && !url.port &&
      (url.hostname === "googleusercontent.com" || url.hostname.endsWith(".googleusercontent.com")) ? value : null;
  } catch { return null; }
}

// Only canonical account profiles contain storage references; author avatars stay unchanged.
export async function resolveAvatars<T>(client: SupabaseClient, payload: T): Promise<T> {
  const targets: any[] = [];
  function visit(value: any) {
    if (!value || typeof value !== "object") return;
    if (typeof value.avatarURL === "string" && value.avatarURL.startsWith("storage:")) targets.push(value);
    for (const child of Object.values(value)) visit(child);
  }
  visit(payload);
  if (!targets.length) return payload;
  const paths = [...new Set<string>(targets.map(t => t.avatarURL.slice(8)).filter(p => storagePath.test(p)))];
  const urls = new Map<string, string>();
  try {
    if (paths.length) {
      const { data } = await client.storage.from(avatarBucket).createSignedUrls(paths, 300);
      for (const item of data ?? []) if (item.path && item.signedUrl && !item.error) urls.set(item.path, item.signedUrl);
    }
  } catch { /* An unavailable avatar does not hide a verified name or trade. */ }
  for (const target of targets) target.avatarURL = urls.get(target.avatarURL.slice(8)) ?? null;
  return payload;
}

export async function cleanupAvatars(client: SupabaseClient) {
  const { data, error } = await client.from("bsmart_profile_avatar_cleanup").select("path").order("created_at").limit(10);
  if (error) throw new Error("avatar_cleanup_unavailable");
  for (const row of data ?? []) {
    if (!storagePath.test(row.path)) continue;
    const { error: removeError } = await client.storage.from(avatarBucket).remove([row.path]);
    if (!removeError) await client.from("bsmart_profile_avatar_cleanup").delete().eq("path", row.path);
  }
}
