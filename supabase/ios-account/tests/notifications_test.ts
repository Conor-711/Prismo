import { handleNotifications, type NotificationBackend } from "../supabase/functions/bsmart-notifications/handler.ts";
const id = "12345678-1234-1234-1234-123456789012";
const device = { installationId: id, apnsToken: "a".repeat(64), environment: "production", locale: "zh-Hans", enabled: true };
function assert(value: unknown): asserts value { if (!value) throw Error("assertion failed"); }
function mock() {
  const calls: [string, Record<string, unknown>][] = [];
  const backend: NotificationBackend = {
    getUser: async () => ({ user: { id, app_metadata: { providers: ["apple"] } } }),
    rpc: async (name, params) => { calls.push([name, params]); return true; },
  };
  return { backend, calls };
}
const request = (body: unknown = device, method = "PUT", token = "a.b.c", endpoint = "device") => new Request(`https://example.com/functions/v1/bsmart-notifications/${endpoint}`, {
  method, headers: { Authorization: "Bearer " + token }, body: JSON.stringify(body),
});
Deno.test("interest sync is account scoped, normalized, and bounded", async () => {
  const { backend, calls } = mock();
  const interests = { installationId: id, authors: ["X:Alice", "x:alice"], money: ["Wallet"],
    tickers: ["gme"], holdings: ["MSTR"], notifyAuthors: true, notifyTickers: true, notifyHoldings: false };
  const response = await handleNotifications(request(interests, "PUT", "a.b.c", "interests"), backend);
  assert(response.status === 200 && calls[0][0] === "bsmart_set_push_interests");
  assert(calls[0][1].p_user === id && JSON.stringify(calls[0][1].p_authors) === '["x:alice"]');
  assert(JSON.stringify(calls[0][1].p_tickers) === '["GME"]');
  for (const bad of [{ ...interests, authors: Array(151).fill("x:a") },
    { ...interests, holdings: ["bad\nvalue"] }, { ...interests, notifyHoldings: "false" }]) {
    assert((await handleNotifications(request(bad, "PUT", "a.b.c", "interests"), backend)).status === 422);
  }
  assert(calls.length === 1);
});
Deno.test("notification registration binds only verified user, not body user", async () => {
  const { backend, calls } = mock();
  const response = await handleNotifications(request({ ...device, userId: "attacker" }), backend);
  assert(response.status === 200 && response.headers.get("cache-control") === "no-store");
  assert(calls[0][1].p_user === id && calls[0][1].p_environment === "production");
  assert(!JSON.stringify(await response.json()).includes(device.apnsToken));
});
Deno.test("unregister is scoped to verified user and installation", async () => {
  const { backend, calls } = mock();
  assert((await handleNotifications(request({ installationId: id }, "DELETE"), backend)).status === 200);
  assert(calls[0][0] === "bsmart_unregister_push" && calls[0][1].p_user === id);
});
Deno.test("unauthenticated and anonymous registration never reaches database", async () => {
  const { backend, calls } = mock();
  assert((await handleNotifications(request(device, "PUT", "bad"), backend)).status === 401);
  backend.getUser = async () => ({ user: { id, is_anonymous: true, app_metadata: { provider: "apple" } } });
  assert((await handleNotifications(request(), backend)).status === 401);
  backend.getUser = async () => ({ user: null });
  assert((await handleNotifications(request(), backend)).status === 401);
  assert(calls.length === 0);
});
Deno.test("bad device fields and oversized bodies rejected", async () => {
  const { backend, calls } = mock();
  for (const input of [null, [], { ...device, installationId: "bad" }, { ...device, apnsToken: "bad" },
    { ...device, environment: "testflight" }, { ...device, enabled: "true" },
    { ...device, locale: "x".repeat(3000) }]) {
    assert((await handleNotifications(request(input), backend)).status === 422);
  }
  assert(calls.length === 0);
});
Deno.test("RPC and Auth failures expose no diagnostics and remain retryable", async () => {
  const { backend } = mock();
  backend.rpc = async () => { throw Error("secret database details"); };
  const response = await handleNotifications(request(), backend);
  assert(response.status === 503 && !(await response.text()).includes("secret"));
  backend.getUser = async () => ({ user: null, unavailable: true });
  assert((await handleNotifications(request(), backend)).status === 503);
});
