import { strict as assert } from "node:assert";
import jpeg from "npm:jpeg-js@0.4.4";
import { profileInput, readProfileBody } from "../supabase/functions/bsmart-profile/input.ts";
import { providerAvatar, resolveAvatars, cleanupAvatars } from "../supabase/functions/bsmart-profile/avatars.ts";
import { handleProfile } from "../supabase/functions/bsmart-profile/handler.ts";
import { handleFeed } from "../supabase/functions/bsmart-feed/handler.ts";

const input = () => ({ username: " Casey ", handle: "@Casey_01", bio: "Long-term investor", revision: 0, avatar: { action: "keep" } });
const owner = crypto.randomUUID(), publicID = crypto.randomUUID();
const row = () => ({ account_id: owner, public_id: publicID, nickname: "Casey", handle: "casey_01", bio: "", revision: 0,
  avatar_url: null, visible: false, feed_visible: false });
const req = (value?: any) => new Request("https://test.invalid/bsmart-profile", {
  method: value === undefined ? "GET" : "PUT", headers: { Authorization: "Bearer a.b.c", "Content-Type": "application/json" },
  body: value === undefined ? undefined : JSON.stringify(value),
});
function mock() {
  const state: any = { row: row(), writes: [], error: null, stale: false };
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: owner, identities: [{ provider: "google" }] } } }) },
    rpc: (_name: string, args: any) => { assert.equal(args.p_account, owner); return { data: state.row }; },
    from: (table: string) => {
      assert.equal(table, "bsmart_feed_profiles");
      const filters: any = {};
      let write: any;
      const q: any = {
        update: (value: any) => { write = value; return q; },
        eq: (key: string, value: any) => { filters[key] = value; return q; }, select: () => q,
        maybeSingle: () => {
          assert.equal(filters.account_id, owner);
          if (write) {
            state.writes.push(write); assert.equal(filters.revision, 0);
            assert.ok(!("visible" in write) && !("feed_visible" in write) && !("account_id" in write));
          }
          return { data: state.error || state.stale ? null : { ...state.row, ...write }, error: state.error };
        },
      }; return q;
    },
  };
  return { client, state };
}

