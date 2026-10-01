import { SignedMediaURLCache } from "../supabase/functions/bsmart-profile/avatars.ts";
import { resolveChat } from "../supabase/functions/bsmart-social/chat.ts";

function assert(value: unknown): asserts value { if (!value) throw Error("assertion failed"); }
function mock() {
  const calls: { bucket: string; paths: string[]; ttl: number }[] = [];
  const client: any = { storage: { from: (bucket: string) => ({
    createSignedUrls: async (paths: string[], ttl: number) => {
      calls.push({ bucket, paths, ttl });
      return { data: paths.map(path => ({ path, signedUrl: `https://test.supabase.co/${bucket}/${path}?token=${calls.length}` })) };
    },
  }) } };
  return { client, calls };
}

Deno.test("media signatures are deduplicated, reused and renewed before expiry", async () => {
  let now = 0;
  const cache = new SignedMediaURLCache(() => now);
  const { client, calls } = mock();
  const first = await cache.resolve(client, "avatars", ["a", "a"], 300);
  const second = await cache.resolve(client, "avatars", ["a"], 300);
  assert(calls.length === 1 && calls[0].paths.length === 1 && first.get("a") === second.get("a"));
  now = 240000;
  const renewed = await cache.resolve(client, "avatars", ["a"], 300);
  assert(Number(calls.length) === 2 && renewed.get("a") !== first.get("a"));
});

Deno.test("concurrent callers share signing but objects buckets and clients remain isolated", async () => {
  const cache = new SignedMediaURLCache();
  const { client, calls } = mock();
  const [a, b] = await Promise.all([cache.resolve(client, "avatars", ["a"], 300), cache.resolve(client, "avatars", ["a"], 300)]);
  assert(calls.length === 1 && a.get("a") === b.get("a"));
  await cache.resolve(client, "avatars", ["new-version"], 300);
  await cache.resolve(client, "images", ["a"], 3600);
  assert(Number(calls.length) === 3);
  const other = mock();
  await cache.resolve(other.client, "avatars", ["a"], 300);
  assert(other.calls.length === 1);
});

Deno.test("failed signatures are not cached and entry count is bounded", async () => {
  const cache = new SignedMediaURLCache(Date.now, 2);
  let attempts = 0;
  const bad: any = { storage: { from: () => ({ createSignedUrls: () => {
    attempts++;
    return { data: null, error: { message: "unavailable" } };
  } }) } };
  assert((await cache.resolve(bad, "avatars", ["a"], 300)).size === 0);
  assert((await cache.resolve(bad, "avatars", ["a"], 300)).size === 0 && attempts === 2);
  const { client, calls } = mock();
  for (const path of ["a", "b", "c", "a"]) await cache.resolve(client, "avatars", [path], 300);
  assert(calls.length === 4);
});

Deno.test("chat image and avatar signing start together and unchanged polls reuse both", async () => {
  const avatar = "11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222.jpg";
  let release!: () => void;
  const barrier = new Promise<void>(resolve => { release = resolve; });
  const buckets: string[] = [];
  const client: any = { storage: { from: (bucket: string) => ({ createSignedUrls: async (paths: string[]) => {
    buckets.push(bucket);
    await barrier;
    return { data: paths.map(path => ({ path, signedUrl: `https://test.supabase.co/${bucket}/${path}` })) };
  } }) } };
  const payload = () => ({ items: [{ image: { path: "message.jpg" }, sender: { avatarURL: "storage:" + avatar } }] });
  const pending = resolveChat(client, payload());
  await Promise.resolve();
  assert(buckets.length === 2);
  release();
  const first = await pending;
  const second = await resolveChat(client, payload());
  assert(buckets.length === 2 && !first.items[0].image.path);
  assert(first.items[0].image.url === second.items[0].image.url);
  assert(first.items[0].sender.avatarURL === second.items[0].sender.avatarURL);
});
