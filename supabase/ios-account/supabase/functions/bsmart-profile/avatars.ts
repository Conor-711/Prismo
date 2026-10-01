import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2.116.0";

export const avatarBucket = "bsmart-profile-avatars";
const storagePath = /^[a-f0-9-]{36}\/[a-f0-9-]{36}\.jpg$/;

type SigningState = {
  entries: Map<string, { url: string; until: number }>;
  pending: Map<string, Promise<Map<string, string>>>;
};

export class SignedMediaURLCache {
  private clients = new WeakMap<SupabaseClient, SigningState>();
  constructor(private now = Date.now, private maximumEntries = 512) {}

  async resolve(client: SupabaseClient, bucket: string, input: string[], ttl: number): Promise<Map<string, string>> {
    let state = this.clients.get(client);
    if (!state) {
      state = { entries: new Map(), pending: new Map() };
      this.clients.set(client, state);
    }
    const paths = [...new Set(input)];
    const key = (path: string) => `${bucket}/${ttl}/${path}`;
    const result = new Map<string, string>();
    for (const [name, value] of state.entries) if (value.until <= this.now()) state.entries.delete(name);
    for (const path of paths) {
      const cached = state.entries.get(key(path));
      if (cached) result.set(path, cached.url);
    }
    const missing = paths.filter(path => !result.has(path) && !state!.pending.has(key(path)));
    if (missing.length) {
      const issuedAt = this.now();
      const target = state;
      const task = (async () => {
        const signed = new Map<string, string>();
        try {
          const { data, error } = await client.storage.from(bucket).createSignedUrls(missing, ttl);
          if (!error) for (const item of data ?? []) {
            if (item.path && missing.includes(item.path) && item.signedUrl && !item.error) {
              signed.set(item.path, item.signedUrl);
              target.entries.set(key(item.path), { url: item.signedUrl, until: issuedAt + Math.max(0, ttl - 60) * 1000 });
            }
          }
          while (target.entries.size > Math.max(1, this.maximumEntries)) {
            target.entries.delete(target.entries.keys().next().value!);
          }
        } catch { /* Never cache a failed signature or relax bucket access. */ }
        return signed;
      })();
      for (const path of missing) state.pending.set(key(path), task);
      void task.finally(() => {
        for (const path of missing) if (target.pending.get(key(path)) === task) target.pending.delete(key(path));
      });
    }
    const tasks = new Set(paths.map(path => state!.pending.get(key(path))).filter(task => task !== undefined));
    for (const signed of await Promise.all(tasks)) {
      for (const path of paths) if (signed.has(path)) result.set(path, signed.get(path)!);
    }
    return result;
  }
}

// Each Edge isolate reuses signatures only after the request's normal authorization and DB read.
export const signedMediaURLs = new SignedMediaURLCache();

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
  const urls = await signedMediaURLs.resolve(client, avatarBucket, paths, 300);
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
