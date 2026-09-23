import { handleSocial } from "../supabase/functions/bsmart-social/handler.ts";

function assert(value: unknown, message = "assertion failed"): asserts value { if (!value) throw Error(message); }
const peer = "11111111-1111-4111-8111-111111111111";
const token = { Authorization: "Bearer a.b.c" };
const req = (path = "", method = "GET", body?: unknown) => new Request("https://test.invalid/bsmart-social" + path, {
  method, headers: { ...token, ...(body ? { "content-type": "application/json" } : {}) },
  body: body ? JSON.stringify(body) : undefined,
});

function mock() {
  const calls: [string, any][] = [];
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: "private-user-id", identities: [{ provider: "google" }] } } }) },
    rpc: async (name: string, args: any) => {
      calls.push([name, args]);
      if (name === "bsmart_social_snapshot") return { data: { following: [], followers: [], conversations: [] } };
      if (name === "bsmart_social_messages_page") return { data: { items: [], nextBeforeAt: null, nextBeforeID: null } };
      if (name === "bsmart_social_send") return { data: { id: peer, isMine: true, text: args.p_text, sentAt: new Date().toISOString() } };
      return { data: null };
    },
    from: (_table: string) => {
      const chain: any = {};
      for (const name of ["select", "gt", "neq", "or", "order", "limit"]) {
        chain[name] = (...args: any[]) => { calls.push([name, args]); return chain; };
      }
      chain.then = (resolve: any) => Promise.resolve({ data: [{ public_id: peer, nickname: "Alice",
        handle: "alice", avatar_url: null }] }).then(resolve);
      return chain;
    },
  };
  return { client, calls };
}

Deno.test("social endpoints reject anonymous and invalid sessions before reading data", async () => {
  const { client, calls } = mock();
  assert((await handleSocial(new Request("https://test.invalid/bsmart-social"), client)).status === 401);
  client.auth.getUser = async () => ({ data: { user: { is_anonymous: true, identities: [{ provider: "google" }] } } });
  assert((await handleSocial(req(), client)).status === 401);
  client.auth.getUser = async () => ({ data: { user: null }, error: { status: 503 } });
  assert((await handleSocial(req(), client)).status === 503);
  assert(calls.length === 0);
});

Deno.test("user search exposes profiles without private account IDs", async () => {
  const { client, calls } = mock();
  const response = await handleSocial(req("/people?q=ali"), client);
  const result = await response.json();
  assert(response.status === 200 && result.people.length === 1);
  assert(Object.keys(result.people[0]).sort().join() === "avatarURL,handle,id,nickname");
  assert(calls.some(([name, args]) => name === "neq" && args.join() === "account_id,private-user-id"));
  assert((await handleSocial(req("/people?q=" + "x".repeat(81)), client)).status === 422);
});

Deno.test("follow is unilateral and first messages require no relationship", async () => {
  const { client, calls } = mock();
  assert((await handleSocial(req("/follows/" + peer, "POST", { follow: true }), client)).status === 200);
  assert((await handleSocial(req("/follows/" + peer, "POST", { follow: false }), client)).status === 200);
  const message = await handleSocial(req("/messages/" + peer, "POST", { text: "hello" }), client);
  assert(message.status === 200 && (await message.json()).isMine);
  assert(calls.some(([name, args]) => name === "bsmart_social_send" && args.p_peer_public === peer));
  assert(!calls.some(([name]) => name.includes("friend")));
});

Deno.test("message boundaries and cursors reject malformed input", async () => {
  const { client, calls } = mock();
  assert((await handleSocial(req("/messages/" + peer, "POST", { text: " " }), client)).status === 422);
  assert((await handleSocial(req("/messages/" + peer + "?beforeAt=2026-09-21T00:00:00Z"), client)).status === 422);
  assert((await handleSocial(req("/messages/" + peer + "?beforeAt=2026-09-21T00%3A00%3A00%2B00%3A00&beforeID=" + peer), client)).status === 200);
  assert((await handleSocial(req("/follows/" + peer, "POST", { follow: "yes" }), client)).status === 422);
  assert((await handleSocial(req("/messages/not-an-id", "POST", { text: "hi" }), client)).status === 404);
  assert(!calls.some(([name]) => name === "bsmart_social_send"));
});