Deno.test("profiles normalize handles but permit duplicate usernames and reject extra account/consent fields", () => {
  const result = profileInput(input());
  assert.equal(result.username, "Casey"); assert.equal(result.handle, "casey_01");
  for (const patch of [{ username: "" }, { username: "x".repeat(29) }, { bio: "x".repeat(121) },
    { handle: "ab" }, { handle: "1casey" }, { handle: "two words" }, { handle: "école" }, { revision: -1 },
    { accountID: owner }, { visible: true }, { avatar: { action: "keep", url: "https://evil.invalid" } }]) {
    assert.throws(() => profileInput({ ...input(), ...patch }));
  }
});
Deno.test("profile uploads decode bounded JPEGs and strip metadata rather than trusting extensions", () => {
  const image = jpeg.encode({ width: 2, height: 2, data: new Uint8Array(16) }, 80).data;
  const base64 = btoa(String.fromCharCode(...image));
  const result = profileInput({ ...input(), avatar: { action: "upload", jpegBase64: base64 } });
  assert.equal(jpeg.decode(result.image!).width, 2);
  for (const bytes of ["not-a-photo", "A".repeat(266669), btoa("<svg>bad</svg>")]) {
    assert.throws(() => profileInput({ ...input(), avatar: { action: "upload", jpegBase64: bytes } }));
  }
});
Deno.test("profile JSON is bounded independently of Content-Length", async () => {
  await assert.rejects(() => readProfileBody(req({ x: "x".repeat(280001) })));
});
Deno.test("profile authentication and ownership never trust client IDs", async () => {
  const { client } = mock();
  assert.equal((await handleProfile(new Request("https://test.invalid/bsmart-profile"), client)).status, 401);
  const result = await handleProfile(req(), client);
  const body = await result.json();
  assert.deepEqual(Object.keys(body).sort(), ["avatarURL", "bio", "handle", "id", "revision", "username"]);
  assert.equal(body.id, publicID); assert.equal(result.headers.get("cache-control"), "no-store");
  client.auth.getUser = () => ({ data: { user: { id: owner, is_anonymous: true, identities: [{ provider: "google" }] } } });
  assert.equal((await handleProfile(req(), client)).status, 401);
});
Deno.test("profile updates preserve consent and distinguish handle collision from stale revision", async () => {
  const { client, state } = mock();
  assert.equal((await handleProfile(req(input()), client)).status, 200);
  assert.equal(state.writes[0].nickname, "Casey"); assert.equal(state.writes[0].revision, 1);
  state.error = { code: "23505" };
  let result = await handleProfile(req(input()), client);
  assert.equal(result.status, 409); assert.equal((await result.json()).error, "handle_taken");
  state.error = null; state.stale = true;
  result = await handleProfile(req(input()), client);
  assert.equal(result.status, 409); assert.equal((await result.json()).error, "profile_conflict");
  state.row.revision = 2;
  assert.equal((await handleProfile(req(input()), client)).status, 409);
});
Deno.test("provider avatars use verified Google identity only, never editable metadata", () => {
  const user: any = { user_metadata: { picture: "https://lh3.googleusercontent.com/fake" }, identities: [] };
  assert.equal(providerAvatar(user), null);
  user.identities = [{ provider: "google", identity_data: { picture: "https://lh3.googleusercontent.com/real" } }];
  assert.equal(providerAvatar(user), "https://lh3.googleusercontent.com/real");
  user.identities[0].identity_data.picture = "https://lh3.googleusercontent.com.evil.invalid/fake";
  assert.equal(providerAvatar(user), null);
});
Deno.test("private avatar paths become expiring URLs; failure never leaks Storage markers", async () => {
  const path = `${publicID}/${crypto.randomUUID()}.jpg`;
  const client: any = { storage: { from: (bucket: string) => {
    assert.equal(bucket, "bsmart-profile-avatars");
    return { createSignedUrls: (paths: string[], ttl: number) => {
      assert.deepEqual(paths, [path]); assert.equal(ttl, 300);
      return { data: [{ path, signedUrl: "https://test.supabase.co/avatar" }] };
    } };
  } } };
  const resolved = await resolveAvatars(client, { items: [{ trader: { avatarURL: "storage:" + path } }] });
  assert.equal(resolved.items[0].trader.avatarURL, "https://test.supabase.co/avatar");
  assert.equal((await resolveAvatars({} as any, { avatarURL: "storage:../../other" })).avatarURL, null);
});
Deno.test("old client sharing payload cannot replace canonical username or avatar", async () => {
  let values: any;
  const client: any = {
    auth: { getUser: () => ({ data: { user: { id: owner, identities: [{ provider: "google" }] } } }) },
    rpc: () => ({ data: row() }),
    from: () => {
      const q: any = { update: (v: any) => { values = v; return q; }, eq: () => q, select: () => q,
        maybeSingle: () => ({ data: row() }), then: (resolve: any) => Promise.resolve(resolve({ error: null })) };
      return q;
    },
  };
  const request = new Request("https://test.invalid/bsmart-feed/sharing", { method: "PUT",
    headers: { Authorization: "Bearer a.b.c", "Content-Type": "application/json" },
    body: JSON.stringify({ nickname: "Old name", useProviderAvatar: false, visible: true, feedVisible: true }) });
  const result = await handleFeed(request, client, { info: async () => ({}), catalog: async () => ({}) });
  assert.equal(result.status, 200);
  assert.deepEqual(Object.keys(values).sort(), ["feed_visible", "updated_at", "visible"]);
  assert.equal((await result.json()).nickname, "Casey");
});

Deno.test("avatar cleanup retries failed removals and only deletes queued versioned paths", async () => {
  const path = `${publicID}/${crypto.randomUUID()}.jpg`;
  const removed: string[] = [], completed: string[] = [];
  let fail = true;
  const client: any = {
    storage: { from: () => ({ remove: (paths: string[]) => {
      removed.push(...paths); return { error: fail ? true : null };
    } }) },
    from: (table: string) => {
      assert.equal(table, "bsmart_profile_avatar_cleanup");
      const q: any = { select: () => q, order: () => q, limit: () => ({ data: [{ path }] }),
        delete: () => q, eq: (_key: string, value: string) => { completed.push(value); return {}; } };
      return q;
    },
  };
  await cleanupAvatars(client); assert.equal(completed.length, 0);
  fail = false; await cleanupAvatars(client);
  assert.deepEqual(removed, [path, path]); assert.deepEqual(completed, [path]);
});
