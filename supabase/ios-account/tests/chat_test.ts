import { handleSocial } from "../supabase/functions/bsmart-social/handler.ts";
import { jpegImage, sharedContent } from "../supabase/functions/bsmart-social/chat.ts";

function assert(value: unknown, message = "assertion failed"): asserts value { if (!value) throw Error(message); }
const id = "11111111-1111-4111-8111-111111111111";
const other = "22222222-2222-4222-8222-222222222222";
const headers = { authorization: "Bearer a.b.c", "content-type": "application/json" };
function request(room = "global", body?: unknown, query = "") {
  return new Request(`https://test.invalid/bsmart-social/chat/${room}${query}`, {
    method: body === undefined ? "GET" : "POST", headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
const jpeg = btoa(String.fromCharCode(255, 216, 255, 192, 0, 11, 8, 0, 16, 0, 24, 1, 1, 17, 0, 255, 217));
function mock() {
  const calls: { name: string; args: any }[] = [];
  const message: any = { id, isMine: true, text: "Hello", sentAt: "2026-09-22T00:00:00Z",
    sender: { id: other, nickname: "Alice", avatarURL: null } };
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: "private-account", identities: [{ provider: "apple" }] } } }) },
    rpc: async (name: string, args: any) => {
      calls.push({ name, args });
      if (name === "bsmart_chat_page") return { data: { items: [structuredClone(message)], nextBeforeAt: null, nextBeforeID: null } };
      if (name === "bsmart_chat_send") return { data: { ...structuredClone(message), text: args.p_text,
        share: args.p_share,
        image: args.p_image_hash ? { path: `${id}-${args.p_image_hash}.jpg`, width: args.p_image_width, height: args.p_image_height } : null } };
      return { data: null };
    },
    storage: { from: (bucket: string) => ({
      upload: async (path: string, bytes: Uint8Array, options: any) => {
        calls.push({ name: "upload", args: { bucket, path, size: bytes.length, options } }); return { data: { path } };
      },
      createSignedUrls: async (paths: string[], expiry: number) => {
        calls.push({ name: "sign", args: { bucket, paths, expiry } });
        return { data: paths.map(path => ({ path, signedUrl: `https://test.invalid/${path}?signed=true` })) };
      },
    }) },
  };
  return { client, calls, message };
}

Deno.test("global chat and direct chat use the verified actor and preserve cursor precision", async () => {
  const { client, calls } = mock();
  assert((await handleSocial(request(), client)).status === 200);
  assert((await handleSocial(request(other, undefined, `?beforeAt=2026-09-22T00:00:00.123456Z&beforeID=${id}`), client)).status === 200);
  assert(calls[0].args.p_room === "global" && calls[0].args.p_actor === "private-account");
  assert(calls[1].args.p_before_at === "2026-09-22T00:00:00.123456Z");
  assert((await handleSocial(request("global", { id, text: "hi", accountId: "forged", replyToID: other }), client)).status === 200);
  assert(calls[2].args.p_actor === "private-account" && calls[2].args.p_reply_id === other && calls[2].args.p_id === id);
});

Deno.test("invalid chat payloads do not call storage or message RPC", async () => {
  const { client, calls } = mock();
  for (const body of [{ id, text: " " }, { id, text: "a".repeat(2001) }, { id, text: "hi", replyToID: "no" },
    { id, text: "hi", imageBase64: "not-an-image" }, { text: "hi" }, { id, text: "hi", imageBase64: "a".repeat(3_200_000) }]) {
    assert((await handleSocial(request("global", body), client)).status === 422);
  }
  assert((await handleSocial(request("global", undefined, "?beforeAt=&beforeID="), client)).status === 422);
  assert((await handleSocial(request("global", undefined, `?beforeID=${id}`), client)).status === 422);
  assert((await handleSocial(request("wrong-room"), client)).status === 404);
  assert(calls.length === 0);
});

Deno.test("JPEG uploads are reserved, immutable and served through signed URLs", async () => {
  const { client, calls } = mock();
  const response = await handleSocial(request("global", { id, text: "", imageBase64: jpeg }), client);
  const message = await response.json();
  assert(response.status === 200 && message.image.width === 24 && message.image.height === 16);
  assert(message.image.url.startsWith("https://") && !message.image.path);
  assert(calls.map(c => c.name).join() === "bsmart_chat_reserve_image,upload,bsmart_chat_send,sign");
  const upload = calls[1].args;
  assert(upload.bucket === "bsmart-chat-images" && upload.options.upsert === false && !upload.path.includes("private-account"));
  assert(calls[3].args.expiry === 3600);
});

Deno.test("JPEG parser rejects oversized dimensions and non-JPEG input", () => {
  assert(jpegImage(jpeg)?.width === 24);
  for (const data of [btoa("<svg>not jpeg</svg>"), jpeg.slice(0, -4),
    btoa(String.fromCharCode(255, 216, 255, 192, 0, 11, 8, 32, 0, 0, 24, 1, 1, 17, 0, 255, 217))]) {
    let rejected = false;
    try { jpegImage(data); } catch { rejected = true; }
    assert(rejected);
  }
});

Deno.test("room/reply violations and account limits fail closed", async () => {
  const { client } = mock();
  client.rpc = async () => ({ error: { code: "P0001", message: "invalid_reply" } });
  assert((await handleSocial(request("global", { id, text: "hi", replyToID: other }), client)).status === 422);
  client.rpc = async () => ({ error: { code: "P0001", message: "rate_limited" } });
  assert((await handleSocial(request("global", { id, text: "hi" }), client)).status === 429);
  client.auth.getUser = async () => ({ data: { user: { id: "anon", is_anonymous: true, identities: [{ provider: "apple" }] } } });
  assert((await handleSocial(request("global", { id, text: "hi" }), client)).status === 401);
});

Deno.test("an uncertain send preserves the same ID on retry", async () => {
  const { client, calls } = mock();
  const original = client.rpc;
  let fail = true;
  client.rpc = async (name: string, args: any) => {
    const result = await original(name, args);
    if (name === "bsmart_chat_send" && fail) { fail = false; throw Error("lost_response"); }
    return result;
  };
  const body = { id, text: "hello", replyToID: other };
  assert((await handleSocial(request("global", body), client)).status === 503);
  assert((await handleSocial(request("global", body), client)).status === 200);
  assert(calls.filter(c => c.name === "bsmart_chat_send").every(c => c.args.p_id === id));
  assert(calls.filter(c => c.name === "bsmart_chat_send").every(c => !("p_share" in c.args)));
});

Deno.test("duplicate photo upload retries reuse the immutable object", async () => {
  const { client } = mock();
  const from = client.storage.from;
  client.storage.from = (bucket: string) => ({ ...from(bucket),
    upload: async () => ({ error: { statusCode: "400", error: "Duplicate" } }),
  });
  assert((await handleSocial(request("global", { id, text: "", imageBase64: jpeg }), client)).status === 200);
});

Deno.test("upload quota failure prevents storage work", async () => {
  const { client, calls } = mock();
  client.rpc = async () => ({ error: { code: "P0001", message: "rate_limited" } });
  assert((await handleSocial(request("global", { id, text: "", imageBase64: jpeg }), client)).status === 429);
  assert(!calls.some(call => call.name === "upload"));
});

Deno.test("shared cards are bounded, typed and use the chat send path", async () => {
  const { client, calls } = mock();
  const share = { kind: "opinion", id, title: "Avery", detail: "#3 · Top 5%",
    summary: "Looks for a break above resistance", ticker: "xyz:NVDA".toUpperCase(),
    publishedAt: "2026-09-22T10:00:00Z", avatarURL: "https://example.com/avery.jpg" };
  assert(sharedContent(share)?.kind === "opinion");
  const result = await handleSocial(request("global", { id, text: "Shared opinion: NVDA", share }), client);
  assert(result.status === 200);
  assert((await result.json()).share.ticker === "XYZ:NVDA");
  assert(calls.find(c => c.name === "bsmart_chat_send")?.args.p_share.avatarURL === share.avatarURL);
  assert(calls.find(c => c.name === "bsmart_chat_send")?.args.p_share.id === id);
  assert((await handleSocial(request("global", { id: other, text: "", share }), client)).status === 200);
  const chinese = { ...share, summary: "市场观点".repeat(70) };
  assert(sharedContent(chinese)?.summary === chinese.summary);
  const oldShare = { ...share };
  delete (oldShare as { avatarURL?: string }).avatarURL;
  assert(sharedContent(oldShare)?.kind === "opinion");
  for (const invalid of [{ ...share, id: "not-an-id" }, { ...share, summary: "x".repeat(301) },
    { ...share, kind: "wallet" }, { ...share, unexpected: "field" }, { ...share, ticker: "<script>" },
    { ...share, avatarURL: "http://example.com/avery.jpg" },
    { ...share, avatarURL: "https://user:pass@example.com/avery.jpg" }]) {
    assert((await handleSocial(request("global", { id, text: "Share", share: invalid }), client)).status === 422);
  }
});
